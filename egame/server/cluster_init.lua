local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
require "common.etool"
require "data.dataDungeon"

--------------启动服务
skynet.start(function()
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

    --初始化配置
    init_game_conf()

    skynet.exit()
end)

--初始化游戏配置
function init_game_conf()
    sharedata.new("dataDungeon", dun_list)
end