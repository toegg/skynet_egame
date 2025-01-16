local skynet = require "skynetex"
local sharedata = require "skynet.sharedata"
require "common.etool"
local misc = require "common.misc"
local pt = require "net.pt"
require "player.player_base"
local pe = require "event.player_event"
require "def.def_event"
require "def.def_msg_type"
local net = require "net.net"
require "def.def_error"

local player_handle = {}

--功能处理定义
-- key：def_msg_type宏定义；val：对应模块
local handler = {
    [MSG_TYPE_DUN] = "dungeon.dungeon_handle",
    [MSG_TYPE_NET] = "net.net"
}

--协议请求处理
function player_handle.cmd_handle(cmd, data)
    if cmd == 10001 then 
        --登录
        player_login(cmd, data)
    elseif cmd == 10002 then  
        --注册
        player_reg(cmd, data)
    elseif cmd == 10010 then  
        --测试
        net.write(cmd, data)
    end
end

--监听事件回调处理
function player_handle.handle_event(event, ...)
    log_print("player_handle.handle_event:", event, ...)
end

--功能处理消息
function player_handle.handle(mod, func, ...)
    if handler[mod] then
        local h = skynet.load(handler[mod])
        h[func](...)
    end
end

----------------------------------内部处理
--登录成功
function player_login(cmd, data)
    local player_info = GetPlayer()
    --已登录，不处理
    if player_info.id then
        return
    end

    local packData = nil
    --先判断是否延迟登出，用回旧的玩家进程
    local oldPid = player_handle.get_player_online_pid(data.role_id)
    if oldPid then
        log_print("player reconect:", data.role_id) 
        net.write(cmd, {res = ERROR_SUCCESS})
        if player_info.gate then
            local res = skynet.call(player_info.gate, "lua", "player_reconnect", player_info.socket_fd, oldPid)
            if res then
                skynet.exit()
                return   
            end         
        end 
    end
    --继续往下走登录流程
    if PlayerLogin(data.role_id, skynet.self()) then
        --注册服务别名
        local player_info = GetPlayer()
        log_print("player login:", player_info.id)
        misc.register_role_fd(skynet.self(), player_info.id)
        --设置在线信息
        player_handle.set_player_online(player_info)
        --注册事件
        pe.init_event(player_info.id)
        --派发事件
        pe.event_dispatch(EVENT_LOGIN)
        net.write(cmd, {res = ERROR_SUCCESS})
    else
        log_print("player login fail")
        --响应客户端   
        net.write(cmd, {res = ERROR_FAIL})
        --关闭连接
        local player_info = GetPlayer()
        if player_info.gate then
            skynet.send(player_info.gate, "lua", "connect_force_close", player_info.socket_fd)
        end       
        skynet.exit()
    end
end

--玩家注册
function player_reg(cmd, data)
    local role_id, res = PlayerReg()
    if res then
        net.write(cmd, {res = ERROR_SUCCESS, role_id = role_id})
    else
        net.write(cmd, {res = ERROR_FAIL, role_id = 0})
    end
end

--玩家在线信息存储到共享内存
function player_handle.set_player_online(player_info)
    local onlines = sharedata.deepcopy("player_onlines")
    onlines[player_info.id] = {id = player_info.id, pid = player_info.pid}
    sharedata.update("player_onlines", onlines)
end

--获取玩家进程信息
function player_handle.get_player_online_pid(role_id)
    local onlines = sharedata.query("player_onlines")
    if onlines[role_id] then
        return onlines[role_id].pid
    end
    return nil
end

--移除玩家在线信息
function player_handle.remove_player_online(role_id)
    local onlines = sharedata.deepcopy("player_onlines")
    onlines[role_id] = nil
    sharedata.update("player_onlines", onlines)
end

return player_handle