--logger.lua
--logger功能支持
local lstdfs        = require("lstdfs")
local lcodec        = require("lcodec")
local llogger       = require("lualog")

local pcall         = pcall
local pairs         = pairs
local tpack         = table.pack
local tunpack       = table.unpack
local dgetinfo      = debug.getinfo
local sformat       = string.format
local fsstem        = lstdfs.stem
local serialize     = lcodec.serialize
local lwarn         = llogger.warn
local lfilter       = llogger.filter
local lis_filter    = llogger.is_filter

local LOG_LEVEL     = llogger.LOG_LEVEL

logger              = {}
local monitors      = _ENV.monitors or {}
local logfeature    = _ENV.logfeature or {}
local dispatching   = false

function logger.init()
    --配置日志信息
    local service_name, index = quanta.service_name, quanta.index
    local path = environ.get("QUANTA_LOG_PATH", "./logs/")
    local rolltype = environ.number("QUANTA_LOG_ROLL", 0)
    local maxline = environ.number("QUANTA_LOG_LINE", 100000)
    llogger.option(path, service_name, index, rolltype);
    llogger.set_max_line(maxline);
    --设置日志过滤
    logger.filter(environ.number("QUANTA_LOG_LVL"))
    --添加输出目标
    llogger.add_dest(service_name);
    llogger.add_lvl_dest(LOG_LEVEL.ERROR)
    --设置daemon
    llogger.daemon(environ.status("QUANTA_DAEMON"))
end

function logger.daemon(daemon)
    llogger.daemon(daemon)
end

function logger.feature(name)
    if not logfeature.features then
        logfeature.features = {}
    end
    if not logfeature.features[name] then
        logfeature.features[name] = true
        llogger.add_dest(name)
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
        --lfilter(level, on/off)
        lfilter(lvl, lvl >= level)
    end
end

local function logger_output(feature, lvl, lvl_name, fmt, log_conf, ...)
    if lis_filter(lvl) then
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
    [LOG_LEVEL.INFO]    = { "info",  { llogger.info,  false, false } },
    [LOG_LEVEL.WARN]    = { "warn",  { llogger.warn,  true,  false } },
    [LOG_LEVEL.DUMP]    = { "dump",  { llogger.dump,  true,  true  } },
    [LOG_LEVEL.DEBUG]   = { "debug", { llogger.debug, true,  false } },
    [LOG_LEVEL.ERROR]   = { "err",   { llogger.error, true,  false } },
    [LOG_LEVEL.FATAL]   = { "fatal", { llogger.fatal, true,  false } }
}
for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logger[lvl_name] = function(fmt, ...)
        local ok, res = pcall(logger_output, "", lvl, lvl_name, fmt, log_conf, ...)
        if not ok then
            local info = dgetinfo(2, "S")
            lwarn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
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
                lwarn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
                return false
            end
            return res
        end
    end
end
