local skynet = require "skynet"
require "skynet.manager"
local queue = require "skynet.queue"
local db = require "db.db_api"
require "def.def_id_create"
require "common.etool"

local q = queue()

local CMD = {}

local idType = ...
idType = tonumber(idType)
local lastId = 0
local serverId = 0
local count = 0     --累计获取次数（达到一定量入库更新）

function CMD.init()
    serverId = tonumber(skynet.getenv("server_id"))
    local auto_id = 0

    --获取对应数据表最大id
    local max_id = get_max_id()

    --自增id表最大id
    local result = db.query(string.format("select count from id_create where type = %d", idType))
    if result.err == nil and #result > 0 then
        auto_id = result[1].count
    else
        auto_id = 0
    end

    --算出lastId
    if max_id == 0 then
        lastId = auto_id + 1
    else
        local tmp_last_id = max_id & 0xFFFFFFFF

        lastId =  math.max(tmp_last_id, auto_id) + 1
    end
end

function CMD.get_id()
    -- 组合成 48 位的 id
    local temp_ser_id = serverId & 0xFFFF
    local temp_last_id = lastId & 0xFFFFFFFF
    local id = (temp_ser_id << 32) | temp_last_id
    -- 更新id
    count = count + 1
    if count >= 20 then
        pcall(update_count, lastId)
    end
    lastId = lastId + 1
    skynet.ret(skynet.pack(id))
end

skynet.start(function()
    if idType == PLAYER_ID then
        skynet.name(".id_player", skynet.self())
    end
    -- 注册skynet.dispatch处理函数
    skynet.dispatch("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("id_create service err:", f, err)
        end
    end)
end)

---------------------内部函数
function get_max_id()
    local result = {}
    if idType == PLAYER_ID then
        --玩家表最大id
        result = db.query("select role_id from player where 1=1 order by role_id desc limit 1") 
        if result.err == nil and #result > 0 then
            return result[1].role_id
        end
    end
    return 0
end

function update_count(lastId) 
    local res = db.query(string.format("update id_create set count = %d where type = %d", lastId, idType))   
    if res.err then
        log_print("id_create update_count Err:", idType, res.err)
    end
end