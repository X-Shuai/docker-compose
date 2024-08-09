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
