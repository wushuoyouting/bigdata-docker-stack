# Iceberg 本地实践文档

> 一句话结论：本目录集中存放 Iceberg 的原理、安装与操作文档。Iceberg 本体是 jar，不是服务。本机方案是现有 Flink 加 JDBC Catalog 加 MinIO，不新增容器。

> 本文解决什么：说明组件定位、文档导航、版本基线、端口与目录约定。
>
> 适用谁：想在本机练习 Iceberg 的初学者。
>
> 读完能做什么：找到目标文档，按版本安装，再做 SQL 练习。

> 整合说明（2026-11-21）：原 /Users/wenhuadong/docker/iceberg 三册文档，与 table_format/Iceberg 的原理及通用操作文档合并于此。原目录保留作历史追溯。

---

## 一、文档清单

组件根目录只放职责文档与导航。安装教程按版本分目录，按形态分文件。

| 文档 | 路径 | 内容 | 适用场景 |
| --- | --- | --- | --- |
| 基本原理 | 基本原理.md | 三层结构、快照、并发、COW 与 MOR、演进 | 理解行为边界 |
| 安装教程 | install/v1.10.1/standalone.md | 挂 jar 加建 JDBC Catalog | 本机搭环境 |
| 基本使用 | 基本使用.md | Flink SQL 建表、写入、快照、增量读取、Schema 演进 | 本机 JDBC 操作 |
| 通用操作 | 通用操作.md | Spark 配 MinIO 的 hadoop catalog、时间旅行、快照维护 | 非本机方案场景 |

① 推荐按基本原理、安装教程、基本使用的顺序阅读。
② 只关心命令的读者，可直接从安装教程进入。
③ 用 Spark 或 Hadoop Catalog 的读者，读通用操作。

## 二、环境说明

① Iceberg 本体是 jar，不是服务。挂进引擎的 classpath 才工作。
② 计算引擎用现有 Flink。不部署新的 Flink 容器，不部署 REST Catalog 容器。
③ Catalog 选 JDBC 型。元数据表落在宿主 PostgreSQL 的 iceberg_meta 库，靠数据库事务保证提交原子性。
④ 对象存储用现有 MinIO，内网地址 http://minio:9000，数据前缀 s3://lakehouse/iceberg/。
⑤ 上游源码副本 table-formats/iceberg/iceberg 已停用，不进仓库，保留作追溯，不再从它构建镜像。

## 三、版本基线

| 项 | 取值 |
| --- | --- |
| Iceberg | 1.10.1 |
| Flink | 1.20.5，现有容器 |
| PostgreSQL | 14.20，宿主，库 iceberg_meta |
| MinIO | RELEASE.2025-02-07T23-21-09Z |
| Catalog 类型 | jdbc，catalog-impl 为 org.apache.iceberg.jdbc.JdbcCatalog |
| 形态 | 挂 jar 到现有 Flink |

版本来自官方发布仓库。实际版本以本机加载结果为准。

## 四、端口与目录

| 项 | 取值 |
| --- | --- |
| 网络 | whd-net，172.30.0.0/24 |
| Flink | 复用现有 flink 容器，不新增 IP |
| PostgreSQL | 宿主 127.0.0.1:5432，容器内用 host.docker.internal:5432 |
| MinIO | http://minio:9000，172.30.0.3 |
| 安装目录 | install/v1.10.1/ |
| 数据目录 | 复用 MinIO 的 object-storage/minio/data，前缀 lakehouse/iceberg |

本机不再为 Iceberg 分配 whd-net 静态地址。凭据从本机环境变量与 minio/.env 读取，真实值不进仓库。

## 五、来源与约定

① 安装教程与本机操作册基于现有 Flink 与 JDBC Catalog 编写。
② 基本原理册与通用操作册来自表格式专题文档。
③ 命令中的凭据为占位符，实际值来自本机环境变量与 .env。
④ 上游源码副本已停用，官方 Quickstart 的 Dockerfile 与 compose 已删除。

## 六、本篇小结

1. 本目录是 Iceberg 文档的唯一整合入口。
2. Iceberg 是 jar，安装等于挂 jar 加建 Catalog，不新增容器。
3. 本机方案是 JDBC Catalog，元数据落 PostgreSQL，数据落 MinIO。
4. 安装教程按版本分目录，当前版本为 v1.10.1。
5. 原理与通用操作按独立分册存放，按需跳读。
