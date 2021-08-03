# init-tidb

BlueCity 初始化 TiDB 集群脚本；可用于`qcloud`, `aws` 云厂商；

- aws-s5-centos-init-tidb.sh 初始化aws TiDB
- qcloud-s5-centos-init-tidb.sh 初始化qcloud TiDB

上述脚本满足

- init_centos_users  初始化 centos 用户
- init_tidb_users 初始化 tidb 用户
- check_new_or_not 检测磁盘是否已挂载
- init_disk  初始化磁盘（包括磁盘调优）
- init_system 初始化系统（包括系统调优）

注：以上脚本请使用root权限执行；

请注意修改脚本中对应的内容关键词：
