> 官方中文教程：暂无。官方文档：https://ui.docs.kafbat.io/

# kafbat UI 安装与使用教程

> 一句话结论：kafbat UI 是 Kafka 的 Web 管理工具。本文档交付单容器安装命令与常用操作。容器接入 whd-net，别名 kafka-ui，宿主端口 18080，容器内固定 8080。

> 核对时点：2026-11-21。Docker Server 29.7.2 / Compose v5.5.0 / macOS arm64。本机 18080 空闲，无 kafka-ui 容器。Kafka 容器别名为 kafka，容器内 bootstrap 地址为 kafka:29092。

> 状态边界：本次只交付文档，容器未启动。镜像固定 tag 为 kafbat/kafka-ui:v1.5.1。安装前按 1.2 核对 tag 与架构。

> 依据：README.md（Kafka 安装文档）、基本操作.md（topic 与消息操作）、配置准则.md 第 2.4 节（地址判据）、第 3.1 节（端口）。

---

## 一、前置核对

### 1.1 环境判据

表 1-1 前置核对项

| 项 | 判据 | 核对命令 |
| --- | --- | --- |
| Docker | Server 29.7.2 及以上 | docker version |
| 共享网络 | whd-net 存在，子网 172.30.0.0/24 | docker network inspect whd-net |
| Kafka 容器 | kafka 处于 Up 状态 | docker ps --filter name=kafka |
| 宿主端口 | 18080 未被监听 | lsof -nP -iTCP:18080 -sTCP:LISTEN |
| 镜像 | v1.5.1 已落地，架构为 arm64 | docker image inspect kafbat/kafka-ui:v1.5.1 |

```bash
docker version --format '{{.Server.Version}}'
docker network inspect whd-net --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker ps --filter 'name=^/kafka$' --format '{{.Names}} | {{.Status}}'
lsof -nP -iTCP:18080 -sTCP:LISTEN
```

① Kafka 未启动时，先按 README.md 第二章启动 Kafka。
② UI 只做展示与管理，不替代 Kafka 服务。

### 1.2 镜像拉取

本机 CPU 架构为 arm64。Docker Hub 直连超时。daemon.json 已配置三个镜像加速站。

① 先试短名拉取。
② 短名拉取失败时，走镜像站完整路径。
③ 拉完后核对镜像架构。
④ 架构输出须为 linux/arm64。

⚠️ 注意（设备·数据）：短名拉取失败属已登记现象。不要改安装命令里的 tag。按下列路径改用镜像站。

短名拉取（优先）：

```bash
docker pull --platform linux/arm64 kafbat/kafka-ui:v1.5.1
```

镜像站完整路径（三选一，成功一条即可）：

```bash
# 轩辕镜像站
docker pull --platform linux/arm64 docker.xuanyuan.me/kafbat/kafka-ui:v1.5.1
docker tag docker.xuanyuan.me/kafbat/kafka-ui:v1.5.1 kafbat/kafka-ui:v1.5.1

# 1ms 镜像站
docker pull --platform linux/arm64 docker.1ms.run/kafbat/kafka-ui:v1.5.1
docker tag docker.1ms.run/kafbat/kafka-ui:v1.5.1 kafbat/kafka-ui:v1.5.1

# DaoCloud 镜像站
docker pull --platform linux/arm64 docker.m.daocloud.io/kafbat/kafka-ui:v1.5.1
docker tag docker.m.daocloud.io/kafbat/kafka-ui:v1.5.1 kafbat/kafka-ui:v1.5.1
```

核对架构：

```bash
docker image inspect kafbat/kafka-ui:v1.5.1 --format '{{.Os}}/{{.Architecture}}'
# 期望输出 linux/arm64
```

⚠️ 注意（设备·数据）：本机未验证 v1.5.1 是否为该镜像站可用 tag。安装前先核对站点的 tag 清单。若三个站点均报 manifest unknown，换同系列稳定 tag 并回填本节。若镜像只有 amd64，启动命令加 --platform linux/amd64，启动会变慢。

docker tag 只改本地名称，不改镜像内容。安装命令继续引用短名。

### 1.3 版本兼容

本机 Kafka 基线为 apache/kafka:4.3.2。kafbat UI 基线为 v1.5.1。

表 1-2 版本兼容结论

| 组合 | 结论 | 依据 |
| --- | --- | --- |
| kafbat v1.5.1 + Kafka 4.3.2 | 推荐组合 | v1.5.1 覆盖 Kafka 4.3.0 metadata version |
| kafbat v1.5.1 + Kafka 4.4.0 | 能连，非官方承诺 | 无官方兼容声明，新版会显示 Unknown |
| kafbat v1.5.1 + Kafka 3.9.1 | 不推荐 | 3.9 已从 Apache 支持列表归档 |

⚠️ 注意（设备·数据）：kafbat UI 用 MetadataVersion 枚举识别集群版本。新版 Kafka 未覆盖时，UI 显示 Unknown。此时 topic 与消息功能通常仍可用。依据：kafbat 官方 FAQ。

---

## 二、安装步骤

### 2.1 启动

⚠️ 注意（设备·数据）：执行前确认 1.1 全部判据通过。Kafka 必须先于 UI 启动。

```bash
docker run -d \
  --name kafka-ui \
  --network whd-net \
  --network-alias kafka-ui \
  --ip 172.30.0.12 \
  -p 18080:8080 \
  -e KAFKA_CLUSTERS_0_NAME=local \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=kafka:29092 \
  -e KAFKA_CLUSTERS_0_READONLY=false \
  --restart unless-stopped \
  kafbat/kafka-ui:v1.5.1
```

### 2.2 参数解释

表 2-1 启动参数

| 参数 | 取值 | 作用 |
| --- | --- | --- |
| name / network-alias | kafka-ui | 容器名与别名一致 |
| image | kafbat/kafka-ui:v1.5.1 | 固定 tag，不用 latest |
| --ip | 172.30.0.12 | 静态 IP，重建保留 |
| network | whd-net | 复用唯一共享网络 |
| ports | 18080:8080 | 宿主 18080 映射容器 8080 |
| KAFKA_CLUSTERS_0_NAME | local | 集群在 UI 中显示的名称 |
| KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS | kafka:29092 | UI 连接 Kafka 的容器内地址 |
| KAFKA_CLUSTERS_0_READONLY | false | 允许在 UI 中创建与删除 topic |
| restart | unless-stopped | 宿主重启后自动拉起 |

⚠️ 注意（设备·数据）：BOOTSTRAPSERVERS 必须写 kafka:29092。写 localhost:9092 会指向 UI 容器自身。依据：配置准则.md 第 2.4 节。

### 2.3 首次访问

① 浏览器打开 http://localhost:18080。
② 首页显示集群 local，即为连接成功。
③ 本机 Kafka 为 PLAINTEXT，无鉴权。UI 也不设登录。

⚠️ 注意（设备·数据）：不要把 18080 映射到公网地址。UI 无鉴权，任何访问者都能删 topic。

---

## 三、验证

表 3-1 验收判据

| 编号 | 视角 | 命令或操作 | 期望 |
| --- | --- | --- | --- |
| 1 | 容器状态 | docker ps --filter name=kafka-ui | Up 状态 |
| 2 | 健康检查 | curl http://localhost:18080/actuator/health | 返回 UP |
| 3 | 首页 | 浏览器打开 http://localhost:18080 | 显示集群 local |
| 4 | Topic 列表 | 首页进入 Topics | 列表为空或仅业务 topic |
| 5 | 网络归属 | docker network inspect whd-net | 容器 kafka-ui 在网内 |

```bash
docker ps --filter 'name=^/kafka-ui$' --format '{{.Names}} | {{.Status}}'
curl -fsS http://localhost:18080/actuator/health | head -c 200
echo
docker logs kafka-ui --tail 50
docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} | {{.IPv4Address}}{{println}}{{end}}'
```

若 /actuator/health 返回 404，改用首页判据：curl -I http://localhost:18080 返回 200。本文档不预设该端点的开关状态。

---

## 四、使用操作

### 4.1 查看集群与 broker

① 首页点击集群 local。
② Clusters 页显示 broker 列表与节点 ID。
③ 单节点 Kafka 只显示一个 broker。

### 4.2 Topic 操作

① 左侧进入 Topics，查看全部 topic。
② 点击 Create topic，填写名称与分区数。
③ 副本因子填 1，单节点不支持更大值。
④ 删除 topic 时选中目标并确认。

⚠️ 注意（设备·数据）：删除 topic 会清除全部消息。操作不可恢复。公共底座交付时 topic 列表须为空。

表 4-1 常用 topic 字段

| 字段 | 填写值 | 说明 |
| --- | --- | --- |
| Topic name | _whd_smoke | 示例名，用完删除 |
| Partitions | 1 | 单节点示例值 |
| Replication factor | 1 | 单节点必须填 1 |
| Cleanup policy | delete | 默认策略 |

### 4.3 消息查看与发送

① 进入目标 topic 的 Messages 页。
② 选择分区与起始位点，查看消息内容。
③ 点击 Produce message，填写 key 与 value。
④ 发送后刷新页面，确认新消息出现。

💡 提示：UI 发送消息等价于 kafka-console-producer.sh。命令行写法见 基本操作.md 第四章。

### 4.4 消费者组

① 左侧进入 Consumers，查看消费者组列表。
② 点击目标组，查看各分区位点与 LAG。
③ LAG 大于 0 表示存在积压。

💡 提示：重置位点请用 基本操作.md 第 5.2 节命令。UI 侧不提供 dry-run，误操作风险更高。

### 4.5 未配置项

① 本机未部署 Schema Registry，不配置该能力。
② 本机未部署 ksqlDB，不配置该能力。
③ UI 内动态新增集群不在本文档范围。该配置是否持久化待实测确认。

---

## 五、停止与重来

### 5.1 停止与启动

```bash
docker stop kafka-ui
docker start kafka-ui
```

stop 与 start 保留容器配置。

### 5.2 重建容器

```bash
docker rm -f kafka-ui
```

然后按 2.1 重新执行 docker run。UI 配置全部来自环境变量，容器内无业务数据。重建不丢 Kafka 消息。

⚠️ 注意（设备·数据）：rm -f 会丢弃 UI 内的动态配置。本文档不依赖动态配置。

### 5.3 卸载

```bash
docker rm -f kafka-ui
docker rmi kafbat/kafka-ui:v1.5.1
```

卸载只删 UI，不影响 kafka 容器与 data 卷。

---

## 六、踩坑表

表 6-1 现象、原因、处理与预防

| 现象 | 原因 | 处理 | 预防 |
| --- | --- | --- | --- |
| 集群显示离线 | BOOTSTRAPSERVERS 写错 | 改为 kafka:29092 并重建容器 | 按表 2-1 填写 |
| 容器内报 Unknown host kafka | UI 未接入 whd-net | 按 2.1 重建并带 --network whd-net | 不省略网络参数 |
| 本机打不开 UI 页面 | 宿主 18080 被占或容器未起 | 按 3.1 判据逐条查 | 起容器前 lsof 查 18080 |
| 无法创建 topic | READONLY 设为 true | 改为 false 并重建容器 | 本机保持 false |
| 镜像拉取超时 | Docker Hub 直连超时 | 按 1.2 走镜像站完整路径 | 固定 tag，不用 latest |
| 架构不匹配报错 | 镜像无 arm64 构建 | 启动命令加 --platform linux/amd64 | 拉取后先核对架构 |
| health 端点返回 404 | 该版本未暴露 actuator | 改用首页 200 判据 | 按第三章双判据验证 |
| 集群版本显示 Unknown | kafbat 未覆盖该 Kafka metadata version | 按 1.3 换用 4.3.2，或提交 PR 更新枚举 | 不追最新 Kafka 版本 |

---

## 七、回填表与小结

表 7-1 本教程登记项

| 项 | 值 | 位置 |
| --- | --- | --- |
| 镜像 tag | kafbat/kafka-ui:v1.5.1 | 2.1 启动命令 |
| Kafka 版本基线 | apache/kafka:4.3.2 | 1.3 版本兼容 |
| 容器名 / 别名 | kafka-ui | 2.1 启动命令 |
| UI 地址 | http://localhost:18080 | 2.3 首次访问 |
| Kafka bootstrap | kafka:29092 | 表 2-1 |
| 宿主端口 | 18080 | 表 2-1 |
| 账号口令 | 无，UI 无鉴权 | 不暴露到公网 |

1. kafbat UI 以单容器接入 whd-net，别名 kafka-ui，宿主端口 18080，容器内固定 8080。
2. 安装命令含镜像拉取路径，短名与镜像站完整路径均可复制执行。
3. Kafka bootstrap 必须写 kafka:29092，不能写 localhost:9092。
4. 本机 UI 无鉴权，只限本机访问。公共层交付时不建任何业务 topic。
