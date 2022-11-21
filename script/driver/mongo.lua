
--mongo.lua
local lbus          = require("luabus")
local lmongo        = require("lmongo")
local lcrypt        = require("lcrypt")
local Socket        = import("driver/socket.lua")

local log_err       = logger.err
local log_info      = logger.info
local qjoin         = qtable.join
local ssub          = string.sub
local sgsub         = string.gsub
local sformat       = string.format
local sgmatch       = string.gmatch
local mtointeger    = math.tointeger
local lmd5          = lcrypt.md5
local lsha1         = lcrypt.sha1
local lrandomkey    = lcrypt.randomkey
local lb64encode    = lcrypt.b64_encode
local lb64decode    = lcrypt.b64_decode
local lhmac_sha1    = lcrypt.hmac_sha1
local lxor_byte     = lcrypt.xor_byte
local mreply        = lmongo.reply_slice
local mopmsg        = lmongo.opmsg_slice
local mdecode       = lmongo.decode_slice
local mencode_s     = lmongo.encode_sparse
local mencode_o     = lmongo.encode_order_slice

local eproto_type   = lbus.eproto_type

local update_mgr    = quanta.get("update_mgr")
local thread_mgr    = quanta.get("thread_mgr")

local DB_TIMEOUT    = quanta.enum("NetwkTime", "DB_CALL_TIMEOUT")

local MongoDB = class()
local prop = property(MongoDB)
prop:reader("ip", nil)          --mongo地址
prop:reader("sock", nil)        --网络连接对象
prop:reader("name", "")         --dbname
prop:reader("port", 27017)      --mongo端口
prop:reader("user", nil)        --user
prop:reader("passwd", nil)      --passwd
prop:reader("cursor_id", nil)   --cursor_id
prop:reader("sessions", {})     --sessions
prop:reader("readpref", nil)    --readPreference

function MongoDB:__init(conf)
    self.name = conf.db
    self.user = conf.user
    self.passwd = conf.passwd
    self.sock = Socket(self)
    self.cursor_id = lmongo.int64(0)
    self:choose_mongos(conf.hosts)
    self:set_options(conf.opts)
    --attach_second
    update_mgr:attach_hour(self)
    update_mgr:attach_second(self)
end


function MongoDB:on_hour()
end

function MongoDB:close()
    if self.sock then
        self.sock:close()
    end
end

function MongoDB:choose_mongos(hosts)
    for host, port in pairs(hosts) do
        self.ip, self.port = host, port
        break
    end
end

function MongoDB:set_options(opts)
    for key, value in pairs(opts) do
        if key == "readPreference" then
            self.readpref = { mode = value }
        end
    end
end

function MongoDB:on_hour()
    if self.sock:is_alive() then
        self:runCommand("ping")
    end
end

function MongoDB:on_second()
    if not self.sock:is_alive() then
        local ok, err = self.sock:connect(self.ip, self.port, eproto_type.common)
        if not ok then
            log_err("[MongoDB][on_second] connect db(%s:%s:%s) failed: %s!", self.ip, self.port, self.name, err)
            return
        end
        if self.user and self.passwd then
            local aok, aerr = self:auth(self.user, self.passwd)
            if not aok then
                log_err("[MongoDB][on_second] auth db(%s:%s) failed! because: %s", self.ip, self.port, aerr)
                self:close()
                return
            end
        end
        log_info("[MongoDB][on_second] connect db(%s:%s:%s) success!", self.ip, self.port, self.name)
    end
end

local function salt_password(password, salt, iter)
    salt = salt .. "\0\0\0\1"
    local output = lhmac_sha1(password, salt)
    local inter = output
    for i = 2, iter do
        inter = lhmac_sha1(password, inter)
        output = lxor_byte(output, inter)
    end
    return output
end

function MongoDB:auth(username, password)
    local nonce = lb64encode(lrandomkey())
    local user = sgsub(sgsub(username, '=', '=3D'), ',', '=2C')
    local first_bare = "n="  .. user .. ",r="  .. nonce
    local sasl_start_payload = lb64encode("n,," .. first_bare)
    local sok, sdoc = self:adminCommand("saslStart", 1, "autoAuthorize", 1, "mechanism", "SCRAM-SHA-1", "payload", sasl_start_payload)
    if not sok then
        return sok, sdoc
    end

    local conversationId = sdoc['conversationId']
    local str_payload_start = lb64decode(sdoc['payload'])
    local payload_start = {}
    for k, v in sgmatch(str_payload_start, "(%w+)=([^,]*)") do
        payload_start[k] = v
    end
    local salt = payload_start['s']
    local rnonce = payload_start['r']
    local iterations = tonumber(payload_start['i'])
    if not ssub(rnonce, 1, 12) == nonce then
        return false, "Server returned an invalid nonce."
    end
    local without_proof = "c=biws,r=" .. rnonce
    local pbkdf2_key = lmd5(sformat("%s:mongo:%s", username, password), 1)
    local salted_pass = salt_password(pbkdf2_key, lb64decode(salt), iterations)
    local client_key = lhmac_sha1(salted_pass, "Client Key")
    local stored_key = lsha1(client_key)
    local auth_msg = first_bare .. ',' .. str_payload_start .. ',' .. without_proof
    local client_sig = lhmac_sha1(stored_key, auth_msg)
    local client_key_xor_sig = lxor_byte(client_key, client_sig)
    local client_proof = "p=" .. lb64encode(client_key_xor_sig)
    local client_final = lb64encode(without_proof .. ',' .. client_proof)

    local cok, cdoc = self:adminCommand("saslContinue", 1, "conversationId", conversationId, "payload", client_final)
    if not cok then
        return cok, cdoc
    end
    local payload_continue = {}
    local str_payload_continue = lb64decode(cdoc['payload'])
    for k, v in sgmatch(str_payload_continue, "(%w+)=([^,]*)") do
        payload_continue[k] = v
    end
    local server_key = lhmac_sha1(salted_pass, "Server Key")
    local server_sig = lb64encode(lhmac_sha1(server_key, auth_msg))
    if payload_continue['v'] ~= server_sig then
        log_err("Server returned an invalid signature.")
        return false
    end
    if not cdoc.done then
        local ccok, ccdoc = self:adminCommand("saslContinue", 1, "conversationId", conversationId, "payload", "")
        if not ccok or not ccdoc.done then
            return false, "SASL conversation failed to complete."
        end
    end
    return true
end

function MongoDB:on_socket_error(sock, token, err)
    for session_id in pairs(self.sessions) do
        thread_mgr:response(session_id, false, err)
    end
    self.sessions = {}
end

function MongoDB:decode_reply(succ, slice)
    local doc = mdecode(slice)
    if doc.writeErrors then
        return false, doc.writeErrors[1].errmsg
    end
    if doc.writeConcernError then
        return false, doc.writeConcernError.errmsg
    end
    if succ and doc.ok == 1 then
        return succ, doc
    end
    return false, doc.errmsg or doc["$err"]
end

function MongoDB:on_slice_recv(slice, token)
    local reply, session_id = mreply(slice)
    local succ, doc = self:decode_reply(reply, slice)
    if not succ then
        thread_mgr:response(session_id, succ, doc)
        return
    end
    thread_mgr:response(session_id, succ, doc)
end

function MongoDB:op_msg(slice_bson)
    if not self.sock then
        return false, "db not connected"
    end
    local session_id = thread_mgr:build_session_id()
    local slice = mopmsg(slice_bson, session_id, 0)
    if not self.sock:send_slice(slice) then
        return false, "send failed"
    end
    self.sessions[session_id] = true
    return thread_mgr:yield(session_id, "mongo_op_msg", DB_TIMEOUT)
end

function MongoDB:adminCommand(cmd, cmd_v, ...)
    local slice_bson = mencode_o(cmd, cmd_v, "$db", "admin", ...)
    return self:op_msg(slice_bson)
end

function MongoDB:runCommand(cmd, cmd_v, ...)
    local slice_bson = mencode_o(cmd, cmd_v or 1, "$db", self.name, ...)
    return self:op_msg(slice_bson)
end

function MongoDB:sendCommand(cmd, cmd_v, ...)
    if not self.sock then
        return false, "db not connected"
    end
    local slice_bson = mencode_o(cmd, cmd_v or 1, "$db", self.name, "writeConcern", {w=0}, ...)
    local pack = mopmsg(slice_bson, 0, 0)
    self.sock:send(pack)
    return true
end

function MongoDB:drop_collection(co_name)
    return self:runCommand("drop", co_name)
end

-- 参数说明
-- indexes={{key={open_id=1,platform_id=1},name="open_id-platform_id",unique=true}, }
function MongoDB:create_indexes(co_name, indexes)
    local succ, doc = self:runCommand("createIndexes", co_name, "indexes", indexes)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:drop_indexes(co_name, index_name)
    local succ, doc = self:runCommand("dropIndexes", co_name, "index", index_name)
    if not succ then
        return succ, doc
    end
    return succ
end

function MongoDB:insert(co_name, doc)
    return self:runCommand("insert", co_name, "documents", { mencode_s(doc) })
end

function MongoDB:update(co_name, update, selector, upsert, multi)
    local cmd_data = { q = selector, u = mencode_s(update), upsert = upsert, multi = multi }
    return self:runCommand("update", co_name, "updates", { cmd_data })
end

function MongoDB:delete(co_name, selector, onlyone)
    local cmd_data = { q = selector, limit = onlyone and 1 or 0 }
    return self:runCommand("delete", co_name, "deletes", { cmd_data })
end

function MongoDB:count(co_name, query, limit, skip)
    local succ, doc = self:runCommand("count", co_name, "query", query, "limit", limit, "skip", skip)
    if not succ then
        return succ, doc
    end
    return succ, mtointeger(doc.n)
end

function MongoDB:find_one(co_name, query, projection)
    local succ, reply = self:runCommand("find", co_name, "$readPreference", self.readpref, "filter", query, "projection", projection, "limit", 1)
    if not succ then
        return succ, reply
    end
    local documents = reply.cursor.firstBatch
    if #documents > 0 then
        return succ, documents[1]
    end
    return succ
end

function MongoDB:find(co_name, query, projection, sortor, limit, skip)
    local succ, reply = self:runCommand("find", co_name, "$readPreference", self.readpref, "filter",
                query, "projection", projection, "sort", sortor, "limit", limit, "skip", skip)
    if not succ then
        return succ, reply
    end
    local results = {}
    local cursor = reply.cursor
    while cursor do
        local documents = cursor.firstBatch or cursor.nextBatch
        qjoin(documents, results)
        if not cursor.id or cursor.id == 0 then
            break
        end
        if limit and #results >= limit then
            break
        end
        self.cursor_id.val = cursor.id
        local msucc, moreply = self:runCommand("getMore", self.cursor_id, "collection", co_name, "batchSize", limit)
        if not msucc then
            return msucc, moreply
        end
        cursor = moreply.cursor
    end
    return true, results
end

function MongoDB:find_and_modify(co_name, update, selector, upsert, fields, new)
    return self:runCommand("findAndModify", co_name, "query", selector, "update", update, "fields", fields, "upsert", upsert, "new", new)
end

return MongoDB
