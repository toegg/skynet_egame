#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define TABLE_SIZE 0x1000  //4096
#define ETS_SIZE 0xFF      //255

char * parse_key(lua_State *L, int index);

// 标识不同数据类型
typedef enum {
    TYPE_TABLE,
    TYPE_INT,
    TYPE_STRING
} ValueType;

// 存储不同类型的数据
typedef union {
    struct HashNode *table_value;   //存放table
    long int_value;
    char* string_value;
} Value;

typedef struct{
    char* key;                      //key
    ValueType val_type;             //val数据类型
    Value val;                      //val数据
    struct HashNode * next;         //hash冲突的链表
    struct HashNode * next_node;    //val数据为table时, val.table_value使用链表
}HashNode;

typedef struct HashTable{
    char* name;                     //表名
    int capacity;                   //表容量，默认4096
    int size;                       //当前容量
    HashNode** table;               //哈希表
    pthread_mutex_t lock;           //锁
    struct HashTable * next;        //hash冲突的链表
}HashTable;

typedef struct{
    int capacity;                   //表容量，默认255
    int size;                       //当前容量
    HashTable** hash_table;
    pthread_mutex_t lock;           //锁
}EtsTable;

//全局变量，管理ets表
static EtsTable* ets_table;

unsigned int hash(const char* key, int capacity) {
    unsigned int hash = 0;
    while (*key) {
        hash = (hash << 5) + hash + *key++;
    }
    return hash % capacity;
}

//初始化ets库
static int linit(lua_State *L){
    pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (ets_table != NULL){
        luaL_error(L, "ets_table_already_init");
        goto linit_err;
    }

    int capacity;
    if (!lua_isinteger(L, 1)) {
        capacity = ETS_SIZE;
    }
    ets_table = (EtsTable*)malloc(sizeof(EtsTable));
    if (ets_table == NULL) {
        luaL_error(L, "ets_table_malloc_fail");
        goto linit_err;
    }
    ets_table->capacity = capacity;
    ets_table->size = 0;
    ets_table->hash_table = (HashTable**)malloc(sizeof(HashTable*) * capacity);
    if (ets_table->hash_table == NULL){
        luaL_error(L, "ets_table->hash_table_malloc_fail");
        free(ets_table);
        goto linit_err;
    }
    pthread_mutex_init(&ets_table->lock, NULL);

    lua_pushboolean(L, 1);
    pthread_mutex_unlock(&lock);
    pthread_mutex_destroy(&lock);
    return 1;

linit_err:
    pthread_mutex_unlock(&lock);
    pthread_mutex_destroy(&lock);
    return 0;
};


//创建ets
static int linit_ets(lua_State *L){
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);
    int capacity;
    if (!lua_isinteger(L, 2)) {
        capacity = TABLE_SIZE;
    }

    pthread_mutex_lock(&ets_table->lock);
    if (ets_table->size >= ets_table->capacity){
        luaL_error(L, "table_num_limit");
        goto linit_ets_error;
    }

    int index = hash(name, ets_table->capacity);
    HashTable* hash_table = (HashTable*)malloc(sizeof(HashTable));
    if (hash_table == NULL){
        luaL_error(L, "hash_table_malloc_fail");
        goto linit_ets_error;
    }
    hash_table->name = name;
    hash_table->capacity = capacity;
    hash_table->size = 0;
    hash_table->table = (HashNode**)malloc(sizeof(HashNode*) * capacity);
    if (hash_table->table == NULL){
        luaL_error(L, "hash_table->table_malloc_fail");
        free(hash_table);
        goto linit_ets_error;
    }
    pthread_mutex_init(&hash_table->lock, NULL);

    hash_table->next = ets_table->hash_table[index];
    ets_table->hash_table[index] = hash_table;
    ets_table->size++;
    pthread_mutex_unlock(&ets_table->lock);

    lua_pushboolean(L, 1);
    return 1;

linit_ets_error:
    pthread_mutex_unlock(&ets_table->lock);
    return 0;
}

//插入数据
static int linsert(lua_State *L){
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);
    char *key = parse_key(L, 2);
    luaL_checkany(L, 3);
    int index = hash(name, ets_table->capacity);
    HashTable *hash_table = ets_table->hash_table[index];
    while(hash_table){
        if (strcmp(hash_table->name, name) == 0) {
            pthread_mutex_lock(&hash_table->lock);
            if (hash_table->size >= hash_table->capacity){
                luaL_error(L, "size_limit");
                pthread_mutex_unlock(&hash_table->lock);
                return 0;
            }

            int key_index = hash(key, hash_table->capacity);
            HashNode *new_node = (HashNode *)malloc(sizeof(HashNode));
            if (new_node == NULL){
                luaL_error(L, "new_node_malloc_fail");
                pthread_mutex_unlock(&hash_table->lock);
                return 0;
            }
            new_node->key = key;
            parse_val(new_node, L, 3);
            new_node->next = hash_table->table[key_index];
            hash_table->table[key_index] = new_node;
            new_node->next_node = NULL; //val本身HashNode不用该值
            pthread_mutex_unlock(&hash_table->lock);
            lua_pushboolean(L, 1);
            return 1;
        }
        hash_table = hash_table->next;
    }
    lua_pushboolean(L, 0);
    return 1;
}

//查找数据
static int lsearch(lua_State *L) {
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);
    char *key = luaL_checkstring(L, 2);
    int index = hash(name, ets_table->capacity);
    HashTable *hash_table = ets_table->hash_table[index];
    while(hash_table){
        if (strcmp(hash_table->name, name) == 0) {
            int key_index = hash(key, hash_table->capacity);
            HashNode *node = hash_table->table[key_index];
            while(node){
                if (strcmp(node->key, key) == 0) {
                    get_val(L, node);
                    return 1;
                }
                node = node->next;
            }
        }
        hash_table = hash_table->next;
    }
    lua_pushnil(L);
    return 1;
}

//查找表所有数据
static int lsearch_all(lua_State *L) {
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);
    int index = hash(name, ets_table->capacity);
    HashTable *hash_table = ets_table->hash_table[index];
    lua_newtable(L);   
    while(hash_table){
        if (strcmp(hash_table->name, name) == 0) {
            int i;
            for (i = 0; i < hash_table->capacity; i++)
            {
                if (hash_table->table[i] == NULL) {
                    continue;
                }
                get_key(L, hash_table->table[i]->key);
                get_val(L, hash_table->table[i]);
                lua_settable(L, -3);
            }
            
        }
        hash_table = hash_table->next;
    }

    return 1;
}

//删除数据
static int ldel(lua_State *L){
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);
    char *key = luaL_checkstring(L, 2);

    int index = hash(name, ets_table->capacity);
    HashTable *hash_table = ets_table->hash_table[index];
    while(hash_table){
        if (strcmp(hash_table->name, name) == 0) {
            pthread_mutex_lock(&hash_table->lock);
            int key_index = hash(key, hash_table->capacity);
            HashNode *node = hash_table->table[key_index];
            HashNode *prev = NULL;
            while(node){
                if (strcmp(node->key, key) == 0) {
                    //更新链表
                    if (prev == NULL) {
                        hash_table->table[key_index] = node->next;
                    } else {
                        prev->next = node->next;
                    }

                    //释放资源
                    free_node(node);
                    lua_pushboolean(L, 1);
                    pthread_mutex_unlock(&hash_table->lock);
                    return 1;
                }
                prev = node;
                node = node->next;
            }
            pthread_mutex_unlock(&hash_table->lock);
        }
        hash_table = hash_table->next;
    }
    lua_pushboolean(L, 0);

    return 1;
}

//删除表所有数据
static int ldel_all(lua_State *L){
    if (ets_table == NULL){
        luaL_error(L, "ets_table_not_init");
        return 0;
    }

    if (!lua_isstring(L, 1)) {
        luaL_error(L, "miss_table_name");
        return 0;
    }

    char *name = luaL_checkstring(L, 1);

    int index = hash(name, ets_table->capacity);
    HashTable *hash_table = ets_table->hash_table[index];
    HashTable *prev = NULL;
    while(hash_table){
        if (strcmp(hash_table->name, name) == 0) {
            pthread_mutex_lock(&hash_table->lock);
            //更新链表
            if (prev == NULL) {
                ets_table->hash_table[index] = hash_table->next;
            } else {
                prev->next = hash_table->next;
            }
            //释放资源
            free_hashtable(hash_table);
            pthread_mutex_unlock(&hash_table->lock);
            lua_pushboolean(L, 1);
            return 1;
        }
        prev = hash_table;
        hash_table = hash_table->next;
    }
    
    lua_pushboolean(L, 0);
    return 1;
}

int luaopen_etscache(lua_State *L)
{
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"create", linit},
        {"init", linit_ets},
        {"insert", linsert},
        {"lookup", lsearch},
        {"lookup_all", lsearch_all},
        {"delete", ldel},
        {"delete_all", ldel_all},
        {NULL, NULL}
    };

    luaL_newlib(L, l);
    return 1;
}

//释放hashtable资源
void free_hashtable(HashTable *hash_table){
    int i;
    for (i = 0; i < hash_table->capacity; i++) {
        HashNode* node = hash_table->table[i];
        while (node != NULL) {
            HashNode* temp = node;
            node = node->next;
            free_node(temp);
        }
    }
}

//释放node资源
void free_node(HashNode *node){
    if(node == NULL){
        return;
    }

    if (node->val_type == TYPE_TABLE) {
        // 迭代释放链表
        HashNode *current = node->val.table_value;
        while (current) {
            HashNode *temp = current;
            current = current->next_node;
            free_node(temp);
        }
    }

    free(node->key);
    free(node);
}

//解析HashNode的key，只能是数字和字符串, 数字会先转成字符串key
char * parse_key(lua_State *L, int index){
    int type = lua_type(L, index); 
    char *key = "";
    int num;
    char tempkey[20];
    switch (type){
        case LUA_TSTRING:  // 字符串
            key = strdup(lua_tostring(L, index));
            break;
        case LUA_TNUMBER:  // 数字
            num = lua_tointeger(L, index);
            sprintf(tempkey, "%d", num);
            key = strdup(tempkey);
            break;
        default:
            luaL_error(L, "key must be string or integer");
            return;
    }

    return key;
}

//获取HashNode的key
void get_key(lua_State *L, char *key){
    if (!is_integer_str(key)){
        lua_pushstring(L, key);
    }else{
        lua_pushinteger(L, atoi(key));
    }
}

//解析HashNode的val和val_type
void parse_val(HashNode *node, lua_State *L, int index) {
    int type = lua_type(L, index);
    switch (type) {
        case LUA_TSTRING:  
            node->val_type = TYPE_STRING;
            node->val.string_value = lua_tostring(L, index);
            break;
        case LUA_TNUMBER: 
            node->val_type = TYPE_INT;
            node->val.int_value = lua_tonumber(L, index);
            break;
        case LUA_TTABLE:  //表
            node->val_type = TYPE_TABLE;
            HashNode *prev_node = (HashNode*)malloc(sizeof(HashNode));
            prev_node->key = NULL;
            prev_node->next = NULL;     //val.table_value不用到该字段，走链表next_node
            prev_node->next_node = NULL;
            new_tbl(L, prev_node, index);
            node->val.table_value = prev_node;
            break;
        default:
            luaL_error(L, "parse_val unsupported type");
            return;
    }
}

//获取HashNode的val
void get_val(lua_State *L, HashNode *node){
    switch (node->val_type){
        case TYPE_STRING:
            lua_pushstring(L, node->val.string_value);
            break;
        case TYPE_INT:
            lua_pushnumber(L, node->val.int_value);
            break;
        case TYPE_TABLE:
            get_tbl(L, node->val.table_value);
            break;        
        default:
            luaL_error(L, "get_val unsupported type");
            return;
    }
}

// 开启HashNode链表保存table
void new_tbl(lua_State *L, HashNode *prev_node, int index){
    //非首次进入循环index为-1，次栈顶才是table
    lua_pushnil(L);
    if (index != 3) {
        index--;
    }
    while (lua_next(L, index)) {
        // print_stack1(L);
        char *key = parse_key(L, -2);
        // 首个节点直接赋值
        if (prev_node->key == NULL) {
            prev_node->key = key;
            parse_val(prev_node, L, -1);
            prev_node->next_node = NULL;
        }else{
            HashNode *new_node = (HashNode *)malloc(sizeof(HashNode));
            new_node->key = key;
            parse_val(new_node, L, -1);
            new_node->next_node = prev_node->next_node;
            prev_node->next_node = new_node;
        }
        lua_pop(L, 1);
    }
}

// 获取HashNode链表数据并压入栈
void get_tbl(lua_State *L,  HashNode *node){
    lua_newtable(L);
    while (node) {
        // print_stack1(L);
        get_key(L, node->key);
        get_val(L, node);
        lua_settable(L, -3);
        node = node->next_node;
    }
}

//判断字符串是否数字
int is_integer_str(char *str) {
    if (str == NULL) {
        return 0;
    }
    while (*str != '\0') {
        if (!isdigit(*str)) {
            return 0;
        }
        str++;
    }
    return 1;
}

//---------------------------------以下是调试内容
int print_table(lua_State *L) {
    if (lua_gettop(L) != 1) {
        luaL_error(L, "expected 1 argument");
        return 0;
    }

    if (lua_istable(L, 1)) {
        print_table_handle(L, 1);
    }

    return 1;
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