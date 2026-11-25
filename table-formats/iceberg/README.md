# Iceberg 本地实践文档

> 一句话结论：本目录集中存放 Iceberg 的原理、安装与操作文档。本机环境采用 Apache 官方 Flink Quickstart 编排。Catalog 为 REST，对象存储为 rustfs。

> 整合说明（2026-11-21）：原 /Users/wenhuadong/docker/iceberg 三册文档，与 table_format/Iceberg 的原理及通用操作文档合并于此。原目录保留作历史追溯。

> 静态地址：本机为 Iceberg 分配 172.30.0.4。分配依据见 /Users/wenhuadong/docker/code-wiki/06-配置基线与例外.md。

## 一、文档清单

| 册 | 文件 | 内容 | 适用场景 |
| --- | --- | --- | --- |
| 一 | 原理.md | 数据布局、元数据树、提交与并发、COW 与 MOR、演进 | 理解行为边界 |
| 二 | 安装教程.md | Docker 起 Flink、REST Catalog 与 rustfs | 本机搭环境 |
| 三 | 基本使用.md | Flink SQL 建表、写入、快照、增量读取、Schema 演进 | 本机 Quickstart 操作 |
| 四 | 通用操作.md | Spark 配 MinIO 的 hadoop catalog、时间旅行、快照维护 | 非 Quickstart 场景 |

① 推荐按一、二、三的顺序阅读。
② 只关心命令的读者，可直接从安装教程进入。
③ 使用 MinIO 或 Spark 的读者，读通用操作。

## 二、环境说明

① 计算引擎选 Flink。Flink 对 Iceberg 的读写支持成熟，SQL 客户端可直接验证。
② Catalog 选 REST。元数据存在对象存储，无需另配数据库。
③ 对象存储选 rustfs。官方编排内置，不映射宿主端口。
④ 本机已运行的 MinIO 不在 Quickstart 网络内。跨容器访问需另行配置，详见通用操作。

## 三、来源与版本

① 安装教程与本机操作册来自官方 Flink Quickstart 编排。
② 原理册与通用操作册来自表格式专题文档。
③ 镜像版本以编写时的官方仓库为准。实际版本以本机拉取结果为准。
④ 命令中的凭据为官方示例值，仅用于容器内通信。生产环境须替换。

## 四、本篇小结

1. 本目录是 Iceberg 文档的唯一整合入口。
2. 本机 Quickstart 与通用 Spark 场景分册存放，互不混淆。
3. 原 iceberg 目录保留作历史追溯，不再新增内容。
