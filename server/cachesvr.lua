#!./quanta
import("kernel.lua")

quanta.startup(function()
    --初始化cachesvr
    import("kernel/cache/cache_mgr.lua")
end)
