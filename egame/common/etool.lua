local skynet = require "skynet"
local os = require "os"
local sharedata = require "skynet.sharedata"
local tablehelp = require "tablehelp"

--获取周开始时间戳
function get_week_start_time()
    -- 获取当前时间戳（秒）
    local current_timestamp = skynet.time()
    -- 将时间戳转换为Lua时间表
    local current_time = os.date("*t", math.floor(current_timestamp))

    -- 计算周开始时间
    -- 周一为一周的开始，os.date("*t")返回的`wday`字段表示星期几，其中周日为1，周一为2，以此类推
    local start_day = current_time.wday - 2
    if start_day == 1 then -- 如果是周日，周开始时间就是周日的0点
        start_day = 7
    end
    -- 减去当前天数与周开始天数的差值
    current_time.day = current_time.day - start_day

    -- 获取周开始时间的时间戳
    local week_start_timestamp = os.time(current_time) - (current_time.hour * 3600 + current_time.min * 60 + current_time.sec)

    return week_start_timestamp
end

--获取table长度(hashmap的table)
function table_len(arr)
    -- if type(arr) ~= "table" then
    --     return 0
    -- end

    -- local len = 0
    -- for k, v in pairs(arr) do
    --     len = len + 1
    -- end   
    -- return len
    return tablehelp.table_len(arr)
end

--判断是否在table中
function is_in_table(arr, val)
    -- if type(arr) ~= "table" then
    --     return false
    -- end

    -- for k, v in pairs(arr) do
    --     if v == val then
    --         return true
    --     end
    -- end
    -- return false
    return tablehelp.is_in_table(arr, val)
end

--判断是否在table中
function is_in_table_func(arr, func, ...)
    -- if type(arr) ~= "table" then
    --     return false
    -- end

    -- for k, v in pairs(arr) do
    --     if func(k, v, ...) then
    --         return true
    --     end
    -- end
    -- return false
    return tablehelp.is_in_table_func(arr, func, ...)
end

--从table中获取
function get_in_table(arr, val)
    -- if type(arr) ~= "table" then
    --     return nil
    -- end

    -- for k, v in pairs(t) do
    --     if v == val then
    --         return v
    --     end
    -- end
    -- return nil
    return tablehelp.get_in_table(arr, val)
end

--从table中获取
function get_in_table_func(arr, func, ...)
    -- if type(arr) ~= "table" then
    --     return nil
    -- end

    -- for k, v in pairs(arr) do
    --     if func(k, v, ...) then
    --         return v
    --     end
    -- end
    -- return nil
    return tablehelp.get_in_table_func(arr, func, ...)
end

--从table中移除
function remove_in_table(arr, val)
    -- if type(arr) ~= "table" then
    --     return nil
    -- end
    
    -- for k, v in pairs(arr) do
    --     if v == val then
    --         table.remove(arr, k)
    --     end       
    -- end
    -- return arr
    return tablehelp.remove_in_table(arr, val)
end

--输出table
function print_table(arr)
    -- if type(arr) == "table" then
    --     for k, v in pairs(arr) do
    --         if type(v) == "table" then
    --             print("key=", k, "val=")
    --             print_table(v)
    --         else
    --             print("key=", k, "val=", v)
    --         end
    --     end
    -- end
    tablehelp.print_table(arr)
end

--获取对应的key
function get_key(val) 
    if type(val) == "number" then
        return tostring(val)
    end
    return val
end

--分割字符串
function spilt(str, pattern) 
    local data = {}
    for part in str:gmatch("[^"..pattern.."]+") do
        table.insert(data, part)
    end
    return data
end

--带时间的输出
function log_print(argsText, ...)
    local info = debug.getinfo(2, "Sl")  -- 获取调用者的信息
    if info then
        skynet.pcall(function(...)
            local logInfo = sharedata.query("logInfo")
            local str = ""
            if logInfo.log then
                --重定向到日志文件，会自带时间，就不加自定义时间格式
                str = string.format("[%s:%d] %s:", info.short_src, info.currentline, argsText) 
            else
                --标准输出，需要自定义时间格式
                local current_sec = skynet.time()
                local data = os.date("*t", math.floor(current_sec))
                str = string.format("%d-%d-%d %d:%d:%d [%s:%d] %s:", data.year, data.month, data.day, data.hour, data.min, data.sec, info.short_src, info.currentline, argsText) 
            end
            skynet.error(str, ...)
        end, ...)
    else
        skynet.error(argsText, ...)
    end
end

--随机整数
function rand(min, max)
    math.randomseed(os.time())
    return math.random(min, max)
end

function etool_test(val)
    log_print("etool_test:", val)
end