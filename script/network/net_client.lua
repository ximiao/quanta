--net_client.lua
local lcrypt            = require("lcrypt")
local log_err           = logger.err
local qeval             = quanta.eval
local qxpcall           = quanta.xpcall
local env_status        = environ.status

local event_mgr         = quanta.get("event_mgr")
local socket_mgr        = quanta.get("socket_mgr")
local thread_mgr        = quanta.get("thread_mgr")
local protobuf_mgr      = quanta.get("protobuf_mgr")

local out_press         = env_status("QUANTA_OUT_PRESS")
local out_encrypt       = env_status("QUANTA_OUT_ENCRYPT")

local FLAG_REQ          = quanta.enum("FlagMask", "REQ")
local FLAG_ZIP          = quanta.enum("FlagMask", "ZIP")
local FLAG_ENCRYPT      = quanta.enum("FlagMask", "ENCRYPT")
local CONNECT_TIMEOUT   = quanta.enum("NetwkTime", "CONNECT_TIMEOUT")
local RPC_CALL_TIMEOUT  = quanta.enum("NetwkTime", "RPC_CALL_TIMEOUT")


local NetClient = class()
local prop = property(NetClient)
prop:reader("ip", nil)
prop:reader("port", nil)
prop:reader("alive", false)
prop:reader("alive_time", 0)
prop:reader("socket", nil)          --连接成功对象
prop:reader("holder", nil)          --持有者
prop:reader("wait_list", {})        --等待协议列表
prop:accessor("decoder", nil)       --解码函数
prop:accessor("encoder", nil)       --编码函数

function NetClient:__init(holder, ip, port)
    self.holder = holder
    self.port = port
    self.ip = ip
end

-- 发起连接
function NetClient:connect(block)
    if self.socket then
        return true
    end
    local proto_type = 1
    local socket, cerr = socket_mgr.connect(self.ip, self.port, CONNECT_TIMEOUT, proto_type)
    if not socket then
        log_err("[NetClient][connect] failed to connect: %s:%d type=%d, err=%s", self.ip, self.port, proto_type, cerr)
        return false, cerr
    end
    --设置阻塞id
    local block_id = block and thread_mgr:build_session_id()
    -- 调用成功，开始安装回调函数
    socket.on_connect = function(res)
        local succes = (res == "ok")
        thread_mgr:fork(function()
            if not succes then
                self:on_socket_error(socket.token, res)
            else
                self:on_socket_connect(socket)
            end
        end)
        if block_id then
            --阻塞回调
            thread_mgr:response(block_id, succes, res)
        end
    end
    socket.on_call_pack = function(recv_len, cmd_id, flag, type, session_id, slice)
        event_mgr:notify_listener("on_proto_recv", cmd_id, recv_len)
        qxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, socket, cmd_id, flag, type, session_id, slice)
    end
    socket.on_error = function(token, err)
        thread_mgr:fork(function()
            self:on_socket_error(token, err)
        end)
    end
    self.socket = socket
    --阻塞模式挂起
    if block_id then
        return thread_mgr:yield(block_id, "connect", CONNECT_TIMEOUT)
    end
    return true
end

function NetClient:get_token()
    return self.socket and self.socket.token
end

function NetClient:encode(cmd_id, data, flag)
    local encode_data
    if self.encoder then
        encode_data = self.encoder(cmd_id, data)
    else
        encode_data = protobuf_mgr:encode(cmd_id, data)
    end
    -- 加密处理
    if out_encrypt then
        encode_data = lcrypt.b64_encode(encode_data)
        flag = flag | FLAG_ENCRYPT
    end
    -- 压缩处理
    if out_press then
        encode_data = lcrypt.lz4_encode(encode_data)
        flag = flag | FLAG_ZIP
    end
    return encode_data, flag
end

function NetClient:decode(cmd_id, slice, flag)
    local decode_data = slice.string()
    if flag & FLAG_ZIP == FLAG_ZIP then
        --解压处理
        decode_data = lcrypt.lz4_decode(decode_data)
    end
    if flag & FLAG_ENCRYPT == FLAG_ENCRYPT then
        --解密处理
        decode_data = lcrypt.b64_decode(decode_data)
    end
    if self.decoder then
        return self.decoder(cmd_id, decode_data)
    else
        return protobuf_mgr:decode(cmd_id, decode_data)
    end
end

function NetClient:on_socket_rpc(socket, cmd_id, flag, type, session_id, slice)
    self.alive_time = quanta.now
    local body, cmd_name = self:decode(cmd_id, slice, flag)
    if not body  then
        log_err("[NetClient][on_socket_rpc] decode failed! cmd_id:%s", cmd_id)
        return
    end
    if session_id == 0 or (flag & FLAG_REQ == FLAG_REQ) then
        -- 执行消息分发
        local function dispatch_rpc_message()
            local _<close> = qeval(cmd_name)
            self.holder:on_socket_rpc(self, cmd_id, body)
        end
        thread_mgr:fork(dispatch_rpc_message)
        --等待协议处理
        local wait_session_id = self.wait_list[cmd_id]
        if wait_session_id then
            self.wait_list[cmd_id] = nil
            thread_mgr:response(wait_session_id, true)
        end
        return
    end
    --异步回执
    thread_mgr:response(session_id, true, body)
end

-- 主动关闭连接
function NetClient:close()
    if self.socket then
        self.socket.close()
        self.alive = false
        self.socket = nil
    end
end

function NetClient:write(cmd_id, data, type, session_id, flag)
    if not self.alive then
        return false
    end
    local body, pflag = self:encode(cmd_id, data, flag)
    if not body then
        log_err("[NetClient][write] encode failed! cmd_id:%s", cmd_id)
        return false
    end
    -- call lbus
    local send_len = self.socket.call_pack(cmd_id, pflag, type or 0, session_id or 0, body, #body)
    if send_len < 0 then
        log_err("[NetClient][write] call_pack failed! code:%s", send_len)
        return false
    end
    return true
end

-- 发送数据
function NetClient:send(cmd_id, data, type)
    return self:write(cmd_id, data, type, 0, FLAG_REQ)
end

-- 发起远程调用
function NetClient:call(cmd_id, data, type)
    local session_id = self.socket.build_session_id()
    if not self:write(cmd_id, data, type, session_id, FLAG_REQ) then
        return false
    end
    return thread_mgr:yield(session_id, cmd_id, RPC_CALL_TIMEOUT)
end

-- 等待远程调用
function NetClient:wait(cmd_id, time)
    local session_id = thread_mgr:build_session_id()
    self.wait_list[cmd_id] = session_id
    return thread_mgr:yield(session_id, cmd_id, time)
end

-- 连接成回调
function NetClient:on_socket_connect(socket)
    self.alive = true
    self.alive_time = quanta.now
    self.holder:on_socket_connect(self)
end

-- 连接关闭回调
function NetClient:on_socket_error(token, err)
    if self.socket then
        self.socket = nil
        self.alive = false
        self.wait_list = {}
        self.holder:on_socket_error(self, token, err)
    end
end

return NetClient
