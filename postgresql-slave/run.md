# Postgres 主从搭建（流复制）

修改docker-compose并启动

```shell
docker-compose -f docker-compose.yml -p postgis-slave up -d
```

创建用户 syscuser 密码为postgres用于主从同步

```sql
create role syncuser login replication encrypted password 'postgres';
```

主 在会后一行加入以下配置 `pg_hba.conf`

```shell
host    replication     syncuser        0.0.0.0/0           trust
如果是多台服务器的主从，这里的IP需要配置成从节点的IP
```

修改/docker_data/postgres/master/data/postgresql.conf

```shell
listen_addresses = '*'   #监听所有IP
archive_mode = on      #允许归档
archive_command = '/bin/date'    #用该命令来归档logfile segment,这里取消归档。
wal_level = replica    #开启热备
max_wal_senders = 10    #这个设置了可以最多有几个流复制连接，差不多有几个从，就设置几个
wal_keep_size = 1024    #设置wal的大小，单位M。  13版本不存在
wal_sender_timeout = 60s #设置流复制主机发送数据的超时时间
max_connections = 100    #这个设置要注意下，从库的max_connections必须要大于主库的
```

重启主库

从库：

```shell
docker exec -it slave bash
cd /var/lib/postgresql/data/
rm -rf *
pg_basebackup -h master -p 5432 -U syncuser -Fp -Xs -Pv -R -D /var/lib/postgresql/data
上诉会先进行备份一次，也可以先备份到一个其他目录，然后替换data下的内容
```

修改 /docker_data/postgres/slave/data/postgresql.conf

```shell
wal_level = replica   # WAL 日志级别为 replica
primary_conninfo ='host=master port=5432 user=syncuser password=postgres'   # 主库连接信息	
hot_standby = on                     # 恢复期间，允许查询
recovery_target_timeline = latest    # 默认
max_connections = 120                # 大于等于主节点，正式环境应当重新考虑此值的大小
```

重启`从库`

验证

```sql
 SELECT usename, application_name, client_addr, sync_state FROM pg_stat_replication ;
 从库会存在一条数据
```

# Postgres备份与恢复

进行一次全量备份：

```
pg_basebackup -Ft -Pv -Xf -z -Z5 -p 5432 -D /var/lib/postgresql/archive 
```

> 1. **`-D, --pgdata=DIRECTORY`**
>    - 指定备份输出目录。这个目录将包含备份数据。
> 2. **`-F, --format=FORMAT`**
>    - 指定输出格式。可以是：
>      - `p`：纯文件
>      - `t`：tar（导出为 tar 包）
> 3. **`-X, --waldir=DIRECTORY`**
>    - 选择如何处理 WAL 文件。可以是：
>      - `none`：不归档 WAL 文件
>      - `fetch`：从主服务器获取 WAL 文件
>      - `stream`：实时流式传输 WAL 文件
> 4. **`-U, --username=NAME`**
>    - 用于连接数据库的用户名。
> 5. **`-h, --host=HOSTNAME`**
>    - 指定数据库服务器的主机名或 IP 地址。
> 6. **`-p, --port=PORT`**
>    - 指定数据库服务器的端口号（默认为 5432）。
> 7. **`-v, --verbose`**
>    - 启用详细输出。
>
> ### 高级参数
>
> - **`-P, --progress`**
>   - 显示备份进度信息。
> - **`--max-rate=RATE`**
>   - 限制备份的最大传输速率（以字节/秒为单位）。
> - **`--include-wall`**
>   - 指定是否包含 WAL 文件（已被其他参数替代，但信息仍有参考价值）。
> - **`--no-recovery`**
>   - 会创建一个不包含恢复文件（即 `recovery.conf` 的目录）。 12版:recovery.signal 恢复后删除
> - **`-T, --tablespace-mapping`**
>   - 允许为移动的表空间级别创建备份。
>
> ### 其他参数
>
> - **`--label=LABEL`**
>   - 指定备份的标签。
> - **`--no-password`**
>   - 在不提示输入密码的情况下连接到数据库。
> - **`--check`**
>   - 进行检查而不进行实际备份。
> - **`--help`**
>   - 显示帮助信息。
> - **`--version`**
>   - 显示版本信息。
>
> 本身并不支持仅备份单个数据库。
>
> 示例：
>
> postgres@1652d4ff599c:/$ pg_basebackup -Ft -Pv -Xf -z -Z5 -p 5432 -D /var/lib/postgresql/archive
> pg_basebackup: initiating base backup, waiting for checkpoint to complete #  正在启动基础备份，并等待当前数据库的检查点（checkpoint）完成。检查点是将内存中的脏页写入磁盘的过程，确保在执行备份时数据库的状态一致
> pg_basebackup: checkpoint completed # 这表示数据库的检查点已经完成，数据现在是安全的，可以进行备份。
> pg_basebackup: write-ahead log start point: 0/1E000060 on timeline 3 #这行显示了备份开始时的 WAL（Write-Ahead Log）位置。具体来说 
>  #0/1E000060 表示 WAL 的起始位置，通常由两个十六进制数字组成的部分表示。
>  #timeline 3 指的是进行备份时的时间线编号，PostgreSQL 允许时间线管理以处理恢复和分支。
> 80878/80878 kB (100%), 1/1 tablespace
> pg_basebackup: write-ahead log end point: 0/1E000138
> pg_basebackup: syncing data to disk ...
> pg_basebackup: base backup completed

增量备份：

```shell
1. 修改配置：
wal_level = 'replica ' #  WAL 的详细级别。对于需要归档和备份的场景，通常建议设置为 replica 或 logical。
archive_mode='on'
archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f' # 它的值可以是一条shell命令或者一个复杂的shell脚本。在archive_command的shell命令或脚本中可以用“%p”表示将要归档的WAL文件的包含完整路径信息的文件名
archive_timeout = 60s   #每60秒归档一次  
max_wal_senders = 10  #允许最多10个WAL发送者  
wal_keep_segments = 64  # 保留64个WAL文件 
```

检查是否归档了

全量备份文件还原

```shell
关闭数据库 /var/lib/postgresql
tar -xvf  /var/lib/postgresql/archive/back/base.tar.gz -C /var/lib/postgresql/data
```

基于还原点

````shell
SELECT pg_create_restore_point('back1');  # 创建还原点
删除data文件 修改 postgre.conf 文件 
restore_command = 'cp /var/lib/postgresql/archive/%f %p'	# 归档文件地址
recovery_target_name = 'back1' # 设置还原点

#data目录下创建recovery.signal
select  pg_wal_replay_resume() # 恢复完成后执行继续执行
重启后后恢复
````

//TODO 修改为脚本文件 

lsn：

```shell
SELECT pg_switch_wal(); --进行日志归档  日志归档 
删除data文件 使用基本恢复 修改 postgre.conf 文件 

restore_command = 'cp /var/lib/postgresql/archive/%f %p'	# 归档文件地址
recovery_target_lsn = '0/1D000100'	 
#data目录下创建recovery.signal
select  pg_wal_replay_resume() # 恢复完成后执行继续执行
重启后后恢复
```

时间线：

```shell
配置文件
restore_command = 'cp /var/lib/postgresql/archive/%f %p'	# 归档文件地址
recovery_target_time = '2024-08-05 13:48:59'	# 恢复的时间，具体时间要按照本机时间 之一时区

#data目录下创建recovery.signal
启动数据库自动还原
select  pg_wal_replay_resume() # 恢复完成后执行继续执行

```

# 高可用

## Keepalived

安装pg数据库

```shell
# Install the repository RPM:
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Install PostgreSQL:
sudo yum install -y postgresql12-server

# Optionally initialize the database and enable automatic start:
sudo /usr/pgsql-12/bin/postgresql-12-setup initdb
sudo systemctl enable postgresql-12
sudo systemctl start postgresql-12
sudo systemctl restart postgresql-12
sudo systemctl status postgresql-12
安装成功后，位置
/var/lib/pgsql/12

安装修改密码
sudo -u postgres
psql -c " ALTER USER postgres WITH PASSWORD 'postgres';"

检查postgresql.conf文件吗，以下内容是否修改正确。
listen_addresses = '*'		# what IP address(es) to listen on;
检查data/pg_hba.conf文件，以下内容是否修改正确。
host    all            all      0.0.0.0/0  md5 

检查防火墙状态：
sudo systemctl status firewalld  
停止防火墙服务：
sudo systemctl stop firewalld  
禁用防火墙（以防重启后自动启动）：
sudo systemctl disable firewalld  

设置环境变量
export PATH=$PATH:/usr/pgsql-12/bin
从库搭建 略

```



keepalived+postgres 高可用：

```shell
keepalived c语言编写，vrrp协议
类似：NGINX的代理，提供一个虚拟ip，
无法解决以下问题：
1.抢占模式下，主库down后数据一致性问题，需要处理
2.
```

安装：

```shell
yum install keepalived -y
```

启动 Keepalived 服务并使其在系统启动时自动启动：

```shell
sudo systemctl start keepalived  
sudo systemctl stop keepalived  
sudo systemctl enable keepalived  
sudo systemctl status keepalived   #验证
sudo systemctl restart keepalived

查看日志
tail -f /var/log/messages  

```

数据库准备

```sql
  创建用户 角色
  CREATE ROLE keepalived NOSUPERUSER NOCREATEDB
                    login ENCRYPTED PASSWORD 'keeplaived';
   创建数据库：
  CREATE DATABASE keepalived
  WITH OWNER=keepalived
  TEMPLATE=TEMPLATE0
  ENCODING='UTF8';
  查看 切换用户 
  \c keepalived keepalived
  创建表
  CREATE TABLE sr_delay(id int4, last_alive timestamp(0) without time zone);
  
 表sr_delay只允许写入一条记录，并且不允许删除此表数据，通过触发器实现。创建触发器函数
 CREATE FUNCTION cannt_delete ()
 RETURNS trigger
 LANGUAGE plpgsql AS $$
 BEGIN
 RAISE EXCEPTION 'You can not delete! ';
 END; $$;
 
 创建cannt_delete和cannt_truncate触发器
 CREATE TRIGGER cannt_delete BEFORE DELETE ON sr_delay
            FOR EACH ROW EXECUTE PROCEDURE cannt_delete();
            
 CREATE TRIGGER cannt_truncate BEFORE TRUNCATE ON sr_delay
            FOR STATEMENT EXECUTE PROCEDURE cannt_delete();
            
插入一条数据
INSERT INTO sr_delay VALUES(1, now());
```

修改pg_hba.conf

```json
# keepalived
host keepalived keepalived 192.168.59.100/32 md5
host keepalived keepalived 192.168.59.101/32 md5
host keepalived keepalived 192.168.58.128/32 md5
host keepalived keepalived 192.168.58.131/32 md5
```

检测脚本：

```shell
#! /bin/bash  

# 配置变量  
export PGPORT=5432  
export PGUSER=keepalived  
export PGDBNAME=keepalived  
export PGDATA=/var/lib/pgsql/12/data  # pg的数据目录  
export LANG=en_US.utf8  
export PGHOME=/usr/pgsql-12  # pg安装目录  
export LD_LIBRARY_PATH=$PGHOME/lib  
export PATH=$PGHOME/bin:$PGPOOL_HOME/bin:$PATH:.  

MONITOR_LOG="/tmp/pg_check.log"  

SQL_UPD_LAST_ALIVE="UPDATE sr_delay SET last_alive = now();"  
SQL_CHECK_HEALTH='SELECT 1;'  

check_if_standby() {  
    local standby_flg=$(psql -p $PGPORT -U postgres -At -c "SELECT pg_is_in_recovery();")  
    if [ "${standby_flg}" == 't' ]; then  
        echo -e "$(date +%F\ %T): This is a standby database, exit!" >> "$MONITOR_LOG"  
        exit 0  
    fi  
}  

update_sr_delay() {  
    echo "$SQL_UPD_LAST_ALIVE" | psql -At -p $PGPORT -U $PGUSER -d $PGDBNAME  
    if [ $? -ne 0 ]; then  
        echo -e "$(date +%F\ %T): Failed to update sr_delay table." >> "$MONITOR_LOG"  
        exit 1  
    fi  
}  

check_primary_health() {  
    echo "$SQL_CHECK_HEALTH" | psql -At -h localhost -p $PGPORT -U $PGUSER -d $PGDBNAME  
    if [ $? -eq 0 ]; then  
        echo -e "$(date +%F\ %T): Primary db is healthy." >> "$MONITOR_LOG"  
        exit 0  
    else  
        echo -e "$(date +%F\ %T): Attention: Primary db is not healthy!" >> "$MONITOR_LOG"  
        exit 1  
    fi  
}  

# 主程序流程  
check_if_standby  
update_sr_delay  
check_primary_health  
```

全局配置：keepalived.conf

```shell
! Configuration File for keepalived  
global_defs {  
    # 定义全局设置，例如通知邮件的选项  
    notification_email {  
        admin@example.com  # 邮件通知的接收者  
    }  
    notification_email_from keepalived@example.com  # 发送者邮件地址  
    smtp_server 127.0.0.1  # SMTP 邮件服务器  
    smtp_connect_timeout 30  # 连接超时时间  
    router_id MY_VRRP_ROUTER  # 路由器标识  
}  



# 监控脚本配置
# 定义一个用于监测 PostgreSQL 状态的脚本
# 该脚本将会被定期调用以确保服务可用
track_script chk_pgsql {
    script "/etc/keepalived/check.sh"  # 监控脚本的路径
    interval 10  # 每2秒检查一次
    weight 3  # 权重
}

vrrp_instance VI_1 {  
    # VRRP 实例的定义  
    state MASTER  # 本节点为主节点  
    interface ens33  # 绑定的网络接口  
    nopreempt  #抢占模式
    virtual_router_id 51  # VRRP ID，所有节点必须相同  
    priority 100  # 节点优先级，主节点优先级最高  
    advert_int 1  # 广播间隔  
    authentication {  
        auth_type PASS  # 认证类型  
        auth_pass keep  # 认证密码  
    }  
    # 虚拟 IP 地址，所有参与的主机都具有此 IP 地址  
    virtual_ipaddress {  
        192.168.59.100  # 主机共享的虚拟 IP 地址  
        192.168.59.101 # 备用虚拟ip
    }  

    # 监控 PostgreSQL 服务的脚本  
    track_script {  
        chk_pgsql  # 监控脚本的名称  
    }  
    notify_master /etc/keepalived/active_standby.sh
}  

```

切换脚本 active_standby

```shell
        #/bin/bash
        # 环境变量
        export PGPORT=1921
        export PGUSER=keepalived
        export PG_OS_USER=postgres
        export PGDBNAME=keepalived
        export PGDATA=/data1/pg10/pg_root
        export LANG=en_US.utf8
        export PGHOME=/opt/pgsql
        export  LD_LIBRARY_PATH=$PGHOME/lib:/lib64:/usr/lib64:/usr/local/lib64:/lib:/usr/
            lib:/usr/local/lib
        export PATH=/opt/pgbouncer/bin:$PGHOME/bin:$PGPOOL_HOME/bin:$PATH:.

        # 设置变量，LAG_MINUTES指允许的主备延迟时间，单位秒
        LAG_MINUTES=60
        HOST_IP=`hostname -i`
        NOTICE_EMAIL="francs3@163.com"
        FAILOVE_LOG='/tmp/pg_failover.log'

        SQL1="SELECT 'this_is_standby' AS cluster_role FROM ( SELECT pg_is_in_recovery()
            AS std ) t WHERE t.std is true; "
        SQL2="SELECT 'standby_in_allowed_lag' AS cluster_lag FROM sr_delay WHERE now()-
            last_alive < interval '$LAG_MINUTES SECONDS'; "

        # 配置对端远程管理卡IP地址、用户名、密码
        FENCE_IP=50.1.225.101
        FENCE_USER=root
        FENCE_PWD=xxxx

        # VIP已发生漂移，记录到日志文件
        echo -e "`date +%F\ %T`: keepalived VIP switchover! " >> $FAILOVE_LOG

        # VIP已漂移，邮件通知
        #echo -e "`date +%F\ %T`: ${HOST_IP}/${PGPORT} VIP发生漂移，需排查问题！\n\nAuthor:
            francs(DBA)" | mutt -s "Error: 数据库VIP发生漂移 " ${NOTICE_EMAIL}
        # pg_failover函数，当主库故障时激活备库
        pg_failover()
        {
        # FENCE_STATUS  表示通过远程管理卡关闭主机成功标志，1 表示失败，0 表示成功
        # PROMOTE_STATUS  表示激活备库成功标志，1 表示失败，0 表示成功
        FENCE_STATUS=1
        PROMOTE_STATUS=1

        # 激活备库前需通过远程管理卡关闭主库主机
        for ((k=0; k<10; k++))
        do
        # 使用ipmitool命令连接对端远程管理卡关闭主机，不同X86设备命令可能不一样
            ipmitool -I lanplus -L OPERATOR -H $FENCE_IP -U $FENCE_USER -P $FENCE_PWD
                power reset
            if [ $? -eq 0 ]; then
                echo -e "`date +%F\ %T`: fence primary db host success."
                FENCE_STATUS=0
                break
            fi
        sleep 1
        done

        if [ $FENCE_STATUS -ne 0 ]; then
            echo -e "`date +%F\ %T`: fence failed. Standby will not promote, please fix
                it manually."
        return $FENCE_STATUS
        fi

        # 激活备库
        su - $PG_OS_USER -c "pg_ctl promote"
        if [ $? -eq 0 ]; then
            echo -e "`date +%F\ %T`: `hostname` promote standby success. "
            PROMOTE_STATUS=0
        fi

        if [ $PROMOTE_STATUS -ne 0 ]; then
            echo -e "`date +%F\ %T`: promote standby failed."
            return $PROMOTE_STATUS
        fi

            echo -e "`date +%F\ %T`: pg_failover() function call success."
            return 0
        }

        # 故障切换过程
        # 备库是否正常的标记，STANDBY_CNT=1 表示正常．
        STANDBY_CNT=`echo $SQL1 | psql -At -p $PGPORT -U $PGUSER -d $PGDBNAME -f - | grep
            -c this_is_standby`
        echo -e "STANDBY_CNT: $STANDBY_CNT"  >> $FAILOVE_LOG

        if [ $STANDBY_CNT -ne 1 ]; then
            echo -e "`date +%F\ %T`: `hostname` is not standby database, failover not
                allowed! " >> $FAILOVE_LOG
            exit 1
        fi

        # 备库延迟时间是否在接受范围内，LAG=1 表示备库延迟时间在指定范围
        LAG=`echo $SQL2 | psql -At -p $PGPORT -U $PGUSER -d $PGDBNAME | grep -c standby_
            in_allowed_lag`
        echo -e "LAG: $LAG"  >> $FAILOVE_LOG

        if [ $LAG -ne 1 ]; then
            echo -e "`date +%F\ %T`: `hostname` is laged far $LAG_MINUTES SECONDS from
                primary , failover not allowed! " >> $FAILOVE_LOG
            exit 1
        fi

        # 同时满足两个条件执行主备切换函数：1、备库正常；2、备库延迟时间在指定范围内。
        if [ $STANDBY_CNT -eq 1 ] && [ $LAG -eq 1 ]; then
            pg_failover >> $FAILOVE_LOG
            if [ $? -ne 0 ]; then
                echo -e "`date +%F\ %T`: pg_failover failed." >> $FAILOVE_LOG
                exit 1
            fi
        fi

        # 判断是否执行故障切换pg_failover函数
        # 1. 当前数据库为备库，并且可用。
        # 2. 备库延迟时间在指定范围内

        # pg_failover函数处理逻辑
        # 1. 通过远程管理卡关闭主库主机
        # 2. 激活备库
```

实验过程

```
关闭主库的 keepalived
ps -ef | grep keepalived | grep -v grep
kill 7527
```

### 问题

1. 出现unsafe permissions found for script

   ```
   修改脚本权限为 744
   ```

2. 关闭 SELinux

## Pg-pool

1. 简介：

2. 模式

   > 原始模式：不负责同步，故障切换功能，不支持负载均衡
   >
   > 主备模式：流复制，使用pg-pool实现高可用和连接池
   >
   > 复制模式：数据同步，所有数据库都返回成功，
   >
   > 连接池：

3. 安装

   ```shell
   yum install pgpool-II # 安装软件
   yum install pgpool-II-pcp   # 安装工具包
   ```

   

4. 配置

   ```
   
   
   1. pcp
   
   2.pg_md5 生成 pool_passwd
   pg_md5 -u postgres -m postgres
   
   ```

   

   > 设置主从： 192.168.59.128 主库  192.168.59.131 从库1 192.168.59.132 从库2

   ```shell
   1.配置免密
   ssh-keygen
   ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.59.128
   ssh root@192.168.59.131  # 测试登录
   
   2.yum 安装 
   yum install pgpool-II
   
   3.配置   pool_hba.conf    
   cp pool_hba.conf.sample pool_hba.conf
   host    replication     syncuser        192.168.59.131/0        md5
   host    replication     syncuser        192.168.59.132/0        md5
   
   4.产生 pool_passwd
   pg_md5 -u postgres -p postgres # 输入密码 
   cat pool_passwd  #查看密码
   也可以在         
   SELECT rolpassword FROM pg_authid WHERE rolname='postgres';
   将结果写入到pool_passwd文件
   
   5.配置pgpool.conf
   cp pgpool.conf.sample-stream  pgpool.conf
   
   listen_addresses = '*'
   port = 9999
   # 连接配置
   backend_hostname0 = '192.168.59.128'  # Host name or IP address to connect to for backend 0
   backend_port0 = 5432      # Port number for backend 0
   backend_weight0 = 1   # 负载均衡时给后端数据库分配的权重 值越大，该实例获得的请求越多
   backend_data_directory0 = '/var/lib/pgsql/12/data' # PostgreSQL 数据库实例的数据目录路径
   backend_flag0 = 'ALLOW_TO_FAILOVER' # 例的状态标志。 ALLOW_TO_FAILOVER，在该后端数据库发生故障时请求转移到其他可用的后端。同时还可以设置为 DISALLOW_TO_FAILOVER 来防止故障转移
   backend_application_name0 = 'server0'    # 数据库实例指定应用程序名称
   
   backend_hostname1 = '192.168.59.131'
   backend_port1 = 5432
   backend_weight1 = 1
   backend_data_directory1 = '/var/lib/pgsql/12/data'
   backend_flag1 = 'ALLOW_TO_FAILOVER'
   backend_application_name1 = 'server1'
   
   backend_hostname2 = '192.168.59.132'
   backend_port2 = 5432
   backend_weight2 = 1
   backend_data_directory2 = '/var/lib/pgsql/12/data'
   backend_flag2 = 'ALLOW_TO_FAILOVER'
   backend_application_name2 = 'server2'
   
   # 认证配置
   enable_pool_hba = on   # 当设置为 on 时，Pgpool-II 将使用自己的访问控制机制（类似于 PostgreSQL 的 pg_hba.conf 文件），来限制哪些客户端可以连接到 Pgpool-II。这允许对连接进行更细粒度的管理，包括用户、客户端 IP 地址和数据库等条件
   pool_passwd = 'pool_passwd' # 该参数指向一个文本文件，其中列出了用户及其密码，
   
   log_destination = 'syslog'  #将日志发送到系统日志守护进程
   log_directory = '/tmp/pgpool_logs' # 日志目录
   log_filename = 'pgpool-%Y-%m-%d_%H%M%S.log' # 日志文件
   
   pid_file_name = '/opt/pgpool/pgpool.pid'  #用于指定存储进程标识符（PID）的文件名。以下是关于 pid_file_name 的详细解释： 系统在启动时会在该文件中写入运行的主进程的进程 ID。这在系统管理中非常有用
   
   # 负载均衡配置
   load_balance_mode = off
   # pgpool复制模式配置和复制检测
   master_slave_mode = on    # 原生流复制关闭
   master_slave_sub_mode = 'stream' 
   
   sr_check_period = 10
   sr_check_user = 'syncuser'
   sr_check_password = 're12a345'
   sr_check_database = 'postgres'
   delay_threshold = 10000000
   # 设置故障转移的脚本，当pgpool主备实例或主机宕机时，触发此脚本进行故障转移，后面四个参数为pgpool系统变量，%d表示宕机的节点ID, %P表示老的主库节点ID, %H表示新主库的主机名，%R表示新主库的数据目录
   failover_command = '/etc/pgpool-II/failover_stream.sh %d %P %H %R'
   
   use_watchdog = on #是否启用watchdog，默认为off
   wd_hostname = '192.168.59.128'  #与当前主机一直
   wd_port = 9000
   wd_priority = 1
   
   #虚拟ip
   delegate_IP = '192.168.59.100'
   if_cmd_path = '/sbin'
   if_up_cmd = 'ip addr add $_IP_$/24 dev ens33 label ens33:1' # 网卡上绑定一个IP
   if_down_cmd = 'ip addr del $_IP_$/24 dev ens33' # 使用ip addr del命令删除IP
   
   # 心跳设置 设置远程 后续两个节点修改
   heartbeat_hostname0 = '192.168.131'
   heartbeat_port0 = 9694
   heartbeat_device0 = 'ens33'  #发送watchdog心跳的网络设备别名
   
   heartbeat_hostname0 = '192.168.131'
   heartbeat_port1 = 9694
   heartbeat_device1 = 'ens33'
   
   #心跳检测
   wd_life_point = 3  #当探测pgpool节点失败后设置重试次数
   wd_lifecheck_query = 'SELECT 1'  #设置pgpool存活检测的SQL
   wd_lifecheck_dbname = 'postgres' #设置pgpool存活检测的数据库
   wd_lifecheck_user = 'syncuser' #设置pgpool存活检测的数据库用户密码。
   wd_lifecheck_password = 'postgres' 
   
   #远程连接 ？？
   #other_pgpool_hostname0 = 'pghost5'   # 设置远程pgpool节点主机名或IP
   #other_pgpool_port0 = 9999             # 设置远程pgpool节点端口号
   #other_wd_port0 = 9000                 # 设置远程pgpool节点watchdog端口号
   ```

5. 开启和关闭：

   ```
   
   关闭
   pgpool -m fast stop
   连接数据库：
   psql -h 192.168.59.128 -p 9999 -U postgres
   查看节点
   show pool_nodes;
   ```

   

6. 问题：

   ```
   1. Pgpool node id file /usr/local/pgpool/etc/pgpool_node_id does not exist
   添加pgpool_node_id 
   设置节点Id 0
   
   
   ```

   

7. 

