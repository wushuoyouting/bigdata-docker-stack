# StarRocks-单机版安装文档

> 本文给本机装好 StarRocks allin1 单容器。适合已接入 whd-net 的机器。读完照命令可完成安装与验收。
> 一句话结论：用 starrocks/allin1-ubuntu:4.1.7 起一个 allin1 单容器。该容器接入 whd-net，宿主端口避开 Doris，hostname 固定，FE 元数据与 BE 数据挂到本机目录。
> 核对时点：2026-11-17。镜像已在本地，ID 7f6041f6d537。实测架构 linux/amd64，架构用 uname -m 实测。本机 Docker Server 29.7.2 / Compose v5.5.0 / macOS arm64。
> 状态：容器已创建并运行，固定 IP 172.30.0.10。装后验收表在装完后执行。

---

## 一、适用边界

表 1-1 组件定位

| 项 | 值 |
| --- | --- |
| 组件 | StarRocks 4.1.7 allin1，单容器同时跑 FE 与 BE |
| 目录 | /Users/wenhuadong/docker/olap/starrocks/ |
| 部署方式 | 单条 docker run，不用 compose |
| 容器名 | starrocks |
| 网络别名 | starrocks |
| 固定 IP | 172.30.0.10，避开 Doris FE 保留的 .8 |
| 共享网络 | whd-net |
| 组件端口 | 容器内保持镜像默认，宿主侧避让 Doris |
| 公共性红线 | 安装阶段不建库、不建表、不建数据源、不提交作业 |

⚠️ 注意：本组件与 Doris 使用同一组容器内部端口。宿主侧必须错开，容器内部端口不变。Doris 已占用 8030 / 9030 / 9010 / 8040 / 9050，本组件用 19030 / 18030 / 18040。

⚠️ 注意：镜像是 linux/amd64，本机是 arm64。启动须带 --platform linux/amd64。指令模拟会增加启动耗时。依据：docker run 平台警告与容器内 uname -m 实测。

⚠️ 注意：镜像 fe.conf 的 FE 堆是 -Xmx8192m。本机内存 16G，须在启动前降到 2048m，并给 BE 设 mem_limit = 2G。依据：镜像内 fe.conf 实测。

---

## 二、前置核对

### 2.1 逐项检查

表 2-1 前置检查项

| 项 | 命令 | 判据 |
| --- | --- | --- |
| Docker 已启动 | docker version | 有 Server 段 |
| 共享网络已存在 | docker network inspect whd-net | 子网是 172.30.0.0/24 |
| 镜像已在本地 | docker image ls 查 starrocks/allin1-ubuntu:4.1.7 | 有该 tag |
| 镜像架构 | docker run 内 uname -m | 输出 x86_64 |
| 宿主端口空闲 | lsof 查三个宿主端口 | lsof 无输出 |
| 内存余量 | docker stats --no-stream | 预留 8G 给本组件 |

💡 提示：whd-net 只建一次。网络已存在时不要重建。重建会让已接入容器全部掉线。

### 2.2 查端口占用

```bash
lsof -nP -iTCP:19030 -iTCP:18030 -iTCP:18040 -sTCP:LISTEN
```

判据：无输出。Doris 已登记 8030 / 9030 / 9010 / 8040 / 9050，本组件的宿主端口改用 19030 / 18030 / 18040。

### 2.3 建目录

```bash
mkdir -p /Users/wenhuadong/docker/olap/starrocks/conf \
         /Users/wenhuadong/docker/olap/starrocks/volumes/fe/meta \
         /Users/wenhuadong/docker/olap/starrocks/volumes/be/storage
```

卷路径一律写绝对路径。换目录执行时不会指错位置。

### 2.4 辨析镜像索引输出

本 tag 指向 OCI 多架构索引。索引只记录各平台的子清单引用，不记录容器配置。依据：Descriptor.mediaType 为 application/vnd.oci.image.index.v1+json。

表 2-2 inspect 字段判读

| 字段 | 输出 | 含义 |
| --- | --- | --- |
| Config | 空对象 | 索引层没有容器配置 |
| Architecture | 空字符串 | 索引层不声明架构 |
| Os | 空字符串 | 索引层不声明操作系统 |
| RootFS | 空对象 | 索引层没有层清单 |
| Size | 3617 | Docker 报出的对象大小，不是镜像体积 |
| Id | sha256:7f6041f6d537… | 索引 digest，与 RepoDigests 一致 |

⚠️ 注意：用 docker image inspect 查架构的命令对本镜像返回空值。该命令读取 Architecture 与 Os。索引层没有这两项。本镜像按下列命令判读。

```bash
docker image ls starrocks/allin1-ubuntu:4.1.7
docker run --rm --entrypoint /bin/bash starrocks/allin1-ubuntu:4.1.7 -c 'uname -m'
```

① 第一条看镜像体积。本机显示 5.17GB。
② 第二条启动一次性容器，不跑服务。Docker 打印平台警告，并输出 x86_64。
③ 平台警告写明 linux/amd64 与本机 linux/arm64/v8 不匹配。本文据此固定 --platform linux/amd64。
④ 真实配置与各层位于索引的子清单里。Docker 按平台自动选择，无需手工解析索引。

💡 提示：docker buildx imagetools inspect 需要访问 registry。本机实测该命令请求超时。判读走上面两条本地命令。

---

## 三、端口与目录规划

### 3.1 端口映射

表 3-1 端口映射表

| 容器内部端口 | 宿主映射端口 | 用途 | 使用方 |
| --- | --- | --- | --- |
| 9030 | 19030 | FE MySQL 协议 | 本机客户端、同网络容器 |
| 8030 | 18030 | FE HTTP、Web UI、Stream Load 入口 | 本机浏览器、同网络容器 |
| 8040 | 18040 | BE HTTP、BE Web | 本机浏览器 |
| 9020 | 不映射 | FE RPC | 容器内部 |
| 9010 | 不映射 | FE edit log | 容器内部 |
| 9050 | 不映射 | BE 心跳 | 容器内部 |
| 9060 | 不映射 | BE 服务端口 | 容器内部 |
| 8060 | 不映射 | BE brpc | 容器内部 |
| 9070 | 不映射 | BE starlet | 容器内部 |

依据：镜像内 fe.conf 与 be.conf 的实测端口。宿主端口避开 Doris 已占用的 8030 / 9030 / 8040。

⚠️ 注意：只映射三个对外端口。内部通信端口留在 whd-net 内，不暴露给宿主机。

### 3.2 目录与挂载

表 3-2 挂载表

| 本机路径 | 容器路径 | 内容 | 权限 |
| --- | --- | --- | --- |
| starrocks/conf/fe.conf | /data/deploy/starrocks/fe/conf/fe.conf | FE 配置 | 可写 |
| starrocks/conf/be.conf | /data/deploy/starrocks/be/conf/be.conf | BE 配置 | 可写 |
| starrocks/volumes/fe/meta | /data/deploy/starrocks/fe/meta | FE 元数据 | 可写 |
| starrocks/volumes/be/storage | /data/deploy/starrocks/be/storage | BE 数据 | 可写 |

⚠️ 注意：镜像 entrypoint.sh 会向两份 conf 追加 priority_networks。只读挂载会让脚本报 Read-only file system。本组件两份 conf 采用可写挂载。

💡 提示：镜像 director/run.sh 明示持久化目录是 fe/meta 与 be/storage。本文只挂这两个目录，不挂整个部署目录。

### 3.3 命名与三套地址

表 3-3 地址判据

| 视角 | MySQL 协议 | FE HTTP |
| --- | --- | --- |
| 本机 | 127.0.0.1:19030 | http://localhost:18030 |
| 同网络容器 | starrocks:9030 | http://starrocks:8030 |
| starrocks 容器内 | 127.0.0.1:9030 | http://127.0.0.1:8030 |

本机用 localhost 与宿主端口。容器内互访用别名，不写 IP。容器访问宿主用 host.docker.internal。

---

## 四、准备配置文件

本文不整份重写镜像默认配置。先从镜像取出默认两份 conf，再改三处。这样保留镜像的其余参数。

### 4.1 取出默认配置

```bash
cd /Users/wenhuadong/docker/olap/starrocks
# 建停止态容器，只为拷贝镜像原生配置
docker create --name sr-conf-probe --platform linux/amd64 starrocks/allin1-ubuntu:4.1.7
docker cp sr-conf-probe:/data/deploy/starrocks/fe/conf/fe.conf ./conf/fe.conf
docker cp sr-conf-probe:/data/deploy/starrocks/be/conf/be.conf ./conf/be.conf
# 删掉临时容器
docker rm sr-conf-probe
```

💡 提示：docker create 只建停止态容器，不启动服务。docker cp 取完配置后立刻删除该容器。

### 4.2 修改三处

```bash
cd /Users/wenhuadong/docker/olap/starrocks
sed -i '' 's/-Xmx8192m/-Xmx2048m/' conf/fe.conf
printf 'priority_networks = 127.0.0.1/32\n' >> conf/fe.conf
printf 'priority_networks = 127.0.0.1/32\nmem_limit = 2G\n' >> conf/be.conf
grep -nE 'Xmx|priority_networks|mem_limit' conf/fe.conf conf/be.conf
```

① -Xmx2048m 把 FE 堆降到 2G。
② priority_networks 预置后，entrypoint.sh 不再追加该行。
③ mem_limit = 2G 把 BE 进程内存上限固定为 2G。

⚠️ 注意：priority_networks 保持 127.0.0.1/32。镜像 director/run.sh 用 127.0.0.1 完成 BE 注册与 bootstrap。改成容器网段会打破该流程。依据：镜像 director/run.sh 实测。

---

## 五、启动命令

```bash
docker run -d \
  --name starrocks \
  --hostname starrocks \
  --platform linux/amd64 \
  --network whd-net \
  --network-alias starrocks \
  --ip 172.30.0.10 \
  -p 19030:9030 \
  -p 18030:8030 \
  -p 18040:8040 \
  --memory=8g \
  -e GLOG_logtostderr=1 \
  -v /Users/wenhuadong/docker/olap/starrocks/conf/fe.conf:/data/deploy/starrocks/fe/conf/fe.conf \
  -v /Users/wenhuadong/docker/olap/starrocks/conf/be.conf:/data/deploy/starrocks/be/conf/be.conf \
  -v /Users/wenhuadong/docker/olap/starrocks/volumes/fe/meta:/data/deploy/starrocks/fe/meta \
  -v /Users/wenhuadong/docker/olap/starrocks/volumes/be/storage:/data/deploy/starrocks/be/storage \
  --health-cmd /data/deploy/health_check.sh \
  --health-interval 30s \
  --health-timeout 10s \
  --health-start-period 180s \
  --health-retries 5 \
  starrocks/allin1-ubuntu:4.1.7
```

表 5-1 参数解释

| 参数 | 作用 | 依据 |
| --- | --- | --- |
| --hostname starrocks | 固定容器 hostname | FE 元数据记录 hostname，改名后 FE 拒绝启动 |
| --platform linux/amd64 | 指定镜像架构 | 镜像仅 amd64，本机是 arm64 |
| --network whd-net --network-alias starrocks | 接入共享网络并固定别名 | whd-net 是全项目唯一网络，别名不随 IP 变化 |
| --ip 172.30.0.10 | 固定容器 IP，避让 Doris FE 保留的 .8 | 动态分配曾自动落到当时 FE 保留地址 .2 |
| -p 三个映射 | 宿主侧避开 Doris 端口 | Doris 占用 8030 / 9030 / 8040，本组件改用 19030 / 18030 / 18040 |
| --memory=8g | 限制容器内存 | 本机 16G，防止挤掉 Doris BE |
| -e GLOG_logtostderr=1 | BE 日志走 stderr，不进 be.INFO 文件 | amd64 镜像在 arm64 上模拟运行时，BE 写日志文件即段错误退出 |
| 两个 conf 单文件挂载 | 降堆、固定 priority_networks | 从镜像取出配置后改这两处 |
| 两个数据目录挂载 | 持久化 FE 元数据与 BE 数据 | 镜像 director/run.sh 的 PERSISTENT_MSG |
| --health-* | 复用镜像自带健康检查 | 镜像 /data/deploy/health_check.sh 实测 |

💡 提示：health_check.sh 要求 bootstrap_done 文件存在。健康检查在启动初期会失败，本文给 180 秒启动宽限期。依据：镜像 health_check.sh 实测。

---

## 六、装后验证

本次不执行本节命令。装完按 ① 到 ⑩ 逐项打勾。

表 6-1 验收判据

| 编号 | 视角 | 命令 | 判据 |
| --- | --- | --- | --- |
| ① | 容器状态 | docker ps --filter name=starrocks | Up，端口映射为 19030 / 18030 / 18040 |
| ② | 健康状态 | docker inspect --format '{{.State.Health.Status}}' starrocks | healthy |
| ③ | 启动日志 | docker logs --tail 100 starrocks | 无 FE / BE 反复重启记录 |
| ④ | 容器内 HTTP | docker exec starrocks curl -fsS http://127.0.0.1:8030/api/health | 返回健康内容 |
| ⑤ | 本机 HTTP | curl -fsS http://localhost:18030/api/health | 返回健康内容，status 为 ok |
| ⑥ | 本机 MySQL | mysql -h127.0.0.1 -P19030 -uroot -e 'show frontends;' | 返回一行 FE，Alive 为 true |
| ⑦ | BE 注册 | docker exec starrocks mysql -h127.0.0.1 -P9030 -uroot -e 'show backends;' | Alive 为 true |
| ⑧ | 同网络 DNS | docker exec superset getent hosts starrocks | 解析到 172.30.0.10 |
| ⑨ | 持久化 | docker stop starrocks 后 docker start starrocks，重做 ④⑤⑦ | 三项结果不变 |
| ⑩ | 公共性检查 | show databases; | 无业务库；未建桶、未建表、未建数据源 |

⚠️ 注意：本机与同网络容器两个视角必须分别验。本机通不等于容器内通。

⚠️ 注意：镜像把 priority_networks 设为 127.0.0.1/32。跨容器连通性本次未实测。若本机 HTTP 或同网络 DNS 不通，先查 whd-net 占用，再从同网络容器用容器 IP 试连。

---

## 七、首次登录与口令

### 7.1 默认账号与登录入口

① 默认账号是 root，默认空口令。首次启动后用容器内 mysql 免密登录确认。

② MySQL 会话在 starrocks 容器内开。镜像内置 /usr/bin/mysql，不依赖本机装客户端。

```bash
docker exec -it starrocks mysql -h127.0.0.1 -P9030 -uroot
```

💡 提示：宿主装有 mysql 客户端时，本机直连 mysql -h127.0.0.1 -P19030 -uroot 等价。默认空口令不带 -p；改口令后须加 -p。

### 7.2 改口令

③ 进入 MySQL 会话后执行。执行时把 &lt;SR_ROOT_PWD&gt; 换成 .env 里的真值：

```sql
set password for 'root'@'%' = password('<SR_ROOT_PWD>');
```

④ 校验：退出会话，用新口令重新登录，能进入即通过。

```bash
docker exec -it starrocks mysql -h127.0.0.1 -P9030 -uroot -p
```

⚠️ 注意：set password 语法在 4.1.7 是否可用，本次未实测。未通过时记录为待确认项，并按官方 4.1 文档核对语法。

💡 提示：真值在交互会话内输入，不落宿主 shell 历史。不要用 docker exec 一次性 -e 方式执行这条 SQL，真值会进宿主历史与 docker inspect。

### 7.3 .env 凭据文件

⑤ .env 由人工创建，路径 /Users/wenhuadong/docker/olap/starrocks/.env，内容两行：

```bash
SR_ROOT_USER=root
SR_ROOT_PWD=<真实口令>
```

⑥ 权限设 600 并核对：

```bash
chmod 600 /Users/wenhuadong/docker/olap/starrocks/.env
ls -l /Users/wenhuadong/docker/olap/starrocks/.env
set -a; . /Users/wenhuadong/docker/olap/starrocks/.env; set +a
```

判据：-rw-------。

⚠️ 注意：真实口令只写 .env。文档只用 &lt;SR_ROOT_PWD&gt; 占位符。口令不进文档、不进日志、不进任何 git 仓库。

💡 提示：SR_ROOT_USER 供远程连接写法引用，如 Superset 数据源与 Stream Load。容器启动不读该变量。director 的 my.cnf 写死 user=root。账号当前固定为 root。

### 7.4 重建容器的口令约束

⑦ 改口令会牵动启动命令。allin1 镜像每次启动都跑 director。director 用 root 连容器内 FE 执行自举 SQL。自举 SQL 把 BE 注册进 FE。连接由 my.cnf 定位。my.cnf 只写 user=root、host=127.0.0.1、port=9030，不写口令。mysql 客户端从环境变量 MYSQL_PWD 取口令。root 有口令而容器无 MYSQL_PWD 时，自举 SQL 报 1045。director 打印 Password error，停止重试并 shutdown。镜像 run.sh 自带这条提示。

⑧ 改口令后重建容器，启动命令必须带 -e MYSQL_PWD：

```bash
# 停止和删除容器
docker stop starrocks
docker rm -f starrocks
# 重新运行容器
docker run -d \
  --name starrocks \
  --hostname starrocks \
  --platform linux/amd64 \
  --network whd-net \
  --network-alias starrocks \
  -e MYSQL_PWD="$SR_ROOT_PWD" \
  --ip 172.30.0.10 \
  -p 19030:9030 \
  -p 18030:8030 \
  -p 18040:8040 \
  --memory=8g \
  -e GLOG_logtostderr=1 \
  -v /Users/wenhuadong/docker/olap/starrocks/conf/fe.conf:/data/deploy/starrocks/fe/conf/fe.conf \
  -v /Users/wenhuadong/docker/olap/starrocks/conf/be.conf:/data/deploy/starrocks/be/conf/be.conf \
  -v /Users/wenhuadong/docker/olap/starrocks/volumes/fe/meta:/data/deploy/starrocks/fe/meta \
  -v /Users/wenhuadong/docker/olap/starrocks/volumes/be/storage:/data/deploy/starrocks/be/storage \
  --health-cmd /data/deploy/health_check.sh \
  --health-interval 30s \
  --health-timeout 10s \
  --health-start-period 180s \
  --health-retries 5 \
  starrocks/allin1-ubuntu:4.1.7
```

表 7-1 口令消费方判读

| 消费方 | 时机 | 口令来源 |
| --- | --- | --- |
| director 自举 SQL | 每次容器启动 | 环境变量 MYSQL_PWD；my.cnf 只写 user=root，不写口令 |
| 远程客户端 | 连接时 | -p 或连接串，与容器环境变量无关 |
| health_check.sh | 每 30 秒 | 不用口令，只走 FE 与 BE 的 HTTP /api/health |

💡 提示：Doris 官方镜像没有 director 自举环节，改口令后不动启动命令。该约束是本 allin1 镜像特有，不是通用做法。

⚠️ 注意：MYSQL_PWD 按 MySQL 官方说明属不推荐的传口令方式。该值会出现在 docker inspect 输出里。镜像把它作为改口令后的唯一支持传法。本机单用户环境接受该方式。不把 docker inspect 输出外贴。

下列输出取自本机实测，展示 FE、BE 与库列表的正常状态。

````bash
mysql> show frontends
    -> ;
+------+------------------------------+-----------+-------------+----------+-----------+---------+--------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
| Id   | Name                         | IP        | EditLogPort | HttpPort | QueryPort | RpcPort | Role   | ClusterId  | Join | Alive | ReplayedJournalId | LastHeartbeat       | IsHelper | ErrMsg | StartTime           | Version       |
+------+------------------------------+-----------+-------------+----------+-----------+---------+--------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
| 2    | 127.0.0.1_9010_1794595619886 | 127.0.0.1 | 9010        | 8030     | 9030      | 9020    | LEADER | 1026269141 | true | true  | 3722              | 2026-11-13 20:30:52 | true     |        | 2026-11-13 20:27:32 | 4.1.7-b81ff9c |
+------+------------------------------+-----------+-------------+----------+-----------+---------+--------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
1 row in set (0.05 sec)

mysql> show backends;
+-----------+-----------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+-----------+------------------+---------------+---------------+---------+----------------+--------+---------------+--------------------------------------------------------+-------------------+-------------+----------+----------+-------------------+------------+------------+-----------------------------------------------------------+----------+------------+
| BackendId | IP        | HeartbeatPort | BePort | HttpPort | BrpcPort | LastStartTime       | LastHeartbeat       | Alive | SystemDecommissioned | ClusterDecommissioned | TabletNum | DataUsedCapacity | AvailCapacity | TotalCapacity | UsedPct | MaxDiskUsedPct | ErrMsg | Version       | Status                                                 | DataTotalCapacity | DataUsedPct | CpuCores | MemLimit | NumRunningQueries | MemUsedPct | CpuUsedPct | DataCacheMetrics                                          | Location | StatusCode |
+-----------+-----------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+-----------+------------------+---------------+---------------+---------+----------------+--------+---------------+--------------------------------------------------------+-------------------+-------------+----------+----------+-------------------+------------+------------+-----------------------------------------------------------+----------+------------+
| 10001     | 127.0.0.1 | 9050          | 9060   | 8040     | 8060     | 2026-11-13 20:27:33 | 2026-11-13 20:31:07 | true  | false                | false                 | 121       | 135.533 KB       | 97.927 GB     | 460.383 GB    | 78.73 % | 78.73 %        |        | 4.1.7-b81ff9c | {"lastSuccessReportTabletsTime":"2026-11-13 20:30:33"} | 97.927 GB         | 0.00 %      | 10       | 1.800GB  | 0                 | 2.59 %     | 0.1 %      | Status: Normal, DiskUsage: 0B/0B, MemUsage: 6.4KB/368.6MB |          | OK         |
+-----------+-----------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+-----------+------------------+---------------+---------------+---------+----------------+--------+---------------+--------------------------------------------------------+-------------------+-------------+----------+----------+-------------------+------------+------------+-----------------------------------------------------------+----------+------------+
1 row in set (0.02 sec)

mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| _statistics_       |
| information_schema |
| sys                |
+--------------------+
3 rows in set (0.05 sec)
````

---

## 八、停止与重来

### 8.1 停止与启动

```bash
docker stop starrocks
docker start starrocks
```

数据留在 volumes/ 两个目录。stop 与 start 不删数据。

### 8.2 重建容器

```bash
docker rm -f starrocks
```

删除后重新执行启动命令。重建时 hostname 必须仍是 starrocks。启动命令必须带 --ip 172.30.0.10。漏带该参数会回到动态分配，再次落到 Doris FE 保留的 .8。

⚠️ 注意：FE 元数据里记录了 hostname。改名会让 FE 拒绝启动。依据：镜像 director/run.sh 的 HOSTNAME_MISMATCH_MSG。

### 8.3 清空数据

```bash
rm -rf /Users/wenhuadong/docker/olap/starrocks/volumes/fe/meta/* \
       /Users/wenhuadong/docker/olap/starrocks/volumes/be/storage/*
```

⚠️ 注意：这条命令删除 FE 元数据与 BE 全部数据，且不可恢复。执行前先确认本机无需保留这些数据。

---

## 九、专属踩坑详解

本章记录本机实测与镜像脚本判读得到的故障。每条按现象、根因、判据、处理、预防展开。部分条目附复核与依据。未实测项直说未实测，不猜测结论。

表 9-1 踩坑速查表

| 编号 | 分类 | 现象 | 一句话处理 |
| --- | --- | --- | --- |
| 9.1.1 | 镜像架构 | inspect 返回 Config 空对象、Size 3617 | 用 docker image ls 与 uname -m 判读 |
| 9.1.2 | 镜像架构 | exec format error 或启动极慢 | 启动带 --platform linux/amd64 |
| 9.2.1 | BE 日志 | show backends 中 BE 为 DISCONNECTED | 启动加 -e GLOG_logtostderr=1 |
| 9.3.1 | 资源端口 | bind: address already in use | 只改 -p 左侧宿主端口 |
| 9.3.2 | 资源端口 | Exit 137、FE 反复重启 | 降堆、设 mem_limit、分时启动 |
| 9.3.3 | 资源端口 | starrocks 动态分配到 172.30.0.8 | 固定 --ip 172.30.0.10，避让 .8 |
| 9.4.1 | 配置启动 | Read-only file system | conf 改可写挂载 |
| 9.4.2 | 配置启动 | FE 不启动并报 hostname mismatch | 固定 --hostname starrocks |
| 9.4.3 | 配置启动 | director 报 Password error | 补 -e MYSQL_PWD |
| 9.5.1 | 网络导入 | 本机通、同网络容器连 9030 不通 | 查 whd-net 与 priority_networks |
| 9.5.2 | 网络导入 | Stream Load 307 指向 127.0.0.1:8040 | 在容器内发起，或改用 insert |
| 9.5.3 | 网络导入 | 容器之间连不上 | 用别名 starrocks，不用 IP |

### 9.1 镜像架构类

**9.1.1 docker image inspect 返回空配置**

现象：docker image inspect 返回 Config 空对象。Os 与 Architecture 为空。Size 为 3617。
根因：该 tag 指向 OCI 多架构索引。索引层不记录容器配置。
判据：Descriptor.mediaType 为 application/vnd.oci.image.index.v1+json。
处理：① 用 docker image ls 看镜像体积。② 用 docker run 的 uname -m 看架构。
预防：判读架构前，先确认对象是镜像清单还是多架构索引。

⚠️ 注意：00-整体安装要求.md 3.7 的架构判读命令对本镜像返回空值。该命令读取 Architecture 与 Os。索引层没有这两项。

**9.1.2 exec format error 或启动极慢**

现象：容器报 exec format error，或启动后长时间无响应。
根因：镜像是 linux/amd64。本机是 linux/arm64/v8。指令模拟带来额外开销。
判据：docker run 打印平台不匹配警告。
处理：启动命令带 --platform linux/amd64。
预防：涉及该镜像的命令都带该参数。取配置用的 docker create 也要带。

💡 提示：平台警告本身不是故障。缺少 --platform 时，Docker 自动选择 amd64 并模拟执行。

### 9.2 BE 日志崩溃（本机实测）

**9.2.1 show backends 中 BE 为 DISCONNECTED**

现象：show backends 中 BE 的 Alive 为 false，ErrMsg 为 Connection refused。supervisorctl status 显示 beservice FATAL，状态为 Exited too quickly。be/log 只有 be.out，没有 be.INFO。be.out 末尾停在 eBPF 那一行。
根因：amd64 的 BE 二进制在 arm64 模拟下写 glog 日志文件时段错误退出。退出码为 139。日志改走 stderr 后，BE 启动与心跳恢复正常。
判据：
① 容器内执行 supervisorctl status。beservice 为 FATAL。FE 与 director 为 RUNNING。
② 查看 be/log。该目录只有 be.out，始终没有 be.INFO。be.out 每次启动只写到 [eBPF] tls_thread_status 一行。
③ 容器内直接跑 bash be/bin/start_backend.sh --be。退出码为 139。
④ 同一命令加 --logconsole，即设置 GLOG_logtostderr=1。命令持续运行并完成心跳。
处理：启动命令加 -e GLOG_logtostderr=1，然后重建容器。BE 日志改落 supervisor 的 be.out，按 200MB 轮转。
预防：所有启动与重建命令都带该环境变量。不要用内存参数替代它。
复核：重建后 show backends 的 Alive 为 true，ErrMsg 为空。容器健康状态转为 healthy。
依据：本机 2026-11-13 实测。结论已沉淀到 PKB。

⚠️ 注意：GLOG_logtostderr=1 只改日志输出目标。它不改 BE 的内存上限与线程数。

### 9.3 资源与端口类

**9.3.1 宿主端口被占用**

现象：docker run 报 bind: address already in use。
根因：宿主端口与 Doris 已登记端口撞车。
判据：lsof -nP -iTCP:19030 -iTCP:18030 -iTCP:18040 -sTCP:LISTEN 有输出。
处理：只改 -p 左侧的宿主端口。容器内部端口保持 9030 / 8030 / 8040。
预防：启动前用 lsof 查 19030 / 18030 / 18040。避开 Doris 已占用的 8030 / 9030 / 8040。

**9.3.2 FE 反复重启或容器 Exit 137**

现象：FE 反复重启，或容器退出码为 137。
根因：FE 默认堆 8G 与 BE 内存合计吃满 16G 本机。
判据：docker inspect 中 OOMKilled 为 true。
处理：① conf/fe.conf 把 -Xmx8192m 改为 -Xmx2048m。② conf/be.conf 设 mem_limit = 2G。③ 启动加 --memory=8g。④ 停掉 Superset 等非必要组件。
预防：Doris BE 最怕被 OOM 杀掉。跑 StarRocks 时优先停 Superset。

**9.3.3 动态 IP 落到 172.30.0.8**

现象：starrocks 容器自动拿到 172.30.0.8。Doris FE 随后起不来。
根因：动态分配池会分配 FE 保留的静态地址 .2。
判据：docker network inspect whd-net 显示 starrocks 占用 .2。
处理：① 先核对 whd-net 的 IP 占用。② 删除冲突容器。③ 启动带 --ip 172.30.0.10 重建。
预防：启动与重建命令都显式带 --ip 172.30.0.10。Doris FE 保留 .2，动态分配会抢占。

### 9.4 配置与启动类

**9.4.1 conf 只读导致 entrypoint 失败**

现象：容器日志报 Read-only file system。FE 或 BE 不启动。
根因：镜像 entrypoint.sh 的 append_if_missing 向两份 conf 追加 priority_networks。只读挂载时写入失败。
判据：docker logs 中出现 Read-only file system。
处理：把两份 conf 改为可写挂载。镜像脚本会向 conf 追加配置。
预防：预置 priority_networks = 127.0.0.1/32 后，脚本不再追加。仍按可写挂载保留容错。

**9.4.2 FE 不启动并报 hostname mismatch**

现象：FE 不启动。fe.log 报 hostname mismatch。
根因：FE 元数据记录了 hostname。重建容器时 hostname 变了。
判据：fe/log/fe.log 出现 hostname mismatch。
处理：重建时固定 --hostname starrocks，与原元数据一致。
预防：所有启动与重建命令都带 --hostname starrocks。依据：镜像 director/run.sh 的 HOSTNAME_MISMATCH_MSG。

**9.4.3 director 报 Password error**

现象：改口令后重启，容器打印 Password error，随后 shutdown。
根因：director 自举 SQL 用 root 连容器内 FE 9030。口令只从环境变量 MYSQL_PWD 取。缺该变量时报 1045。
判据：docker logs 出现 Password error 或 1045。
处理：重建时带 -e MYSQL_PWD="$SR_ROOT_PWD"。真值从 .env 取，由 mysql 客户端在自举时读取。
预防：改口令后同步更新 .env。所有重建命令都带该变量。

⚠️ 注意：MYSQL_PWD 会出现在 docker inspect 输出里。本机单用户环境接受该方式。不把输出外贴。

### 9.5 网络与导入类

**9.5.1 跨容器连 starrocks:9030 不通**

现象：本机连 19030 正常。同网络容器连 starrocks:9030 失败。
根因：priority_networks 为 127.0.0.1/32 时，FE 只绑 loopback。
判据：docker exec superset getent hosts starrocks 能解析。同网络容器连 9030 不通。
处理：① 用 docker network inspect whd-net 确认容器在网内。② 从同网络容器用容器 IP 试连。③ 仍不通则调整 priority_networks，并同步核对 director 的 bootstrap 连接地址。
预防：调整前先备份 conf 与 meta。

⚠️ 注意：这条路径未实测。不要直接改 priority_networks。改动会打破 director 的 loopback 自举流程。

**9.5.2 Stream Load 报 307 并指向 127.0.0.1:8040**

现象：从宿主或跨容器发起 Stream Load。返回 307 后重定向到 127.0.0.1:8040，导入失败。
根因：BE 以 127.0.0.1 注册。重定向地址指向发起方自己。
判据：curl 返回 307。Location 头含 127.0.0.1:8040。
处理：在 starrocks 容器内发起 Stream Load，或改用 insert 写入。
预防：外部 Stream Load 路径未实测。使用前先验证 BE 的注册地址。

**9.5.3 容器之间连不上**

现象：同网络容器报 Unknown host 或 Connection refused。
根因：写了 localhost，或写了容器 IP。
判据：同网络容器解析 starrocks 无结果。
处理：容器互访统一用别名 starrocks。本机用宿主端口，容器间用别名。
预防：容器互访不用 localhost，也不用 IP。

---

## 十、本篇小结

1. 本组件是单容器 allin1。别名 starrocks，固定 IP 172.30.0.10，宿主端口 19030 / 18030 / 18040。
2. 镜像是 amd64。启动须带 --platform，FE 堆须降。
3. hostname 固定、conf 可写、两个数据目录持久化，是三条硬约束。
4. 该 tag 是多架构索引。inspect 返回空配置属正常，判读用 docker image ls 与 uname -m。
