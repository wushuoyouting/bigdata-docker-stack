# Flink 组件

> **一句话定位**：Flink 是本机湖仓链路的计算引擎。它从 Doris 读 ADS 结果，写入 MinIO 上的 Paimon 湖表，让 Doris 再通过只读 Catalog 回查对账。
>
> **Paimon 不是服务**：Paimon 是表格式加一组 connector jar。它不单独起容器。要独立部署的只有 Flink 集群。

## 一、文档地图

| 文档 | 回答什么 | 何时读 |
| --- | --- | --- |
| 基本原理.md | Flink 是什么，JM、TM、Client 各做什么 | 安装前 |
| 安装教程.md | 单容器怎么装、怎么验收 | 第一次安装 |
| 基本使用.md | Web UI、SQL CLI、作业提交怎么用 | 装完之后 |
| 外部对接.md | Doris、Paimon、MinIO 怎么接 | 需要写湖时 |
| Dinky安装使用.md | 图形化 Web SQL IDE 怎么装 | 需要图形界面时 |

> 本文只做导航。命令全文放安装教程，参数细节放对应专题。读者按上表顺序读即可。

## 二、部署形态

> **本机选型**：一个容器同时跑 JobManager、TaskManager，SQL Client 按需从同一个容器进入。本机是 16G 内存的演示环境，不为角色隔离多开容器。

| 形态 | 容器数 | 适用 |
| --- | --- | --- |
| 单容器本地集群 | 1 | 本机演示、学习、开发调试 |
| 官方分容器集群 | 1 JM + N TM | 生产、需要单独扩 TM、需要故障隔离 |

**为什么官方分开**：三个角色职责不同。JM 做调度与协调，TM 做执行，Client 只提交作业。分开后能独立扩容 TM、独立重启 JM、给不同角色分配内存。生产环境按此部署。

**为什么本机合并**：单机演示不需要独立扩容。合并后只有一份镜像、一个容器名、一个 checkpoint 目录。省内存，也省掉跨容器 RPC 地址配置。SQL Client 不是常驻服务，是镜像自带的命令行工具，用的时候从容器内调用。

> 单容器的代价是 JM 与 TM 共命运。一个进程组退出，整个容器结束。这个代价在本机可接受。

## 三、当前基线

> **核对时点**：2026-11-17。macOS arm64 / Docker Desktop。以下为实测值。

| 项 | 实测值 |
| --- | --- |
| 镜像 | flink:1.20.5-java11，arm64 原生 |
| 集群形态 | 单容器 flink，JM + TM 同容器 |
| Web UI | http://localhost:8081 |
| 网络 | whd-net，容器别名 flink |
| 槽位 | 2 |
| 元数据持久化 | checkpoints/ 目录绑定挂载 |
| 客户端 | docker exec 进容器调 sql-client.sh |

> **历史状态**：此前用 flink-jobmanager 与 flink-taskmanager 两个容器。本次整理后改为单容器。旧容器名不再使用。若本机仍存在旧容器，先按安装教程清理。

## 四、端口与目录

| 端口 | 用途 | 是否映射宿主 |
| --- | --- | --- |
| 8081 | Web UI 与 REST | 是 |
| 6123 | JM 与 TM 内部 RPC | 否 |

| 目录 | 内容 |
| --- | --- |
| jars/ | connector jar，整目录挂载到 /opt/flink/custom-jars，启动时软链进 lib |
| checkpoints/ | checkpoint 与 savepoint，JM 与 TM 共用 |
| sql/ | Doris 与 Paimon 脚本副本，挂载到 /opt/flink/sql |

## 五、边界说明

**独立安装阶段**：装集群并挂载 jar 与 sql 目录。验到 Web UI 有 TM、SQL Client 能执行 SHOW CATALOGS。不建 Catalog，不提交写湖作业。

**外部对接阶段**：需要写湖时再读外部对接.md。该阶段使用已挂载的 connector jar、建 Paimon Catalog、提交写回作业，并做 MinIO 与 Doris 回查。

jar 与 sql 一律从宿主机挂载。容器重建后依赖与脚本不丢失。直接 docker cp 进容器的文件会在重建时丢失。

**图形界面阶段**：需要浏览器写 SQL 时再读 Dinky安装使用.md。Dinky 复用本集群，不另起计算引擎。

## 六、版本矩阵

| 组件 | 版本 |
| --- | --- |
| Flink 镜像 | flink:1.20.5-java11 |
| Paimon connector | paimon-flink-1.20-1.3.1.jar |
| Doris connector | flink-doris-connector-1.20-25.1.0.jar |
| S3 文件系统 | flink-s3-fs-hadoop-1.20.5.jar |
| Java | 11 |

> jar 版本必须与 Flink 大版本 1.20 一致。Doris 内置 Paimon 版本、Flink 侧 connector 版本、Paimon 表格式版本三者不是一回事。写湖前按官方兼容矩阵复核。
