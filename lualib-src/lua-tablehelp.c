#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>

// 这个宏用于检查参数是否为nil
#define ISNIL(L, index) (lua_isnil(L, index))

void print_stack1(lua_State *L);
void print_val(lua_State *L, int index, char *str);
void print_table_handle(lua_State *L, int index);

// 获取Lua的长度
static int table_len(lua_State *L) {
    // 检查参数是否为table
    if (!lua_istable(L, 1)) {
        luaL_error(L, "expected table");
        return 0; // 在发生错误时返回0
    }

    int len = 0; // 初始化长度计数器
    lua_pushnil(L); // 将nil推入栈，用于pairs()

    // 遍历Lua表
    while (lua_next(L, 1)) { 
        if (!ISNIL(L, -2)) { // 如果键不是nil（即数组部分）
            len++; // 增加长度计数器
        }
        
        lua_pop(L, 1); // 弹出值（因为我们不需要它）
    }
    
    lua_pushinteger(L, len); // 将长度推入Lua栈
    return 1; // 返回值的数量
}

// 是否在table中
static int is_in_table(lua_State *L) {
    if (lua_gettop(L) != 2) {
        luaL_error(L, "expected 2 arguments");
        return 0;
    }

    // 检查第一个参数是否为表
    if (!lua_istable(L, 1)) {
        luaL_error(L, "expected table");
        return 0;
    }

    // 将 nil 推入栈，用于 pairs()
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        if (lua_compare(L, -1, 2, LUA_OPEQ)) {  // 比较表中的值与目标值
            lua_pushboolean(L, 1);  // 返回 true
            return 1;
        }
        // 弹出值，保留键
        lua_pop(L, 1);
    }

    // 如果未找到匹配项，返回 0
    lua_pushboolean(L, 0);
    return 1;
}

// 是否在table中，自带func
static int is_in_table_func(lua_State *L){
    int top = lua_gettop(L);  // 获取堆栈的大小
    if (top < 3) {
        luaL_error(L, "expected 3 arguments");
        return 0;
    }
    if (!lua_istable(L, 1)) {
        luaL_error(L, "expected table");
        return 0;
    }

    if (!lua_isfunction(L, 2)) {
        luaL_error(L, "expected table");
        return 0;
    }

    //函数参数个数
    int func_args = top - 2;
    int i;

    // 遍历table
    lua_pushnil(L);  // 将nil压入栈，作为遍历的起始值

    while (lua_next(L, 1)) {
        // 此时栈顶是value，次顶是key
        // 将key和value传递给函数
        lua_pushvalue(L, 2);  // 将函数压入栈
        lua_pushvalue(L, -3);  // 将key压入栈
        lua_pushvalue(L, -3);  // 将value压入栈
        for (i = 0; i < func_args; i++)
        {
            lua_pushvalue(L, 3 + i);
        }
        

        // 调用函数
        if (lua_pcall(L, 2 + func_args, 1, 0) != LUA_OK) {
            luaL_error(L, "Error calling function: %s", lua_tostring(L, -1));
            return 0;
        }
        // 检查返回值
        if (lua_toboolean(L, -1)) {
            lua_pushboolean(L, 1);
            return 1;
        }

        lua_pop(L, 2);  // 弹出value和返回值，保留key用于下一次迭代
    }
    lua_pushboolean(L, 0);
    return 1;
}

// 从table中获取值
static int get_in_table(lua_State *L) {
    if (lua_gettop(L) != 2){
        luaL_error(L, "expected 2 arguments");
        return 0;
    }

    // 检查第一个参数是否为表
    if (!lua_istable(L, 1)) {
        luaL_error(L, "expected table");
        return 0;
    }

    // 将 nil 推入栈，用于 pairs()
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        if (lua_compare(L, -1, 2, LUA_OPEQ)) {
            lua_pushvalue(L, -1);
            return 1;
        }
        lua_pop(L, 1);
    }
    lua_pushnil(L);
    return 1;
}

// 输出table
static int print_table(lua_State *L) {
    if (lua_gettop(L) != 1) {
        luaL_error(L, "expected 1 argument");
        return 0;
    }

    if (lua_istable(L, 1)) {
        print_table_handle(L, 1);
    }

    return 1;
}

// 从table中获取值，自带func
static int get_in_table_func(lua_State *L) {
    int top = lua_gettop(L);  // 获取堆栈的大小
    if (top < 3) {
        luaL_error(L, "expected 3 arguments");
        return 0;
    }
    if (!lua_istable(L, 1)) {
        luaL_error(L, "expected table");
        return 0;
    }

    if (!lua_isfunction(L, 2)) {
        luaL_error(L, "expected table");
        return 0;
    }

    //函数参数个数
    int func_args = top - 2;
    int i;

    // 遍历table
    lua_pushnil(L);  // 将nil压入栈，作为遍历的起始值
    while (lua_next(L, 1)) {
        lua_pushvalue(L, 2);
        lua_pushvalue(L, -3);
        lua_pushvalue(L, -3);
        for (i = 0; i < func_args; i++)
        {
            lua_pushvalue(L, 3 + i);
        }

        if (lua_pcall(L, 2 + func_args, 1, 0) != LUA_OK) {
            luaL_error(L, "Error calling function: %s", lua_tostring(L, -1));
            return 0;
        }

        if (lua_toboolean(L, -1)) {
            lua_pushvalue(L, -2);
            return 1;
        }
        lua_pop(L, 2);
    }
    lua_pushnil(L);
    return 1;
}

// 从table中移除
static int remove_in_table(lua_State *L){
    if (lua_gettop(L) != 2){
        luaL_error(L, "expected 2 arguments");
        return 0;
    }

    // 将 nil 推入栈，用于 pairs()
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        if (lua_compare(L, -1, 2, LUA_OPEQ)) {
            lua_pushvalue(L, -2);
            lua_pushnil(L);
            lua_settable(L, 1);
        }
        lua_pop(L, 1);
    }

    lua_pushvalue(L, 1);
    return 1;
}

// 库初始化函数，注册lua函数
int luaopen_tablehelp(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"table_len", table_len},
        {"is_in_table", is_in_table},
        {"is_in_table_func", is_in_table_func},
        {"get_in_table", get_in_table}, 
        {"remove_in_table", remove_in_table},
        {"get_in_table_func", get_in_table_func},
        {"print_table", print_table},
        {NULL, NULL}
    };

    luaL_newlib(L, l);
    return 1;
}

void print_stack1(lua_State* L) {
    int top = lua_gettop(L);  // 获取堆栈的大小
    printf("Stack size: %d\n", top);
    int i;
    for (i = 1; i <= top; i++) {
        int type = lua_type(L, i);  // 获取堆栈中第 i 个值的类型
        switch (type) {
            case LUA_TSTRING:  // 字符串
                printf("  [%d] STRING: %s\n", i, lua_tostring(L, i));
                break;
            case LUA_TNUMBER:  // 数字
                printf("  [%d] NUMBER: %f\n", i, lua_tonumber(L, i));
                break;
            case LUA_TBOOLEAN:  // 布尔值
                printf("  [%d] BOOLEAN: %s\n", i, lua_toboolean(L, i) ? "true" : "false");
                break;
            case LUA_TNIL:  // nil
                printf("  [%d] NIL\n", i);
                break;
            case LUA_TFUNCTION:  // 函数
                printf("  [%d] FUNCTION\n", i);
                break;
            case LUA_TTABLE:  // 表
                printf("  [%d] TABLE\n", i);
                break;
            default:
                printf("  [%d] UNKNOWN\n", i);
                break;
        }
    }
}

void print_val(lua_State *L, int index, char *str) {
    int type = lua_type(L, index);
    switch (type)
    {
    case LUA_TSTRING:
        printf("%s=%s\n", str, lua_tostring(L, index));
        break;         
    case LUA_TNUMBER:  // 数字
        printf("%s=%f\n", str, lua_tonumber(L, index));
        break;   
    default:
        break;
    }
}

void print_table_handle(lua_State *L, int index) {
    lua_pushnil(L);
    if (index != 1) {
        index--;
    }
    while (lua_next(L, index)) {
        // 此时栈顶是value，次顶是key
        print_val(L, -2, "key");
        if (lua_istable(L, -1)){
            print_table_handle(L, -1);
        }else{
            print_val(L, -1, "val");
        }
        lua_pop(L, 1);
    }
}