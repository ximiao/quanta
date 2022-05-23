--database_cfg.lua
--luacheck: ignore 631

--获取配置表
local config_mgr = quanta.get("config_mgr")
local database = config_mgr:get_table("database")

--导出配置内容
database:upsert({
    quanta_deploy = 'publish',
    driver = 'mongo',
    db = 'quanta',
    default = true,
    host = '127.0.0.1',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'publish',
    driver = 'mongo',
    db = 'quanta_rmsg',
    default = false,
    host = '127.0.0.1',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'develop',
    driver = 'mongo',
    db = 'quanta',
    default = true,
    host = '127.0.0.1',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'develop',
    driver = 'mongo',
    db = 'quanta_rmsg',
    default = false,
    host = '127.0.0.1',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'local',
    driver = 'mongo',
    db = 'quanta',
    default = true,
    host = '9.134.163.87',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'local',
    driver = 'mysql',
    db = 'quanta',
    default = true,
    host = '9.134.163.87',
    user = 'root',
    passwd = '123456',
    port = 3306,
})

database:upsert({
    quanta_deploy = 'local',
    driver = 'redis',
    db = '0',
    default = true,
    host = '9.134.163.87',
    user = 'root',
    passwd = '123456',
    port = 6380,
})

database:upsert({
    quanta_deploy = 'local',
    driver = 'mongo',
    db = 'quanta_rmsg',
    default = false,
    host = '9.134.163.87',
    user = 'root',
    passwd = '123456',
    port = 27017,
})

database:upsert({
    quanta_deploy = 'local',
    driver = 'clickhouse',
    db = 'quanta',
    default = true,
    host = '9.134.163.87',
    user = 'default',
    passwd = '123456',
    port = 9004,
})

database:set_version('08596bb35016e83f849fa228d157f888')