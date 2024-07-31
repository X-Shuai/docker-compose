### postgis

```shell
docker-compose -f docker-compose.yml -p postgis up -d
# 安装pgadmin
docker run  -d --name pgadmin -p 5434:80  -e "PGADMIN_DEFAULT_EMAIL=xs-shuai@qq.com" -e "PGADMIN_DEFAULT_PASSWORD=xs1234"  dpage/pgadmin4
```

