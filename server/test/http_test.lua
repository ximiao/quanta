-- http_test.lua
import("network/http_client.lua")
local ljson = require("lcjson")
local ltimer = require("ltimer")

local qget          = quanta.get
local ltime         = ltimer.time
local log_debug     = logger.debug
local json_encode   = ljson.encode

local thread_mgr    = qget("thread_mgr")
local http_client   = qget("http_client")

if quanta.index == 1 then
    local data = {aaa = 123}
    local on_post = function(path, body, headers)
        log_debug("on_post: %s, %s, %s", path, body, headers)
        return data
    end
    local on_get = function(path, query, headers)
        log_debug("on_get: %s, %s, %s", path, query, headers)
        return data
    end
    local HttpServer = import("network/http_server.lua")
    local server = HttpServer("0.0.0.0:8888")
    server:register_get("*", on_get)
    server:register_post("*", on_post)
    quanta.server = server
elseif quanta.index == 2 then
    thread_mgr:fork(function()
        local post_data = json_encode({title = "test", text = "http test"})
        local ROBOT_URL = "https://open.feishu.cn/open-apis/bot/hook/56b34b9e1c0b4fc0acadef8ebc3894ad"
        local ok, status, res = http_client:call_post(ROBOT_URL, post_data)
        log_debug("feishu test : %s, %s, %s", ok, status, res)
    end)
    for i = 1, 1 do
        thread_mgr:fork(function()
            local data = {aaa = 123}
            local tk = ltime()
            local ok, status, res = http_client:call_post("http://127.0.0.1:8888/node_status1", data)
            log_debug("node_status1 : %s, %s, %s, %s", ltime() - tk, ok, status, res)
            ok, status, res = http_client:call_get("http://127.0.0.1:8888/node_status2", data)
            log_debug("node_status2 : %s, %s, %s, %s", ltime() - tk, ok, status, res)
            ok, status, res = http_client:call_put("http://127.0.0.1:8888/node_status3", data)
            log_debug("node_status3 : %s, %s, %s, %s", ltime() - tk, ok, status, res)
            ok, status, res = http_client:call_del("http://127.0.0.1:8888/node_status4", data)
            log_debug("node_status4 : %s, %s, %s, %s", ltime() - tk, ok, status, res)
        end)
    end
end
