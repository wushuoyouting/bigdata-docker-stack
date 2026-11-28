SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.dynamic-table-options.enabled' = 'true';
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
SET 'pipeline.name' = 'iceberg_dws_stream_dws_trade_user_order_refund_1d_full';

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
CREATE DATABASE IF NOT EXISTS iceberg_dws_stream;

CREATE TABLE IF NOT EXISTS iceberg_dws_stream.dws_trade_user_order_refund_1d_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `order_refund_count_1d` BIGINT COMMENT 'daily refund count',
    `order_refund_num_1d` BIGINT COMMENT 'daily refund sku num',
    `order_refund_amount_1d` DECIMAL(16, 2) COMMENT 'daily refund amount',
    PRIMARY KEY (`user_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_dws_stream.dws_trade_user_order_refund_1d_full(
    user_id,
    k1,
    order_refund_count_1d,
    order_refund_num_1d,
    order_refund_amount_1d
)
SELECT
    user_id,
    k1,
    COUNT(*) AS order_refund_count_1d,
    SUM(refund_num) AS order_refund_num_1d,
    SUM(refund_amount) AS order_refund_amount_1d
FROM iceberg_dwd_stream.dwd_trade_order_refund_full
GROUP BY user_id, k1;


