> 官方中文教程：暂无。官方文档：https://iceberg.apache.org/docs/latest/

> **本文范围**：把 Iceberg 装进已有的 Flink 集群。挂三个 jar，设一个环境变量，建一个 JDBC Catalog。元数据落在宿主 PostgreSQL，数据落在 MinIO。不新增容器，不部署 REST 服务。装完验到能建表、写入并读回。

# Iceberg 安装

> **一句话结论**：三个 jar 加一个环境变量再加一个 JDBC Catalog。jar 是 iceberg-flink-runtime、iceberg-aws-bundle 与 PostgreSQL driver。环境变量是 AWS_REGION=us-east-1。Catalog 指向宿主 PG 的 iceberg_meta 库，warehouse 指向 s3://lakehouse/iceberg/。验收四条：三个 jar 加载成功、区域变量就位、Catalog 建成、写入能读回。

> **本文解决什么**：本机已有 Flink 与 MinIO，怎么让 Flink 具备读写 Iceberg 表的能力。
>
> **适用谁**：已装 Flink 1.20.5 与 MinIO，且本机有 PostgreSQL 的用户。
>
> **读完能做什么**：挂齐 jar、建好 JDBC Catalog、验证端到端落盘，再进入基本使用建表读写。

> **核对时点**：2026-11-26。macOS / Docker Desktop。Flink 1.20.5 单容器，MinIO RELEASE.2025-02-07T23-21-09Z，宿主 PostgreSQL 14.20。三者都在 whd-net 或通过 host.docker.internal 互访。PG 用户 root，元数据库 iceberg_meta 已建，库内两张表的 owner 为 root。

---

## 一、适用范围

| 项 | 取值 |
| --- | --- |
| 版本 | Iceberg 1.10.1，Flink 1.20.5 |
| 形态 | 挂 jar 到现有 Flink，不新增容器 |
| 操作系统 | macOS / Docker Desktop |
| 内存下限 | 复用现有 Flink，无额外占用 |
| 元数据 | JDBC Catalog，落在宿主 PG 14.20 的 iceberg_meta |
| 数据文件 | MinIO 桶 lakehouse，前缀 s3://lakehouse/iceberg/ |
| 不覆盖 | REST Catalog 部署、Spark 引擎安装 |

> Iceberg 本体是 jar，不是服务。Catalog 只负责表名到元数据的映射。JDBC 型用现有数据库做映射，无需独立容器。

---

## 二、安装前复核

```bash
docker ps --filter name=flink \
  --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'

docker ps --filter name=minio \
  --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'

docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} | {{.IPv4Address}}{{println}}{{end}}'

psql -h 127.0.0.1 -d postgres -c 'select version();' | head -3
psql -h 127.0.0.1 -d iceberg_meta -c 'select current_database();'

lsof -nP -iTCP:5432 -sTCP:LISTEN
```

| 检查项 | 期望 | 不满足时 |
| --- | --- | --- |
| Flink 容器 | 状态 Up | 按 Flink 安装教程启动 |
| MinIO 容器 | 状态 Up，监听 9000 | 按 MinIO 安装教程启动 |
| whd-net | 含 flink 与 minio | 网络不存在时按根 README 创建 |
| PostgreSQL | 宿主 5432 监听 | 启动 Homebrew PostgreSQL |
| iceberg_meta 库 | 查询返回库名 | 执行 psql -d postgres -c 'CREATE DATABASE iceberg_meta;' |
| lakehouse 桶 | 已建 | 用 mc 建桶，见 MinIO 使用教程 |

> 宿主 PG 只监听 127.0.0.1。容器内须走 host.docker.internal:5432，不能写 localhost。PG 连接凭据不写进文档，从本机环境变量读取。

---

## 三、安装步骤

### 3.1 准备 jar

三个 jar 都要进 Flink 的 classpath。runtime 提供 Iceberg 连接器，aws-bundle 提供 S3FileIO 依赖，driver 提供 JDBC 连接。三个 jar 已下载到本机 jars 目录。

```bash
JARS=/Users/wenhuadong/docker/streaming/flink/jars
ls -lh "$JARS/iceberg-flink-runtime-1.20-1.10.1.jar" \
  "$JARS/iceberg-aws-bundle-1.10.1.jar" \
  "$JARS/postgresql-42.7.4.jar"
```

预期列出三个文件。runtime 约 37M，aws-bundle 约 60M，driver 约 1M。

本机 jars 目录另有旧版 iceberg-flink-runtime-1.20-1.9.2.jar，已移入 archive 子目录。挂载时只用 1.10.1，不要挂旧版。两个 Iceberg runtime 同时进 classpath 会触发类冲突。

jar 缺失时需重新下载。

```bash
curl -fL -o "$JARS/iceberg-flink-runtime-1.20-1.10.1.jar" \
  https://repo.maven.apache.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.20/1.10.1/iceberg-flink-runtime-1.20-1.10.1.jar
curl -fL -o "$JARS/iceberg-aws-bundle-1.10.1.jar" \
  https://repo.maven.apache.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.10.1/iceberg-aws-bundle-1.10.1.jar
curl -fL -o "$JARS/postgresql-42.7.4.jar" \
  https://repo.maven.apache.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar
```

预期输出下载进度，文件落到 jars 目录。下载后用 unzip -t 核对完整性。

> runtime jar 的版本号要与 Flink 大版本对齐。本机 Flink 1.20.5，因此取 runtime-1.20。aws-bundle 与 runtime 版本一致，同为 1.10.1。PostgreSQL driver 版本固定为 42.7.4，不用 latest。
>
> iceberg-flink-runtime 内含 S3FileIO 类，但不含它依赖的 AWS SDK。缺 aws-bundle 时建 Catalog 报 ClassNotFoundException: software.amazon.awssdk.core.exception.SdkException。此 jar 不可省略。

### 3.2 挂载 jar 到 Flink

本机 Flink 容器用目录挂载加软链接加载 jar。启动时脚本把 custom-jars 目录下每个 jar 软链到 lib。因此只需把三个 jar 放进 jars 目录，无需改 docker run 参数。

```bash
docker exec flink ls -l /opt/flink/lib | grep -E 'iceberg|aws|postgresql' || echo '尚未挂载'
```

预期列出三个 jar。若未挂载，重建容器时确认命令含三行挂载：

```bash
-v /Users/wenhuadong/docker/streaming/flink/jars:/opt/flink/custom-jars:ro \
-v /Users/wenhuadong/docker/streaming/flink/conf/config.yaml:/opt/flink/conf/config.yaml:ro \
-v /Users/wenhuadong/docker/streaming/flink/checkpoints:/checkpoints
```

容器启动命令中的软链接循环：

```bash
for j in /opt/flink/custom-jars/*.jar; do
  n=$(basename "$j")
  ln -sf "$j" "/opt/flink/lib/$n"
done
```

预期重建后 docker exec 能列出三个 jar。

> 不用整目录挂载到 lib。目录挂载会遮住镜像自带依赖，导致启动异常。custom-jars 是独立目录，软链逐个加入 lib，不影响原有依赖。

### 3.3 设置 AWS_REGION 环境变量

S3FileIO 依赖 AWS SDK 解析区域。即使 Catalog 里写了 s3.region，SDK 仍从环境变量或系统属性读取。容器缺该变量时，写入报 SdkClientException: Unable to load region from any of the providers。

重建容器时加一行环境变量：

```bash
-e AWS_REGION=us-east-1
```

验证：

```bash
docker exec flink printenv AWS_REGION
```

预期输出 us-east-1。

> us-east-1 只为满足 SigV4 签名，MinIO 不校验具体区域值。该变量在容器创建时固定，重建后需重新传入。

### 3.4 准备元数据库与账号

JDBC Catalog 用 root 账号连接宿主 PG。元数据库为 iceberg_meta。库内两张表由首次建 Catalog 时自动创建。

用超级用户创建数据库并授权。本机超级用户为 wenhuadong，root 为普通用户。

```bash
psql -h 127.0.0.1 -U wenhuadong -d postgres \
  -c "CREATE DATABASE iceberg_meta;"
psql -h 127.0.0.1 -U wenhuadong -d postgres \
  -c "GRANT ALL PRIVILEGES ON DATABASE iceberg_meta TO root;"
```

预期输出 CREATE DATABASE 与 GRANT。库已存在时首条报错，可忽略。

### 3.5 修复表 owner

若库内表由其它账号创建，root 访问会报 permission denied for table iceberg_tables。用超级用户把表 owner 改为 root。

```bash
psql -h 127.0.0.1 -U wenhuadong -d iceberg_meta -c \
  "ALTER TABLE iceberg_tables OWNER TO root; \
   ALTER TABLE iceberg_namespace_properties OWNER TO root;"
```

预期输出两条 ALTER TABLE，表不存在时报错可忽略。

验证 root 能访问。

```bash
psql -h 127.0.0.1 -U root -d iceberg_meta \
  -c "select tablename, tableowner from pg_tables where schemaname='public';"
```

预期两行，owner 为 root。这是本机已修复的状态。

### 3.6 准备连接参数

JDBC Catalog 需要 PG 地址、账号、口令，以及 MinIO 地址与凭据。口令从本机环境变量读取，不写进文档。

账号固定为 root。口令按本机实际值设置，只在当前 shell 生效。

```bash
export PGUSER=root
export PGPASSWORD='123456'
set -a
. /Users/wenhuadong/docker/object-storage/minio/.env
set +a
echo "PG 用户=$PGUSER  PG 口令已设置=${PGPASSWORD:+yes}  MINIO_AK 已加载=${MINIO_AK:+yes}"
```

把 &lt;PG_PWD&gt; 替换为 root 的实际口令。预期三项均显示已设置或 yes。

| 参数 | 取值 | 来源 |
| --- | --- | --- |
| PG 地址 | host.docker.internal:5432 | 容器内访问宿主固定写法 |
| PG 库 | iceberg_meta | 3.4 建库 |
| PG 用户 | root | 固定账号，普通用户 |
| PG 口令 | &lt;PG_PWD&gt; | 本机口令，不写进文档 |
| MinIO 地址 | http://minio:9000 | 容器内网地址 |
| MinIO 凭据 | &lt;MINIO_AK&gt; 与 &lt;MINIO_SK&gt; | minio/.env |

---

## 四、启动与验证

### 4.1 建 JDBC Catalog

进入 Flink SQL 客户端，执行以下语句。

```bash
docker exec -it flink ./bin/sql-client.sh
```

```sql
CREATE CATALOG iceberg_pg WITH (
  'type' = 'iceberg',
  'catalog-impl' = 'org.apache.iceberg.jdbc.JdbcCatalog',
  'uri' = 'jdbc:postgresql://host.docker.internal:5432/iceberg_meta',
  'jdbc.user' = '<PG_USER>',
  'jdbc.password' = '<PG_PWD>',
  'warehouse' = 's3://lakehouse/iceberg/',
  'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
  's3.endpoint' = 'http://minio:9000',
  's3.access-key-id' = '<MINIO_AK>',
  's3.secret-access-key' = '<MINIO_SK>',
  's3.path-style-access' = 'true'
);
```

Flink 的 catalog-type 只支持 hive、hadoop、rest。JDBC 不能写 catalog-type=jdbc，必须用 catalog-impl 指定实现类。

执行 SHOW CATALOGS 确认新建成功。

```sql
SHOW CATALOGS;
```

预期列表含 iceberg_pg。

### 4.2 冒烟读写

执行以下语句建表、写入并读回。

```sql
USE CATALOG iceberg_pg;
CREATE DATABASE IF NOT EXISTS demo_db;
USE demo_db;
SET 'execution.checkpointing.interval' = '10s';
CREATE TABLE IF NOT EXISTS events (
  id BIGINT,
  name STRING
) USING iceberg;
INSERT INTO events VALUES (1, 'alice');
SELECT * FROM events;
```

预期 SELECT 返回一行，id 为 1，name 为 alice。

### 4.3 验证落盘

检查 MinIO 出现数据文件，检查 PG 出现元数据表。

```bash
psql -h 127.0.0.1 -d iceberg_meta -c '\dt'
```

预期列出 iceberg_tables 与 iceberg_namespace_properties 两张表。

```bash
set -a
. /Users/wenhuadong/docker/object-storage/minio/.env
set +a
docker run --rm --network whd-net --platform linux/amd64 \
  -e MC_HOST_lake="http://${MINIO_AK}:${MINIO_SK}@minio:9000" \
  minio/mc:RELEASE.2025-08-13T08-35-41Z \
  ls --recursive lake/lakehouse/iceberg/ | head -20
```

预期列出 metadata 与 data 目录下的文件。

### 4.4 停止与重来

```bash
docker stop flink
docker start flink
```

Catalog 定义随 Flink 会话保存。容器重启后需重新执行 4.1 的 CREATE CATALOG。数据与元数据不丢，它们分别在 MinIO 与 PG。

| 动作 | 数据安全 |
| --- | --- |
| Flink stop/start | 数据与元数据保留，会话 Catalog 定义需重建 |
| 重建 Flink 容器 | jar 挂载保留，需重新执行 4.1 |
| 清空 iceberg_meta | 只用于明确重置元数据，执行前先备份 |

---

## 五、验收对照

| 判据 | 检查方式 | 通过标准 |
| --- | --- | --- |
| jar 加载 | docker exec flink ls /opt/flink/lib | 列出 iceberg、aws-bundle、postgresql 三个 jar |
| 区域变量 | docker exec flink printenv AWS_REGION | 输出 us-east-1 |
| 数据库就位 | psql -h 127.0.0.1 -d iceberg_meta -c '\dt' | 列出 iceberg 前缀的表 |
| Catalog 建成 | SHOW CATALOGS | 列表含 iceberg_pg |
| 写入读回 | 4.2 的 SELECT | 返回 id 为 1、name 为 alice |
| 数据落盘 | 4.3 的 mc ls | lakehouse/iceberg 下有 metadata 与 data 文件 |
| 元数据落库 | 4.3 的 psql 查表 | iceberg_meta 含 iceberg 前缀表 |

---

## 六、故障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 建 Catalog 报类找不到 | 缺 PostgreSQL driver jar | 按 3.1 下载并挂载 |
| 报 SdkException 类找不到 | 缺 aws-bundle jar | 按 3.1 下载并挂载 iceberg-aws-bundle |
| 报 Unable to load region | 容器缺 AWS_REGION | 按 3.3 重建容器并设 us-east-1 |
| 报 Connection refused | PG 地址写 localhost | 改为 host.docker.internal:5432 |
| 报数据库不存在 | iceberg_meta 未建 | 执行 psql -d postgres -c 'CREATE DATABASE iceberg_meta;' |
| 报认证失败 | PG 用户应为 root，口令错误 | 复核 PGUSER=root 与口令，口令不进文档 |
| 报 permission denied for table iceberg_tables | 表 owner 不是 root | 用超级用户执行 3.5 的 ALTER TABLE OWNER TO root |
| 报 SignatureDoesNotMatch | MinIO 凭据错误 | 重新 source minio/.env |
| 建 Catalog 报 catalog-type 无效 | 写了 catalog-type=jdbc | 删除该行，只用 catalog-impl |
| INSERT 后查不到数据 | 未开 checkpoint | 写入前 SET execution.checkpointing.interval |
| 容器内连不上 MinIO | endpoint 写成 localhost | 改为 http://minio:9000 |
| jar 挂载后启动异常 | 挂了整个目录或源文件不存在 | 改为单文件挂载，ls -l 核对源文件 |
