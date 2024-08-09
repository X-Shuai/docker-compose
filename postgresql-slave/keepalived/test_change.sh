#!/bin/bash

# 配置变量
PGPORT=${PGPORT:-5432}
VIP_HOST=${VIP_HOST:-192.168.59.100}  # 虚拟主机 IP
PGUSER=${PGUSER:-keepalived}
PGDBNAME=${PGDBNAME:-keepalived}
PGDATA=${PGDATA:-/var/lib/pgsql/12/data}  # 数据目录
LANG=${LANG:-en_US.utf8}
LOG_PATH=${LOG_PATH:-/tmp/log.log}

# SQL 查询语句
IS_MASTER_QUERY="SELECT pg_is_in_recovery()"

# 执行查询并获取结果
is_master_result=$(echo "$IS_MASTER_QUERY" | psql -At -p $PGPORT -U $PGUSER -d $PGDBNAME 2>/dev/null)

# 检查查询是否成功
if [ $? -ne 0 ]; then
    echo "$(date +%F\ %T): 查询执行失败" >> "$LOG_PATH"
    exit 1
fi

# 处理查询结果
if [ "$is_master_result" = "t" ]; then
    echo "$(date +%F\ %T): 当前数据库为从库，开始提升为主库" >> "$LOG_PATH"

    # 停止复制进程
    echo "$(date +%F\ %T): 停止复制进程" >> "$LOG_PATH"
    pg_ctl -D "$PGDATA" promote

    if [ $? -eq 0 ]; then
        echo "$(date +%F\ %T): 成功提升为主库" >> "$LOG_PATH"
    else
        echo "$(date +%F\ %T): 提升为主库失败" >> "$LOG_PATH"
        exit 1
    fi
else
    echo "$(date +%F\ %T): 当前数据库为主库，无需提升" >> "$LOG_PATH"
fi

# 记录测试结束信息
echo "$(date +%F\ %T): 测试 over！" >> "$LOG_PATH"
