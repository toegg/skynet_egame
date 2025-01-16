local socket = require "skynet.socket"
local skynet = require "skynet"
require "common.etool"

local pt = {}

-- i: 有符号整数, 对应lua中的number
-- I: 无符号整数，对应lua中的number
-- b：有符号字节（char），对应Lua中的number。
-- B：无符号字节（unsigned char），对应Lua中的number。
-- h：有符号短整型（short），对应Lua中的number。
-- H：无符号短整型（unsigned short），对应Lua中的number。
-- l：有符号长整型（long），对应Lua中的number。
-- L：无符号长整型（unsigned long），对应Lua中的number。
-- f：单精度浮点数（float），对应Lua中的number。
-- d：双精度浮点数（double），对应Lua中的number。
-- x：填充字节（用于对齐），不返回值。
-- X：反向填充字节（用于对齐），不返回值。
-- s：零终止的字符串（char *），对应Lua中的string。
-- z：长度为前面指定值的零终止字符串，对应Lua中的string。
-- p：指针（void *），对应Lua中的number（通常是地址）。

------------------------------协议的读
function pt.read(fd, cmd)
    -- 解析数据长度，4字节
    local lenData = socket.read(fd, 4)
    if not lenData then
        return false
    end
    local length = string.unpack('>I', lenData)
    -- log_print("length:", length)
    if length <= 0 then 
        --空数据的，直接派发
        return pt_dispatch(cmd, {}) 
    else
        -- 解析数据
        local list = socket.read(fd, length)
        if not list then 
            return false 
        end 
        return pt_dispatch(cmd, list) 
    end
end

function pt_dispatch(cmd, list)
    -- 根据协议到不同分支处理
    local pre_cmd = math.floor(cmd / 100) 
    if pre_cmd == 100 then
        return pt_100_read(cmd, list)
    elseif pre_cmd == 200 then
        return pt_200_read(cmd, list)
    end
end

function pt_100_read(cmd, list)
    -- log_print("list", list)
    if cmd == 10001 then
        local role_id = string.unpack(">I8", list)
        log_print("10001 - role_id:", role_id)
        return {role_id = role_id}   
    elseif cmd == 10002 then
        log_print("10002 - :")
        return {} 
    elseif cmd == 10010 then
        local strlen = string.unpack(">I2", list)  
        local msg = string.sub(list, 3)
        log_print("10010 - data_len:", strlen)
        log_print("10010 - data_msg:", msg)
        return {msg = msg}
    end
end

function pt_200_read(cmd, list)
    if cmd == 20001 then
        local dun_id = string.unpack(">I", list)
        log_print("20001 - dun_id:", dun_id)
        return {dun_id = dun_id}
    elseif cmd == 20002 then
        log_print("20002 - ")
        return {}      
    elseif cmd == 20018 then
        local dun_id = string.unpack(">I", list)
        log_print("20018 - dun_id:", dun_id)
        return {dun_id = dun_id}
    end   
end

------------------------------协议的写
function pt.write(cmd, data)
    local pre_cmd = math.floor(cmd / 100) 
    if pre_cmd == 100 then
        return pt_100_write(cmd, data)
    elseif pre_cmd == 200 then
        return pt_200_write(cmd, data)
    end
end

function pt_100_write(cmd, data)
    local pack_data = nil
    if cmd == 10001 then
        pack_data = string.pack(">I", data.res)
    elseif cmd == 10002 then
        pack_data = string.pack(">I>I8", data.res, data.role_id)
    elseif cmd == 10010 then
        local args1_len = string.pack(">I2", #data.msg)
        pack_data = args1_len..data.msg
    end
    return pt.pack(cmd, pack_data)
end

function pt_200_write(cmd, data)
    local pack_data = nil
    if cmd == 20001 then
        pack_data = string.pack(">I", data.res)
    elseif cmd == 20002 then
        pack_data = string.pack(">I", data.res)
    elseif cmd == 20018 then
        local args1 = string.pack(">I", data.dun_id)
        local args2_len = string.pack(">I2", #data.role_list)
        local args3 = ""
        pack_data = args1..args2_len
        for k, v in pairs(data.role_list) do
            args3 = args3..string.pack(">I8>I", v.role_id, v.time)
        end
        pack_data = pack_data..args3
    end
    return pt.pack(cmd, pack_data)
end

function pt.pack(cmd, pack_data)
    return string.pack(">I>I", cmd, #pack_data)..pack_data
end

return pt