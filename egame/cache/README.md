# redis层的使用，涉及持久化的数据(非联表)用封装好的cache层

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

## 使用规则
### 第一步. 添加配置

--配置1
尽量把同个功能的表放在同一个配置，一个配置会启动一个服务管理管理数据

1. 新建模块，cache.conf.cache_模块.lua

2. 参考cache_player.lua
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
            ["index"] = {"player_id", "skin_id"},
            ["field"] = {"player_id", "skin_id", "data"},
            ["json"] = {"data"}
        }       
    end
    return nil
end

return cache
```

--配置2 
打开cache.cache_config.lua

1. 添加宏定义
    CACHE_关键字 = 3
    ....
2. 添加索引
    CACHE_关键字 = "cache.conf.cache_模块"

### 第二步 如何使用

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