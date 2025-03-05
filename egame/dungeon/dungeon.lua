local skynet = require "skynetex"
local sd = require "skynet.sharedata"
local queue = require "skynet.queue"
local misc = require "common.misc"
local api = require "clusters.clusters_api"
require "def.def_dungeon"
require "def.def_msg_type"
require "common.etool"
require "def.def_error"

local q = queue()
local CMD = {}
local dun_state = BASE_DUN_STATE

--开启副本
function CMD.init(dun_id, room_id, role_list, args)
    log_print("dungeon start")
    --读取配置
    local list = sd.query("dataDungeon")
    local st_time = math.floor(skynet.time())
    local et_time = st_time + list[dun_id].time
    --设置超时时间
    skynet.timeout((et_time - st_time) * 100, dungeon_timeout)
    --基础副本数据
    dun_state.dun_id = dun_id
    dun_state.dun_type = list[dun_id].type
    dun_state.room_id = room_id
    dun_state.cluster_type = api.is_center()
    dun_state.st_time = st_time
    dun_state.et_time = et_time
    dun_state.role_list = role_list
    dun_state.is_end = 0
    dun_state.typical_data = {}
    --额外设置
    for k, v in pairs(args) do
        if k == "do_func" then
            if v.func and type(v.func) == "function" and v.args then
                v(dun_state, v.args) 
            end
        elseif k == "typical_data" then
            for k1, v1 in pairs(v) do
                dun_state.typical_data[k1] = v1
            end
        end
    end
    --拉玩家进入副本
    for k, v in pairs(role_list) do
        pull_player_into_dungeon(v)
    end
end

--主动退出副本
function CMD.quit_dun(role_id, node)
    if is_in_table_func(dun_state.role_list, function(k, v, val)
            return v.id == val
        end, role_id) then
        --默认单人，退出就结束了
        log_print("quit_dun", role_id)
        close_dun() 
    else
        api.apply(node, misc.get_role_fd_name(role_id), "handle", MSG_TYPE_NET, "write", 20002, {res = ERROR_NOT_ON_DUN})
    end
end

--进入副本失败
function CMD.handle_enter_fail(...)
    log_print("dungeon fail close", ...)
    skynet.exit()
end

skynet.start(function()
    --服务的消息处理
    skynet.dispatchex("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("dungeon service err:", f, err)
        end
    end)
end)


---------------------内部函数
---副本超时结束
function dungeon_timeout()
    close_dun()
    skynet.exit()
end

function close_dun()
    log_print("dun_is_over", dun_state.dun_id, skynet.self())
    --拉玩家退出副本
    for k, v in pairs(dun_state.role_list) do
        pull_player_out_dungeon(v)
    end 
end

--拉玩家进入副本
function pull_player_into_dungeon(dun_role)
    log_print("pull_player_into_dungeon")
    local args = {dun_id = dun_state.dun_id, is_cls = dun_state.cluster_type, dun_pid = skynet.self(), room_id = dun_state.room_id}
    api.apply(dun_role.node, dun_role.role_fd_name, "handle", MSG_TYPE_DUN, "pull_into_dungeon", args) 
end

--拉玩家退出副本
function pull_player_out_dungeon(dun_role)
    log_print("pull_player_out_dungeon")
    local args = {dun_pid = skynet.self()}
    api.apply(dun_role.node, dun_role.role_fd_name, "handle", MSG_TYPE_DUN, "pull_out_dungeon", args)
end