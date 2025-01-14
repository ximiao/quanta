self=false
stds.quanta = {
    globals = {
        --common
        "coroutine", "qtable", "qstring", "qmath", "ncmd_cs",
        "quanta", "environ", "signal", "luabt", "service", "logger",
        "import", "class", "enum", "mixin", "property", "singleton", "super", "implemented",
        "logfeature", "db_property", "classof", "is_class", "is_subclass", "instanceof", "conv_class",
        "codec", "crypt", "stdfs", "luabus", "luakit", "json", "protobuf", "curl", "timer", "aoi", "log", "worker", "http", "bson", "detour"
    }
}
std = "max+quanta"
max_cyclomatic_complexity = 13
max_code_line_length = 160
max_comment_line_length = 160
exclude_files = {
    "extend/lmake/share.lua",
    "server/robot/accord/page/*"
}
include_files = {
    "script/*.lua",
    "server/*.lua",
    "script/*/*.lua",
    "server/*/*.lua",
    "script/*/*/*.lua",
    "server/*/*/*.lua",
    "script/*/*/*/*.lua",
    "server/*/*/*/*.lua",
    "extend/lmake/*.lua",
    "tools/*/*.lua",
}
ignore = {"212", "213", "512"}

