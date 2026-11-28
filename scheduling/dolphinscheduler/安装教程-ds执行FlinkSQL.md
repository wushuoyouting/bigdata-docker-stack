# DolphinScheduler 执行 FlinkSQL 安装教程

本文用于让 DolphinScheduler 的 Flink 任务节点提交 SQL 到现有 Flink 集群。DS 容器安装 Flink 客户端，通过 REST 连接集群。集群不新增容器，数据仍落 MinIO 或 PostgreSQL。读者照做可完成部署并跑通一个 SQL 节点。

## 一、结论

DS 容器需要三样东西：Flink 客户端、connector jar、环境变量 FLINK_HOME。

Flink 客户端不是单个 jar，而是完整发行包。本机从现有 flink 容器复制核心目录，版本自动一致。客户端通过三行 SET 连接 flink:8081，作业在集群 TaskManager 上运行。

## 二、适用范围

| 项 | 取值 |
| --- | --- |
| DS 版本 | 3.4.3 standalone |
| Flink 版本 | 1.20.5，现有容器 |
| 网络 | whd-net，DS 为 172.30.0.2，Flink 为 172.30.0.14 |
| 表格式 | Paimon 1.3.1、Iceberg 1.10.1、Hudi 1.2.1 |
| 数据底座 | MinIO 桶 lakehouse，元数据落文件系统或宿主 PG |
| 不覆盖 | SQL Gateway、YARN 模式、多 Worker 部署 |

## 三、安装前复核

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'ds-standalone|flink'

docker exec ds-standalone getent hosts flink
docker exec ds-standalone curl -s -m 5 http://flink:8081/overview | head -c 200

docker exec flink sh -c 'du -sh /opt/flink'
```

| 检查项 | 期望 |
| --- | --- |
| DS 容器 | 状态 Up |
| Flink 容器 | 状态 Up |
| flink 解析 | 返回 172.30.0.14 |
| 集群接口 | 返回 JSON，含 slots-total |
| 发行包 | 约 889M |

## 四、准备客户端

### 4.1 复制发行包

从运行中的 flink 容器复制核心目录。不需要下载，版本自动一致。

```bash
CLIENT=/Users/wenhuadong/docker/scheduling/dolphinscheduler/flink
rm -rf "$CLIENT"
mkdir -p "$CLIENT"

for d in bin lib conf plugins opt licenses examples; do
  docker cp flink:/opt/flink/$d "$CLIENT/"
done
```

预期生成七个目录，约 513M。检查客户端脚本：

```bash
ls -l "$CLIENT/bin/sql-client.sh"
```

### 4.2 修正 lib 中的软链接

源容器的 lib 里 connector jar 是软链接。docker cp 会复制成断裂软链，必须换成实体文件。

```bash
python3 << 'PYEOF'
import os, glob, shutil
dst = "/Users/wenhuadong/docker/scheduling/dolphinscheduler/flink/lib"
for f in glob.glob(dst + "/*"):
    if os.path.islink(f):
        os.unlink(f)
src = "/Users/wenhuadong/docker/streaming/flink/jars"
skip = {"paimon-flink-1.20-2.0.0.jar", "iceberg-flink-runtime-1.20-1.9.2.jar"}
for f in glob.glob(src + "/*.jar"):
    name = os.path.basename(f)
    if name in skip:
        continue
    shutil.copy2(f, os.path.join(dst, name))
print("lib 准备完成")
PYEOF
```

预期 lib 下有 27 个实体 jar。排除旧版 Paimon 与 Iceberg runtime，避免类冲突。

检查关键依赖：

```bash
ls "$CLIENT/lib" | grep -iE 'iceberg|paimon|mysql|postgres|hudi'
```

预期列出 Iceberg runtime、aws-bundle、Paimon runtime、Paimon s3、MySQL CDC、MySQL driver、PG driver、Hudi bundle 八个 jar。

### 4.3 准备 Java 11

DS 镜像自带 Java 8，Flink 1.20.5 需要 Java 11。从 flink 容器复制 JDK 到客户端目录。

```bash
docker cp flink:/opt/java/openjdk \
  /Users/wenhuadong/docker/scheduling/dolphinscheduler/flink/java11
```

预期生成 java11 目录，约 132M。这样不影响 DS 自身的 Java 8。

### 4.4 准备 SQL 目录

SQL 脚本放在 DS 目录，供 DS 节点读取。

```bash
mkdir -p /Users/wenhuadong/docker/scheduling/dolphinscheduler/sql
```

DS 任务节点用 init.sql 放连接参数，用 node.sql 放业务 SQL。也可把已有脚本复制过来。

## 五、修改编排并重启

### 5.1 编辑 compose 文件

文件位置：

```
/Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml
```

在服务的 volumes 段加入两行：

```yaml
- ../../../scheduling/dolphinscheduler/flink:/opt/flink
- /Users/wenhuadong/docker/streaming/flink/sql:/opt/sql:ro
```

第一行为客户端，第二行为 SQL 脚本目录。按实际相对路径调整第一行。

### 5.2 设置环境变量

在环境变量配置文件中加入：

```
FLINK_HOME=/opt/flink
JAVA_HOME=/opt/flink/java11
PATH=/opt/flink/java11/bin:/opt/flink/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

PATH 必须写容器内路径，不能写宿主机 PATH。否则 config.sh 报 arithmetic syntax error。

DS 任务用 sudo -u root -i 启动 login shell，会重新加载 profile 并丢弃容器环境变量。仅设置 env_file 不够，任务里仍报 /bin/sql-client.sh 不存在。必须在 /etc/profile.d 中放一份环境变量脚本。

创建脚本 flink/ds-flink-env.sh：

```
export FLINK_HOME=/opt/flink
export JAVA_HOME=/opt/flink/java11
export AWS_REGION=us-east-1
export PATH=/opt/flink/java11/bin:/opt/flink/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

再在 compose 的 volumes 段加一行：

```yaml
- ../flink/ds-flink-env.sh:/etc/profile.d/ds-flink-env.sh:ro
```

重启后验证：

```bash
docker exec ds-standalone sudo -u root -i bash -c 'echo $FLINK_HOME; which sql-client.sh'
```

预期输出 /opt/flink 与 /opt/flink/bin/sql-client.sh。

文件位置：

```
/Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/dolphinscheduler.env
```

### 5.3 重启 DS

```bash
cd /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf
docker compose -f docker-compose.whd.yml down
docker compose -f docker-compose.whd.yml up -d
```

等待健康检查通过：

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep ds-standalone
```

预期状态为 Up (healthy)。

### 5.4 验证客户端

```bash
docker exec ds-standalone printenv FLINK_HOME
docker exec ds-standalone ls -l /opt/flink/bin/sql-client.sh
docker exec ds-standalone ls /opt/flink/lib | grep -i iceberg
```

预期依次输出 /opt/flink、脚本信息、Iceberg 相关 jar。

## 六、配置 Flink 任务节点

### 6.1 建立任务

在 DS 项目里新建任务，类型选 FLINK。

| 参数 | 取值 |
| --- | --- |
| 程序类型 | SQL |
| Flink 版本 | 1.20.5 或默认项 |
| 部署模式 | standalone |
| 初始化 SQL | 见下文 |
| SQL 内容 | 业务 SQL |

### 6.2 初始化 SQL

在初始化 SQL 框中写入连接参数。每次执行时 DS 会把它写入 init.sql 并先运行。

```
SET 'execution.target' = 'remote';
SET 'rest.address' = 'flink';
SET 'rest.port' = '8081';
SET 'sql-client.execution.result-mode' = 'tableau';
```

rest.address 写容器名 flink，不写 localhost。后者在 DS 容器内指向自己，连接失败。

### 6.3 业务 SQL

SQL 内容框写已有脚本内容。例如 Iceberg ODS 采集脚本：

```
INSERT INTO iceberg_ods.ods_order_detail_full SELECT ...
```

脚本里的 CREATE CATALOG 保留即可。连接参数由 init.sql 提供，业务 SQL 不需要重复写。

### 6.4 凭据占位符

脚本中的 AK/SK、PG 口令用真值替换后再粘贴。真值只在 DS 任务定义中保存，不写进仓库。

## 七、验收

### 7.1 手工验证命令

在 DS 容器内直接跑一个最小作业：

```bash
docker exec ds-standalone bash -c "cat > /tmp/t.sql <<'EOF'
SET 'execution.target' = 'remote';
SET 'rest.address' = 'flink';
SET 'rest.port' = '8081';
CREATE TABLE src (id INT) WITH ('connector'='datagen', 'number-of-rows'='3');
CREATE TABLE sink (id INT) WITH ('connector'='blackhole');
INSERT INTO sink SELECT id FROM src;
EOF
/opt/flink/bin/sql-client.sh -f /tmp/t.sql"
```

预期最后输出作业提交成功。

### 7.2 检查集群作业

```bash
curl -s http://localhost:8081/jobs | python3 -m json.tool
```

预期列表中出现新作业。

### 7.3 验收表

| 判据 | 检查方式 | 通过标准 |
| --- | --- | --- |
| 客户端就位 | docker exec ds-standalone ls /opt/flink/bin | 列出 sql-client.sh |
| jar 就位 | docker exec ds-standalone ls /opt/flink/lib | 列出 iceberg 与 paimon |
| 环境变量 | docker exec ds-standalone printenv FLINK_HOME | 输出 /opt/flink |
| 集群连通 | docker exec ds-standalone curl http://flink:8081/overview | 返回 JSON |
| DS 任务 | 任务实例详情 | 状态成功 |
| 集群作业 | 8081 作业列表 | 新作业出现 |

## 八、故障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| /bin/sql-client.sh 不存在 | FLINK_HOME 未设置 | 按 5.2 设置环境变量并重启 |
| UnsupportedClassVersionError | DS 自带 Java 8 | 按 4.3 复制 Java 11，设 JAVA_HOME |
| Unable to load region | login shell 缺 AWS_REGION | ds-flink-env.sh 加 export AWS_REGION |
| config.sh arithmetic syntax error | PATH 写成宿主机值 | PATH 用容器内固定路径 |
| 连接 localhost:8081 失败 | rest.address 写错 | 改为 flink |
| No FileSystem for scheme s3 | 缺 s3 jar | 按 4.2 复制 connector |
| ClassNotFoundException SdkException | 缺 aws-bundle | 按 4.2 复制 connector |
| 类冲突 | 多版本 runtime 共存 | 排除旧版 jar |
| 作业在 8081 看不到 | 缺 execution.target=remote | 初始化 SQL 加三行 SET |
| 容器重启后配置丢失 | 未写入 compose | 按 5.1 持久化挂载 |

## 九、本篇小结

1. DS 的 Flink 节点依赖 Worker 容器内的 Flink 客户端。
2. 客户端从现有 flink 容器复制，版本天然一致。
3. lib 中的软链必须替换为实体 jar。
4. 连接地址写容器名 flink，不写 localhost。
5. 作业由 DS 客户端提交，实际运行在 flink 集群。
