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

CREATE TABLE IF NOT EXISTS dws.dws_trade_user_payment_nd_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `payment_count_7d` BIGINT COMMENT 'recent 7 day payment count',
    `payment_num_7d` BIGINT COMMENT 'recent 7 day payment sku num',
    `payment_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day payment amount',
    `payment_count_30d` BIGINT COMMENT 'recent 30 day payment count',
    `payment_num_30d` BIGINT COMMENT 'recent 30 day payment sku num',
    `payment_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day payment amount',
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

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_nd_current_date_param AS
    SELECT CAST('2026-11-24' AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_nd_payment_1d AS
    SELECT
        user_id,
        CAST(k1 AS DATE) AS dt,
        payment_count_1d,
        payment_num_1d,
        payment_amount_1d
    FROM dws.dws_trade_user_payment_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_nd_payment_agg AS
    SELECT
        p.user_id,
        SUM(CASE WHEN p.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN p.payment_count_1d ELSE 0 END) AS payment_count_7d,
        SUM(CASE WHEN p.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN p.payment_num_1d ELSE 0 END) AS payment_num_7d,
        SUM(CASE WHEN p.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN p.payment_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS payment_amount_7d,
        SUM(p.payment_count_1d) AS payment_count_30d,
        SUM(p.payment_num_1d) AS payment_num_30d,
        SUM(p.payment_amount_1d) AS payment_amount_30d
    FROM tmp_dws_trade_user_payment_nd_payment_1d p
    CROSS JOIN tmp_dws_trade_user_payment_nd_current_date_param cp
    WHERE p.dt BETWEEN cp.cur_date - INTERVAL '29' DAY AND cp.cur_date
    GROUP BY p.user_id
;

INSERT INTO dws.dws_trade_user_payment_nd_full(
    user_id,
    k1,
    payment_count_7d,
    payment_num_7d,
    payment_amount_7d,
    payment_count_30d,
    payment_num_30d,
    payment_amount_30d
)
SELECT
    pa.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    pa.payment_count_7d,
    pa.payment_num_7d,
    pa.payment_amount_7d,
    pa.payment_count_30d,
    pa.payment_num_30d,
    pa.payment_amount_30d
FROM tmp_dws_trade_user_payment_nd_payment_agg pa
CROSS JOIN tmp_dws_trade_user_payment_nd_current_date_param cp;
