hotfix_api.lua是热更脚本，有热更内容通过改脚本实现

## 支持热更的流程步骤：

第一步：服务要引入skynetex, 
`local skynet = require "skynetex"`

第二步：服务初始化用 skynet.dispatchex 代替 skynet.dispatch

第三步：
    在hotfix_api模块下写热更脚本，CMD.reloads[script_str] = reloadInfo
其中 *script_str* 是对应函数方法的字符串格式
其中 *reloadInfo* 的格式：
```lua
local typeReloadGlobal, typeReloadLocal = 1, 2
local reloadInfo = {
    type = nil,     --热更的方法类型. typeReloadGlobal | typeReloadLocal
    m = nil,        --local方法的模块名
    f = nil         --local方法的方法名
}
```

第四步：进入节点的debug_console控制台, 找到hotfix服务的地址

第五步：执行热更脚本，格式为：inject :地址 egame/hotfix/hotfix_api.lua

### 可以参考hotfix_api.lua已有的脚本