### 在[上一篇的基础上](https://blog.csdn.net/toegg/article/details/145190176)做了改进，主要三个更新：

1. 基础框架引入多一层redis缓存，用于持久化数据，加速数据访问。原本需要通过mysql读取的操作，直接改成与redis层交互，redis会自动写入mysql，保证AP 最终一致性。
2. 引入热更新机制，通过inject指令操作脚本更新全局和local方法
3. 用C封装实现**table**没提供的常用操作，比如**某个元素是否在table中**is_in_table等等几个接口，压测接口500w，性能提高了百分10%左右。

### 目录结构小调整：
    egame  
    --cache         redis缓存层机制
    --clusters      跨服和游戏服节点服务  
    --common        公共方法  
    --data          游戏配置  
    --db            mysql连接池和redis池服务  
    --def           宏定义  
    --dungeon       副本功能逻辑  
    --event         玩家事件  
    --id_create     全局唯一id服务  
    --listen        socket服务  
    --net           网络协议解析  
    --player        玩家服务和逻辑  
    --server        节点初始化服务  

### 主要的3部分调整

#### 第一部分 -- 引入redis缓存
**用hash类型存储**  

--key主要有4种：  

----第一种：mysql表数据对应的主键  

`` key:index_表名;  field:main_index;  val:indexList``
其中**main_index**一般是主键，而联合主键的main_index就是联合主键中的主要字段，比如玩家对应多条装备数据，则用玩家id作为main_index  
**indexList**则是对应的主键列表，用table格式序列化成json

----第二种：主键对应的具体数据
``key:rec_表名;  field:index;  val:表行所有数据``

----第三种：脏数据，待写入mysql
``key:dirty_表名;  field:index; val:1(删除);0(写入)``

----第四种：清表
``key:dirty_truncate_all;  field:表名;  val:清除类型1(truncate);0(delete)``

**使用规则**   

第一步. 添加配置

配置1
尽量把同个功能的表放在同一个配置，一个配置会启动一个服务管理管理数据

1. 新建模块，cache.conf.cache_模块.lua

2. 参考cache_dungeon.lua
```lua
local cache = {}

function cache.tables()
    return {"mysql表名1", "mysql表名2"...}
end

function cache.table(tab)
    if tab == "mysql表名1" then
        return {
            ["main_index"] = "主要的主键字段，一般玩家id",
            ["index"] = {"完整的主键字段, 联合主键就用逗号隔开"},
            ["field"] = {"所有字段，用逗号隔开"},
            ["json"] = {"table形式等长文本需要json解析的，多个用逗号隔开"}
        }
    elseif tab == "mysql表名2" then
        return {
            ["main_index"] = "player_id",
            ["index"] = {"player_id", "dun_id"},
            ["field"] = {"player_id", "dun_id", "data"},
            ["json"] = {"data"}
        }       
    end
    return nil
end

return cache
```

配置2 
打开cache.cache_config.lua

1. 添加宏定义
    CACHE_关键字 = 3
    ....
2. 添加索引
    CACHE_关键字 = "cache.conf.cache_模块"

第二步 如何使用

查询，插入/更新，删除，清表操作
```lua
    --获取多条表数据(res是table，没数据则为空)
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "fetch", "mysql表名", "main_index字段值")
    --获取单条表数据(res是table，没数据则为空)
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "fetch", "mysql表名", "main_index字段值")
    print_table(res[1])


    --插入数据（res对应def.def_error.lua定义的错误码）
    local info = {player_id = 1, dun_id = 1001, data = {1, 2, 3, 4}}
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "replace", "mysql表名", info)
    log_print(res)

    --更新数据（res对应def.def_error.lua定义的错误码）
    info.data = {1, 2}
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "replace", "mysql表名", info)
    log_print(res)   


    --删除表对应main_index的多条数据（res对应def.def_error.lua定义的错误码）
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "delete", "mysql表名", "main_index字段值", "all")
    log_print(res)
    --删除表对应的单条数据（res对应def.def_error.lua定义的错误码）
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "delete", "mysql表名", "main_index字段值", {"index的字段值1", "index的字段值2"})
    log_print(res)


    --清表 
    ----最后一个参数，1表示用 delete清表；2表示用 truncate清表
    ----（res对应def.def_error.lua定义的错误码）
    local res = skynet.call(skynet.localname(".cache.conf.cache_模块"), "lua", "delete_all", "mysql表名", 1)
    log_print(res)
```
***
#### 第二部分 -- 引入热更新机制

`hotfix_api.lua`是热更脚本，有热更内容通过改脚本实现

**支持热更的流程步骤：**

第一步：服务要引入skynetex, 
`local skynet = require "skynetex"`

第二步：服务初始化用 `skynet.dispatchex` 代替 `skynet.dispatch`

第三步：
    在`hotfix_api`模块下写热更脚本，`CMD.reloads[script_str] = reloadInfo`
其中 `script_str`是对应函数方法的字符串格式
其中 `reloadInfo` 的格式：
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

可以参考`hotfix_api.lua`已有的脚本

#### 第三部分 -- C封装table的相关操作
    源码在工程目录的lualib-src的lua-tablehelp.c
    主要封装了7个接口，对应common.etool中的7个方法
```c
        {"table_len", table_len},
        {"is_in_table", is_in_table},
        {"is_in_table_func", is_in_table_func},
        {"get_in_table", get_in_table}, 
        {"remove_in_table", remove_in_table},
        {"get_in_table_func", get_in_table_func},
        {"print_table", print_table},
```

### 额外：  
  
    简单练手的搭建，写得粗暴，有问题的话请见谅或反馈
