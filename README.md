一个简单的基于skynet搭建的游戏服务器框架，可以作为学习用。skynet集群 + mysql存储 + 自定义协议 + 事件系统 + 全局唯一id生成 + 简单登录注册逻辑 + 简单副本框架逻辑

使用前准备：

1. 默认安装了mysql，导入egame/skynet.sql到数据库

2. 配置egame/econfig 和 egame/ecenterconfig
   修改内容：自定义变量下的内容都可以修改，主要是db信息要调整为自己的mysql信息，其它可以默认不改
   **注意
   节点信息的node_list需要按照格式配置，格式：节点名node-ip:端口，其中节点名node对应node变量

3. 先启动跨服节点ecenterconfig
    ./skynet egame/ecenterconfig
   再启动游戏服节点econfig
    ./skynet egame/econfig

目录结构：

    主要都是在game下
    egame  
    --clusters      跨服和游戏服节点服务  
    --common        公共方法  
    --data          游戏配置  
    --db            mysql连接池服务  
    --def           宏定义  
    --dungeon       副本功能逻辑  
    --event         玩家事件  
    --id_create     全局唯一id服务  
    --listen        socket服务  
    --net           网络协议解析  
    --player        玩家服务和逻辑  
    --server        节点初始化服务  

框架结构：
    一个跨服中心节点clusters_center，对应多个游戏服节点clusters_node（例子只有一个，多个可以改econfig启动多个）
    游戏服节点启动listen/socketelisten监听指定端口，一个socket连接进来之后开启一个player服务
    （主要都是围绕player服务展开，接收socket消息-》player服务-》net解析-》player_handle，dungeon_handle处理协议内容，展开逻辑）

大概使用步骤：
    以新增dungeon副本功能为例子
    1. data目录下新增副本配置，正常这个是自动生成的

    2. cluster_init和server_init模块的init_game_conf加载对应的配置，用sharedata存储

    3. 处理协议部分，net.handler按备注说明加上副本协议号和处理模块

    4. pt模块中的pt_dispatch和pt.write加上对应协议号的分支，按协议号对应的格式解析

    5. player_handle模块中的handler按备注说明加上副本处理模块（这是外部服务发消息给玩家服务处理逻辑，比如副本服务发消息给玩家服务进入副本等）

    6. def目录下新增需要的宏定义模块和dungeon目录处理副本逻辑

其它：   

    事件监听系统event目录：  
        事件宏定义为def_event  
        data_player_event模块按格式新增事件和对应回调处理模块  
        player_event.event_dispatch(event, ...)派发事件  

额外：  

    简单练手的搭建，写得粗暴，有问题的话请见谅或反馈
