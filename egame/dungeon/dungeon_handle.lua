local skynet = require "skynet"
require "def.def_dungeon"
local sd = require "skynet.sharedata"
require "def.def_error"
require "player.player_base"
local net = require "net.net"
local misc = require "common.misc"
local clusters_api = require "clusters.clusters_api"

local dun = BASE_DUN_STATUS

----协议处理
function dun.cmd_handle(cmd, data)
    if cmd == 20001 then
        --进入副本
        enter_dun(data)
    elseif cmd == 20002 then
        --退出副本
        quit_dun(data)
    end
end
---------进入副本相关
----进入副本
function enter_dun(data) 
    local err, res  = check_pull_into(data)
    if err then
        local d_role = BASE_DUN_ROLE
        local player_info = GetPlayer()
        d_role.id = player_info.id 
        d_role.name = player_info.name
        d_role.node = player_info.node
        d_role.role_fd_name = misc.get_role_fd_name(player_info.id)
        d_role.server_id = skynet.getenv("server_id")
        d_role.is_leader = 1
        d_role.online = 1
        d_role.is_reward = 0
        d_role.typical_data = {}
        --是跨服还是游戏服副本
        if res.cls_type == 1 then
            local node = skynet.getenv("node")
            skynet.send(node, "lua", "apply_to_center", nil, "func_handle", "dun", data.dun_id, 0, {[player_info.id ] = d_role}, {})
        else
            local dungeon = skynet.newservice("dungeon")
            skynet.send(dungeon, "lua", "init", data.dun_id, 0, {[player_info.id ] = d_role}, {}) 
        end
    else
        net.write(20001, {res = res})
    end
end

----副本进程拉玩家进入副本
function dun.pull_into_dungeon(args)
    log_print("pull_into_dungeon")
    local err, res = check_pull_into(args)
    if err then
        reset_dun_data()
        dun.dun_id = args.dun_id
        dun.is_cls = args.is_cls
        dun.dun_pid = args.dun_pid
        dun.is_end = 0
        dun.other = {}
        net.write(20001, {res = ERROR_SUCCESS})
    else
        apply_to_dun(args.dun_pid, args.is_cls, "handle_enter_fail", res)
        net.write(20001, {res = ERROR_FAIL})
    end
end

--检测是否能进入副本
function check_pull_into(args)
    local dun_id = args.dun_id
    local list = sd.query("dataDungeon")
    if is_on_dun() then
        return false, ERROR_IS_ON_DUN
    elseif list[dun_id] == nil then
        return false, ERROR_MISS_CONFIG
    end
    return true, list[dun_id]
end
---------退出副本相关
----主动退出副本
function quit_dun(data)
    if is_on_dun() then
        local player_info = GetPlayer()
        apply_to_dun(dun.dun_pid, dun.is_cls, "quit_dun", player_info.id, player_info.node)
    else
        net.write(20002, {res = ERROR_NOT_ON_DUN})
    end
end

----副本进程拉玩家退出副本
function dun.pull_out_dungeon(args)
    if args.dun_pid == dun.dun_pid then
        log_print("pull_out_dungeon")
        reset_dun_data()
        net.write(20002, {res = ERROR_SUCCESS})
    else
        net.write(20002, {res = ERROR_FAIL})
    end
end
---------------------内部函数
--重置副本数据
function reset_dun_data()
    dun.dun_id = 0
    dun.is_cls = false
    dun.dun_pid = nil
    dun.is_cls = 0
    dun.other = {}
end

--发送消息给副本服务
function apply_to_dun(pid, is_cls, cmd, ...)
    if is_cls then
        clusters_api.apply("center_node", pid, cmd, ...)
    else
        skynet.send(pid, "lua", cmd, ...)
    end
end

--是否在副本中
function is_on_dun()
    return dun.dun_id and dun.dun_id > 0
end

return dun