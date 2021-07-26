--test.lua
import("kernel.lua")

local log_info      = logger.info
local qxpcall       = quanta.xpcall
local quanta_update = quanta.update
local qxpcall_quit  = quanta.xpcall_quit

quanta.run = function()
    qxpcall(quanta_update, "quanta_update error: %s")
end

-- 初始化
if not quanta.init_flag then
    local function startup()
        --初始化quanta
        quanta.init()
        --初始化test
        --[[
        import("test/etcd_test.lua")
        import("test/json_test.lua")
        import("test/pack_test.lua")
        import("test/mongo_test.lua")
        import("test/router_test.lua")
        import("test/protobuf_test.lua")
        import("test/http_test.lua")
        import("test/rpc_test.lua")
        import("test/log_test.lua")
        import("test/crypt_test.lua")
        import("test/timer_test.lua")
        ]]
        import("test/timer_test.lua")
        log_info("test %d now startup!", quanta.id)
    end
    qxpcall_quit(startup, "quanta startup error: %s")
    quanta.init_flag = true
end