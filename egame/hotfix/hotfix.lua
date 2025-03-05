local skynet = require "skynet"
local queue = require "skynet.queue"
require "skynet.manager"
require "common.etool"

local q = queue()
local CMD = {}
local pidMap = {}
CMD.reloads = {}

function CMD.add(pid)
    pidMap[pid] = 1
end

function check_reload()
    skynet.timeout(200, function()
        check_reload()
        if table_len(CMD.reloads) > 0 then
            for k, v in pairs(CMD.reloads) do
                if v.type == 1 then
                    for kk, vv in pairs(pidMap) do
                        skynet.send(kk, "lua", "__reload_global", k)
                    end
                else
                    for kk, vv in pairs(pidMap) do
                        skynet.send(kk, "lua", "__reload_local", k, v.m, v.f)
                    end
                end
            end
            CMD.reloads = {}
        end
    end)
end

--初始化服务
skynet.start(function(...)
    skynet.name(".hotfix", skynet.self())
    skynet.fork(check_reload)
    -- 注册skynet.dispatch处理函数
    skynet.dispatch("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(q, f, ...)
        if not status then
            log_print("hotfix service err:", f, err)
        end
    end)
end)
