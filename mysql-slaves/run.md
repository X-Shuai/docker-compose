### MySQL

```shell
# 5.7
docker-compose -f docker-compose.yml -p mysql up -d
```
```
master 授权
检查两个的 service-id 

show variables like '%server_id%';

#master 
show master status;

grant replication slave,replication client on *.* to 'master'@'%' identified by "master";

 salve配置,

 change master to master_host='mysql-master',master_user='master',master_password='master',master_port=3306,master_log_file='mysql-bin.000003', master_log_pos=459,master_connect_retry=30;

#slave
 SHOW VARIABLES LIKE '%read_only%'; #查看只读状态
SET GLOBAL super_read_only=1; #super权限的用户只读状态 1.只读 0：可写
SET GLOBAL read_only=1; #普通权限用户读状态 1.只读 0：可写
```