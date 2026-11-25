# Kafka 安装文档

> 一句话结论：本文档交付单节点 Kafka 的编排与安装命令。Kafka 采用 KRaft 模式。broker 与 controller 跑在同一个进程。容器接入 whd-net，别名 kafka。本机端口 9092，容器内端口 29092。

> 核对时点：2026-11-21。Docker Server 29.7.2 / Compose v5.5.0 / macOS arm64。共享网络 whd-net 已存在，子网 172.30.0.0/24。版本基线已由 3.9.1 改为 4.3.2。

> 状态边界：本次只交付文档与编排文件。容器未启动。镜像 apache/kafka:4.3.2 的 arm64 构建在本机未完成拉取。安装前按 1.2 复核。

> 版本选型：4.3.2 属 Apache 仍支持版本。kafbat UI v1.5.1 覆盖 Kafka 4.3.0 metadata version。4.4.0 无官方兼容声明，本机暂不采用。依据：kafbat 官方 FAQ 与 GitHub releases。

> 日常 topic 与消息操作见 基本操作.md。kafbat UI 安装与使用见 kafbat-ui-安装使用教程.md。

---

## 一、前置核对

### 1.1 环境判据

表 1-1 前置核对项

| 项 | 判据 | 核对命令 |
| --- | --- | --- |
| Docker | Server 29.7.2 及以上 | docker version |
| Compose | v5.5.0 及以上 | docker compose version |
| 共享网络 | whd-net 存在，子网 172.30.0.0/24 | docker network inspect whd-net |
| 宿主端口 | 9092 未被监听 | lsof -nP -iTCP:9092 -sTCP:LISTEN |
| 数据目录 | /Users/wenhuadong/docker/messaging/kafka/data 为空 | ls -la /Users/wenhuadong/docker/messaging/kafka/data |
| 编排语法 | docker compose config 无报错 | 见下方命令块 |

```bash
docker version --format '{{.Server.Version}}'
docker compose version
docker network inspect whd-net --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'
lsof -nP -iTCP:9092 -iTCP:9093 -sTCP:LISTEN
ls -la /Users/wenhuadong/docker/messaging/kafka/data
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml config -q
```

### 1.2 镜像与架构核对

本机 CPU 架构为 arm64。Docker Hub 直连超时。daemon.json 已配置三个镜像加速站。编排固定 tag 为 apache/kafka:4.3.2，不用 latest。

① 先试短名拉取。
② 短名拉取失败时，走镜像站完整路径。
③ 拉完后核对镜像架构。
④ 架构输出须为 linux/arm64。

⚠️ 注意（设备·数据）：本机 Docker Hub 直连超时。短名拉取失败属已登记现象。不要改编排里的 tag。按下列路径改用镜像站。

短名拉取（优先）：

```bash
docker pull --platform linux/arm64 apache/kafka:4.3.2
```

镜像站完整路径（三选一，成功一条即可）：

```bash
# 轩辕镜像站
docker pull --platform linux/arm64 docker.xuanyuan.me/apache/kafka:4.3.2
docker tag docker.xuanyuan.me/apache/kafka:4.3.2 apache/kafka:4.3.2

# 1ms 镜像站
docker pull --platform linux/arm64 docker.1ms.run/apache/kafka:4.3.2
docker tag docker.1ms.run/apache/kafka:4.3.2 apache/kafka:4.3.2

# DaoCloud 镜像站
docker pull --platform linux/arm64 docker.m.daocloud.io/apache/kafka:4.3.2
docker tag docker.m.daocloud.io/apache/kafka:4.3.2 apache/kafka:4.3.2
```

核对架构：

```bash
docker image inspect apache/kafka:4.3.2 --format '{{.Os}}/{{.Architecture}}'
# 期望输出 linux/arm64
```

docker tag 只改本地名称，不改镜像内容。编排继续引用短名。若三个站点均报 manifest unknown，先核对站点的 tag 清单。本文档不预设替代 tag。


### 1.3 公共性红线

① 本次不创建任何业务 topic。
② 本次不改 whd-net 的子网与网关。
③ 本次不动 Doris、MinIO、Flink、Superset、DolphinScheduler 的容器。
④ 本次不映射 29092 与 9093 到宿主。


---

## 二、安装步骤

### 2.1 文件清单

```text
kafka/
├── README.md                  # 本文档：安装手册
├── 基本操作.md                 # topic 与消息操作
├── kafbat-ui-安装使用教程.md   # kafbat UI 安装与使用
├── docker-compose.whd.yml     # 编排，name: kafka
├── conf/                      # 当前为空，配置由环境变量注入
└── data/                      # KRaft 元数据与消息日志，bind mount
```

conf/ 当前为空。镜像配置全部由编排的 environment 注入。后续若增加 server.properties，按 :ro 挂载，并在本文档登记。

### 2.2 启动

① 复核第一章全部判据。
② 执行启动命令。
③ 等待健康检查转为 healthy。

```bash
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml up -d
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml ps
docker inspect kafka --format '{{.State.Health.Status}}'
```

### 2.3 参数解释

表 2-1 编排参数

| 参数 | 取值 | 作用 |
| --- | --- | --- |
| name | kafka | Compose 项目名等于组件目录名 |
| image | apache/kafka:4.3.2 | 固定 tag，KRaft 单节点 |
| container_name / hostname / 网络别名 | kafka | 三者一致，供同网络容器解析 |
| user | 0:0 | 容器内以 root 写宿主 bind mount 数据卷 |
| ports | 9092:9092 | 仅本机客户端口映射到宿主 |
| volumes | 绝对路径 data:/var/lib/kafka/data | 消息与 KRaft 元数据持久化 |
| networks | whd-net external: true | 复用唯一共享网络，禁止 compose 自建 |
| restart | unless-stopped | 宿主重启后自动拉起 |

表 2-2 环境变量

| 变量 | 取值 | 作用 |
| --- | --- | --- |
| KAFKA_NODE_ID | 1 | 节点号，与投票名单一致 |
| KAFKA_PROCESS_ROLES | broker,controller | 单进程兼任两个角色，不部署 ZooKeeper |
| KAFKA_LISTENERS | INTERNAL://:29092,EXTERNAL://:9092,CONTROLLER://:9093 | 定义三个监听端点 |
| KAFKA_ADVERTISED_LISTENERS | INTERNAL://kafka:29092,EXTERNAL://localhost:9092 | 返回给客户端的地址，决定客户端能否连回 |
| KAFKA_LISTENER_SECURITY_PROTOCOL_MAP | 三个 listener 均为 PLAINTEXT | 本机明文，无鉴权 |
| KAFKA_INTER_BROKER_LISTENER_NAME | INTERNAL | broker 间通信走 29092 |
| KAFKA_CONTROLLER_LISTENER_NAMES | CONTROLLER | 控制器走 9093 |
| KAFKA_CONTROLLER_QUORUM_VOTERS | 1@kafka:9093 | 单节点投票名单 |
| KAFKA_LOG_DIRS | /var/lib/kafka/data | 数据写入挂载卷 |
| KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR | 1 | 单节点必须降为 1 |
| KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR | 1 | 单节点必须降为 1 |
| KAFKA_TRANSACTION_STATE_LOG_MIN_ISR | 1 | 单节点必须降为 1 |
| KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS | 0 | 免去首次 rebalance 等待 |
| KAFKA_HEAP_OPTS | -Xms512m -Xmx512m | 限堆，避免挤占 Doris BE 内存 |

⚠️ 注意（设备·数据）：KAFKA_ADVERTISED_LISTENERS 决定客户端能否连回。改别名或宿主端口时，必须同步改这一行。


### 2.4 地址判据

表 2-3 三套地址

| 场景 | 客户端写什么 | 反例 |
| --- | --- | --- |
| 本机客户端 → Kafka | localhost:9092 | kafka:29092 |
| 同网络容器 → Kafka | kafka:29092 | localhost:9092 |
| 容器内客户端 → 宿主 broker | 本文档不提供此路径 | host.docker.internal:9092 |

第三行的原因：EXTERNAL listener 向客户端宣告 localhost:9092。其他容器收到该地址后指向自身，连接随即失败。

---

## 三、首次初始化

### 3.1 KRaft 格式化

① 镜像首次启动自动格式化数据目录。
② 格式化结果写入 meta.properties。
③ 该文件随 bind mount 保留。
④ 容器重建不会重复格式化。

```bash
docker exec kafka sh -c 'ls -la /var/lib/kafka/data | head -20'
docker logs kafka 2>&1 | grep -E 'formatted|started' | tail -10
```

⚠️ 注意（设备·数据）：本机未实装，首次格式化结果待执行上述命令复核。若日志报 cluster id 相关错误，先保留日志原文，再决定是否在编排中补环境变量。本文档不预设该变量的名称。

### 3.2 健康检查

编排的 healthcheck 调用 kafka-broker-api-versions.sh。镜像内 CLI 目录按 /opt/kafka/bin 编写。安装前先复核路径。

```bash
docker run --rm --entrypoint sh apache/kafka:4.3.2 -c 'ls /opt/kafka/bin | head -10'
docker exec kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | head -5
```

路径与镜像不符时，同步改编排的 healthcheck 与本文档命令。

### 3.3 公共性收口

```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

期望输出为空。业务 topic 由项目阶段创建。

---

## 四、连通性验证

表 4-1 验收判据

| 编号 | 视角 | 命令要点 | 期望 |
| --- | --- | --- | --- |
| 1 | 容器状态 | docker compose ps | healthy |
| 2 | 本机客户端口 | kafka-topics.sh 连 localhost:9092 | 列出 topic，无报错 |
| 3 | 同网络容器 | 临时容器连 kafka:29092 | 返回 broker API 版本 |
| 4 | 收发消息 | 临时 topic 写入并读出 | 读回原消息 |
| 5 | 网络归属 | docker network inspect whd-net | 容器 kafka 在网内 |

### 4.1 三视角命令

```bash
# 视角 1 / 2：容器状态与本机客户端
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml ps
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# 视角 3：同网络临时容器，复用同一镜像，不引入新镜像
docker run --rm --network whd-net \
  --entrypoint /opt/kafka/bin/kafka-broker-api-versions.sh \
  apache/kafka:4.3.2 --bootstrap-server kafka:29092 | head -5

# 视角 5：网络归属
docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} | {{.IPv4Address}}{{println}}{{end}}'
```

### 4.2 收发消息冒烟

⚠️ 注意（设备·数据）：临时 topic _whd_smoke 用完即删。交付时 topic 列表须为空。

```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --create \
  --topic _whd_smoke --partitions 1 --replication-factor 1

printf 'whd-kafka-smoke\n' | docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic _whd_smoke

docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic _whd_smoke \
  --from-beginning --timeout-ms 8000

docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic _whd_smoke
```

期望第三条命令读回 whd-kafka-smoke。第四条命令执行后，3.3 的 topic 列表回到空。

---

## 五、单独停止与重来

### 5.1 停止与启动

```bash
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml stop
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml start
```

### 5.2 重建容器

⚠️ 注意（设备·数据）：down 不加 -v。bind mount 数据卷保留，KRaft 集群 ID 不变。

```bash
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml down
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml up -d
```

### 5.3 清空数据

⚠️ 注意（设备·数据）：此操作删除全部消息与 KRaft 元数据。集群 ID 重新生成。执行前确认无项目在用。

```bash
docker compose -f /Users/wenhuadong/docker/messaging/kafka/docker-compose.whd.yml down
rm -rf /Users/wenhuadong/docker/messaging/kafka/data/*
```


---

## 六、踩坑与回填

### 6.1 踩坑表

表 6-1 现象、原因、处理与预防

| 现象 | 原因 | 处理 | 预防 |
| --- | --- | --- | --- |
| 启动后退出，日志报副本因子不满足 | 单节点却用了默认副本因子 3 | 核对三个副本因子变量均为 1 | 不改这三个变量 |
| 本机客户端连上后立刻断 | advertised 地址写成 kafka:29092 | EXTERNAL listener 改回 localhost:9092 | 按表 2-3 写地址 |
| 同网络容器报 Connection refused | 容器客户端写了 localhost:9092 | 改用 kafka:29092 | 按表 2-3 写地址 |
| 日志报数据目录无写权限 | 宿主 bind mount 与容器 uid 不匹配 | 保留 user: 0:0 | 不删 user 行 |
| healthcheck 一直 unhealthy | CLI 路径与镜像不符 | 按 3.2 复核并同步改编排 | 升级镜像后重跑 3.2 |
| 镜像拉取超时或报 manifest unknown | Docker Hub 直连超时，加速站缺该 tag | 按 1.2 走镜像站完整路径，再用 docker tag 改成短名 | 固定 tag，不用 latest |
| 交付时 topic 列表非空 | 冒烟 topic 未删除 | 按 4.2 删除 _whd_smoke | 交付前跑 3.3 |

镜像站完整路径命令见 1.2。站点来源与平台登记见全局基线 E-06。

### 6.2 回填表

表 6-2 本组件登记项

| 项 | 值 | 位置 |
| --- | --- | --- |
| 镜像 tag | apache/kafka:4.3.2 | docker-compose.whd.yml |
| Compose 项目名 | kafka | 编排首行 |
| 网络别名 | kafka | 全局基线 |
| 宿主端口 | 9092 | 全局基线 |
| 容器内部端口 | 29092 / 9093，不映射宿主 | 编排 environment |
| 数据卷 | /Users/wenhuadong/docker/messaging/kafka/data | 编排 volumes |
| 账号口令 | 无，PLAINTEXT 无鉴权 | 不设；不暴露到公网 |

---

## 七、本篇小结

1. Kafka 以单节点 KRaft 模式接入 whd-net，别名 kafka。
2. 双 listener 分别服务本机与同网络容器。地址写错会连回自身。
3. 本次只交付文档与编排。容器未启动，格式化结果待实装复核。
4. 公共层交付时 topic 列表为空，业务 topic 由项目阶段创建。
