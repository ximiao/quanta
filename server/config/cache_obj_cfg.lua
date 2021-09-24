--cache_obj_cfg.lua
--luacheck: ignore 631

--获取配置表
local config_mgr = quanta.get("config_mgr")
local cache_obj = config_mgr:get_table("cache_obj")

--导出版本号
cache_obj:set_version(10000)

--导出配置内容
cache_obj:upsert({
    cache_name = 'account',
    cache_total = false,
    cache_table = 'account',
    cache_key = 'open_id',
    cache_group = 1,
    expire_time = 3000,
    flush_time = 3600,
    store_time = 120,
    store_count = 20,
})

cache_obj:upsert({
    cache_name = 'player',
    cache_total = false,
    cache_table = 'player',
    cache_key = 'player_id',
    cache_group = 1,
    expire_time = 600,
    flush_time = 0,
    store_time = 120,
    store_count = 200,
})

cache_obj:upsert({
    cache_name = 'career_image',
    cache_total = false,
    cache_table = 'career_image',
    cache_key = 'player_id',
    cache_group = 1,
    expire_time = 3000,
    flush_time = 3600,
    store_time = 120,
    store_count = 200,
})