--kernel.lua
local ltimer = require("ltimer")

import("basic/basic.lua")
import("kernel/perfeval_mgr.lua")
import("kernel/update_mgr.lua")

local ltime         = ltimer.time
local qxpcall       = quanta.xpcall
local qxpcall_quit  = quanta.xpcall_quit

local socket_mgr    = nil
local update_mgr    = quanta.get("update_mgr")

local QuantaMode    = enum("QuantaMode")

--初始化gm
local function init_gm()
    import("agent/gm_agent.lua")
end

--初始化环境变量
local function init_environ()
    import("basic/environ.lua") 
    environ.init()
end

--初始化信号
local function init_signal()
    import("basic/signal.lua")
    signal.init()
end

--初始化服务
local function init_service()
    import("basic/service.lua")
    import("kernel/config_mgr.lua")
    service.init()
end

--初始化日志
local function init_logger()
    import("basic/logger.lua")
    import("basic/console.lua")
    logger.init()
end

--初始化网络
local function init_network()
    local lbus = require("luabus")
    local max_conn = environ.number("QUANTA_MAX_CONN", 64)
    socket_mgr = lbus.create_socket_mgr(max_conn)
    quanta.socket_mgr = socket_mgr
end

--初始化路由
local function init_router()
    import("kernel/router_mgr.lua")
    import("driver/webhook.lua")
end

--初始化网络
local function init_network()
    local lbus = require("luabus")
    local max_conn = env_number("QUANTA_MAX_CONN", 64)
    socket_mgr = lbus.create_socket_mgr(max_conn)
    quanta.socket_mgr = socket_mgr
end

function quanta.init()
    quanta.frame = 0
    --初始化随机种子
    math.randomseed(quanta.now_ms)
    --初始化模块
    init_signal()
    local qmode = init_environ()
    if qmode > QuantaMode.TINY then
        init_service()
        init_logger()
    end
    if qmode > QuantaMode.TOOL then
        init_network()
    end
    if qmode == QuantaMode.SERVICE then
        init_gm()
        init_router()
        import("basic/utility.lua")
        --加载统计
        import("kernel/statis_mgr.lua")
        --加载协议
        import("kernel/protobuf_mgr.lua")
        --加载monotor
        if not environ.get("QUANTA_MONITOR_HOST") then
            import("agent/monitor_agent.lua")
            import("kernel/netlog_mgr.lua")
        end
    end
end

--启动
function quanta.startup(entry)
    local function start(entry)
        --初始化quanta
        quanta.init()
        --启动服务器
        entry()
    end
    qxpcall_quit(start, "quanta startup error: %s", entry)
end

--日常更新
local function update()
    socket_mgr.wait(10)
    local now_ms, now_s = ltime()
    quanta.now = now_s
    quanta.now_ms = now_ms
    --系统更新
    update_mgr:update(now_ms)
end

--底层驱动
quanta.run = function()
    qxpcall(update, "quanta.run error: %s")
end
