local skynet = require "skynet"

--按需加载模块，避免重复加载
function skynet.load(name)
    if package.loaded[name] then
        return package.loaded[name]
    else
        return require(name)
    end
end

return skynet