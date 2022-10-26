-- session.lua
local log_warn      = logger.warn
local log_debug     = logger.debug
local tunpack       = table.unpack
local event_mgr     = quanta.get("event_mgr")
local protobuf_mgr  = quanta.get("protobuf_mgr")
local NetClient     = import("network/net_client.lua")

local SessionModule = mixin()
local prop = property(SessionModule)
prop:reader("client", nil)
prop:reader("cmd_doers", {})

function SessionModule:__init()
end

function SessionModule:disconnect()
    if self.client then
        self.client:close()
    end
end

function SessionModule:connect(ip, port, block)
    if self.client then
        self.client:close()
    end
    self.serial = 1
    self.client = NetClient(self, ip, port)
    return self.client:connect(block)
end

-- 连接成回调
function SessionModule:on_socket_connect(client)
    log_debug("[SessionModule][on_socket_connect] %s", self:get_title())
end

-- 连接关闭回调
function SessionModule:on_socket_error(client, token, err)
    log_debug("[SessionModule][on_socket_error] %s, err:%s", self:get_title(), err)
end

-- ntf消息回调
function SessionModule:on_socket_rpc(client, cmd_id, body)
    event_mgr:notify_listener("on_server_message", cmd_id, body)
    local doer = self.cmd_doers[cmd_id]
    if not doer then
        log_warn("[SessionModule][on_socket_rpc] cmd %s hasn't register doer!, msg=%s", cmd_id, body)
        return
    end
    local module, handler = tunpack(doer)
    module[handler](self, body)
end


-- 注册NTF消息处理
function SessionModule:register_doer(pb_name, module, handler)
    local cmdid = protobuf_mgr:enum("NCmdId", pb_name)
    self.cmd_doers[cmdid] = {module, handler}
end

function SessionModule:conv_type(cmdid)
    if type(cmdid) == "string" then
        cmdid = protobuf_mgr:msg_id(cmdid)
    end
    if cmdid < 10000 then
        return 0
    end
    return (cmdid // 1000) % 10
end

function SessionModule:send(cmdid, data)
    if self.client then
        return self.client:send(cmdid, data, self:conv_type(cmdid))
    end
end

function SessionModule:call(cmdid, data)
    if self.client then
        local ok, resp = self.client:call(cmdid, data, self:conv_type(cmdid))
        return ok, resp
    end
    return false
end

-- 等待NTF命令或者非RPC命令
function SessionModule:wait(cmdid, time)
    if self.client then
        return self.client:wait(cmdid, time)
    end
    return false
end

return SessionModule
