# 大数据容器栈

> **一句话定位**：本仓库用 Docker 部署大数据组件。每个组件提供安装教程、基本原理和基本使用。初学者能在本机完成部署与 SQL 练习。

> **本文解决什么**：说明项目定位、组件清单、学习路径和维护约定。
>
> **适用谁**：想在本机练习大数据组件的初学者。
>
> **读完能做什么**：找到目标组件，按教程完成部署，再按基本使用做练习。

---

## 一、项目定位

本仓库不是生产部署方案。它面向本机学习与功能验证。

**轻量部署**：每个组件使用 Docker 单容器。不引入 Keeper 或多机编排。内存占用低，适合 16G 本机。

**三类文档**：基本原理讲设计取舍。安装教程带读者完成部署。基本使用讲装完后的操作。

**统一底座**：所有容器接入 whd-net 网络。端口与固定 IP 统一分配。组件之间按服务名互访。

> 数据目录、日志与插件 jar 不进仓库。口令使用占位符，真实凭据留在本地。

## 二、学习路径

初学者按下面顺序练手。每一步都有对应目录。

| 顺序 | 组件 | 练什么 | 目录 |
| --- | --- | --- | --- |
| ① | MinIO | 对象存储与路径风格访问 | object-storage/minio |
| ② | Kafka | 主题创建与消息收发 | messaging/kafka |
| ③ | Flink | SQL 作业与 checkpoint | streaming/flink |
| ④ | Doris | 建表导入与 OLAP 查询 | olap/doris |
| ⑤ | ClickHouse | 列存与 MergeTree | olap/clickhouse |
| ⑥ | Paimon | 湖表读写与合并 | table-formats/paimon |
| ⑦ | Spark | 批处理与 Spark SQL | streaming/spark |

> 每步先读基本原理，再按安装教程部署，最后用基本使用做练习。

## 三、组件清单

组件按功能域归入一级目录。一级目录名小写英文。

| 功能域 | 目录 | 组件 |
| --- | --- | --- |
| 调度编排 | scheduling | dolphinscheduler |
| 流计算 | streaming | flink、fluss、spark |
| 分析查询 | olap | doris、starrocks、clickhouse |
| 可视化 | bi | superset |
| 消息总线 | messaging | kafka |
| 数据集成 | integration | seatunnel |
| 数据开发 | development | dinky |
| 对象存储 | object-storage | minio、garage、seaweedfs |
| 湖仓表格式 | table-formats | paimon、iceberg、hudi、delta |
| 智能工具 | ai | mineru |
| 选型参考 | references | stable-combinations |

> garage 与 seaweedfs 目录已建，安装教程待补。读者按目录内实际文件学习。

## 四、快速开始

① 安装 Docker Desktop。本机内存下限 16G。

```bash
git clone https://github.com/wushuoyouting/bigdata-docker-stack.git
cd bigdata-docker-stack
```

预期输出：仓库克隆完成，终端进入项目根目录。

② 创建共享网络。已有网络会保留。

```bash
docker network inspect whd-net >/dev/null 2>&1 || \
  docker network create --driver bridge \
  --subnet 172.30.0.0/24 --gateway 172.30.0.1 whd-net
```

预期输出：whd-net 存在，子网为 172.30.0.0/24。

③ 打开目标组件的 README。
④ 按安装教程复核端口与目录占用。
⑤ 执行教程中的启动命令。
⑥ 按教程的验收对照逐条核对。

## 五、文档结构

组件根目录只放四类职责文档与导航。安装教程按版本分目录，按形态分文件。

| 文档 | 回答什么 |
| --- | --- |
| README.md | 组件定位、基线、端口与目录 |
| 基本原理.md | 为什么这样设计 |
| 安装教程.md | 怎么装、怎么验收 |
| 基本使用.md | 装完后怎么操作 |
| 外部对接.md | 与其他组件怎么联动 |

目录示意。

```text
clickhouse/
├── README.md
├── 基本原理.md
├── 基本使用.md
└── install/
    └── v26.8/
        └── standalone.md
```

> 部分组件的文档还不完整。读者按目录内实际文件学习。

## 六、维护约定

### 6.1 目录命名

项目内文件夹名统一小写英文。禁止大写字母与中文目录名。版本号用 v 加数字，如 v4.1。形态名用 standalone、pseudo-cluster、cluster。文件名与目录名保持一致规则。

### 6.2 安装教程结构

每篇安装教程固定六章，顺序等于操作顺序。

| 章节 | 内容 |
| --- | --- |
| 适用范围 | 版本、形态、操作系统、内存下限 |
| 安装前复核 | 端口查询命令、目录避让关系 |
| 安装步骤 | 拉取镜像、建目录、写配置 |
| 启动与验证 | 启动命令与预期输出 |
| 验收对照 | 判据、检查方式、通过标准 |
| 故障速查 | 该形态特有的失败场景 |

安装命令写成独立代码块，整段可复制。验收章放在全部安装与配置步骤之后。参数说明表紧贴使用它的命令。

### 6.3 开源排除

开源排除由根目录 .gitignore 执行。排除项覆盖七类内容。

| 类别 | 典型路径 |
| --- | --- |
| 系统与工具目录 | .DS_Store、.codebuddy、.mimosa |
| Python 虚拟环境 | ai/mineru/.mineru |
| 上游源码副本 | table-formats/iceberg/iceberg、scheduling/dolphinscheduler/flink |
| 运行时数据 | olap/doris/volumes、messaging/kafka/data、streaming/flink/sql/warehouse |
| 日志 | 所有 .log 文件 |
| 大依赖包与凭据 | 所有 .jar、.env、docker-compose.whd.yml |
| 本机运维档案 | code-wiki |

真实 .env 排除，.env.example 提交。code-wiki 只保留本地，不参与开源。组件文档以各组件目录为准。

### 6.4 写作基线

中文内容遵守统一写作规范。代码块外不使用行内反引号。代码块外尖括号占位符转为 HTML 实体。标题单行，宽度小于十五个汉字。句长不超过三十字。一句只写一件事。同物全程同词。不写跨章节或跨文档的位置引用。口令一律用占位符，真值不进仓库。

### 6.5 提交约定

每次修改完成后提交并推送到 GitHub，不留未提交的本地改动。

一个任务对应一个提交。提交信息带模块前缀，说明改动原因。文档与它对应的配置改动放在同一提交。不同模块的改动不混在一个提交里。

上游发行版副本与运行时数据只在本地保留。提交前用 git status 核对暂存范围，确认没有把排除内容带进仓库。

## 七、形态定义

| 形态 | 实例数 | 机器数 | 用途 |
| --- | --- | --- | --- |
| 单机 | 一个进程 | 一台 | 功能验证与 SQL 调试 |
| 伪集群 | 多个进程 | 一台 | 验证多角色协作 |
| 集群 | 多个进程 | 多台 | 生产部署与容量测试 |

三种形态的端口写入同一张表。分配前查询现有占用。每种形态使用独立数据目录，目录名带形态后缀。
