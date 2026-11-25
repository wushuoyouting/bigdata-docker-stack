> **本文范围**：在已装好的 SeaTunnel 3.1.0 容器上开启并使用 Web UI。本文不装独立组件，只讲内嵌 Web UI 的开启、访问与功能边界。

# SeaTunnel Web UI 开启教程

> **一句话结论**：3.1.0 的 Web UI 内嵌在引擎里，不用单独装 seatunnel-web。HTTP 默认已开启，直接访问 http://localhost:18081/#/overview。

> **本文解决什么**：想用浏览器看 SeaTunnel 集群与作业，但不确定要不要再装一个 seatunnel-web。
>
> **适用谁**：已完成安装教程、容器 seatunnel 处于 Up 的用户。
>
> **读完能做什么**：打开 Web UI 看集群与作业，理解它与 REST API 的关系，需要时改端口。

---

## 一、先厘清一个误区

SeaTunnel 3.x 把 Web UI 收进了引擎。它与 REST API 共用同一套 HTTP 能力，不是独立服务。前端资源随引擎包内置。开启 HTTP 即可访问，无需额外部署。

独立的 apache/seatunnel-web 项目是旧版 2.3.x 的配套。它只支持 SeaTunnel 2.3.8 引擎，官方标记为实验项目，且没有官方 Docker 镜像。它与 3.1.0 不匹配，本机不用它。

| 对比项 | 3.1.0 内嵌 Web UI | 独立 seatunnel-web 1.0.2 |
| --- | --- | --- |
| 是否独立部署 | 否，随引擎 | 是，独立服务 |
| 端口 | 18081（宿主） | 8801 |
| 匹配引擎 | 3.1.0 | 2.3.8 |
| 官方 Docker 镜像 | 有，apache/seatunnel | 无 |
| 功能 | 监控为主 | 数据源管理加拖拽设计器 |

> 本机引擎是 3.1.0，所以正确的 Web 界面就是内嵌这套。独立的 seatunnel-web 是为 2.3.x 服务的，强行配合 3.1.0 会版本不兼容。

## 二、配置说明

Web UI 由 seatunnel.yaml 的 seatunnel.engine.http 节控制。

```yaml
seatunnel:
  engine:
    http:
      enable-http: true
      port: 8080
```

| 配置项 | 默认值 | 作用 |
| --- | --- | --- |
| enable-http | true | 是否开启 HTTP 服务 |
| port | 8080 | 容器内 HTTP 监听端口 |

镜像默认配置已开启 HTTP，容器内端口 8080。安装教程里宿主已映射 18081，所以无需改动任何配置。Web UI 与 REST API 共用这一个端口。

## 三、访问与验收

浏览器打开：

```text
http://localhost:18081/#/overview
```

命令行先确认 HTTP 服务可用：

```bash
curl -fsS http://localhost:18081/system-monitoring-information; echo
```

预期输出：返回 HTTP 200 与 JSON，含集群节点信息。浏览器随后能看到 Overview 页，显示版本、槽位数、工作节点数、任务计数。

> 路由放在 URL 的 fragment 里，以 #/ 开头。Safari 会重新请求 hash 路由，若打开空白，改用 Chrome 或 Firefox 访问。

## 四、Web UI 能看什么

| 页面 | 内容 |
| --- | --- |
| Overview | 项目版本、集群槽位、工作节点数、任务计数 |
| Jobs | 运行中与已完成的作业，支持分页 |
| Job Detail | 作业配置、DAG、源与目标指标、日志、实时观测 |
| Workers | 各工作节点的系统监控信息 |
| Master | 主节点的系统监控信息 |

> 3.1.0 内嵌 Web UI 只做监控，不含作业设计器。作业仍用配置文件或 REST API 提交。看结果靠 Jobs 与 Job Detail，提作业靠基本使用里的命令。

## 五、需要改宿主端口时

默认宿主端口 18081。若 18081 被占用，改 docker run 的 -p 参数即可。容器内 HTTP 端口 8080 不变，seatunnel.yaml 不用动。

```bash
docker rm -f seatunnel

docker run -d \
  --name seatunnel \
  --network whd-net \
  --network-alias seatunnel \
  --ip 172.30.0.19 \
  -p 18082:8080 \
  -v /Users/wenhuadong/docker/integration/seatunnel/jobs:/jobs \
  apache/seatunnel:3.1.0 \
  /opt/seatunnel/bin/seatunnel-cluster.sh
```

| 参数 | 作用 |
| --- | --- |
| -p 18082:8080 | 宿主 18082 映射容器 8080 |

> 改的是宿主映射端口，容器内 HTTP 端口 8080 不变，所以不用改 seatunnel.yaml。只有要改容器内端口时，才需要 docker cp 取配置改 port，改完挂载回去。

## 六、故障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 页面打不开 | 容器未起或端口未通 | docker ps 与 curl 复查 |
| 打开空白页 | Safari 重请求 hash 路由 | 换 Chrome 或 Firefox |
| 看不到作业 | 作业未提交或已结束 | 用 REST API 提交后刷新 Jobs |
| 改端口后起不来 | 手写配置有误 | 用 docker cp 取默认文件再改 |
| 想拖拽设计作业 | 内嵌 UI 不支持 | 作业用配置或 REST API 提交 |

## 七、小结

1. 3.1.0 的 Web UI 内嵌在引擎里，与 REST API 共用容器内 8080。
2. 默认已开启，宿主映射 18081 后直接访问即可，无需额外安装。
3. 独立的 seatunnel-web 只服务 2.3.x，与 3.1.0 不匹配，本机不用。
4. 内嵌 Web UI 只做监控，作业仍需配置或 REST API 提交。
5. 改端口先 docker cp 取默认配置，改完挂载，不手写整份文件。
