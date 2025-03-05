local skynet = require "skynetex"
local queue = require "skynet.queue"
require "common.etool"
local pt = require "player.player_handle"

local q = queue()
local CMD = {}

function CMD.test()
    local i = 0
    while true do
        skynet.sleep(150)
        pt.cmd_handle(10011, {})
        i = i + 1
        etool_test(i)
    end
end

skynet.start(function()
    --服务的消息处理
    skynet.dispatchex("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("test service err:", f, err)
        end
    end)
end)