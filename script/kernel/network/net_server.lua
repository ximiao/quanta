--session_mgr.lua
local log_err       = logger.err
local log_info      = logger.info
local env_addr      = environ.addr
local qxpcall       = quanta.xpcall

local event_mgr     = quanta.event_mgr
local thread_mgr    = quanta.thread_mgr
local protobuf_mgr  = quanta.protobuf_mgr
local perfeval_mgr  = quanta.perfeval_mgr
local statis_mgr    = quanta.statis_mgr

local RpcType       = enum("RpcType")
local NetwkTime     = enum("NetwkTime")

-- Dx协议会话对象管理器
local NetServer = class()
local prop = property(NetServer)
prop:accessor("sessions", {})           --会话列表
prop:accessor("session_type", "default")--会话类型
prop:accessor("session_count", 0)       --会话数量
prop:accessor("listener", nil)          --监听器
prop:accessor("decoder", nil)           --解码函数
prop:accessor("encoder", nil)           --编码函数

function NetServer:__init(session_type)
    self.session_type = session_type
end

--induce：根据index推导port
function NetServer:setup(ip, port, induce)
    -- 开启监听
    if not ip or not port then
        log_err("[NetServer][setup] ip:%s or port:%s is nil", ip, port)
        os.exit(1)
    end
    local listen_proto_type = 1
    local socket_mgr = quanta.socket_mgr
    local real_port = induce and (tonumber(port) + quanta.index) or port
    self.listener = socket_mgr.listen(ip, real_port, listen_proto_type)
    if not self.listener then
        log_err("[NetServer][setup] failed to listen: %s:%d type=%d", ip, real_port, listen_proto_type)
        os.exit(1)
    end
    log_info("[NetServer][setup] start listen at: %s:%d type=%d", ip, real_port, listen_proto_type)
    -- 安装回调
    self.listener.on_accept = function(session)
        qxpcall(self.on_session_accept, "on_dx_accept: %s", self, session)
    end
end

-- 连接回调
function NetServer:on_session_accept(session)
    log_debug("[on_session_accept]: token:%s, ip:%s", session.token, session.ip)
    self:add_session(session)
    -- 设置超时(心跳)
    session.set_timeout(NetwkTime.NETWORK_TIMEOUT)
    -- 绑定call回调
    session.on_call_dx = function(recv_len, cmd_id, flag, session_id, data)
        statis_mgr:statis_notify("on_dx_recv", cmd_id, recv_len)
        local eval = perfeval_mgr:begin_eval("dx_s_cmd_" .. cmd_id)
        qxpcall(self.on_call_dx, "on_call_dx: %s", self, session, cmd_id, flag, session_id, data)
        perfeval_mgr:end_eval(eval)
    end
    -- 绑定网络错误回调（断开）
    session.on_error = function(err)
        qxpcall(self.on_session_err, "on_session_err: %s", self, session)
    end
    --初始化序号
    session.serial = 0
    session.serial_sync = 0
    --通知链接成功
    event_mgr:notify_listener("on_session_accept", session)
end

function NetServer:write(session, cmd_id, data, session_id, flag)
    local body = self:encode(cmd_id, data)
    if not body then
        log_err("[NetServer][write] encode failed! cmd_id:%s", cmd_id)
        return false
    end
    session.serial = session.serial + 1
    -- call lbus
    local session_id = session_id or 0
    local send_len = session.call_dx(cmd_id, flag or RpcType.RPC_REQ, session_id, body)
    if send_len > 0 then
        statis_mgr:statis_notify("on_dx_send", cmd_id, send_len)
        return true
    end
    log_err("[NetServer][write] call_dx failed! code:%s", send_len)
    return false
end

-- 发送数据
function NetServer:send_dx(session, cmd_id, data, session_id)
    return self:write(session, cmd_id, data, session_id)
end

-- 回调数据
function NetServer:callback_dx(session, cmd_id, data, session_id)
    return self:write(session, cmd_id, data, session_id, RpcType.RPC_RES)
end

-- 发起远程调用
function NetServer:call_dx(session, cmd_id, data)
    local session_id = thread_mgr:build_session_id()
    if not self:write(session, cmd_id, data, session_id) then
        return false
    end
    return thread_mgr:yield(session_id, NetwkTime.RPC_CALL_TIMEOUT)
end

function NetServer:encode(cmd_id, data)
    if self.encoder then
        return self.encoder(cmd_id, data)
    end
    return protobuf_mgr:encode(cmd_id, data)
end

function NetServer:decode(cmd_id, data)
    if self.decoder then
        return self.decoder(cmd_id, data)
    end
    return protobuf_mgr:decode(cmd_id, data)
end

-- 收到远程调用回调
function NetServer:on_call_dx(session, cmd_id, flag, session_id, data)
    local now_tick = quanta.now
    session.alive_time = now_tick
    -- 解码
    local body = self:decode(cmd_id, data)
    if not body then
        log_err("[NetServer][on_call_dx] decode failed! cmd_id:%s", cmd_id)
        return
    end
    if session_id == 0 or flag == RpcType.RPC_REQ then
        local function dispatch_rpc_message(session, cmd, bd)
            local result = event_mgr:notify_listener("on_session_cmd", session, cmd, bd, session_id)
            if not result[1] then
                log_err("[NetServer][on_call_dx] on_session_cmd failed! cmd_id:%s", cmd_id)
            end
        end
        thread_mgr:fork(dispatch_rpc_message, session, cmd_id, body)
        return
    end
    --异步回执
    thread_mgr:response(session_id, true, body)
end

--检查序列号
function NetServer:check_serial(session, cserial)
    local sserial = session.serial
    if cserial and cserial ~= session.serial_sync then
        event_mgr:notify_listener("on_session_sync", session)
    end
    session.serial_sync = sserial
    return sserial
end

-- 关闭会话
-- @param session: 会话对象
function NetServer:close_session(session)
    if session then
        session.close()
    end
end

-- 关闭会话
-- @param token: 目标会话的token
function NetServer:close_session_by_token(token)
    local session = self.sessions[token]
    self:close_session(session)
end

-- 会话被关闭回调
function NetServer:on_session_err(session, err)
    thread_mgr:fork(function()
        event_mgr:notify_listener("on_session_err", session, err)
    end)
    self:remove_session(session)
end

-- 添加会话
function NetServer:add_session(session)
    self.sessions[session.token] = session
    self.session_count = self.session_count + 1
    statis_mgr:statis_notify("on_dx_conn_update", self.session_type, self.session_count)
end

-- 移除会话
function NetServer:remove_session(session)
    self.sessions[session.token] = nil
    self.session_count = self.session_count - 1
    statis_mgr:statis_notify("on_dx_conn_update", self.session_type, self.session_count)
end

-- 查询会话
function NetServer:get_session_by_token(token)
    return self.sessions[token];
end

return NetServer
