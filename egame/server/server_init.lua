local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
require "common.etool"
require "data.dataDungeon"
require "def.def_id_create"

--------------启动服务
skynet.start(function()
    --初始化玩家在线共享数据 sharedata方法
    sharedata.new("player_onlines", {})

    --初始化标志位，是否有重定向日志输出 (在这之后才能使用自定义的log_print输出方法)
    local log = skynet.getenv("logger")
    if log == nil then
        sharedata.new("logInfo", {log = nil})
    else
        sharedata.new("logInfo", {log = true})
    end

    --初始化db池
    local db = skynet.newservice("db")
    skynet.send(db, "lua", "init")
    --初始化redis池
    local rd = skynet.newservice("db/rd")
    skynet.send(rd, "lua", "init") 

    --初始化配置
    init_game_conf()

    --启动唯一id服务
    for k, v in pairs(ID_LIST) do
        local id_create = skynet.newservice("id_create", v)
        skynet.send(id_create, "lua", "init") 
    end

    --启动cache层服务
    skynet.newservice("cache/cache_mgr")

    --启动热更
    skynet.newservice("hotfix")
    skynet.exit()
end)

--初始化游戏配置
function init_game_conf()
    sharedata.new("dataDungeon", dun_list)
end