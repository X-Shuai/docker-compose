### MySQL

```shell
# 5.7
docker-compose -f docker-compose.yml -p mysql up -d
```
```
master 授权
检查两个的 service-id 
grant replication slave,replication client on *.* to 'master'@'%' identified by "master";
 salve配置,
 change master to master_host='mysql-master',master_user='master',master_password='master',master_port=3306,master_log_file='mysql-bin.000001', master_log_pos=154,master_connect_retry=30;
```