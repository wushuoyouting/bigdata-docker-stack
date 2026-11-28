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
CREATE DATABASE IF NOT EXISTS iceberg_dws;

CREATE TABLE IF NOT EXISTS iceberg_dws.dws_traffic_page_visitor_page_view_1d_full(
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
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_dws.dws_traffic_page_visitor_page_view_1d_full /*+ OPTIONS('upsert-enabled' = 'true') */(
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
FROM iceberg_dwd.dwd_traffic_page_view_full
GROUP BY mid_id, k1, brand, model, operate_system, page_id;
