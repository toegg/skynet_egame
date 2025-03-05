local skynet = require "skynet"

--按需加载模块，避免重复加载
function skynet.load(name)
    if package.loaded[name] then
        return package.loaded[name]
    else    
        return require(name)
    end
end

--全局方法热更
local function __reload_global( script_str, ... )
    print(string.format("[skynet __reload_global] service:%s", skynet.self()))
    local param = {...}
    local ok, data = xpcall(function(...)  
        local func = load(script_str)
        if func then 
            func(...)
        else
            assert(false)
        end 
    end, debug.traceback)
    if data ~= nil then
        print(string.format("[skynet __reload_global] service:%s fail:%s", skynet.self(), data))
    end
    skynet.ret(skynet.pack(ok))
end

--local方法热更
local function __reload_local( script_str, m, f, ... )
    print(string.format("[skynet __reload_local] service:%s", skynet.self()))
    local param = {...}
    local ok, data = xpcall(function()  
        local mod = require(m)
        local func = load(script_str)
        if func then 
            mod[f] = func()  
        else
            assert(false)
        end 
    end, debug.traceback)
    if data ~= nil then
        print(string.format("[skynet __reload_local] service:%s fail:%s", skynet.self(), data))
    end
    skynet.ret(skynet.pack(ok))
end

-- 这个接口的服务才能使用热更接口
function skynet.dispatchex(typename, func)
    local function funcex(session, source, cmd, ...)
        if typename == "lua" and cmd == "__reload_global" then
            __reload_global( ... ) 
        elseif typename == "lua" and cmd == "__reload_local" then
            __reload_local( ... ) 
        else
            func(session, source, cmd, ...)
        end 
    end 

    --使用热更服务，加入热更服务列表
    skynet.send(".hotfix", "lua", "add", skynet.self())

    skynet.dispatch(typename, funcex)
end

return skynet