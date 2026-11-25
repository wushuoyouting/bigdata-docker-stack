# Superset 安装手册

> **本文位置**：全局组件目录 /Users/wenhuadong/docker/bi/superset/，供本机所有项目共用；组件地图见 /Users/wenhuadong/docker/README.md。文中提到的 sql/、04-实操手册.md、06-Superset看板配置.md 属于项目仓库 ~/prj/asr-resume/prj/湖仓一体/，不随本目录迁移。

> **一句话结论**：Superset 是**最后一个装、最不必常驻**的组件，一条 docker run 起来，初始化管理员后，用 **MySQL 协议连 Doris FE** 就能查 ADS 表。它不需要额外服务端组件，但有三个必做动作：**设 SUPERSET_SECRET_KEY、初始化管理员、确认容器内装了 MySQL 驱动**。

> **本篇只负责把 Superset 装起来并连上 Doris**；四个图表的数据集 SQL 与维度度量配置见 06-Superset看板配置.md。

> **核对时点**：2026-11。镜像 tag 与多平台构建说明见 https://superset.apache.org/docs/installation/docker-builds ，本机 arm64 请务必先看的镜像选择。

---

## 1. 前置

| 项 | 检查命令 | 判据 |
| --- | --- | --- |
| 共享网络 | docker network ls \| grep whd-net | 存在 |
| Doris FE 可用 | 本机 mysql -h127.0.0.1 -P&lt;FE_QUERY_PORT&gt; -uroot -e 'SELECT 1' | 返回 1 |
| ADS 表已产出 | sql/04_ads.sql 已执行 | 04-实操手册.md 的阶段产物；**没跑也能先装 Superset**，只是连上后暂时没表可查 |
| 端口未占用 | lsof -nP -iTCP:8088 -sTCP:LISTEN | 无输出，8088 空闲 |

> **全局目录**：本组件的配置与数据都在 /Users/wenhuadong/docker/bi/superset/ 下，卷路径一律写绝对路径，命令可在任意目录执行。

---

## 2. 镜像选择

Superset 官方发布镜像历史上以 linux/amd64 为主，新版本开始提供多平台构建，并对部分 tag 使用 -arm 后缀。两条备选：

```bash
# 备选 A：优先试原生多平台 / arm 后缀 tag
docker pull apache/superset:<SUPERSET_TAG>-arm

# 备选 B：没有 arm 版本时用 amd64 模拟（能跑，但启动明显更慢）
export DOCKER_DEFAULT_PLATFORM=linux/amd64
docker pull --platform linux/amd64 apache/superset:<SUPERSET_TAG>
```

**怎么判断该用哪条**：

```bash
docker image inspect apache/superset:<SUPERSET_TAG> \
  --format '{{.Os}}/{{.Architecture}}'
# 输出 linux/arm64 → 用原生；linux/amd64 → 走模拟
```

> 模拟模式下 Superset 首次初始化要等好几分钟，日志里长时间没有输出**不等于**卡死，先看 docker logs -f superset。性能差异写在这里，别在演示时才发现。

---

## 3. 独立启动命令

```bash
mkdir -p /Users/wenhuadong/docker/bi/superset/home

docker run -d \
  --name superset \
  --network whd-net \
  --network-alias superset \
  --ip 172.30.0.17 \
  -p 8088:8088 \
  -e SUPERSET_SECRET_KEY='<SUPERSET_SECRET_KEY>' \
  -e TALISMAN_ENABLED='False' \
  -v /Users/wenhuadong/docker/bi/superset/home:/app/superset_home \
  apache/superset:<SUPERSET_TAG>
```

**参数逐项解释**

| 参数 | 作用 | 为什么这么写 |
| --- | --- | --- |
| --network whd-net | 接入共享网络 | 容器内要用别名 doris-fe 连 FE |
| --ip 172.30.0.17 | 固定 IP | 全局固定 IP 基线（2026-11-14 起全组件强制）；重建必带，漏带会动态漂移 |
| -p 8088:8088 | Web UI | 宿主机端口可改，容器内部保持 8088 |
| SUPERSET_SECRET_KEY | 会话/加密签名密钥 | **不设会每次启动生成随机值**，重启后登录态与加密凭据失效；自己生成一个长随机串 |
| TALISMAN_ENABLED='False' | 关闭强制 HTTPS 头 | 本机是 HTTP 访问，不关会被重定向到 HTTPS 导致页面打不开（版本相关，见踩坑表） |
| -v .../superset-home:/app/superset_home | 元数据库与配置持久化 | 默认 SQLite 落在这里；删容器不丢看板与数据源 |
| &lt;SUPERSET_TAG&gt; | 镜像版本 | 固定一个明确版本，别用 latest |

生成密钥示例：

```bash
openssl rand -base64 42
```

> **元数据库说明**：单机演示用容器内默认 SQLite 足够，**不额外起 PostgreSQL**，这样「每个组件单独部署」的边界不被打破。若以后要多人使用，再单独部署 PG 并配置 SQLALCHEMY_DATABASE_URI。

---

## 4. 端口与目录规划

| 端口 | 用途 | 地址 |
| --- | --- | --- |
| 8088 | Web UI | 本机 http://localhost:8088 |

| 目录 | 内容 |
| --- | --- |
| /Users/wenhuadong/docker/bi/superset/home/ | SQLite 元数据库、配置、上传文件；不在任何 git 仓库内 |

---

## 5. 首次初始化

**顺序固定，不要跳步**：

```bash
# 1) 建/升级元数据库表结构
docker exec -it superset superset db upgrade

# 2) 建管理员（口令自行设定，别用默认值）
docker exec -it superset superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname Admin \
  --email admin@example.local \
  --password '<SUPERSET_ADMIN_PWD>'

# 3) 初始化角色与权限
docker exec -it superset superset init

# 4) 看日志确认服务已监听
docker logs -f superset --tail 100
```

**判据**：

```bash
curl -fsS http://localhost:8088/healthcheck
# 期望返回 OK
```

浏览器打开 http://localhost:8088，用第 2 步的账号登录，能看到首页即通过。

> superset fab create-admin 在部分新版本里被 flask fab create-admin 取代，报 No such command 时换成 docker exec -it superset flask fab create-admin ...，参数不变。

---

## 6. 数据源配置

### 6.1 MySQL 驱动

Superset 走 MySQL 协议连 Doris，但**Python 驱动不是必然自带**：

```bash
docker exec -it superset python -c 'import pymysql; print(pymysql.__version__)'
```

若报 ModuleNotFoundError，在容器内装一次（重启容器会丢，见踩坑表）：

```bash
docker exec -it superset pip install PyMySQL
docker restart superset
```

> 这不算「多装一个组件」，只是容器内的一个 Python 包；不需要额外起服务。

### 6.2 UI 操作路径

1. 登录 http://localhost:8088。
2. 右上角 **Settings（齿轮）** → **Database Connections**。
3. 右上 **+ DATABASE**（新版是 **+ Database**）。
4. **Select a database**：下拉选 **MySQL**（不要选 Doris，除非你装了 sqlalchemy-doris 驱动）。
5. **SQLALCHEMY URI** 填：

   ```text
   mysql+pymysql://<FE_USER>:<FE_PWD>@doris-fe:<FE_QUERY_PORT>/game_db?charset=utf8mb4
   ```

 | 片段 | 说明 |
 | --- | --- |
 | mysql+pymysql:// | 用 PyMySQL 驱动走 MySQL 协议 |
 | &lt;FE_USER&gt;:&lt;FE_PWD&gt; | Doris 账号；root 空密码写 root@ |
 | doris-fe | **容器内别名**，不是 localhost |
 | &lt;FE_QUERY_PORT&gt; | FE 的**容器内部** MySQL 协议端口（通常 9030），不是宿主机映射端口 |
 | game_db | sql/00_init.sql 建的库 |
6. **Display Name** 填 Doris · 湖仓演示。
7. 点 **TEST CONNECTION**，看到 Connection looks good! 再点 **CONNECT / SAVE**。
8. 顶部 **SQL Lab** → **SQL Editor**，选刚建的数据源，执行：

   ```sql
   SHOW TABLES;
   ```

 能看到 ADS_MV_* 四张表即说明整条链路打通（前提是 sql/04_ads.sql 已执行）。

> **端口判据**：容器之间访问用的是「容器内部端口」。如果你在 /Users/wenhuadong/docker/scheduling/dolphinscheduler/README.md 里把 FE 的 9030 映射成了宿主机 9031，这里仍写容器内部的 9030，而不是 9031。

---

## 7. 连通性验证（分层做）

| 层 | 命令 / 操作 | 判据 |
| --- | --- | --- |
| 服务自身 | curl -fsS http://localhost:8088/healthcheck | OK |
| 容器解析 FE | docker exec superset sh -c 'getent hosts doris-fe' | 返回 IP |
| 容器到 FE 端口 | docker run --rm --network whd-net busybox:1.36 sh -c 'nc -zv doris-fe 9030' | open |
| 数据源 | Superset UI TEST CONNECTION | Connection looks good! |
| 能查到表 | SQL Lab SHOW TABLES; | 返回 ADS_MV_* |

---

## 8. 单独停止与重来

```bash
# 停 / 起（看板与数据源都保留）
docker stop superset
docker start superset

# 看日志
docker logs -f superset --tail 100

# 完全重来（保留元数据）
docker rm -f superset
# 再执行第 3 节 docker run，第 5 节只需跑 db upgrade + init（管理员已存在会跳过）

# 完全重来（连元数据库清空，谨慎）
docker rm -f superset
rm -rf /Users/wenhuadong/docker/bi/superset/home/*
# 再执行第 3、5、6 节全部步骤
```

> 清空元数据会丢掉已配好的数据源与四个图表；06 的配置需要重做一遍。

---

## 9. 本组件专属踩坑

| 现象 | 原因 | 解决 / 预防 |
| --- | --- | --- |
| exec format error / 容器立刻退出 | arm64 上拉了 amd64 专属镜像 | 选 -arm tag 或 DOCKER_DEFAULT_PLATFORM=linux/amd64 |
| 启动后浏览器自动跳 HTTPS、页面打不开 | Talisman 强制安全头 | 设 TALISMAN_ENABLED='False'（版本相关，有些版本用 SUPERSET_CONFIG 覆盖） |
| 每次重启都要重新登录、数据源凭据失效 | 没设 SUPERSET_SECRET_KEY，随机密钥每次变 | 固定一个长随机串并持久化到启动命令 |
| TEST CONNECTION 报 Can't connect to MySQL server on 'doris-fe' | 别名没生效 / FE 没接入共享网络 / 端口写错 | getent hosts doris-fe；回 /Users/wenhuadong/docker/scheduling/dolphinscheduler/组件手册补接；端口用**容器内部** 9030 |
| 把 &lt;FE_QUERY_PORT&gt; 写成宿主机映射端口 | 容器内访问不走宿主机映射 | 用 docker inspect 查容器内部端口 |
| No module named pymysql | 镜像未带 PyMySQL | 容器内 pip install PyMySQL 后重启；或改用镜像自带的 mysqlclient 对应 mysql:// URI |
| 数据源能存、TEST CONNECTION 能过，但**建数据集 500 Fatal error：No module named 'MySQLdb'** | Superset 的 db_engine_specs/mysql.py 在类型探测 get_datatype 里**硬 import MySQLdb**，与所用驱动（pymysql）无关；本机 slim 镜像里 mysqlclient 因无 apt 网络 + 缺编译依赖（default-libmysqlclient-dev/gcc）装不上，不能直接 pip install mysqlclient | 在挂载卷用户站点放一个极简 MySQLdb.py shim，只暴露 constants.FIELD_TYPE（用 pymysql.constants.FIELD_TYPE 填充），路径 /app/superset_home/.local/lib/python3.10/site-packages/MySQLdb.py，随卷持久化；stop/start 不丢，但 docker rm 容器会丢（卷在则保留）。shim 内容：<br>import sys, types; import pymysql.constants as _pcc;<br>constants = types.ModuleType('MySQLdb.constants');<br>class FIELD_TYPE: pass;<br>for k in dir(_pcc.FIELD_TYPE):<br> if not k.startswith('_'): setattr(FIELD_TYPE, k, getattr(_pcc.FIELD_TYPE, k));<br>constants.FIELD_TYPE = FIELD_TYPE; sys.modules['MySQLdb.constants'] = constants |
| pip install 后重启容器驱动又没了 | 改动只在容器可写层，docker rm 会丢 | 用 stop/start 而不是 rm 重来；或做成自定义镜像固化 |
| 密码含 @ / : / # 导致 URI 解析错 | URL 里没转义 | 对特殊字符做 URL 编码（%40、%3A），或改用不含特殊字符的演示账号 |
| root 空密码的 URI 怎么写都不对 | 多了个空 : | 写 mysql+pymysql://root@doris-fe:9030/game_db?... |
| superset fab create-admin 报 No such command | 新版本命令入口变了 | 换 flask fab create-admin，参数不变 |
| 初始化很久没反应、CPU 高 | amd64 模拟 + 首次 db upgrade | 等几分钟看日志，别急着 docker rm |
| 能连上但 SHOW TABLES 是空的 | sql/ 脚本还没跑或库名不对 | 先跑 04-实操手册.md；确认 URI 里的库是 game_db |
| 挂载卷后权限报错 | 本机目录属主与容器内用户不一致 | docker logs superset 看具体路径；必要时 chmod -R 777 /Users/wenhuadong/docker/bi/superset/home（仅本机学习环境） |
| 16G 机器上 Superset 一起，Doris BE 被杀 | 内存吃满 | 按 安装手册分时启动，看板配完就 docker stop superset |

---

## 10. 本篇小结

1. Superset 一条 docker run 起来，三件事必做：固定 SUPERSET_SECRET_KEY、db upgrade + create-admin + init、确认容器内有 MySQL 驱动。
2. 数据源 URI 用 mysql+pymysql://...@doris-fe:&lt;容器内部端口&gt;/game_db，**别名 + 容器内部端口**是容器内访问的正确写法。
3. arm64 上先查镜像架构，原生 -arm 优先，否则用 amd64 模拟并接受启动变慢。
4. 默认 SQLite 元数据库挂在 /Users/wenhuadong/docker/bi/superset/home/，不额外引入 PG，保持「单组件独立部署」边界。
5. 它是最吃内存、最不必常驻的一个，看板配完停掉，别挤掉 Doris BE。

---

回到全局组件地图：/Users/wenhuadong/docker/README.md；继续实操：04-实操手册.md
