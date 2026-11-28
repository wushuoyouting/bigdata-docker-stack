SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.exec.resource.default-parallelism' = '1';
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

CREATE TABLE IF NOT EXISTS dws.dws_traffic_page_visitor_page_view_1d_full(
    `mid_id` STRING COMMENT 'visitor id',
    `k1` STRING COMMENT 'partition field',
    `brand` STRING COMMENT 'device brand',
    `model` STRING COMMENT 'device model',
    `operate_system` STRING COMMENT 'device os',
    `page_id` STRING COMMENT 'page id',
    `during_time_1d` BIGINT COMMENT 'daily during time',
    `view_count_1d` BIGINT COMMENT 'daily page view count',
    PRIMARY KEY (`mid_id`, `page_id`, `k1`) NOT ENFORCED
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

INSERT INTO dws.dws_traffic_page_visitor_page_view_1d_full(
    mid_id,
    k1,
    brand,
    model,
    operate_system,
    page_id,
    during_time_1d,
    view_count_1d
)
SELECT
    mid_id,
    k1,
    brand,
    model,
    operate_system,
    page_id,
    SUM(during_time) AS during_time_1d,
    COUNT(*) AS view_count_1d
FROM dwd.dwd_traffic_page_view_full
GROUP BY mid_id, k1, brand, model, operate_system, page_id;
