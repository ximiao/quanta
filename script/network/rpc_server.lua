--rpc_server.lua
local lcodec            = require("lcodec")

local pairs             = pairs
local tpack             = table.pack
local tunpack           = table.unpack
local signalquit        = signal.quit
local log_err           = logger.err
local log_warn          = logger.warn
local log_info          = logger.info
local qeval             = quanta.eval
local qxpcall           = quanta.xpcall
local lencode           = lcodec.encode_slice
local ldecode           = lcodec.decode_slice

local event_mgr         = quanta.get("event_mgr")
local thread_mgr        = quanta.get("thread_mgr")
local socket_mgr        = quanta.get("socket_mgr")

local FLAG_REQ          = quanta.enum("FlagMask", "REQ")
local FLAG_RES          = quanta.enum("FlagMask", "RES")
local SUCCESS           = quanta.enum("KernCode", "SUCCESS")
local RPCLINK_TIMEOUT   = quanta.enum("NetwkTime", "RPCLINK_TIMEOUT")
local RPC_CALL_TIMEOUT  = quanta.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local RpcServer = singleton()

local prop = property(RpcServer)
prop:reader("ip", "")                     --监听ip
prop:reader("port", 0)                    --监听端口
prop:reader("clients", {})
prop:reader("listener", nil)
prop:reader("holder", nil)                  --持有者

--induce：根据index推导port
function RpcServer:__init(holder, ip, port, induce)
    if not ip or not port then
        log_err("[RpcServer][setup] ip:%s or port:%s is nil", ip, port)
        signalquit()
        return
    end
    local real_port = induce and (port + quanta.index - 1) or port
    self.listener = socket_mgr.listen(ip, real_port)
    if not self.listener then
        log_err("[RpcServer][setup] now listen %s:%s failed", ip, real_port)
        signalquit()
        return
    end
    self.holder = holder
    self.ip, self.port = ip, real_port
    log_info("[RpcServer][setup] now listen %s:%s success!", ip, real_port)
    self.listener.on_accept = function(client)
        qxpcall(self.on_socket_accept, "on_socket_accept: %s", self, client)
    end
    event_mgr:add_listener(self, "rpc_heartbeat")
end

--rpc事件
function RpcServer:on_socket_rpc(client, session_id, rpc_flag, recv_len, source, rpc, ...)
    client.alive_time = quanta.now
    event_mgr:notify_listener("on_rpc_recv", rpc, recv_len)
    if session_id == 0 or rpc_flag == FLAG_REQ then
        local function dispatch_rpc_message(...)
            local _<close> = qeval(rpc)
            local rpc_datas = event_mgr:notify_listener(rpc, client, ...)
            if session_id > 0 then
                client.call_rpc(session_id, FLAG_RES, rpc, tunpack(rpc_datas))
            end
        end
        thread_mgr:fork(dispatch_rpc_message, ...)
        return
    end
    thread_mgr:response(session_id, ...)
end

--连接关闭
function RpcServer:on_socket_error(token, err)
    local client = self.clients[token]
    if client then
        self.clients[token] = nil
        if client.id then
            thread_mgr:fork(function()
                self.holder:on_client_error(client, token, err)
            end)
        end
    end
end

--accept事件
function RpcServer:on_socket_accept(client)
    client.set_timeout(RPCLINK_TIMEOUT)
    self.clients[client.token] = client
    client.call_rpc = function(session_id, rpc_flag, rpc, ...)
        local send_len = client.call(session_id, rpc_flag, lencode(0, rpc, ...))
        if send_len < 0 then
            event_mgr:notify_listener("on_rpc_send", rpc, send_len)
            log_err("[RpcServer][call_rpc] call failed! code:%s", send_len)
            return false
        end
        return true, SUCCESS
    end
    client.on_call = function(recv_len, session_id, rpc_flag, slice)
        local rpc_res = tpack(pcall(ldecode, slice))
        if not rpc_res[1] then
            log_err("[RpcServer][on_socket_accept] on_call decode failed %s!", rpc_res[2])
            return
        end
        qxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, client, session_id, rpc_flag, recv_len, tunpack(rpc_res, 2))
    end
    client.on_error = function(token, err)
        qxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
    end
    --通知收到新client
    self.holder:on_client_accept(client)
end

--send接口
function RpcServer:call(client, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    if client.call_rpc(session_id, FLAG_REQ, rpc, ...) then
        return thread_mgr:yield(session_id, rpc, RPC_CALL_TIMEOUT)
    end
    return false, "rpc server send failed"
end

--send接口
function RpcServer:send(client, rpc, ...)
    return client.call_rpc(0, FLAG_REQ, rpc, ...)
end

--broadcast接口
function RpcServer:broadcast(rpc, ...)
    for _, client in pairs(self.clients) do
        client.call_rpc(0, FLAG_REQ, rpc, ...)
    end
end

--servicecast接口
function RpcServer:servicecast(service_id, rpc, ...)
    for _, client in pairs(self.clients) do
        if service_id == 0 or client.service_id == service_id then
            client.call_rpc(0, FLAG_REQ, rpc, ...)
        end
    end
end

--获取client
function RpcServer:get_client(token)
    return self.clients[token]
end

--获取client
function RpcServer:get_client_by_id(quanta_id)
    for _, client in pairs(self.clients) do
        if client.id == quanta_id then
            return client
        end
    end
end

--选主
function RpcServer:find_master(service)
    local new_master = nil
    for _, client in pairs(self.clients) do
        local client_id = client.id
        if service == client.service and client_id then
            if not new_master or client_id < new_master.id then
                new_master = client
            end
        end
    end
    return new_master
end

--rpc回执
-----------------------------------------------------------------------------
--服务器心跳协议
function RpcServer:rpc_heartbeat(client, node)
    --回复心跳
    self:send(client, "on_heartbeat", quanta.id)
    if not node then
        --正常心跳
        self.holder:on_client_beat(client)
        return
    end
    if not client.id then
        -- 检查重复注册
        local client_id = node.id
        local eclient = self:get_client_by_id(client_id)
        if eclient then
            eclient.id = nil
            self:send(eclient, "rpc_client_kickout", quanta.id, "service replace")
            log_warn("[RpcServer][rpc_heartbeat] client(%s) be kickout, service replace!", eclient.name)
        end
        -- 通知注册
        client.id = client_id
        client.name = node.name
        client.service = node.service
        client.service_name = node.service_name
        self.holder:on_client_register(client, node, client_id)
    end
end

return RpcServer
