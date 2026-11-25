# SeaTunnel 组件

> **一句话定位**：SeaTunnel 是本机湖仓链路的数据集成工具。它用自研的 Zeta 引擎独立运行，默认不交给 Flink 执行。

> **先澄清两个疑问**：SeaTunnel 需要独立部署，本机用 Docker 单容器安装。"交给 Flink 执行"是旧认知，现在它自带执行引擎，Flink 只是三种可选项之一。

## 一、文档地图

| 文档 | 回答什么 | 何时读 |
| --- | --- | --- |
| 基本原理.md | SeaTunnel 是什么，Zeta 与 Flink 是什么关系 | 安装前 |
| 安装教程.md | 单容器怎么装、怎么验收 | 第一次安装 |
| 基本使用.md | 作业怎么写、怎么提交、怎么看结果 | 装完之后 |
| Web UI 开启教程.md | 浏览器怎么看集群与作业 | 需要图形界面时 |

> 本文只做导航。命令全文放安装教程，作业写法放基本使用，取舍依据放基本原理。读者按上表顺序读即可。

## 二、部署形态

> **本机选型**：一个容器同时跑 Zeta 引擎的 master 与 worker。这与本机 Flink 单容器的选型一致，都为省内存。镜像自带脚本 seatunnel-cluster.sh，不带参数默认以 master_and_worker 角色启动，单容器即是单节点集群。

| 形态 | 容器数 | 适用 |
| --- | --- | --- |
| 单节点单容器 | 1 | 本机演示、学习、开发调试 |
| 分容器集群 | 1 master + N worker | 生产、需要横向扩容、需要故障隔离 |

**为什么官方分开**：Zeta 引擎分 master 与 worker 两类角色。master 做调度与协调，worker 执行数据读写。分开后可独立扩 worker、独立重启 master、给不同角色分配内存。生产环境按此部署。

**为什么本机合并**：单机演示不需要横向扩容。合并后只有一份镜像、一个容器名。省内存，也省掉跨容器成员发现配置。master_and_worker 角色由镜像脚本默认支持，无需额外参数。

> 单容器的代价是 master 与 worker 共命运。一个进程组退出，整个容器结束。这个代价在本机可接受。

## 三、先回答两个疑问

### 3.1 要不要单独用 Docker 装

要。SeaTunnel 3.x 默认用自研的 Zeta 引擎，这是一套 master 加 worker 的独立服务。它需要独立部署。本机用 Docker 单容器装，一个容器同时承担两个角色。

### 3.2 它不是交给 Flink 执行吗

那是旧认知。SeaTunnel 早期（1.x 时代，原名 Waterdrop）跑在 Spark 上，后来支持 Flink。从 2.3.x 起，它引入自研的 Zeta 引擎并成为默认引擎。现在它支持三种执行引擎：Zeta、Flink、Spark。交给 Flink 执行只是三者之一，不再是首选。

## 四、本机引擎选型

| 引擎 | 是否独立部署 | 本机选择 | 原因 |
| --- | --- | --- | --- |
| Zeta | 是 | 选用 | 默认推荐、无外部依赖、资源低、CDC 好 |
| Flink | 否，复用已有集群 | 不选 | 本机 Flink 限 1G 内存，不宜再背同步作业 |
| Spark | 否 | 不选 | 本机无 Spark，且链路以流为主 |

官方初选规则只有一条：没有现成 Flink 或 Spark 运维体系时，优先从 Zeta 开始。本机虽有 Flink，但它是限 1G 内存的单容器演示集群，主业是写湖链路。数据同步作业独立交给 Zeta，不抢占 Flink 槽位，职责更清晰。

## 五、当前基线

> **核对时点**：2026-11-22。macOS arm64 / Docker Desktop。以下为规划值，安装教程落地后回填实测值。

| 项 | 取值 |
| --- | --- |
| 镜像 | apache/seatunnel:3.1.0，arm64 原生 |
| 集群形态 | 单容器 seatunnel，master + worker 同容器 |
| 引擎 | Zeta（SeaTunnel Engine） |
| REST API 与 Web UI | http://localhost:18081 |
| 网络 | whd-net，容器别名 seatunnel，固定 IP 172.30.0.19 |
| 作业目录 | jobs/ 目录绑定挂载到容器 /jobs |
| 客户端 | docker exec 进容器调 seatunnel.sh |

## 六、端口与目录

| 端口 | 用途 | 是否映射宿主 |
| --- | --- | --- |
| 18081 | REST API 与 Web UI（宿主），容器内 8080 | 是 |
| 5801 | Hazelcast 集群内部通信 | 否 |

| 目录 | 内容 |
| --- | --- |
| jobs/ | 作业配置文件，绑定挂载到容器 /jobs |

> 5801 只在集群成员之间通信。单节点 master_and_worker 时它只在容器内部用，不映射宿主。将来扩成多节点集群时，成员之间在 whd-net 内直接用 5801 互通，同样不需要映射宿主。

## 七、版本矩阵

| 组件 | 版本 |
| --- | --- |
| SeaTunnel 镜像 | apache/seatunnel:3.1.0 |
| 执行引擎 | Zeta |
| Java | 11（3.1.0 最低要求 11） |
| 内置连接器 | FakeSource、Console |

> 镜像默认只带 FakeSource 与 Console 两个连接器。对接 MySQL、Doris、Kafka 等源端时，需要把对应 connector jar 放进容器的 connectors/ 目录。这是后续外部对接阶段的事，独立安装阶段不涉及。
