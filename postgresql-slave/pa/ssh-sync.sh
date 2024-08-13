#!/bin/bash
# 定义目标主机数组
hosts=("root@192.168.59.133" "root@192.168.59.134" "root@192.168.59.135" "root@192.168.59.136" )  # 替换为实际的用户名和主机名

# 生成 SSH 密钥，使用默认路径和空密码
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "root"

# 将公钥同步到目标主机
for host in "${hosts[@]}"; do
    echo "将公钥同步到 $host ..."
    ssh-copy-id "$host"
done
echo "所有公钥已成功同步！"