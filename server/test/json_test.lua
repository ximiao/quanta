--json_test.lua
local ljson     = require("lcjson")
local lcodec    = require("lcodec")

local json_encode   = ljson.encode
local json_decode   = ljson.decode
local new_guid      = lcodec.guid_new

local test  = {
    tid = 3.1415926,
    player_id = new_guid()
}

print(test.tid)
print(test.player_id)

local a = json_encode(test)
print(a)

local b = json_decode(a)
print(type(b.tid), b.tid)
print(type(b.player_id), b.player_id)

os.exit()
