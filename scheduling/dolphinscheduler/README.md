# DS 安装手册

> **本文位置**：全局组件目录 /Users/wenhuadong/docker/scheduling/dolphinscheduler/，供本机所有项目共用。组件地图 /Users/wenhuadong/docker/README.md ｜ 强制规则 /Users/wenhuadong/docker/配置准则.md ｜ 项目侧索引 ~/prj/asr-resume/prj/湖仓一体/deploy/00-已有环境核对.md ｜ 安装总览 ~/prj/asr-resume/prj/湖仓一体/02-安装手册.md。
>
> **本文按「装一遍要读的顺序」编排**：方案与现状 → 安装前核查 → 红线与账号选型 → 编排与目录 → 账号与库准备 → 启动 → 验证 → 停止重来 → 回填与小结 → **踩坑（最后一节）**。照启动至验证各步做即可完成安装；排障看最后一节踩坑。

> **一句话结论**：不再为 DS 起 PostgreSQL 容器，直接用**宿主机 Homebrew PostgreSQL 14.20** 里已有的 dolphinscheduler 库；只起一个 ds-standalone 容器，经 host.docker.internal:5432 连宿主库，并直接落在共享网络 whd-net。账号用 root / &lt;DS_DB_PWD&gt;（已就绪）；owen / &lt;DS_DB_PWD&gt; 作为备选。**库已存在，不创建、不删除、不重跑初始化 SQL。**

> **核对时点**：2026-11-10。Docker Server 29.7.2 / Compose v5.5.0 / macOS arm64；镜像 apache/dolphinscheduler-standalone-server:3.4.3（arm64，4.45GB）已在本机。本文所有「实测」均为只读核查所得。

> **当前状态（2026-11-10 安装完成并验收）**：
> - **已完成**：root 角色与库/表属主准备（由你执行）；ds-standalone 启动，healthy、UI 200、登录 API login success；四视角验证全通；restart 后 64 张表 / admin / 3.4.3 / 属主 root 全部保留。
> - **容器现状**：ds-standalone Up (healthy)，172.30.0.2，Compose 项目名 dolphinscheduler，接入 whd-net；宿主 PG 上 root 有 10 个连接池会话。
> - **不需要执行**：建库、删库、重跑 dolphinscheduler_postgresql.sql、改宿主 PG 配置文件；这些是明确红线。
> - **已知限制**：日志有 OverLoad ... cpu usage 1.0 告警（本机 CPU 采样过高触发 Master 过载保护），不影响 UI / 登录。

---

## 1. 方案与当前状态

### 1.1 相对旧方案改了什么

| # | 旧做法 | 本方案 | 为什么 |
| --- | --- | --- | --- |
| 1 | compose 里多起一个 ds-postgres 容器 | **复用宿主机 PG** :5432 | 宿主已装 PG 14.20，不必重复部署 |
| 2 | 容器别名 ds-postgres:5432 | host.docker.internal:5432 | 容器访问宿主机服务的标准写法（Docker Desktop for Mac） |
| 3 | 保留 dsnet，用 docker network connect 补接 | ds-standalone 由编排**直接落在 whd-net** | 只有一张共享网络，不再补接、不再有 dsnet |
| 4 | 默认内存 H2（jdbc:h2:mem:dolphinscheduler） | 外置 PostgreSQL（SPRING_PROFILES_ACTIVE=postgresql） | 内存库在容器重建后项目/数据源/工作流全丢 |
| 5 | 每次启动自动跑初始化 SQL | SPRING_SQL_INIT_MODE=never | 官方 SQL 带 DROP TABLE，重启会清库 |

### 1.2 实测台账（复核用）

```bash
psql -w -h 127.0.0.1 -U wenhuadong -d postgres -c '\du'
psql -w -h 127.0.0.1 -U wenhuadong -d postgres \
  -tAc "select datname, pg_get_userbyid(datdba) from pg_database where datname='dolphinscheduler';"
PGPASSWORD=<DS_DB_PWD> psql -w -h 127.0.0.1 -U root -d dolphinscheduler \
  -tAc "select current_user, (select version from t_ds_version), (select count(*) from t_ds_project);"
docker ps -a --filter name=ds- --format '{{.Names}}\t{{.Status}}'
```

| 项 | 实测值 |
| --- | --- |
| 宿主 PG | PostgreSQL 14.20（Homebrew），数据目录 /opt/homebrew/var/postgresql@14 |
| 已有库 | dolphinscheduler（**复用**）、datapivot 等，共 11 个 |
| 库 owner | root |
| 表 | 64 张，**全部 owner = root**（原为 ds，已转移） |
| schema 版本 | t_ds_version = 3.4.3，与镜像一致 |
| 业务数据 | t_ds_user = 1（默认 admin）、t_ds_project = 0、t_ds_datasource = 0 → **空 schema，无业务数据** |
| 角色 | wenhuadong（Superuser / Create role / Create DB）、owen（Superuser / Create DB）、root（普通 LOGIN，rolsuper=f）、ds（普通 LOGIN，已不拥有对象） |
| root 权限 | has_database_privilege(... CREATE)=t、has_schema_privilege(... public, CREATE)=t、has_table_privilege(... t_ds_user, INSERT/UPDATE/SELECT)=t |
| 活跃会话 | 3 个 owen@::1 连在 dolphinscheduler 库上（你的查询会话；截图时为 active，实测时为 idle） |
| 监听 / 鉴权 | listen_addresses = localhost；pg_hba.conf 全 trust，放行 127.0.0.1/32、::1/128 |
| DS 容器 | ds-standalone Up (healthy)，172.30.0.2，project dolphinscheduler；UI 200、登录 API login success、宿主 PG root 有 10 个连接池会话 |

---

## 2. 安装前核查

### 2.1 宿主 PG

```bash
psql --version
psql -w -h 127.0.0.1 -U wenhuadong -d postgres -tAc \
  "select current_user, version(), current_setting('listen_addresses'), current_setting('hba_file');"
psql -w -h 127.0.0.1 -U wenhuadong -d postgres -c '\du'
psql -w -h 127.0.0.1 -U wenhuadong -d postgres -c '\l'
```

| 检查项 | 实测结果 | 结论 |
| --- | --- | --- |
| 超级用户 | wenhuadong；owen 也是 Superuser | 建模/授权用 -U wenhuadong |
| root 角色 | **已存在**，可登录，非超级用户 | 主线账号，编排已按它配好 |
| 监听 | 只监听 127.0.0.1 / ::1 | 不对外暴露 |
| 访问控制 | pg_hba.conf 全 trust | — |
| dolphinscheduler 库 | 已存在，owner root，64 张表 | **不创建、不删除** |
| 活跃会话 | 3 个 owen 连接 | **不要终止、不能 DROP DATABASE** |

### 2.2 容器→宿主

```bash
docker run --rm --network whd-net postgres:16-alpine \
  psql -w -h host.docker.internal -U root -d dolphinscheduler \
  -tAc "select current_user, inet_client_addr(), inet_server_addr(), (select count(*) from t_ds_user);"
# 实测：root | 127.0.0.1 | 127.0.0.1 | 1
```

| 检查项 | 实测结果 |
| --- | --- |
| host.docker.internal 解析 | 192.168.65.254 |
| 容器内 TCP :5432 | 可达 |
| 容器内用 wenhuadong 登录 | 成功，客户端地址显示 127.0.0.1 |
| 容器内用 root 登录并查表 | 成功（t_ds_user = 1） |

> **为什么不用改 postgresql.conf / pg_hba.conf**：Docker Desktop 把 host.docker.internal 的流量转发到宿主 loopback，服务端看到的是 127.0.0.1，正好命中现有 host all all 127.0.0.1/32 trust。改配置文件会牵连 datapivot 等其它库，**本方案不动它**。
>
> host.docker.internal 是 Docker Desktop for Mac 提供的名字；Linux 上需要 --add-host=host.docker.internal:host-gateway。

### 2.3 镜像、端口、共享网络

```bash
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep dolphinscheduler
lsof -nP -iTCP:12345 -iTCP:25333 -iTCP:5432 -sTCP:LISTEN
docker network inspect whd-net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker compose -f /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml config -q
```

| 检查项 | 期望 / 实测 |
| --- | --- |
| 镜像 | apache/dolphinscheduler-standalone-server:3.4.3 已在本机 |
| 12345 / 25333 | 空闲（宿主 5432 被 PG 占用，不冲突） |
| whd-net | 已存在，172.30.0.0/24，成员 doris-fe / doris-be |
| compose 语法 | config -q 通过 |

---

## 3. 红线与账号选型

### 3.1 库结构红线

你已明确「**库已经存在，不再创建**」。因此：

| 操作 | 本方案 | 原因 |
| --- | --- | --- |
| CREATE DATABASE dolphinscheduler | **禁止** | 库已存在，且是 3.4.3 的空 schema |
| DROP DATABASE dolphinscheduler | **禁止** | 有 3 个 owen 会话连着；会失败，且会毁掉现有结构 |
| 重跑 sql/dolphinscheduler_postgresql.sql | **禁止** | 开头是 DROP TABLE IF EXISTS ... + CREATE，还带默认 admin INSERT，会把 64 张表清空重建 |
| REASSIGN OWNED BY ds TO ... | **不需要** | 属主已全部是 root（实测） |
| 改 postgresql.conf / pg_hba.conf | **不需要** | 改了会牵连其它库 |

sql/dolphinscheduler_postgresql.sql 保留在目录里**只作备份/升级参考**，安装流程不执行它。

### 3.2 PG 侧不校验

pg_hba.conf 是 trust，经 host.docker.internal 进来的连接显示为 127.0.0.1，命中 host all all 127.0.0.1/32 trust。**密码写在 DS 的 JDBC 配置里，但 PG 不校验**——这一点和 Doris 不同（Doris root@% 是真校验口令的，见 doris/组件手册）。

> **不要为了「让密码生效」去改这一行**：它是全局规则，改成 scram-sha-256 会同时影响 datapivot、dqc_meta 等所有本机连接。安全上依靠「PG 只监听 localhost、5432 不映射进容器」即可。

### 3.3 账号选型

| 项 | root / &lt;DS_DB_PWD&gt;（**主线，编排已按它配好**） | owen / &lt;DS_DB_PWD&gt;（备选） |
| --- | --- | --- |
| 是否已存在 | **是**（已创建，可登录） | 是（本机既有账号） |
| 权限 | 普通角色，但**库 owner + 64 张表 owner**，CREATE / 读写实测全通 | **Superuser, Create DB**，权限最大 |
| 改动量 | 已完成（无需再做任何事） | 零改动 |
| 最小权限原则 | ✅ 比超级用户收敛 | ❌ 把超级用户交给应用，且是共用账号（3 个会话正在用） |
| 与编排一致性 | ✅ SPRING_DATASOURCE_USERNAME: root 已写好 | 需改 SPRING_DATASOURCE_USERNAME: owen |

**结论：沿用 root / &lt;DS_DB_PWD&gt。** 它已具备完整权限且不是超级用户，owen 保留给你日常查库和其它项目使用。若你坚持用 owen，只需把编排里 SPRING_DATASOURCE_USERNAME 改成 owen，其余全部不变（口令同为 &lt;DS_DB_PWD&gt;）。

> 上一版手册写「root 角色不存在、待创建」「表 owner 是 ds」「宿主 PG 未做任何改动」——**这些已被本次核对推翻**：root 已创建、库与表属主已转 root、宿主 PG 已完成账号准备。本手册据此订正。

---

## 4. 编排文件与目录

```
/Users/wenhuadong/docker/scheduling/dolphinscheduler/     # 全局组件目录，不进任何 git 仓库
├── README.md                                  # 本文，唯一安装手册
├── conf/
│   ├── docker-compose.whd.yml                 # 编排文件（只有一个 ds-standalone 服务）
│   └── dolphinscheduler.env                   # 环境变量配置：数据源账号/口令、JVM、sql.init.mode
├── sql/dolphinscheduler_postgresql.sql        # 官方初始化 SQL：仅备份/升级参考，**安装不执行**
├── volumes/ds/logs/                           # DS 日志（映射 /opt/dolphinscheduler/logs）
├── volumes/ds/resources/                      # 资源中心 / 任务临时目录（映射 /tmp/dolphinscheduler）
└── volumes/postgres/                          # 上一轮容器化 PG 的废弃数据，保留不删，本方案不用
```

> **编排文件与配置都在 conf/**：执行一律 docker compose -f /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml ...。Compose 以 **conf/** 为基准解析相对路径，所以 env_file: ./dolphinscheduler.env 指向 conf/dolphinscheduler.env，卷必须写 ../volumes/ds/... 才回到组件根的 volumes/。**改配置只改 conf/dolphinscheduler.env**（数据源账号/口令、JVM、SPRING_SQL_INIT_MODE 等全在里面），改完 up -d 生效；不要在组件根目录再放第二份编排文件，否则相对路径基准会变、两处口径分叉。

| 参数 | 值 | 为什么 |
| --- | --- | --- |
| env_file: ./dolphinscheduler.env | conf/dolphinscheduler.env | 环境变量集中成一份配置，编排文件只管结构；含真实口令，不进 git |
| name: dolphinscheduler | **Compose 项目名 = 组件名** | 公共组件命名规则（全局基线） |
| ipv4_address | 172.30.0.2 | **固定 IP**：自动分配曾漂到 172.30.0.8，占住 Doris FE 的静态 IP 导致 FE 起不来；固定后 FE .8 / BE .9 / DS .2 互不冲突 |
| container_name / 别名 | ds-standalone | 全局基线已登记 |
| networks.whd-net.external: true | 引用外部共享网络 | down 不会删掉 whd-net |
| SPRING_PROFILES_ACTIVE | postgresql | 镜像内置 on-profile: postgresql：驱动 org.postgresql.Driver、Quartz PostgreSQLDelegate |
| SPRING_DATASOURCE_URL | jdbc:postgresql://host.docker.internal:5432/dolphinscheduler | 容器连宿主 PG |
| SPRING_DATASOURCE_USERNAME / PASSWORD | root / "&lt;DS_DB_PWD&gt;" | 改 owen 只需换用户名 |
| SPRING_SQL_INIT_MODE | never | 防止启动时重跑 DROP TABLE 清库 |
| JAVA_OPTS | -Xms512m -Xmx2g -Xmn512m ... | 镜像默认 -Xms4g -Xmx4g 且 ExitOnOutOfMemoryError，本机 Docker Desktop 会 OOM（旧容器 Exited(137) 即此原因） |
| SPRING_JACKSON_TIME_ZONE | Asia/Shanghai | 与镜像 TZ 一致 |

| 端口 | 谁用 | 写什么 |
| --- | --- | --- |
| 12345 | 本机浏览器 → DS UI | http://localhost:12345/dolphinscheduler/ui |
| 25333 | DS API（可选） | localhost:25333 |
| 5432 | DS 容器 → 宿主 PG | host.docker.internal:5432（**不是** localhost，也不映射宿主） |
| 9030 | DS → Doris FE | doris-fe:9030（同网络别名） |

> **只有 UI / API 端口映射到宿主**；5432 是宿主已有服务，容器走 host.docker.internal 访问，符合准则「只把必要的端口映射到宿主」。

---

## 5. 账号与库准备

### 5.1 复核清单（只读）

```bash
# 1) 角色存在且可登录
PGPASSWORD=<DS_DB_PWD> psql -w -h 127.0.0.1 -U root -d dolphinscheduler \
  -tAc "select current_user, current_database(), (select version from t_ds_version);"
#   期望：root | dolphinscheduler | 3.4.3

# 2) 库与表属主都是 root
psql -w -h 127.0.0.1 -U wenhuadong -d postgres \
  -tAc "select datname, pg_get_userbyid(datdba) from pg_database where datname='dolphinscheduler';"
psql -w -h 127.0.0.1 -U wenhuadong -d dolphinscheduler \
  -tAc "select tableowner, count(*) from pg_tables where schemaname='public' group by tableowner;"
#   期望：dolphinscheduler | root ／ root | 64

# 3) 建表 / 读写权限
psql -w -h 127.0.0.1 -U wenhuadong -d dolphinscheduler -tAc \
  "select has_database_privilege('root','dolphinscheduler','CREATE'),
          has_schema_privilege('root','public','CREATE'),
          has_table_privilege('root','t_ds_user','INSERT,UPDATE,SELECT');"
#   期望：t|t|t

# 4) 从容器视角连一次（DS 将来的路径）
docker run --rm --network whd-net postgres:16-alpine \
  psql -w -h host.docker.internal -U root -d dolphinscheduler \
  -tAc "select current_user, (select count(*) from t_ds_user);"
#   期望：root | 1
```

| 检查项 | 通过标准 | 实测 |
| --- | --- | --- |
| root 可登录 | 返回 root | ✅ |
| 库 owner | root | ✅ |
| 表 owner | 64 张全为 root | ✅ |
| schema 版本 | 3.4.3 | ✅（与镜像一致，无需初始化） |
| 业务数据 | t_ds_project = 0、t_ds_user = 1 | ✅ 空 schema，未清库重建 |
| 权限 | t / t / t | ✅ |
| 容器内连接 | 成功 | ✅ |

### 5.2 已完成动作

> 以下由你执行、本轮核对确认；**重复执行会报错或产生副作用**（CREATE ROLE 会报已存在，REASSIGN OWNED 在无对象时无意义）。

```sql
-- 以超级用户 wenhuadong 执行（已完成，仅留档）
CREATE ROLE root WITH LOGIN PASSWORD '<DS_DB_PWD>';
ALTER DATABASE dolphinscheduler OWNER TO root;
-- 在 dolphinscheduler 库内执行（已完成，仅留档）
REASSIGN OWNED BY ds TO root;
GRANT ALL ON SCHEMA public TO root;
```

### 5.3 明确不做的事

| 不做 | 原因 |
| --- | --- |
| CREATE DATABASE dolphinscheduler | 库已存在，你已明确不再创建 |
| DROP DATABASE / 终止 owen 会话 | 3 个会话是你的查询窗口或别的服务；删库会失败且毁数据 |
| 执行 sql/dolphinscheduler_postgresql.sql | 含 DROP TABLE IF EXISTS，会清空 64 张表 |
| 再建 root、再转属主 | 已完成 |
| 改 pg_hba.conf 启用密码校验 | 全局规则，牵连其它库 |

**默认账号**：admin / dolphinscheduler123（来自既有 schema），首次登录后请修改。

---

## 6. 启动

```bash
# 1) 共享网络已存在，确认即可，不要重建
docker network inspect whd-net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
#   期望：172.30.0.0/24

# 2) 语法自检
docker compose -f /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml config -q

# 3) 起容器
docker compose -f /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml up -d

# 4) 看状态与日志
docker compose -f /Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml ps
docker logs -f --tail 100 ds-standalone
```

**等待点**：standalone 内含 Master / Worker / API / Alert 与 Quartz，首次启动约 1–2 分钟；编排里 healthcheck 探 12345 登录页，healthy 之前别去点 UI。

```bash
# 循环等 UI 就绪（最多 3 分钟）
for i in $(seq 1 36); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    http://localhost:12345/dolphinscheduler/ui/login 2>/dev/null || true)
  [ "$code" = "200" ] && { echo "DS UI 就绪"; break; }
  echo "第 ${i} 次：还没就绪，等 5s"; sleep 5
done
```

| 步骤 | 判据 | 不通过怎么办 |
| --- | --- | --- |
| 1 网络 | 172.30.0.0/24 | 按全局 README 建，不要删了重建 |
| 2 语法 | 无输出 | 检查 YAML 缩进与引号（&lt;DS_DB_PWD&gt; 必须加引号） |
| 3 up -d | 容器创建成功 | docker logs ds-standalone --tail 100 |
| 4 等 UI | compose ps 为 healthy，HTTP 200 | — |

---

## 7. 连通性验证

```bash
# 视角 1：本机 → DS UI
curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://localhost:12345/dolphinscheduler/ui/login

# 视角 2：DS 容器 → 宿主 PG（证明 JDBC 地址写得通）
docker exec ds-standalone bash -c 'echo > /dev/tcp/host.docker.internal/5432 && echo OK'

# 视角 3：DS 容器 → Doris FE（05 建数据源前的预检）
docker exec ds-standalone sh -c 'getent hosts doris-fe'
docker exec ds-standalone bash -c 'echo > /dev/tcp/doris-fe/9030 && echo OK'

# 视角 4：网络成员与 Compose 项目名
docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
docker inspect ds-standalone \
  --format '{{index .Config.Labels "com.docker.compose.project"}}'
```

| 检查项 | 通过标准 |
| --- | --- |
| compose ps | ds-standalone healthy |
| 视角 1 | HTTP 200；浏览器能用 admin / dolphinscheduler123 登录 |
| 视角 2 | 输出 OK；日志里数据源是 PostgreSQL，无 Communications link failure |
| 视角 3 | doris-fe 解析出 172.30.0.8，9030 输出 OK |
| 视角 4 | 成员含 doris-fe / doris-be / ds-standalone；项目名为 dolphinscheduler |
| 日志 | 无 relation ... does not exist、无 permission denied、无 OutOfMemoryError |

> ⚠️ **Doris 数据源要带口令**：doris-fe:9030 的 root@% 非空口令，只有 FE 容器内 loopback 免密。在 DS 里建数据源时按 安装手册回填表的 &lt;FE_USER&gt; / &lt;FE_PWD&gt; 填。

**持久化复核**：在 UI 里随便建一个项目 → docker compose restart ds-standalone → 重新登录确认项目还在；同时复核宿主 PG 里表数仍是 64、t_ds_project 计数未归零（证明 sql.init.mode=never 生效、没有重跑 DROP TABLE）。

---

## 8. 停止与重来

```bash
F=/Users/wenhuadong/docker/scheduling/dolphinscheduler/conf/docker-compose.whd.yml

docker compose -f "$F" stop          # 停容器，宿主 PG 与元数据不动
docker compose -f "$F" start
docker compose -f "$F" restart       # 复核持久化用这个

docker compose -f "$F" down          # 删容器；**不要加 -v**，卷数据保留
docker compose -f "$F" up -d
```

> down 不会删 whd-net（external: true），也不会动宿主机 PG。DS 元数据在宿主 PG 里，**容器删了也不丢**。
> 只有明确要清空 DS 元数据时，才在宿主 PG 里手工处理 dolphinscheduler 库；本手册不提供一键清库命令。
> 上一轮容器化 PG 的 volumes/postgres/ 是废弃数据，本方案不使用；保留不删，确认无用后再自行清理。

---

## 9. 回填表与本篇小结

> 本节位于**不进 git 的本机全局目录**，故记录真实值；项目仓库侧的索引页与回填表一律使用 &lt;DS_DB_PWD&gt; 等占位符，**禁止把真值写进任何 git 仓库**。

回填到 /Users/wenhuadong/prj/asr-resume/prj/湖仓一体/安装手册（**真实口令不写进版本库**）：

| 占位符 | 本手册值 | 实际值 |
| --- | --- | --- |
| &lt;DS_WEB_URL&gt; | http://localhost:12345/dolphinscheduler/ui | 待回填
| &lt;DS_ADMIN&gt; / &lt;DS_PWD&gt; | admin / 首次登录后自设 | 待回填
| &lt;DS_CONTAINER&gt; | ds-standalone | 待回填
| &lt;DS_DB_HOST_IN&gt; | host.docker.internal | 待回填
| &lt;DS_DB_PORT&gt; / 库名 | 5432 / dolphinscheduler（**已存在，不创建**） | 待回填
| &lt;DS_DB_USER&gt; / &lt;DS_DB_PWD&gt; | root / &lt;DS_DB_PWD&gt;（备选 owen / &lt;DS_DB_PWD&gt;） | 待回填
| &lt;FE_QUERY_HOST&gt; / 端口 | doris-fe / 9030 | 待回填
| 共享网络 / 子网 | whd-net / 172.30.0.0/24 | 待回填
| Compose 项目名 | dolphinscheduler | 待回填

1. **不再起 PG 容器**：宿主 PG 14.20 的 dolphinscheduler 库直接复用，容器用 host.docker.internal:5432 连。
2. **不需要改宿主 PG 配置**：实测容器连接被转发成 127.0.0.1，现有 listen_addresses=localhost + pg_hba trust 已放行；改配置会牵连其它库。
3. **库已存在，只核对不创建**：不 CREATE DATABASE、不 DROP DATABASE、不重跑 DROP TABLE 的初始化 SQL；root 角色与 64 张表属主均已就绪。
4. **账号主线 root / &lt;DS_DB_PWD&gt;**：已创建、非超级用户、库与表 owner、容器内实测可连；owen / &lt;DS_DB_PWD&gt; 是 Superuser 备选，改动编排一个环境变量即可切换。PG 侧 trust 不校验密码，与 Doris 侧必须带口令不同。
5. **启动不再刷库**：SPRING_SQL_INIT_MODE=never + 限堆 JAVA_OPTS 是编排里两条不能删的配置。
6. **网络只有一张 whd-net**：DS 直接落在网上，用别名 doris-fe:9030 访问 Doris；不再有 dsnet、也不再做 docker network connect 补接。

---

## 10. 专属踩坑

| # | 现象 | 原因 | 解决 / 预防 |
| --- | --- | --- | --- |
| 1 | FATAL: role "root" does not exist | 账号准备没做 | 本环境**已创建**；若换机器，按 5.2 留档 SQL 建角色 |
| 2 | CREATE ROLE root 报 already exists | 重复执行 5.2 | 本节只做复核，勿重复创建；改查 5.1 清单 |
| 3 | CREATE DATABASE 报已存在 / DROP DATABASE 失败 | 库已存在且有 3 个 owen 会话 | **本方案不建库、不删库**；不要终止那些会话 |
| 4 | 启动后表被清空 / admin 密码被重置 | spring.sql.init 重跑了带 DROP TABLE 的 SQL | 编排固定 SPRING_SQL_INIT_MODE=never；初始化 SQL 安装流程不执行 |
| 5 | permission denied for table t_ds_* | 账号不是表 owner 也没被授权 | 复核 5.1 的表属主与 has_table_privilege；本环境 64 张表已全是 root |
| 6 | FATAL: no pg_hba.conf entry for host ... | 换了 Linux / 没走 Docker Desktop 转发 | 本手册按 macOS 实测；Linux 需 host-gateway 并加对应网段规则 |
| 7 | JDBC 写 localhost:5432 连不上 | 在容器里 localhost 指容器自己 | 必须写 host.docker.internal:5432 |
| 8 | 改了 pg_hba.conf 后 datapivot 等库连不上 | trust 是全局规则 | 不要为单个组件改 hba；安全靠「只监听 localhost」 |
| 9 | Exited (137) / OutOfMemoryError | 镜像默认 -Xmx4g | 编排里 JAVA_OPTS 限到 2g |
| 10 | OverLoad ... cannot consumes commands 告警 | Master 采到宿主 CPU 使用率 100% | 本机学习环境常见，不代表启动失败；UI 200 + 能建项目即视为可用 |
| 11 | UI 502 / 登录页打不开 | standalone 启动慢 | 等 1–2 分钟看 docker logs ds-standalone --tail 100，以 healthcheck 为准 |
| 12 | 重启后项目/数据源消失 | 用了默认内存 H2 | 确认 SPRING_PROFILES_ACTIVE=postgresql 生效，日志里数据源是 PostgreSQL |
| 13 | DS 里建 Doris 数据源报 Access denied | 误以为 Doris root 免密 | Doris root@% 非空口令，只有 FE 容器内 loopback 免密；填 &lt;FE_PWD&gt，见 doris/组件手册 |
| 14 | compose ps 看不到容器 | 改过 name: 但没重建标签 | 按 全局基线：旧 name 下 down → 改文件 → up -d，不加 -v |
| 15 | sql.init 相关表不存在（relation ... does not exist） | 库被清过或版本不匹配 | 复核 t_ds_version=3.4.3 与 64 张表；确需重建只能在你确认会话来源后另行处理，本手册不提供清库命令 |

**看日志的三个入口**：docker compose -f &lt;编排文件&gt; logs --tail 100；volumes/ds/logs/ 下的 standalone 日志；宿主 PG 侧 pg_stat_activity 看 DS 连接是否建立。
