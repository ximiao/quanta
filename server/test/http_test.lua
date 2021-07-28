-- http_test.lua
import("kernel/network/http_client.lua")
local ljson = require("lcjson")
ljson.encode_sparse_array(true)

local json_encode   = ljson.encode
local serialize     = logger.serialize

local thread_mgr    = quanta.get("thread_mgr")
local http_client   = quanta.get("http_client")

if quanta.index == 1 then
    local data = {aaa = 123}
    local on_post = function(path, body, headers)
        print("on_post:", path, body, headers)
        return data
    end
    local on_get = function(path, headers)
        print("on_get:", path, serialize(headers))
        return data
    end
    local HttpServer = import("kernel/network/http_server.lua")
    local server = HttpServer()
    server:setup("0.0.0.0:8888", on_post, on_get)
    quanta.server = server
elseif quanta.index == 2 then
    thread_mgr:fork(function()
        local post_data = json_encode({title = "test", text = "http test"})
        local ROBOT_URL = "https://open.feishu.cn/open-apis/bot/hook/56b34b9e1c0b4fc0acadef8ebc3894ad"
        local ok, status, res = http_client:call_post(ROBOT_URL, {}, post_data)
        logger.info("feishu test : %s, %s, %s", ok, status, res)
    end)
    for i = 1, 1 do
        thread_mgr:fork(function()
            local tk = quanta.get_time_ms()
            local ok, status, res = http_client:call_post("http://10.100.0.19:8080/node_status", {}, json_encode(data))
            logger.info("node_status : %s, %s, %s, %s", quanta.get_time_ms() - tk, ok, status, res)
        end)
    end
end
