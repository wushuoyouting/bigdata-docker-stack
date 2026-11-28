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

CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.jdbc.JdbcCatalog',
    'uri' = 'jdbc:postgresql://host.docker.internal:5432/iceberg_meta',
    'jdbc.user' = 'root',
    'jdbc.password' = '123456',
    'warehouse' = 's3://lakehouse/iceberg/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minio:9000',
    's3.access-key-id' = 'ak6c52d75066d96ddd',
    's3.secret-access-key' = '5cf0fa1d0e1fd9bf182be642beca1a15',
    's3.region' = 'us-east-1',
    's3.path-style-access' = 'true'
);
USE CATALOG iceberg_catalog;
CREATE DATABASE IF NOT EXISTS iceberg_ads;

CREATE TABLE IF NOT EXISTS iceberg_ads.ads_activity_stats_full(
    `dt` STRING COMMENT 'stat date',
    `activity_id` BIGINT COMMENT 'activity id',
    `activity_name` STRING COMMENT 'activity name',
    `start_date` STRING COMMENT 'activity start date',
    `reduce_rate` DECIMAL(16, 2) COMMENT 'activity reduce rate',
    PRIMARY KEY (`dt`, `activity_id`) NOT ENFORCED
) PARTITIONED BY (`dt`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ads.ads_activity_stats_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    dt,
    activity_id,
    activity_name,
    start_date,
    reduce_rate
)
SELECT
    CAST(CURRENT_DATE AS STRING) AS dt,
    activity_id,
    activity_name,
    start_date,
    CASE
        WHEN original_amount_30d = CAST(0 AS DECIMAL(16, 2)) THEN CAST(0 AS DECIMAL(16, 2))
        ELSE CAST(activity_reduce_amount_30d / original_amount_30d AS DECIMAL(16, 2))
    END AS reduce_rate
FROM iceberg_dws.dws_trade_activity_order_nd_full
WHERE k1 = CAST(CURRENT_DATE AS STRING);
