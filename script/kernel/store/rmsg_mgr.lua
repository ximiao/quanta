--rmsg_mgr.lua
import("kernel/store/mongo_agent.lua")
local lcrypt = require("lcrypt")
local bson          = require("bson")

local bdate         = bson.date
local log_err       = logger.err
local log_info      = logger.info
local new_guid      = lcrypt.guid_new

local mongo_agent   = quanta.get("mongo_agent")
local check_success = utility.check_success

local DBGroup       = enum("DBGroup")
local DBGROUP_HASH  = DBGroup.HASH

local RmsgMgr = class()
local prop = property(RmsgMgr)
prop:reader("table_name", "") -- table_name
prop:reader("ttl", nil)       -- ttl

function RmsgMgr:__init(name, ttl)
    if ttl then
        self.ttl = ttl
        self:build_ttl(name)
    end
    self.table_name = name
    log_info("[RmsgMgr][init] init rmsg table: %s", name)
end

function RmsgMgr:build_ttl(name)
    log_info("[RmsgMgr][build_ttl] rmsg table:%s", name)
    local query = { name, { { key = { ttl = 1 }, expireAfterSeconds = 0, name = "ttl", unique = false } } }
    local ok, code = mongo_agent:create_indexes(1, query, DBGROUP_HASH, 0)
    if ok and check_success(code) then
        log_info("[RmsgMgr][build_ttl] rmsg table %s build due index success")
    end
end

-- 查询未处理消息列表
function RmsgMgr:list_message(to)
    local query = { self.table_name, {to = to, deal_time = 0}, {_id = 0}, {time = 1} }
    local ok, code, result = mongo_agent:find(to, query, DBGROUP_HASH, to)
    if ok and check_success(code) then
        return result
    end
end

-- 设置信息为已处理
function RmsgMgr:deal_message(to, uuid)
    log_info("[RmsgMgr][deal_message] deal message: %s", uuid)
    local query = { self.table_name, {["$set"] = {deal_time = quanta.now}}, {uuid = uuid} }
    return mongo_agent:update(to, query, DBGROUP_HASH, to)
end

-- 删除消息
function RmsgMgr:delete_message(to, uuid)
    log_info("[RmsgMgr][delete_message] delete message: %s", uuid)
    return mongo_agent:delete(to, {self.table_name, {uuid = uuid}}, DBGROUP_HASH, to)
end

-- 发送消息
function RmsgMgr:send_message(from, to, typ, body, id)
    local uuid = id or new_guid()
    local doc = {
        uuid = uuid,
        from = from, to = to,
        type = typ, body = body,
        time = quanta.now,
        deal_time = 0,
    }
    --设置过期ttl字段
    if self.ttl then
        doc.ttl = bdate(quanta.now + self.ttl)
    end
    local ok = mongo_agent:insert(to, {self.table_name, doc}, DBGROUP_HASH, to)
    if not ok then
        log_err("[RmsgMgr][send_message] send message failed: %s, %s, %s, %s", uuid, from, to, typ)
    else
        log_info("[RmsgMgr][send_message] send message succeed: %s, %s, %s, %s", uuid, from, to, typ)
    end
    return ok
end

return RmsgMgr
