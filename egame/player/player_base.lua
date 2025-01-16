local skynet = require "skynet"
local db = require "db.db_api"
local player_event = require "event.player_event"
require "common.etool"
require "def.def_player"

--玩家信息
local player_info = BASE_PLAYER_INFO

--获取玩家信息
function GetPlayer()
    return player_info
end

--玩家信息设置
function PlayerSet(KeyValMap)
    for k, v in pairs(KeyValMap) do
        player_info[k] = v
    end
end

--玩家登录
function PlayerLogin(role_id, pid)
    local res = db.query(string.format("select * from player where role_id=%d", role_id))
    if res.err == nil and #res > 0 then
        PlayerSet({id = role_id, name = res[1].name, online = 1, pid = pid, node = skynet.getenv("node")})
        return true
    end
    return false
end

--玩家注册
function PlayerReg()
    local role_id = skynet.call(skynet.localname(".id_player"), "lua", "get_id")
    if role_id > 0 then
        local res = db.query(string.format("insert into player(role_id) values (%d)", role_id))
        if res.err then
            log_print("PlayerReg Err:", res.err)
            return 0, false
        else
            if res.affected_rows and res.affected_rows > 0 then
                return role_id, true
            end 
        end
    end 
    return 0, false
end