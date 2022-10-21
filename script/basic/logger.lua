--logger.lua
--logger功能支持
local llog          = require("lualog")
local lstdfs        = require("lstdfs")
local lcodec        = require("lcodec")

local pcall         = pcall
local pairs         = pairs
local tpack         = table.pack
local tunpack       = table.unpack
local dgetinfo      = debug.getinfo
local sformat       = string.format
local serialize     = lcodec.serialize
local fsstem        = lstdfs.stem

local LOG_LEVEL     = llog.LOG_LEVEL

logger              = {}
local driver        = quanta.get_logger()
local monitors      = _ENV.monitors or {}
local logfeature    = _ENV.logfeature or {}
local dispatching   = false

function logger.init()
    --配置日志信息
    local service_name, index = quanta.service_name, quanta.index
    local path = environ.get("QUANTA_LOG_PATH", "./logs/")
    local rolltype = environ.number("QUANTA_LOG_ROLL", 0)
    local maxline = environ.number("QUANTA_LOG_LINE", 100000)
    driver.option(path, service_name, index, rolltype);
    driver.set_max_line(maxline);
    --设置日志过滤
    logger.filter(environ.number("QUANTA_LOG_LVL"))
    --添加输出目标
    driver.add_dest(service_name);
    driver.add_lvl_dest(LOG_LEVEL.ERROR)
    --设置daemon
    driver.daemon(environ.status("QUANTA_DAEMON"))
end

function logger.daemon(daemon)
    driver.daemon(daemon)
end

function logger.feature(name)
    if not logfeature.features then
        logfeature.features = {}
    end
    if not logfeature.features[name] then
        logfeature.features[name] = true
        driver.add_dest(name)
    end
end

function logger.add_monitor(monitor)
    monitors[monitor] = true
end

function logger.remove_monitor(monitor)
    monitors[monitor] = nil
end

function logger.filter(level)
    for lvl = LOG_LEVEL.DEBUG, LOG_LEVEL.FATAL do
        --driver.filter(level, on/off)
        driver.filter(lvl, lvl >= level)
    end
end

local function logger_output(feature, lvl, lvl_name, fmt, log_conf, ...)
    if driver.is_filter(lvl) then
        return false
    end
    local content
    local lvl_func, extend, swline = tunpack(log_conf)
    if extend then
        local args = tpack(...)
        for i, arg in pairs(args) do
            if type(arg) == "table" then
                args[i] = serialize(arg, swline and 1 or 0)
            end
        end
        content = sformat(fmt, tunpack(args, 1, args.n))
    else
        content = sformat(fmt, ...)
    end
    if not dispatching then
        --防止重入
        dispatching = true
        for monitor in pairs(monitors) do
            monitor:dispatch_log(content, lvl_name, lvl)
        end
        dispatching = false
    end
    return lvl_func(content, feature)
end

local LOG_LEVEL_OPTIONS = {
    [LOG_LEVEL.INFO]    = { "info",  { driver.info,  false, false } },
    [LOG_LEVEL.WARN]    = { "warn",  { driver.warn,  true,  false } },
    [LOG_LEVEL.DUMP]    = { "dump",  { driver.dump,  true,  true  } },
    [LOG_LEVEL.DEBUG]   = { "debug", { driver.debug, true,  false } },
    [LOG_LEVEL.ERROR]   = { "err",   { driver.error, true,  false } },
    [LOG_LEVEL.FATAL]   = { "fatal", { driver.fatal, true,  false } }
}
for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logger[lvl_name] = function(fmt, ...)
        local ok, res = pcall(logger_output, "", lvl, lvl_name, fmt, log_conf, ...)
        if not ok then
            local info = dgetinfo(2, "S")
            driver.warn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
            return false
        end
        return res
    end
end

for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logfeature[lvl_name] = function(feature)
        if not feature then
            local info = dgetinfo(2, "S")
            feature = fsstem(info.short_src)
        end
        logger.feature(feature)
        return function(fmt, ...)
            local ok, res = pcall(logger_output, feature, lvl, lvl_name, fmt, log_conf, ...)
            if not ok then
                local info = dgetinfo(2, "S")
                driver.warn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
                return false
            end
            return res
        end
    end
end
