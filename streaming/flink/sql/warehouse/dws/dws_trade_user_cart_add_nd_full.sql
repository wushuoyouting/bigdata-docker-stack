SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
SET 'execution.runtime-mode' = 'batch';

CREATE CATALOG paimon_minio WITH (
    'type' = 'paimon',
    'metastore' = 'filesystem',
    'warehouse' = 's3://lakehouse/paimon',
    's3.endpoint' = 'http://minio:9000',
    's3.access-key' = 'ak6c52d75066d96ddd',
    's3.secret-key' = '5cf0fa1d0e1fd9bf182be642beca1a15',
    's3.path.style.access' = 'true'
);
USE CATALOG paimon_minio;
CREATE DATABASE IF NOT EXISTS dws;

CREATE TABLE IF NOT EXISTS dws.dws_trade_user_cart_add_nd_full(
    `user_id` STRING COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `cart_add_count_7d` BIGINT COMMENT 'recent 7 day cart add count',
    `cart_add_num_7d` BIGINT COMMENT 'recent 7 day cart add sku num',
    `cart_add_count_30d` BIGINT COMMENT 'recent 30 day cart add count',
    `cart_add_num_30d` BIGINT COMMENT 'recent 30 day cart add sku num',
    PRIMARY KEY (`user_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'connector' = 'paimon',
    'metastore.partitioned-table' = 'true',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true',
    'partition.expiration-time' = '1 d',
    'partition.expiration-check-interval' = '1 h',
    'partition.timestamp-formatter' = 'yyyy-MM-dd',
    'partition.timestamp-pattern' = '$k1'
);

CREATE TEMPORARY VIEW tmp_dws_trade_user_cart_add_nd_current_date_param AS
    SELECT CAST('2026-11-24' AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_cart_add_nd_cart_add_1d AS
    SELECT
        user_id,
        CAST(k1 AS DATE) AS dt,
        cart_add_count_1d,
        cart_add_num_1d
    FROM dws.dws_trade_user_cart_add_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_cart_add_nd_cart_add_agg AS
    SELECT
        c.user_id,
        SUM(CASE WHEN c.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN c.cart_add_count_1d ELSE 0 END) AS cart_add_count_7d,
        SUM(CASE WHEN c.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN c.cart_add_num_1d ELSE 0 END) AS cart_add_num_7d,
        SUM(c.cart_add_count_1d) AS cart_add_count_30d,
        SUM(c.cart_add_num_1d) AS cart_add_num_30d
    FROM tmp_dws_trade_user_cart_add_nd_cart_add_1d c
    CROSS JOIN tmp_dws_trade_user_cart_add_nd_current_date_param cp
    WHERE c.dt BETWEEN cp.cur_date - INTERVAL '29' DAY AND cp.cur_date
    GROUP BY c.user_id
;

INSERT INTO dws.dws_trade_user_cart_add_nd_full(
    user_id,
    k1,
    cart_add_count_7d,
    cart_add_num_7d,
    cart_add_count_30d,
    cart_add_num_30d
)
SELECT
    ca.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    ca.cart_add_count_7d,
    ca.cart_add_num_7d,
    ca.cart_add_count_30d,
    ca.cart_add_num_30d
FROM tmp_dws_trade_user_cart_add_nd_cart_add_agg ca
CROSS JOIN tmp_dws_trade_user_cart_add_nd_current_date_param cp;
