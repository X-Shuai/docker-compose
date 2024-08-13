#!/bin/bash  

# 定义要追加的 IP 地址和主机名  
hosts=(  
    "192.168.59.133    node1"  
    "192.168.59.134    node2"  
    "192.168.59.135    node3"  
    "192.168.59.136    node4"  
)  

# 循环遍历每个主机条目并追加到 /etc/hosts  
for host in "${hosts[@]}"; do  
    echo "正在添加到 /etc/hosts: $host"  
    echo "$host" | sudo tee -a /etc/hosts > /dev/null  
done  

echo "所有主机条目已成功添加到 /etc/hosts！" 