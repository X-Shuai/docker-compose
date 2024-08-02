启动脚本：

> 注意看shell内的映射文件

```shell
docker-compose -f docker-compose.yml -p postgis-slave up -d
```

实践：

容器数据映射

```shell
docker run -d -p 54321:5432 --name postgis-tmp -e POSTGRES_PASSWORD=postgres postgis/postgis:12-3.2
```

复制到当前目录：

```shell
docker cp postgis-tmp:/var/lib/postgresql/data ./master/
docker cp postgis-tmp:/var/lib/postgresql/data ./slave/
```

停止删除：

```shell
docker stop postgis-tmp
docker rm postgis-tmp
```

上诉过程可以不用

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
primary_conninfo ='host=master port=15432 user=syncuser password=postgres'   # 主库连接信息	
hot_standby = on                     # 恢复期间，允许查询
recovery_target_timeline = latest    # 默认
max_connections = 120                # 大于等于主节点，正式环境应当重新考虑此值的大小
```

重启`从库`

验证

```sql
 SELECT usename, application_name, client_addr, sync_state FROM pg_stat_replication ;
```



## 备份与恢复
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

//TODO







````shell
#设置还原




#并创建recovery.signal
重启后后恢复
````





```shell
1. 创建归档目录，archive_wals目录自然用来存放归档了
2. wal_level参数可选的值有minimal、replica和logical，从minimal到replica再到logical级别，WAL的级别依次增高，在WAL中包含的信息也越多
修改为 replica
3. archive_mode参数可选的值有on、off和always，默认值为off，开启归档需要修改为on，
4. archive_command参数
	archive_command参数的默认值是个空字符串，它的值可以是一条shell命令或者一个复杂的shell脚本。在archive_command的shell命令或脚本中可以用“%p”表示将要归档的WAL文件的包含完整路径信息的文件名
	archive_command = 'cp %p 归档目录/%f'。
	show archive_command; --查看
	修改archive_command不需要重启，只需要reload即可
	如果归档命令未成功执行，它会周期性地重试，在此期间已有的WAL文件将不会被复用，新产生的WAL文件会不断占用pg_wal的磁盘空间，直到pg_wal所在的文件系统被占满后数据库关闭
 5. 备份 可以使用 pg_start_backup 和 pg_stop_backup或者 pg_basebackup命令 
 
 在postres用户下
	第一种：pg_start_backup
 	步骤1 执行pg_start_backup开始备份，如下所示：
 	SELECT pg_start_backup('base', false, false); --开始备份
	select pg_stop_backup(false); --结束备份
    第二种：全量备份 
postgres@1652d4ff599c:/$ pg_basebackup -Ft -Pv -Xf -z -Z5 -p 5432 -D /var/lib/postgresql/archive
pg_basebackup: initiating base backup, waiting for checkpoint to complete #  正在启动基础备份，并等待当前数据库的检查点（checkpoint）完成。检查点是将内存中的脏页写入磁盘的过程，确保在执行备份时数据库的状态一致
pg_basebackup: checkpoint completed # 这表示数据库的检查点已经完成，数据现在是安全的，可以进行备份。
pg_basebackup: write-ahead log start point: 0/1E000060 on timeline 3 #这行显示了备份开始时的 WAL（Write-Ahead Log）位置。具体来说 
 #0/1E000060 表示 WAL 的起始位置，通常由两个十六进制数字组成的部分表示。
 #timeline 3 指的是进行备份时的时间线编号，PostgreSQL 允许时间线管理以处理恢复和分支。
80878/80878 kB (100%), 1/1 tablespace
pg_basebackup: write-ahead log end point: 0/1E000138
pg_basebackup: syncing data to disk ...
pg_basebackup: base backup completed


     创建表
     CREATE TABLE tbl
        (
            id SERIAL PRIMARY KEY,
            ival INT NOT NULL DEFAULT 0,
            description TEXT,
            created_time TIMESTAMPTZ NOT NULL DEFAULT now()
     );
     添加数据
  
     SELECT pg_switch_wal(); #手动进行一次WAL切换 由于WAL文件是写满16MB才会进行归档
   
    > \df pg_create_restore_point 查看还原点数据 
    //配置sql
pg_basebackup -Ft -Pv -Xf -z -Z5 -p 5432 -D /var/lib/postgresql/data/archive/back

```



