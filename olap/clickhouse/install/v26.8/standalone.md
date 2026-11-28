> 官方中文教程：https://clickhouse.com/docs/zh

> **本文范围**：把一个独立的 ClickHouse 单节点装起来。用官方镜像跑一个容器。挂载配置、数据、日志与 jar 目录。装完验到 HTTP 健康、命令行能查询。不建业务表，不接外部数据源。

# ClickHouse 单机安装

> **一句话结论**：一个 clickhouse/clickhouse-server:26.8.40.7 容器。宿主映射 8123 与 19000。固定 IP 172.30.0.20，加入 whd-net。配置、数据、日志与 jar 目录全部从宿主挂载。验收三条：ping 返回 Ok、SELECT 1 返回 1、容器日志无异常。

> **本文解决什么**：本机需要一套能独立运行的 ClickHouse，用于学习日志场景的 SQL 调试。本文给出单容器安装法。
>
> **适用谁**：已装 Docker Desktop、懂基本 docker 命令、想在本机跑 ClickHouse 的用户。
>
> **读完能做什么**：一条命令起单节点、验证安装、停止与重来、处理常见启动故障。

> **核对时点**：2026-11-27。macOS arm64 / Docker Desktop。本机已完成安装：镜像 26.8.40.7 拉取成功，摘要 sha256:6d462904f276。容器 clickhouse 运行中，HTTP 与命令行均验证通过。宿主 8123 与 19000 由本容器占用。宿主 9000 已被 MinIO 占用。whd-net 分配使用 .20。

---

## 一、适用范围

| 项 | 取值 |
| --- | --- |
| 版本 | ClickHouse 26.8.40.7，LTS 通道 |
| 形态 | 单节点单容器 |
| 操作系统 | macOS arm64 / Docker Desktop |
| 内存下限 | 宿主可用 4G，容器不设硬上限 |
| 网络 | whd-net，固定 IP 172.30.0.20 |
| 不覆盖 | 分片副本集群、Keeper 部署 |

> 本机内存还要分给其他组件。安装后按 docker stats 观察占用，再决定是否加内存上限。

## 二、安装前复核

```bash
lsof -nP -iTCP:8123 -sTCP:LISTEN || echo '8123 空闲'
lsof -nP -iTCP:19000 -sTCP:LISTEN || echo '19000 空闲'
lsof -nP -iTCP:9000 -sTCP:LISTEN

docker ps -a --filter name=clickhouse \
  --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'

docker network inspect whd-net \
  --format '{{range .Containers}}{{.Name}} | {{.IPv4Address}}{{println}}{{end}}'

docker manifest inspect clickhouse/clickhouse-server:26.8.40.7 \
  >/dev/null 2>&1 && echo '标签可达' || echo '标签不可达，先核对版本号'
```

| 检查项 | 期望 | 不满足时 |
| --- | --- | --- |
| 8123 | 空闲 | 停掉占用进程后复查 |
| 19000 | 空闲 | 换未占端口，并同步映射与连接地址 |
| 9000 | 被 MinIO 占用 | 不映射宿主 9000 |
| 旧容器 | 无同名 clickhouse | 执行 docker rm -f clickhouse |
| whd-net | 存在，172.30.0.20 未被占用 | 换 .20 之后的未用地址 |
| 镜像标签 | 输出标签可达 | 按 LTS 通道重新核对版本号 |

> **注意**：26.8.40.7 已实测可拉取，摘要 sha256:6d462904f276。若 manifest 检查输出标签不可达，先核对仓库标签与 arm64 架构。

## 三、安装步骤

### 3.1 建运行目录

```bash
mkdir -p /Users/wenhuadong/docker/olap/clickhouse/conf/config.d
mkdir -p /Users/wenhuadong/docker/olap/clickhouse/data-standalone
mkdir -p /Users/wenhuadong/docker/olap/clickhouse/logs-standalone
mkdir -p /Users/wenhuadong/docker/olap/clickhouse/jars
chmod 777 /Users/wenhuadong/docker/olap/clickhouse/data-standalone
chmod 777 /Users/wenhuadong/docker/olap/clickhouse/logs-standalone
```

预期输出为空。四个目录创建完成，两个运行目录授予容器进程写权限。

> 容器内进程以非 root 用户运行。宿主目录默认权限会挡住写入。本机为本地演示目录授予 777，生产环境改用固定用户与属主。

> jars 目录存放外部对接要用的驱动 jar，例如 JDBC 驱动。容器以只读方式挂载该目录。jar 放宿主，容器重建不丢。服务端本体是单个二进制，不加载 jar，该目录供后续外部对接与桥接进程使用。

### 3.2 拉取镜像

```bash
docker pull clickhouse/clickhouse-server:26.8.40.7
```

预期输出分层下载进度，最后一行显示镜像摘要。

### 3.3 写覆盖配置

把单文件配置写到宿主 conf 目录。该文件覆盖镜像默认配置，不改动镜像内部文件。

```bash
cat > /Users/wenhuadong/docker/olap/clickhouse/conf/config.d/whd.xml <<'EOF'
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
    <logger>
        <level>information</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>100M</size>
        <count>3</count>
    </logger>
    <max_connections>200</max_connections>
    <keep_alive_timeout>3</keep_alive_timeout>
</clickhouse>
EOF
chmod 644 /Users/wenhuadong/docker/olap/clickhouse/conf/config.d/whd.xml
```

预期输出为空。配置文件落盘，权限为 644。

| 参数 | 取值 | 作用 |
| --- | --- | --- |
| listen_host | 0.0.0.0 | 允许容器外访问 HTTP 与原生端口 |
| logger.level | information | 记录查询与启动信息 |
| logger.log | clickhouse-server.log | 主日志路径 |
| logger.errorlog | clickhouse-server.err.log | 错误日志路径 |
| logger.size | 100M | 单日志文件轮转阈值 |
| logger.count | 3 | 保留的历史日志文件数 |
| max_connections | 200 | 最大并发连接数 |
| keep_alive_timeout | 3 | 空闲连接保持秒数 |

> 挂载单个文件，不挂载整个 config.d 目录。整目录挂载会遮住镜像自带的 docker_related_config.xml。

### 3.4 写口令文件

先写模板。模板提交仓库，只含占位符。

```bash
cat > /Users/wenhuadong/docker/olap/clickhouse/.env.example <<'EOF'
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=<CH_PWD>
EOF
chmod 644 /Users/wenhuadong/docker/olap/clickhouse/.env.example
```

再生成本地口令文件，并编辑占位符。

```bash
cp /Users/wenhuadong/docker/olap/clickhouse/.env.example \
  /Users/wenhuadong/docker/olap/clickhouse/.env
chmod 600 /Users/wenhuadong/docker/olap/clickhouse/.env
vi /Users/wenhuadong/docker/olap/clickhouse/.env
```

CLICKHOUSE_USER 保持 default。把 CLICKHOUSE_PASSWORD 的占位符替换为本地口令，保存退出。.env 文件不提交仓库。

| 变量 | 取值 | 作用 |
| --- | --- | --- |
| CLICKHOUSE_USER | default | 连接账号 |
| CLICKHOUSE_PASSWORD | 本地口令 | 该账号的登录口令 |

> 镜像入口脚本读取这两个变量。CLICKHOUSE_USER 指定账号，CLICKHOUSE_PASSWORD 给该账号设置口令。留空占位符会让服务以空口令运行。改完变量要重建容器才生效。

### 3.5 启动容器

```bash
docker run -d \
  --name clickhouse \
  --hostname clickhouse \
  --network whd-net \
  --network-alias clickhouse \
  --ip 172.30.0.20 \
  --ulimit nofile=262144:262144 \
  -p 8123:8123 \
  -p 19000:9000 \
  -v /Users/wenhuadong/docker/olap/clickhouse/conf/config.d/whd.xml:/etc/clickhouse-server/config.d/whd.xml:ro \
  -v /Users/wenhuadong/docker/olap/clickhouse/data-standalone:/var/lib/clickhouse \
  -v /Users/wenhuadong/docker/olap/clickhouse/logs-standalone:/var/log/clickhouse-server \
  -v /Users/wenhuadong/docker/olap/clickhouse/jars:/opt/clickhouse/custom-jars:ro \
  --env-file /Users/wenhuadong/docker/olap/clickhouse/.env \
  clickhouse/clickhouse-server:26.8.40.7
```

预期输出一串容器 ID。docker ps 显示容器 Up。

| 参数 | 作用 |
| --- | --- |
| 容器名与别名 clickhouse | 同网络组件按此名访问服务 |
| --ip 172.30.0.20 | 固定 IP，重建不漂移 |
| --ulimit nofile | 提高文件描述符上限，避免表多时报错 |
| -p 8123:8123 | 暴露 HTTP 接口与内置 Web UI |
| -p 19000:9000 | 宿主 19000 映射原生协议端口 |
| whd.xml 单文件挂载 | 配置从宿主读取，容器重建不丢 |
| data-standalone 挂载 | 数据片段与元数据落到宿主目录 |
| logs-standalone 挂载 | 服务日志落到宿主目录 |
| jars 挂载 | 驱动 jar 放宿主，容器内只读可见 |
| --env-file | 从本地文件注入账号与口令 |

> 宿主 9000 已由 MinIO 占用，因此原生协议映射为 19000。容器内仍监听 9000，同网络容器写 clickhouse:9000。

> jar 一律从宿主挂载，不用 docker cp。容器删除重建后驱动仍在，不需要重新拷贝。

## 四、启动与验证

### 4.1 等待就绪

```bash
for i in $(seq 1 30); do
  curl -fsS http://localhost:8123/ping -o /dev/null 2>/dev/null && {
    echo 'HTTP 就绪'; break
  }
  echo "第 ${i} 次：未就绪，等 2s"; sleep 2
done
```

预期输出最后一行显示 HTTP 就绪。首次启动要初始化系统表，耗时数秒。

### 4.2 冒烟验证

```bash
set -a
. /Users/wenhuadong/docker/olap/clickhouse/.env
set +a

docker exec -i -e CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" clickhouse \
  clickhouse-client --user "$CLICKHOUSE_USER" --query "SELECT 1 AS ok"
```

预期输出 1。

### 4.3 停止与重来

```bash
docker stop clickhouse
docker start clickhouse

docker logs -f clickhouse --tail 100

docker rm -f clickhouse
```

| 动作 | 数据安全 |
| --- | --- |
| stop / start | 容器可写层与三个挂载目录全保留 |
| docker rm -f | 配置、数据、日志均为绑定挂载，保留 |
| docker rm -v | 不使用，本机未建命名卷 |
| 删除 data-standalone | 只用于明确重置数据，执行前先备份 |

> 重来时重跑 3.5 的 docker run。口令文件与配置仍在宿主，不需要重写。

## 五、验收对照

| 判据 | 检查方式 | 通过标准 |
| --- | --- | --- |
| 容器状态 | docker ps --filter name=clickhouse | 状态 Up，端口含 8123 与 19000 |
| HTTP 健康 | curl -fsS http://localhost:8123/ping | 输出 Ok. |
| 命令行查询 | 4.2 的 docker exec 命令 | 输出 1，无认证异常 |
| 配置生效 | docker exec clickhouse grep listen_host /etc/clickhouse-server/config.d/whd.xml | 输出 0.0.0.0 |
| 日志无异常 | docker logs clickhouse --tail 100 | 无 error 或 exception 字样 |
| 数据目录可写 | docker exec clickhouse clickhouse-client --query "SELECT count() FROM system.parts" | 返回数字，无权限异常 |
| 版本 | docker exec clickhouse clickhouse-client --version | 输出 26.8.40.7 |
| jar 目录挂载 | docker inspect clickhouse --format 取 Mounts 列表 | 含 /opt/clickhouse/custom-jars，模式为 ro |

> 最后一条同时验证挂载目录可写。容器进程以非 root 用户运行，目录权限不足会在该步报异常。

## 六、故障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| docker pull 报标签不存在 | 26.8.40.7 标签远端未核验 | 用 docker manifest inspect 查 LTS 通道现有标签 |
| 容器起后立刻退出 | 配置 XML 语法错或口令文件缺失 | docker logs clickhouse 看首行异常 |
| 容器日志报权限拒绝 | 数据与日志目录属主不对 | 复核 3.1 的目录权限 |
| curl ping 无响应 | 容器未起或 8123 未映射 | docker ps 与 lsof 复查 |
| 命令行报 Authentication failed | .env 占位符未替换 | 编辑 .env，写入本地口令后重建容器 |
| 原生协议连不上 9000 | 宿主 9000 被 MinIO 占用 | 宿主改连 19000，容器内连 clickhouse:9000 |
| 固定 IP 冲突 | .20 已被其他容器占用 | docker network inspect 核对后换地址 |
| 查询报 too many open files | nofile 上限未生效 | 复核 --ulimit 参数并重建容器 |
| Web UI 打不开 | 访问了根路径 | 用 http://localhost:8123/play |
| 配置改动不生效 | 挂载的是目录而非单文件 | 按 3.3 改为单文件挂载并重建容器 |
| jar 目录内写入失败 | 该目录按只读挂载 | 在宿主 jars 目录增删文件，容器内只读 |
