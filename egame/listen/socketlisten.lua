local skynet = require "skynet"
local socket = require "skynet.socket"
local pt = require "net.pt"
require "common.etool"

--dispatch处理指令
local CMD = {}
--客户端连接表
local clients = {}

--开启连接
local function client_connect(fd, addr)
    log_print("client connect is", addr)
    skynet.fork(function()
        --客户端信息存储
        local clientInfo = {}
        clientInfo.addr = addr
        clientInfo.pid = skynet.newservice("player")
        clients[fd] = clientInfo
        skynet.send(clientInfo.pid, "lua", "socket_connect", fd, skynet.self(), addr)
        --开始接受消息
        socket.start(fd)
        socket.onclose(fd, client_close)
        msg_receive(fd)
    end)
end

--关闭连接
function client_close(fd)
    log_print("client connect is close")
    if clients[fd] then
        skynet.send(clients[fd].pid, "lua", "delay_logout")
    end
    clients[fd] = nil
end

--接收socket请求消息
function msg_receive(fd)
    while true do
        --解析协议号cmd，4字节
        local receiveData = socket.read(fd, 4)
        if not receiveData then
            -- log_print("Connection closed or error occurred")
            break
        end 
        -- >代表大端序，I表示无符号整数
        local cmd = string.unpack('>I', receiveData)
        log_print("receive cmd :", cmd)

        local data = pt.read(fd, cmd)

        -- 通知玩家进程处理
        if clients[fd] then
            skynet.send(clients[fd].pid, "lua", "cmd_read", cmd, data)
        end
    end
end

--接收socket响应消息
function CMD.msg_response(source, fd, packData)
    if packData ~= nil then
        socket.write(fd, packData) 
    end
end

--重连更新玩家进程信息
function CMD.player_reconnect(source, fd, pid)
    if clients[fd] then
        local res = skynet.call(pid, "lua", "reconnect")
        if res then
            clients[fd].pid = pid
            skynet.ret(skynet.pack(true))
            return 
        end
        skynet.ret(skynet.pack(false))
    else
        skynet.ret(skynet.pack(false))
    end 
end

--强制关闭连接
function CMD.connect_force_close(source, fd)
    socket.close(fd)
    skynet.ret(skynet.pack(true))
end

--初始化服务
skynet.start(function()
    log_print("esocket listen start")
    -- 启动监听
    local listenFd = socket.listen(skynet.getenv("socket_ip"), skynet.getenv("socket_port"))
    socket.start(listenFd, client_connect)
    
    -- 注册skynet.dispatch处理函数
    skynet.dispatch("lua", function (session, source, cmd, ...) 
        local f = assert(CMD[cmd])
        local status, err = skynet.pcall(f, source, ...)
        if not status then
            log_print("socketlisten service err:", f, err)
        end
    end)

    --收集info信息
    skynet.info_func(function()
        return clients
    end)
end)