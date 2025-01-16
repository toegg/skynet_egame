local skynet = require "skynetex"
local socket = require "skynet.socket"
require "player.player_base"
local pt = require "net.pt"
require "common.etool"

local net = {}

-----功能处理(注意，对应的模块处理协议方法约定是: 模块.cmd_handle(cmd, data))
-- key：协议前三位；val：对应模块
local handler = {
    [100] = "player.player_handle",
    [200] = "dungeon.dungeon_handle"
}

--接收客户端请求
function net.read(cmd, data)
    local pre_cmd = math.floor(cmd / 100) 
    if handler[pre_cmd] then
        --非100协议需要是登录状态才可以
        local player_info = GetPlayer()
        if pre_cmd ~= 100 and player_info.id <= 0 then
            return 
        end
        local mod = skynet.load(handler[pre_cmd])
        mod.cmd_handle(cmd, data)
    end
end

--响应给客户端
function net.write(cmd, data)
    local packData = pt.write(cmd, data)
    local player_info = GetPlayer()
    if player_info.gate then
        skynet.send(player_info.gate, "lua", "msg_response", player_info.socket_fd, packData)
    end
end

return net