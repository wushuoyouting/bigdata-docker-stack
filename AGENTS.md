# 项目全局规则

本文规定本项目的目录命名、开源排除与组件文档结构。适用对象是维护本项目的开发者与 AI 助手。读完能按统一约定新增组件与文档。

## 一、规则位置

项目规则写入根目录 AGENTS.md。该文件随仓库提交，开源后可被读取。AI 助手的持久化记忆只存摘要，以本文件为准。

## 二、目录命名

项目内文件夹名统一小写英文。禁止大写字母与中文目录名。版本号用 v 加数字，如 v4.1。形态名用 standalone、pseudo-cluster、cluster。文件名与目录名保持一致规则。

## 三、开源排除

开源排除由根目录 .gitignore 执行。排除项覆盖六类内容。

| 类别 | 典型路径 |
| --- | --- |
| 系统与工具目录 | .DS_Store、.codebuddy、.mimosa |
| Python 虚拟环境 | ai/mineru/.mineru |
| 上游源码副本 | table-formats/iceberg/iceberg |
| 运行时数据 | olap/doris/data、messaging/kafka/data |
| 日志 | 所有 .log 文件 |
| 大依赖包与凭据 | 所有 .jar、.env、docker-compose.whd.yml |
| 本机运维档案 | code-wiki |

table-formats/iceberg/iceberg 整目录排除。真实 .env 排除，.env.example 提交。code-wiki 是本机运维档案，只保留本地，不参与开源。该档案记录固定 IP、容器状态与历史资产，不作为文档权威。组件文档以各组件目录为准。

## 四、顶层分类

组件按功能域归入一级目录。一级目录名小写英文，组件名保持原名小写。跨组件的同类能力不重复建目录。

| 一级目录 | 功能域 | 归入组件 |
| --- | --- | --- |
| scheduling | 调度编排 | dolphinscheduler、airflow |
| streaming | 流计算 | flink、fluss |
| olap | 分析查询 | doris、starrocks、clickhouse |
| bi | 可视化 | superset |
| messaging | 消息总线 | kafka |
| integration | 数据集成 | seatunnel |
| development | 数据开发 | dinky |
| object-storage | 对象存储 | minio、garage、seaweedfs |
| table-formats | 湖仓表格式 | paimon、iceberg、hudi、delta |
| ai | 智能工具 | mineru |
| references | 选型参考 | stable-combinations |

目录树示意。

```text
docker/
├── scheduling/
│   ├── dolphinscheduler/
│   └── airflow/
├── streaming/
│   ├── flink/
│   └── fluss/
├── olap/
│   ├── doris/
│   ├── starrocks/
│   └── clickhouse/
├── bi/
│   └── superset/
├── messaging/
│   └── kafka/
├── integration/
│   └── seatunnel/
├── development/
│   └── dinky/
├── object-storage/
│   ├── minio/
│   ├── garage/
│   └── seaweedfs/
├── table-formats/
│   ├── paimon/
│   ├── iceberg/
│   ├── hudi/
│   └── delta/
├── ai/
│   └── mineru/
├── references/
│   └── stable-combinations/
├── code-wiki/
├── AGENTS.md
└── .gitignore
```

新增组件按功能域对号入座。跨功能域的组件放主用途目录，不重复建项。

## 五、组件目录规划

组件根目录只放四类职责文档与导航。安装教程按版本分目录，按形态分文件。

```text
doris/
├── README.md
├── 基本原理.md
├── 基本使用.md
├── 外部对接.md
├── install/
│   ├── v2.1/
│   │   ├── standalone.md
│   │   ├── pseudo-cluster.md
│   │   └── cluster.md
│   └── v4.1/
│       ├── standalone.md
│       ├── pseudo-cluster.md
│       └── cluster.md
├── conf/
└── volumes/
```

根目录不放入安装命令全文。README 只做版本矩阵与教程入口。conf 与 volumes 等运行时目录由 .gitignore 排除。

## 六、安装教程结构

每篇安装教程固定六章，顺序等于操作顺序。

| 章节 | 内容 |
| --- | --- |
| 适用范围 | 版本、形态、操作系统、内存下限 |
| 安装前复核 | 端口查询命令、目录避让关系 |
| 安装步骤 | 拉取镜像、建目录、建账号、写配置 |
| 启动与验证 | 启动命令与预期输出 |
| 验收对照 | 判据、检查方式、通过标准 |
| 故障速查 | 该形态特有的失败场景 |

安装命令写成独立代码块，整段可复制。验收章放在全部安装与配置步骤之后。参数说明表紧贴使用它的命令。

## 七、文档职责

组件文档按职责拆分，不混型。README 只做导航。基本原理讲清设计取舍。安装教程带读者完成部署。基本使用面向有基础的人。外部对接说明联动方式。

## 八、写作基线

中文内容遵守统一写作规范。代码块外不使用行内反引号。代码块外尖括号占位符转为 HTML 实体。标题单行，宽度小于十五个汉字。句长不超过三十字。一句只写一件事。同物全程同词。不写跨章节或跨文档的位置引用。口令一律用占位符，真值不进仓库。

## 九、形态定义

| 形态 | 实例数 | 机器数 | 用途 |
| --- | --- | --- | --- |
| 单机 | 一个进程 | 一台 | 功能验证与 SQL 调试 |
| 伪集群 | 多个进程 | 一台 | 验证多角色协作 |
| 集群 | 多个进程 | 多台 | 生产部署与容量测试 |

三种形态的端口写入同一张表。分配前查询现有占用。每种形态使用独立数据目录，目录名带形态后缀。
