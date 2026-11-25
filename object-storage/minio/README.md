# MinIO 安装手册

> **本文位置**：全局组件目录 /Users/wenhuadong/docker/object-storage/minio/，供本机所有项目共用；组件地图见 /Users/wenhuadong/docker/README.md。文中提到的 sql/、03-数据准备.md、data/out/ 属于项目仓库 ~/prj/asr-resume/prj/湖仓一体/，不随本目录迁移。

> **一句话结论**：MinIO 是整套链路的**数据起点**，一条 docker run 就能起来。它真正的难点不在启动，而在两件事：**S3 API 端口（9000）与 Console 端口（9001）别混用**，以及 **Doris 的 BE 容器必须能访问到它**——只在本机 curl 通不算数。

> **适用**：本机 macOS arm64，独立容器部署，不依赖任何 compose 文件。本文只涉及 MinIO 一个组件，装坏可单独重来，不影响已装的 Doris / DolphinScheduler。
>
> **核对时点**：2026-11，镜像 tag 与 Console 功能以 https://min.io/download 与 https://hub.docker.com/r/minio/minio 为准。

---

## 1. 前置

| 项 | 检查命令 | 判据 |
| --- | --- | --- |
| Docker 已启动 | docker version | 有 Server 段 |
| 共享网络已建 | docker network ls \| grep whd-net | 存在；没有就先看 安装手册 |
| 端口没被占 | lsof -nP -iTCP:9000 -iTCP:9001 -sTCP:LISTEN | 无输出 |
| 卷目录已建 | mkdir -p /Users/wenhuadong/docker/object-storage/minio/data | 目录存在，且已不在任何 git 仓库内 |

> **全局目录**：本组件的配置与数据都在 /Users/wenhuadong/docker/object-storage/minio/ 下，卷路径一律写绝对路径，命令可在任意目录执行。

---

## 2. 独立启动命令

```bash
mkdir -p /Users/wenhuadong/docker/object-storage/minio/data

docker run -d \
  --name minio \
  --network whd-net \
  --network-alias minio \
  --ip 172.30.0.3 \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER='<MINIO_AK>' \
  -e MINIO_ROOT_PASSWORD='<MINIO_SK>' \
  -v /Users/wenhuadong/docker/object-storage/minio/data:/data \
  minio/minio:<MINIO_TAG> \
  server /data --console-address ":9001"
```

**参数逐项解释**

| 参数 | 作用 | 为什么这么写 |
| --- | --- | --- |
| --name minio / --network-alias minio | 稳定 DNS 名 | 容器内一律用 http://minio:9000；别名避免重启后 IP 变化 |
| --ip 172.30.0.3 | 固定 IP | 全局固定 IP 基线（2026-11-14 起全组件强制）；重建必带，漏带会动态漂移 |
| --network whd-net | 接入共享网络 | Doris FE/BE、Flink、DS 都要访问它 |
| -p 9000:9000 | **S3 API** | Doris WITH S3、mc、造数上传全走这个口 |
| -p 9001:9001 | **Console** | 只有浏览器管理用，S3 客户端绝不能指向它 |
| MINIO_ROOT_USER / MINIO_ROOT_PASSWORD | 根凭据 | 口令至少 8 位；**首次启动后自行设定，不要用默认值**，也不要写进版本库 |
| -v .../minio-data:/data | 对象数据持久化 | 删容器不丢数据；路径已不在任何 git 仓库内 |
| server /data --console-address ":9001" | 启动参数 | 不写 --console-address 时 Console 会随机端口，-p 9001 就白映射了 |
| &lt;MINIO_TAG&gt; | 镜像版本 | 固定一个明确的 release tag，别用 latest（升级后行为会变） |

> 取一个明确 tag：在 Docker Hub 的 minio/minio Tags 页挑一个 RELEASE.YYYY-MM-DDTHH-MM-SSZ 形式的稳定版填进去。arm64 与 amd64 都有官方构建。

---

## 3. 端口与目录规划

| 端口 | 协议 | 谁用 | 地址 |
| --- | --- | --- | --- |
| 9000 | S3 API (HTTP) | Doris S3 Load（BE）、Flink/Paimon、mc、造数上传 | 容器内 http://minio:9000；本机 http://localhost:9000 |
| 9001 | Web Console | 你本人 | http://localhost:9001 |

| 路径 | 内容 |
| --- | --- |
| /Users/wenhuadong/docker/object-storage/minio/data/ | 容器内 /data，MinIO 全部对象数据 |
| s3://lakehouse/ods/user_profile/ | 画像数据文件 |
| s3://lakehouse/ods/user_event/ | 事件数据文件 |
| s3://lakehouse/paimon/ | Paimon warehouse（Flink 写、Doris 只读回查） |

> **为什么只建一个桶**：本方案是单机演示，一个 lakehouse 桶 + 前缀分区最简单；Doris 的 S3 Load 与 Paimon warehouse 用同一套 endpoint 和凭据，少一处配置就少一处错。生产环境才需要按用途拆桶与拆凭据。

---

## 4. 首次初始化：登录与建桶

### 4.1 浏览器方式

1. 打开 http://localhost:9001。
2. 用前面设的 &lt;MINIO_AK&gt; / &lt;MINIO_SK&gt; 登录。
3. 左侧 **Buckets** → 右上 **Create Bucket**。
4. Bucket Name 填 lakehouse，其余保持默认，**不要**开启 Versioning / Object Locking（演示场景用不上，开了会让 Paimon 文件的删除行为变复杂）。
5. 点 **Create Bucket**。
6. 进入该桶 → **Create new path**，依次建 ods/user_profile/、ods/user_event/、paimon/ 三个前缀（MinIO 里前缀只是对象名的一部分，建不建目录都不影响写入，但建了便于肉眼核对）。
7. 左侧 **Access Keys** → 另建一对只用于本项目的密钥；本方案直接用根凭据即可，**但务必记住这是本机学习环境**。

### 4.2 命令行方式

```bash
docker run --rm -it \
  --network whd-net \
  --entrypoint /bin/sh \
  minio/mc:<MC_TAG> -c '
    mc alias set lake http://minio:9000 "<MINIO_AK>" "<MINIO_SK>" &&
    mc mb --ignore-existing lake/lakehouse &&
    mc ls lake &&
    mc anonymous set none lake/lakehouse
  '
```

| 命令 | 作用 |
| --- | --- |
| mc alias set | 从**容器内**用 http://minio:9000 建别名，顺便验证跨容器 DNS |
| mc mb | 建桶；--ignore-existing 让重跑不报错 |
| mc ls | 列出桶，确认创建成功 |
| mc anonymous set none | 关闭匿名访问，避免数据裸奔 |

---

## 5. 连通性验证

### 5.1 本机

```bash
curl -fsS http://localhost:9000/minio/health/live -o /dev/null -w '%{http_code}\n'
# 期望：200
```

### 5.2 容器内（关键）

```bash
# 同网络临时容器，验证 DNS 与端口
docker run --rm --network whd-net busybox:1.36 \
  sh -c 'nslookup minio && nc -zv minio 9000'

# 从 MinIO 容器自己的网络视角探测健康接口
docker run --rm --network whd-net curlimages/curl:8.10.1 \
  -fsS http://minio:9000/minio/health/live -o /dev/null -w '%{http_code}\n'
```

### 5.3 BE 侧验证

S3 Load 由 BE 实际下载文件，所以这一步是整套链路能不能跑通的分水岭。

```bash
# 1) DNS 能否解析
docker exec <Doris-BE容器名> sh -c 'getent hosts minio || nslookup minio'

# 2) 端口能否连通（BE 镜像里可能没有 curl/wget，挑一个能用的）
docker exec <Doris-BE容器名> sh -c 'wget -qO- http://minio:9000/minio/health/live && echo OK'
# 或
docker exec <Doris-BE容器名> bash -c 'echo > /dev/tcp/minio/9000 && echo OK'
```

**判据**：能解析出 IP，且端口探测成功。若 DNS 通但连不上，多半是 BE 没接入 whd-net，回 /Users/wenhuadong/docker/scheduling/dolphinscheduler/组件手册补接。

> 如果 BE 容器既没有 wget 也没有 bash，用的临时容器方式替代即可——它和 BE 在同一个网络，结论等价（前提是 BE 已接入该网络）。

---

## 6. 把造数产物放进桶里

造数脚本产出在本地 data/out/（03-数据准备.md），用 mc 上传：

```bash
docker run --rm -it \
  --network whd-net \
  -v /Users/wenhuadong/prj/asr-resume/prj/湖仓一体/data/out:/upload:ro \
  --entrypoint /bin/sh \
  minio/mc:<MC_TAG> -c '
    mc alias set lake http://minio:9000 "<MINIO_AK>" "<MINIO_SK>" &&
    mc cp --recursive /upload/user_profile/ lake/lakehouse/ods/user_profile/ &&
    mc cp --recursive /upload/user_event/  lake/lakehouse/ods/user_event/ &&
    mc ls --recursive lake/lakehouse/ods/
  '
```

**落湖文件约定**（sql/02_load.sql 会按这个约定写 Load 路径）：

| 约定 | 值 | 原因 |
| --- | --- | --- |
| 格式 | CSV（默认）或 Parquet | 由造数脚本 fmt 参数决定 |
| 表头 | **默认不带** | Doris S3 Load 会把表头当脏数据；--with-header 只用于文档示例 |
| 命名 | part-00000.csv 之类 | DATA INFILE("s3://lakehouse/ods/user_profile/*") 通配符能一次读干净 |
| 列序 | 严格按 data/schema/game_fields.json | 字段口径唯一，Load 不指定列映射时靠列序对齐 |

---

## 7. 单独停止与重来

```bash
# 停止 / 启动（不影响其它容器）
docker stop minio
docker start minio

# 看日志
docker logs -f minio --tail 100

# 完全重来（保留数据）
docker rm -f minio
# 再执行第 2 节的 docker run

# 完全重来（连数据一起清空，谨慎）
docker rm -f minio
rm -rf /Users/wenhuadong/docker/object-storage/minio/data/*
mkdir -p /Users/wenhuadong/docker/object-storage/minio/data
# 再执行第 2 节的 docker run + 第 4 节建桶
```

> **重来前想清楚**：清空 /Users/wenhuadong/docker/object-storage/minio/data 会连 Paimon warehouse 一起删掉，Doris 里的 ODS 数据还在，但 sql/06_check.sql 的湖仓对账会失败，需要重跑写回作业。

---

## 8. 本组件专属踩坑

| 现象 | 原因 | 解决 / 预防 |
| --- | --- | --- |
| S3 Load 报 Connection refused / UnknownHost: minio | BE 容器没接入 whd-net，或 endpoint 写了 localhost | endpoint 改 http://minio:9000；按 /Users/wenhuadong/docker/scheduling/dolphinscheduler/组件手册把 BE 接入共享网络 |
| 本机 curl localhost:9000 通，导入还是失败 | 视角错了，下载方是 BE 不是本机 | 做 BE 侧验证 |
| 把 9001 写进 s3.endpoint | Console 口不是 S3 API | 改成 9000；9001 只给浏览器 |
| AccessDenied / SignatureDoesNotMatch | AK/SK 写错、含特殊字符未转义，或客户端与服务端时间差太大 | 核对凭据；检查本机时间同步；密码里的 $、! 在 shell 里用单引号包住 |
| The request signature we calculated does not match 且密钥没错 | 走成了 virtual-host 风格（lakehouse.minio:9000） | **S3 Load** 里加 "use_path_style" = "true"；Paimon Catalog 里则是 s3.path.style.access，两者属性名不同别混用 |
| mc 能连但 Doris 报 bucket does not exist | 桶名写错、或 Load 路径前缀写了 lakehouse/ 之外的名字 | mc ls lake 核对桶名；路径统一 s3://lakehouse/ods/... |
| MINIO_ROOT_PASSWORD 设得太短导致容器起不来 | MinIO 强制最少 8 位 | 换一个 ≥8 位的口令 |
| Console 里找不到某菜单 | 较新的社区版精简了部分 Console 功能 | 用 mc 命令行做等价操作；或固定一个功能完整的 release tag |
| 挂载卷后容器反复重启 | 本机目录权限 / 磁盘满 | docker logs minio 看具体报错；df -h 看剩余空间 |
| 删了容器数据还在，以为清空了 | 数据卷还在 | 只有显式 rm -rf /Users/wenhuadong/docker/object-storage/minio/data/* 才会清数据 |
| 表头被当成一行脏数据 | 落湖 CSV 带了表头 | 造数脚本默认不带表头；sql/02_load.sql 里 max_filter_ratio 也不是用来兜这个的 |

---

## 9. 本篇小结

1. 一条 docker run 起 MinIO，9000 是 S3 API、9001 是 Console，**别混**。
2. 建一个 lakehouse 桶，规划 ods/ 与 paimon/ 两类前缀，跟 Doris、Flink 共用一套 endpoint 与凭据。
3. **从 BE 容器验证可达**是必做项，这是单组件独立部署最容易翻车的地方。
4. Doris **S3 Load** 必须开 use_path_style=true（Paimon Catalog 才用 s3.path.style.access，两个属性名别混）；落湖文件默认不带表头、列序严格按字段口径文件。
5. 单独 docker stop/rm 即可重来，不会影响其他组件。

---

下一篇：/Users/wenhuadong/docker/streaming/flink/README.md
