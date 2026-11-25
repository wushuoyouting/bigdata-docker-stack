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

CREATE TABLE IF NOT EXISTS dws.dws_trade_user_payment_td_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `payment_date_first` STRING COMMENT 'first payment date',
    `payment_date_last` STRING COMMENT 'last payment date',
    `payment_count_td` BIGINT COMMENT 'to date payment count',
    `payment_num_td` BIGINT COMMENT 'to date payment sku num',
    `payment_amount_td` DECIMAL(16, 2) COMMENT 'to date payment amount',
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

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_td_current_date_param AS
    SELECT CAST('2026-11-24' AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_td_payment_1d AS
    SELECT
        user_id,
        CAST(k1 AS DATE) AS dt,
        payment_count_1d,
        payment_num_1d,
        payment_amount_1d
    FROM dws.dws_trade_user_payment_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_payment_td_payment_agg AS
    SELECT
        p.user_id,
        MIN(p.dt) AS payment_date_first_dt,
        MAX(p.dt) AS payment_date_last_dt,
        SUM(p.payment_count_1d) AS payment_count_td,
        SUM(p.payment_num_1d) AS payment_num_td,
        SUM(p.payment_amount_1d) AS payment_amount_td
    FROM tmp_dws_trade_user_payment_td_payment_1d p
    CROSS JOIN tmp_dws_trade_user_payment_td_current_date_param cp
    WHERE p.dt <= cp.cur_date
    GROUP BY p.user_id
;

INSERT INTO dws.dws_trade_user_payment_td_full(
    user_id,
    k1,
    payment_date_first,
    payment_date_last,
    payment_count_td,
    payment_num_td,
    payment_amount_td
)
SELECT
    pa.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    CAST(pa.payment_date_first_dt AS STRING) AS payment_date_first,
    CAST(pa.payment_date_last_dt AS STRING) AS payment_date_last,
    pa.payment_count_td,
    pa.payment_num_td,
    pa.payment_amount_td
FROM tmp_dws_trade_user_payment_td_payment_agg pa
CROSS JOIN tmp_dws_trade_user_payment_td_current_date_param cp;
