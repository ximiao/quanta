--test.lua
import("kernel.lua")

quanta.startup(function()--初始化test
    --[[
    import("test/codec_test.lua")
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
    import("test/mysql_test.lua")
    import("test/redis_test.lua")
    import("test/stdfs_test.lua")
    import("test/cmdline_test.lua")
    import("test/ws_test.lua")
    import("test/influx_test.lua")
    import("test/graylog_test.lua")
    import("test/zipkin_test.lua")
    import("test/clickhouse_test.lua")
    import("test/nacos_test.lua")
    import("test/url_test.lua")
    ]]
    import("test/worker_test.lua")
end)
