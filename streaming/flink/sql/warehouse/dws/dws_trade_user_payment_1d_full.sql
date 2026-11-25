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

CREATE TABLE IF NOT EXISTS dws.dws_trade_user_payment_1d_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `payment_count_1d` BIGINT COMMENT 'daily payment count',
    `payment_num_1d` BIGINT COMMENT 'daily payment sku num',
    `payment_amount_1d` DECIMAL(16, 2) COMMENT 'daily payment amount',
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

INSERT INTO dws.dws_trade_user_payment_1d_full(
    user_id,
    k1,
    payment_count_1d,
    payment_num_1d,
    payment_amount_1d
)
SELECT
    user_id,
    k1,
    COUNT(DISTINCT order_id) AS payment_count_1d,
    SUM(sku_num) AS payment_num_1d,
    SUM(split_payment_amount) AS payment_amount_1d
FROM dwd.dwd_trade_pay_detail_suc_full
GROUP BY user_id, k1;
