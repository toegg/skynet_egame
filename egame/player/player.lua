local skynet = require "skynetex"
local queue = require "skynet.queue"
require "common.etool"
require "player.player_base"
local player_handle = require "player.player_handle"
local net = require "net.net"

local q = queue()
local CMD = {}
local DelayLogoutTime = 20

--socket连接信息
function CMD.socket_connect(socket_fd, gate, addr)
    PlayerSet({socket_fd = socket_fd, gate = gate, addr = addr})
    --20s内没有请求登录则强制关闭
    skynet.timeout(DelayLogoutTime * 100, CMD.force_close)
end

--重连
function CMD.reconnect()
    player_handle.reconnect()
    skynet.ret(skynet.pack(true))
end

--延迟登出游戏
function CMD.delay_logout()
    local player_info = GetPlayer()
    log_print("game role delay_logout:", player_info.id)
    player_handle.delay_logout()
    skynet.timeout(DelayLogoutTime * 100, CMD.logout)
end

--登出游戏
function CMD.logout()
    local player_info = GetPlayer()
    if player_info.online <= 0 then
        log_print("game role logout:", player_info.id)
        player_handle.logout()
        skynet.exit() 
    end
end

--超时没登录强制关闭
function CMD.force_close()
    local player_info = GetPlayer()
    if not player_info.id or player_info.id <= 0 then
        if player_info.gate then
            skynet.send(player_info.gate, "lua", "connect_force_close", player_info.socket_fd)
        end    
        skynet.exit()
    end 
end

--接收到功能处理消息
function CMD.handle(mod, func, ...)
    local res = player_handle.handle(mod, func, ...)
    if res ~= nil then
        skynet.ret(skynet.pack(res))
    end
end

--接收到协议
function CMD.cmd_read(cmd, data)
    net.read(cmd, data)
end

--初始化服务
skynet.start(function(...)
    -- 注册skynet.dispatch处理函数
    skynet.dispatchex("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("player service err:", f, err)
        end
    end)
end)
