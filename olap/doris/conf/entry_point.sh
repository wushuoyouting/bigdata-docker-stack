#!/bin/bash
# BE 启动脚本（沿用旧容器的修复版，见 02-安装Doris手册.md 第 5.1 节）
#
# 原版问题：健康检查通过 mysql 客户端连 FE，但 FE 默认禁止远程 root 登录，
# 导致 60 秒超时后 exit 1 杀掉容器。实际上 BE 进程本身是正常的。
# 修复：健康检查失败时只打警告，不退出。
#
# 【重要约束】validate_environment 用正则要求 FE_SERVERS 第二段是点分十进制 IP，
# 不能写容器名；parse_config 会从 BE_ADDR 推导 PRIORITY_NETWORKS = 前三段 + .0/24，
# 所以 whd-net 子网与两份 conf 的 priority_networks 都必须是 172.30.0.0/24。

set -eo pipefail
shopt -s nullglob

readonly DORIS_HOME="/opt/apache-doris"
readonly MAX_RETRY_TIMES=60
readonly RETRY_INTERVAL=1
readonly MYSQL_PORT=9030

log_message() {
    local level="$1"; shift
    local message="$*"
    if [ "$#" -eq 0 ]; then message="$(cat)"; fi
    printf '%s [%s] [Entrypoint]: %s\n' "$(date -Iseconds)" "${level}" "${message}"
}
log_info()  { log_message "INFO" "$@"; }
log_warn()  { log_message "WARN" "$@" >&2; }
log_error() { log_message "ERROR" "$@" >&2; }

is_sourced() {
    [ "${#FUNCNAME[@]}" -ge 2 ] &&
    [ "${FUNCNAME[0]}" = 'is_sourced' ] &&
    [ "${FUNCNAME[1]}" = 'source' ]
}

validate_ip_address() {
    local ip="$1"
    local ipv4_regex="^[1-2]?[0-9]?[0-9](\.[1-2]?[0-9]?[0-9]){3}$"
    local ipv6_regex="^([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)$"
    [[ $ip =~ $ipv4_regex ]] || [[ $ip =~ $ipv6_regex ]]
}

validate_port() {
    local port="$1"
    [[ $port =~ ^[1-6]?[0-9]{1,4}$ ]] && [ "$port" -le 65535 ]
}

validate_environment() {
    declare -g run_mode
    if [[ -n "$FE_SERVERS" && -n "$BE_ADDR" ]]; then
        run_mode="ELECTION"
        local fe_servers_regex="^.+:[1-2]{0,1}[0-9]{0,1}[0-9]{1}(\.[1-2]{0,1}[0-9]{0,1}[0-9]{1}){3}:[1-6]{0,1}[0-9]{1,4}(,.+:[1-2]{0,1}[0-9]{0,1}[0-9]{1}(\.[1-2]{0,1}[0-9]{0,1}[0-9]{1}){3}:[1-6]{0,1}[0-9]{1,4})*$"
        if ! [[ $FE_SERVERS =~ $fe_servers_regex ]]; then
            log_error "Invalid FE_SERVERS format. Expected: name:ip:port[,name:ip:port]..."
        fi
        if ! validate_ip_address "$(echo "$BE_ADDR" | cut -d: -f1)" || \
           ! validate_port "$(echo "$BE_ADDR" | cut -d: -f2)"; then
            log_error "Invalid BE_ADDR format. Expected: ip:port"
        fi
        log_info "Running in Election mode"
        return
    fi
    if [[ -n "$FE_MASTER_IP" && -n "$BE_IP" && -n "$BE_PORT" ]]; then
        run_mode="ASSIGN"
        if ! validate_ip_address "$FE_MASTER_IP"; then log_error "Invalid FE_MASTER_IP format"; fi
        if ! validate_ip_address "$BE_IP"; then log_error "Invalid BE_IP format"; fi
        if ! validate_port "$BE_PORT"; then log_error "Invalid BE_PORT"; fi
        log_info "Running in Assign mode"
        return
    fi
    log_error "Missing required parameters. Please check documentation."
}

parse_config() {
    declare -g MASTER_FE_IP CURRENT_BE_IP CURRENT_BE_PORT PRIORITY_NETWORKS
    if [ "$run_mode" = "ELECTION" ]; then
        MASTER_FE_IP=$(echo "$FE_SERVERS" | cut -d, -f1 | cut -d: -f2)
        CURRENT_BE_IP=$(echo "$BE_ADDR" | cut -d: -f1)
        CURRENT_BE_PORT=$(echo "$BE_ADDR" | cut -d: -f2)
    else
        MASTER_FE_IP="$FE_MASTER_IP"
        CURRENT_BE_IP="$BE_IP"
        CURRENT_BE_PORT="$BE_PORT"
    fi
    PRIORITY_NETWORKS=$(echo "$CURRENT_BE_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')
    export MASTER_FE_IP CURRENT_BE_IP CURRENT_BE_PORT PRIORITY_NETWORKS
}

check_be_status() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY_TIMES ]; do
        if [ "$1" = "true" ]; then
            if mysql -uroot -P"${MYSQL_PORT}" -h"${MASTER_FE_IP}" \
                -N -e "SHOW FRONTENDS" 2>/dev/null | grep -w "${MASTER_FE_IP}" &>/dev/null; then
                log_info "Master FE is ready"
                return 0
            fi
        else
            if mysql -uroot -P"${MYSQL_PORT}" -h"${MASTER_FE_IP}" \
                -N -e "SHOW BACKENDS" 2>/dev/null | grep -w "${CURRENT_BE_IP}" | grep -w "${CURRENT_BE_PORT}" | grep -w "true" &>/dev/null; then
                log_info "BE node is ready"
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
        if [ $((retry_count % 20)) -eq 1 ]; then
            if [ "$1" = "true" ]; then
                log_info "Waiting for master FE... ($retry_count/$MAX_RETRY_TIMES)"
            else
                log_info "Waiting for BE node... ($retry_count/$MAX_RETRY_TIMES)"
            fi
        fi
        sleep "$RETRY_INTERVAL"
    done
    return 1
}

process_init_files() {
    local f
    for f; do
        case "$f" in
            *.sh)     if [ -x "$f" ]; then log_info "Executing $f"; "$f"; else log_info "Sourcing $f"; . "$f"; fi ;;
            *.sql)    log_info "Executing SQL file $f"; mysql -uroot -P"${MYSQL_PORT}" -h"${MASTER_FE_IP}" < "$f" ;;
            *.sql.gz) log_info "Executing compressed SQL file $f"; gunzip -c "$f" | mysql -uroot -P"${MYSQL_PORT}" -h"${MASTER_FE_IP}" ;;
            *)        log_warn "Ignoring $f" ;;
        esac
    done
}

main() {
    validate_environment
    parse_config

    # Start BE Node
    {
        set +e
        bash init_be.sh 2>/dev/null
    } &

    # 等待 BE 就绪，失败只打警告不退出
    if ! check_be_status false; then
        log_warn "Health check timed out (FE may require password for remote root). BE process is running in background, continuing."
    fi

    # Processing initialization files
    if [ -d "/docker-entrypoint-initdb.d" ]; then
        sleep 15
        process_init_files /docker-entrypoint-initdb.d/*
    fi

    # Waiting for BE process
    wait
}

if ! is_sourced; then
    main "$@"
fi
