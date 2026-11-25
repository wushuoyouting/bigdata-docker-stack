# Dinky 安装使用

> **一句话结论**：Dinky 给现有 Flink 集群补上 Web SQL IDE。它在浏览器写 SQL、预览结果、提交作业。元数据存本机 PostgreSQL，执行仍交给已有的 flink-jobmanager 与 flink-taskmanager。Dinky 不替代 Flink，也不另起一套计算集群。

> **本文解决什么**：本机已装好 Flink，但只有 sql-client.sh 可用。shell 看结果不便。本文用 Dinky 提供图形化执行与结果查看，并把元数据落到本机 PostgreSQL。本机 PG 已由 Homebrew 安装并运行，不再用 Docker 起 PG。

> **核对时点**：2026-11-17。macOS arm64 / Docker Desktop。whd-net 已含 minio .5、superset .6、flink-jobmanager .7、flink-taskmanager .8、starrocks .9；kafka 预留 .10；8888 待复核。
>
> **本机镜像与版本**：Dinky 选 1.2.4-flink1.20，与本机 flink:1.20.5-java11 的大版本一致。官方快速体验页的 1.1.0-flink1.17 版本不匹配，不用。

---

## 一、本次范围

| 本次必须做 | 本次禁止做 |
| --- | --- |
| 确认本机 PG 可连、dinky 库可用 | 在本机 PG 里建任何业务库表 |
| 起 Dinky 容器并接 whd-net | 在验收阶段建 Paimon 或 Doris Catalog |
| 注册 Standalone 集群指向现有 JM | 提交 01_paimon_catalog.sql 等业务脚本 |
| Local 模式预览 SELECT 1 | 执行任何 INSERT INTO 写回作业 |
| 验证作业可提交到外部 JM | 把 Dinky 当生产调度平台 |

> Dinky 的 Local 预览在 Dinky 容器内起迷你集群，不占用现有 TM。提交到外部集群才走 flink-jobmanager。Local 用于看结果，Standalone 用于正式提交。

---

## 二、安装前复核

```bash
lsof -nP -iTCP:8888 -sTCP:LISTEN || echo '8888 空闲'

brew services list 2>/dev/null | grep -i postgres
lsof -nP -iTCP:5432 -sTCP:LISTEN | head -3

psql -h 127.0.0.1 -U root -d dinky -tAc 'select 1' 2>&1

docker ps -a --filter name=dinky \
  --format '{{.Names}}\t{{.Status}}'

docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} | {{.IPv4Address}}{{println}}{{end}}'

ls -ld /Users/wenhuadong/docker/development/dinky/ \
       /Users/wenhuadong/docker/development/dinky/customJar/ 2>/dev/null
```

| 检查项 | 期望 | 不满足时 |
| --- | --- | --- |
| 8888 | 空闲 | 查占用进程 |
| PG 服务 | postgresql@14 started | brew services start postgresql@14 |
| 5432 | 127.0.0.1 与 [::1] 监听 | 检查 PG 配置与启动状态 |
| dinky 库 | select 1 返回 1 | 建库：createdb dinky，再授权 root |
| 同名容器 | 不存在 | 有残留则 stop 后 rm |
| whd-net | 含 flink-jobmanager .7 | 先按 Flink 安装教程装完并验收 |
| .11 地址 | 未被占用 | 占用时换一个 .12 以后的地址 |

**基线参数**：本机 PG 不在 whd-net 中。Dinky 容器经 host.docker.internal 访问宿主机 PG。Dinky 容器加入 whd-net，使用固定 IP 172.30.0.16。JobManager 地址写容器内 REST 地址 flink-jobmanager:8081，不带协议前缀。

> **分时启动**：16G 机器上 Doris BE 优先。验证 Dinky 期间 Superset 保持运行即可，不再同时起 StarRocks。
>
> **口令占位**：本文所有口令均写占位符。实际口令由本机 dinky/.env 提供，该文件 chmod 600、不进 git。Dinky 连接 PG 使用 root 账号，口令由本机生成，不写入本文。

### 2.1 拉取镜像并核对架构

① 拉取 Dinky 镜像。tag 里的 flink1.20 与本机 Flink 大版本一致。

```bash
docker pull dinkydocker/dinky-standalone-server:1.2.4-flink1.20
```

预期输出：下载各层，最后显示镜像的完整 ID。若本地已有镜像，显示 Image is up to date。

② 核对镜像架构。

```bash
docker image inspect dinkydocker/dinky-standalone-server:1.2.4-flink1.20 \
  --format '{{.Os}}/{{.Architecture}}'
```

| 返回结果 | 处理 |
| --- | --- |
| linux/arm64 | docker run 时不加 platform 参数 |
| linux/amd64 | 后续 docker run 加 --platform linux/amd64，接受启动变慢 |

> 本机是 arm64。若返回 linux/amd64，docker run 要加 --platform linux/amd64。模拟运行性能下降，仅用于本机体验。

---

## 三、准备目录与参数

### 3.1 建目录

```bash
mkdir -p /Users/wenhuadong/docker/development/dinky/customJar
```

| 目录 | 用途 |
| --- | --- |
| customJar | Dinky 自定义依赖，映射到 /opt/dinky/customJar/ |

### 3.2 创建参数文件

dinky/.env 是本机参数文件。用 heredoc 新建，参数直接写在脚本里。以下是本机案例参数：账号 root，库 dinky，地址为宿主机 PG。

```bash
cat > /Users/wenhuadong/docker/development/dinky/.env <<'EOF'
PG_USER=root
PG_PASSWORD=<PG_PWD>
PG_DATABASE=dinky
PG_ADDR=host.docker.internal:5432
EOF

chmod 600 /Users/wenhuadong/docker/development/dinky/.env
```

> 口令用占位符 &lt;PG_PWD&gt;，本文不写口令原文。实际执行前把占位符换成新生成的口令。文件权限设为 600，不进 git。

读取参数供后续命令使用：

```bash

set -a
. /Users/wenhuadong/docker/development/dinky/.env 
set +a

echo "PG_USER=$PG_USER  PG_DATABASE=$PG_DATABASE  PG_ADDR=$PG_ADDR"
```

预期输出：回显案例参数值，口令不回显。

> dinky 库属主是 root。Dinky 使用 root 账号连接，已授予 dinky 库全部权限与 public schema 权限。重建环境时按下方语句授权。

```bash
psql -h 127.0.0.1 -U root -d postgres -c \
  "ALTER ROLE root WITH PASSWORD '<PG_PWD>'; \
   GRANT ALL PRIVILEGES ON DATABASE dinky TO root;"
psql -h 127.0.0.1 -U root -d dinky -c \
  "GRANT ALL ON SCHEMA public TO root;"
```

尖括号占位符在代码块内保持原样。实际执行时把 &lt;PG_PWD&gt; 换成新口令。本机已完成此步，无需重跑。

---

## 四、启动 Dinky

### 4.1 准备自定义依赖

内置 History Server 需要 flink-s3-fs-presto jar。缺少时抓取线程抛 NoClassDefFoundError，触发 Flink 致命异常处理器，容器启动约 15 秒后自动退出。这个 jar 是必需的，不能省。

sql-client 与 sql-gateway 两个 jar 供容器外 SQL CLI 使用。容器外调用该 CLI 仍有 classpath 冲突，日常执行 SQL 用作业开发页面。这两个 jar 保留不影响作业开发。

三个 jar 都从本机同 tag 的 Flink 镜像取出。宿主机源必须先是文件。

```bash
SRC=/Users/wenhuadong/docker/development/dinky/customJar

docker run --rm --entrypoint sh "flink:1.20.5-java11" \
  -c 'cat /opt/flink/opt/flink-s3-fs-presto-*.jar' \
  > "$SRC/flink-s3-fs-presto-1.20.5.jar"

docker run --rm --entrypoint sh "flink:1.20.5-java11" \
  -c 'cat /opt/flink/opt/flink-sql-client-*.jar' \
  > "$SRC/flink-sql-client-1.20.5.jar"

docker run --rm --entrypoint sh "flink:1.20.5-java11" \
  -c 'cat /opt/flink/opt/flink-sql-gateway-*.jar' \
  > "$SRC/flink-sql-gateway-1.20.5.jar"

ls -l "$SRC"
```

预期输出：三个 jar 文件大小非 0。presto jar 约 92M，另两个约 1M。

> 若后续要用 Dinky 建 Paimon 或 Doris Catalog，再把 flink/jars/ 下的 connector jar 也放进 customJar。验收阶段不放，保持最小依赖。

### 4.2 启动容器

```bash
docker run -d \
  --name dinky \
  --network whd-net \
  --network-alias dinky \
  --ip 172.30.0.16 \
  -p 8888:8888 \
  --restart unless-stopped \
  -e DB_ACTIVE=postgresql \
  -e POSTGRES_ADDR="$PG_ADDR" \
  -e POSTGRES_DATABASE="$PG_DATABASE" \
  -e POSTGRES_USER="$PG_USER" \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" \
  -v /Users/wenhuadong/docker/development/dinky/customJar:/opt/dinky/customJar/:ro \
  dinkydocker/dinky-standalone-server:1.2.4-flink1.20

docker logs -f dinky --tail 100
```

预期输出：日志出现 Started DinkyApplication。日志不含 Connection refused: host.docker.internal:5432。

| 参数 | 取值 | 为什么 |
| --- | --- | --- |
| --ip 172.30.0.16 | 固定值 | 避开 Kafka 的 .11 |
| -p 8888:8888 | 固定值 | Web UI 与 REST 端口 |
| -e DB_ACTIVE | pgsql | 切到外部 PostgreSQL，默认 h2 |
| -e POSTGRES_ADDR | host.docker.internal:5432 | 容器内访问宿主机 PG |
| -e POSTGRES_DATABASE | dinky | 库名 |
| -e POSTGRES_USER | root | Dinky 连接账号 |
| -e POSTGRES_PASSWORD | 变量引用 | 口令，不落文档 |
| -v customJar 路径 | 只读挂载 | 只加依赖，不改镜像自带 lib |

> 容器持续 Up 且日志出现 Started DinkyApplication，即说明 PG 连接成功。Dinky 启动时必须连库初始化，连不上会退出。无需另做通路验证。

> docker run 用 POSTGRES_DATABASE 作库名变量。docker-compose 的 env 文件用 POSTGRES_DB。两个名字不同，本文按 docker run 写。写 localhost:5432 在容器内指向 Dinky 自己，连接必失败。

> 镜像若为 amd64，在 docker run 后加 --platform linux/amd64。Dinky 1.2 用 WebSocket 推日志，本机直连 8888，不经过 Nginx，无需代理配置。

### 4.3 首次登录与元数据验证

浏览器打开 http://localhost:8888。用官方快速体验页给出的初始账号登录，首次登录后立即修改口令。初始口令不写入本仓库。

在宿主机执行 psql 验证元数据表。

```bash
psql -h 127.0.0.1 -U root -d dinky -c '\dt'
```

预期输出：列出 dinky 元数据表。若返回 No relations found，查 Dinky 启动日志的建表错误。

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 页面打不开 | 容器未起或 8888 被占 | docker logs dinky；lsof 查端口 |
| Connection refused: host.docker.internal | PG 未起或地址写 localhost | 确认 PG 服务启动，地址写 host.docker.internal |
| password authentication failed | .env 口令与 PG 不一致 | 核对 PG_PASSWORD，改后重建 Dinky 容器 |
| No relations found | Dinky 未在 dinky 库建表 | 查启动日志，确认 root 有建表权限 |
| 登录后立即掉线 | WebSocket 被代理拦截 | 本机直连 8888，不配 Nginx |

---

## 五、注册 Flink 集群

> **前提**：flink-jobmanager 与 flink-taskmanager 均 Up，http://localhost:8081/overview 返回 taskmanagers ≥ 1。

① 登录 Dinky，进入注册中心 → 集群实例 → 新建。

② 按表填写。

| 配置项 | 取值 |
| --- | --- |
| 集群名称 | local-flink-120 |
| 类型 | Standalone |
| JobManager 地址 | flink-jobmanager:8081 |

③ 保存后看状态列。状态正常即注册成功。

④ 点集群行的 Flink Web UI，应跳到同一 Dashboard。

> JobManager 地址写容器内 REST 地址。写 http://localhost:8081 会指向 Dinky 容器自己，注册必失败。

---

## 六、执行与查看

### 6.1 Local 预览

> **提示**：Local 预览在 Dinky 容器内起迷你集群，不占用现有 TM。它只用于调试和看结果。

① 数据开发 → 目录 → 右键新建作业。

② 作业类型选 FlinkSQL，名称填 preview_select。

③ 右侧执行模式选 Local，并行度填 1。

④ 填入以下 SQL。

```sql
CREATE TABLE Orders (
  order_number BIGINT,
  price DECIMAL(32,2),
  buyer ROW<first_name STRING, last_name STRING>,
  order_time TIMESTAMP(3)
) WITH (
  'connector' = 'datagen',
  'rows-per-second' = '1',
  'number-of-rows' = '5'
);

SELECT order_number, price, buyer.first_name, order_time FROM Orders;
```

⑤ 点工具条预览。日志区实时输出，完成后切到结果页，点获取最新数据。

预期输出：结果页显示 5 行订单数据，含顺序号、价格、名字、时间。

### 6.2 提交到外部集群

> **注意**：本步只提交 datagen 到 blackhole 的演示作业，不写 Paimon、不写 MinIO。验收阶段到此为止。

① 新建作业 submit_demo，执行模式选 Standalone，集群选 local-flink-120。

② 填入以下 SQL。

```sql
CREATE TABLE datagen_source (
  id BIGINT,
  name STRING
) WITH (
  'connector' = 'datagen',
  'number-of-rows' = '10'
);

CREATE TABLE blackhole_sink (
  id BIGINT,
  name STRING
) WITH (
  'connector' = 'blackhole'
);

INSERT INTO blackhole_sink SELECT id, name FROM datagen_source;
```

③ 点执行按钮提交。

④ 打开 http://localhost:8081 → Jobs，应看到新作业。有界源约数秒后变 FINISHED，属正常。

| 检查点 | 通过标准 |
| --- | --- |
| Dinky 运维中心 | 作业状态 FINISHED，日志无异常 |
| Flink Dashboard | Jobs 列表出现同名作业 |
| 本机 PG | 作业记录写入 dinky 库，重启 Dinky 后仍在 |

> 有界源作业会自己结束。判据是作业到达 FINISHED 且无异常，不是长期 RUNNING。

### 6.3 SQL CLI 控制台

① 数据开发 → SQL CLI → 选择 local-flink-120 → 连接。

② 执行以下语句。

```sql
SELECT 1 AS ok;
```

预期输出：结果列 ok 显示 1。

> 若控制台报缺 flink-sql-client 或 flink-sql-gateway 类，从 Flink 镜像重新取 jar 放进 customJar，再重启 Dinky。

---

## 七、验收对照

> **前提**：本章在安装、集群注册、演示作业全部完成后执行。逐条核对，全通过即交付。

| # | 判据 | 检查方式 | 通过标准 |
| --- | --- | --- | --- |
| ① | 本机 PG 可连，dinky 库存在 | psql -h 127.0.0.1 -U root -d dinky -c 'select 1' | 返回 1 |
| ② | Dinky 页面可登录 | 浏览器打开 http://localhost:8888 | 用初始账号登录后进入首页 |
| ③ | 集群注册状态正常 | 注册中心 → 集群实例 → 状态列 | 状态列显示正常 |
| ④ | SQL CLI 可执行 SELECT 1 | 数据开发 → SQL CLI → 连接集群 | 结果列 ok 显示 1 |
| ⑤ | Local 预览返回一行结果 | 工具条预览 → 结果页获取最新数据 | 结果页显示 5 行订单数据 |
| ⑥ | 提交作业出现在 Flink Dashboard | http://localhost:8081 → Jobs | Jobs 列表出现 submit_demo，状态 FINISHED |

> 六条全通过，说明 Dinky 与本机 PG、现有 Flink 集群的对接完成。任一不通过，按故障速查定位。

---

## 八、停止、重启与重来

```bash
docker stop dinky
docker start dinky
docker logs -f dinky --tail 100
```

| 动作 | 数据安全 |
| --- | --- |
| stop / start | customJar 保留，元数据在本机 PG，作业记录不丢 |
| docker rm -f dinky | 容器可写层丢失，元数据仍在本机 PG |
| 本机 PG 重启 | 先停 Dinky 再重启 PG，最后起 Dinky |
| docker rm -v | 禁止，会删命名卷 |

> 本机 PG 由 brew services 管理，不随 Dinky 容器停止。Dinky 重启后重新连本机 PG。PG 未就绪就起 Dinky，日志会报连接拒绝。

---

## 九、故障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 容器启动约 15 秒后退出，日志含 NoClassDefFoundError: S3FileSystemFactory | 缺 flink-s3-fs-presto jar | 按 4.1 取 jar 放进 customJar 后重启 |
| 容器启动即退出，日志报 PG 连接拒绝 | 容器到宿主机通路不通 | brew services start postgresql@14；再用下方命令测通路 |
| Connection refused: host.docker.internal:5432 | PG 服务未起 | brew services start postgresql@14 |
| password authentication failed | .env 口令与 PG 不一致 | 核对 PG_PASSWORD，改后重建 Dinky 容器 |
| No relations found | Dinky 未在 dinky 库建表 | 查启动日志，确认 root 有建表权限 |
| 容器内 localhost:5432 连不上 | 指向容器自己 | 改 host.docker.internal:5432 |
| 集群状态异常 | JM 地址写错或容器不通 | 写 flink-jobmanager:8081，nslookup 验证 |
| 提交作业报 ClassNotFoundException | connector jar 只在 JM 与 TM，Dinky 侧缺 | 把对应 jar 放入 customJar 后重启 Dinky |
| exec format error | amd64 镜像在 arm64 未模拟 | docker run 加 --platform linux/amd64 |
| 预览结果页空白 | WebSocket 日志被代理拦截 | 本机直连 8888，不配 Nginx |
| 作业 FINISHED 却被判失败 | 有界源自行结束 | 看状态 FINISHED 且日志无异常 |
| 重启后作业记录消失 | 元数据落到了容器可写层 | 确认 DB_ACTIVE=pgsql 且本机 PG 在跑 |

Dinky 启动失败时，用临时容器测容器到宿主机 PG 的通路：

```bash
docker run --rm --network whd-net flink:1.20.5-java11 bash -c \
  'getent hosts host.docker.internal; \
   timeout 3 bash -c "cat < /dev/null > /dev/tcp/host.docker.internal/5432" \
   2>/dev/null && echo "PG 通路正常" || echo "PG 通路失败"'
```

预期输出：先打印 host.docker.internal 的解析地址，最后显示 PG 通路正常。

---

## 十、小结

1. Dinky 是 Web SQL IDE，不替代 Flink 集群。执行仍走现有 JM 与 TM。
2. 元数据存本机 PostgreSQL。DB_ACTIVE 取 pgsql，地址写 host.docker.internal:5432。
3. 容器持续 Up 且日志出现 Started DinkyApplication，即证明 PG 连接成功。
4. 镜像选 1.2.4-flink1.20，与本机 Flink 大版本一致。arch 不符就模拟。
5. 验收两步：Local 预览看结果，Standalone 提交看 Dashboard。
6. 验收阶段不建业务 Catalog、不提交写回作业。业务脚本留到项目阶段。
