--robot_cfg.lua
--luacheck: ignore 631

--获取配置表
local config_mgr = quanta.get("config_mgr")
local robot = config_mgr:get_table("robot")

--导出配置内容
robot:upsert({
    index = 1,
    ip = '127.0.0.1',
    port = 20013,
    open_id = 'test_001',
    access_token = '123123',
    openid_type = 2,
    start = 1000,
    count = 1,
    tree_id = 1001,
})

robot:upsert({
    index = 2,
    ip = '127.0.0.1',
    port = 20013,
    open_id = 'test_002',
    access_token = '123123',
    openid_type = 2,
    start = 1000,
    count = 1,
    tree_id = 1002,
})

--general md5 version
robot:set_version('345889d85029114bab5603736dc5f5b6')