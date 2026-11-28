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
SET 'pipeline.name' = 'iceberg_dws_stream_dws_trade_user_order_refund_nd_full';

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

CREATE TABLE IF NOT EXISTS iceberg_dws_stream.dws_trade_user_order_refund_nd_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `order_refund_count_7d` BIGINT COMMENT 'recent 7 day refund count',
    `order_refund_num_7d` BIGINT COMMENT 'recent 7 day refund sku count',
    `order_refund_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day refund amount',
    `order_refund_count_30d` BIGINT COMMENT 'recent 30 day refund count',
    `order_refund_num_30d` BIGINT COMMENT 'recent 30 day refund sku count',
    `order_refund_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day refund amount',
    PRIMARY KEY (`user_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_refund_nd_current_date_param AS
    SELECT CAST(DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_refund_nd_refund_1d AS
    SELECT
        user_id,
        CAST(k1 AS DATE) AS dt,
        order_refund_count_1d,
        order_refund_num_1d,
        order_refund_amount_1d
    FROM iceberg_dws_stream.dws_trade_user_order_refund_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_refund_nd_refund_agg AS
    SELECT
        r.user_id,
        SUM(CASE WHEN r.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN r.order_refund_count_1d ELSE 0 END) AS order_refund_count_7d,
        SUM(CASE WHEN r.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN r.order_refund_num_1d ELSE 0 END) AS order_refund_num_7d,
        SUM(CASE WHEN r.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN r.order_refund_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS order_refund_amount_7d,
        SUM(r.order_refund_count_1d) AS order_refund_count_30d,
        SUM(r.order_refund_num_1d) AS order_refund_num_30d,
        SUM(r.order_refund_amount_1d) AS order_refund_amount_30d
    FROM tmp_dws_trade_user_order_refund_nd_refund_1d r
    CROSS JOIN tmp_dws_trade_user_order_refund_nd_current_date_param cp
    WHERE r.dt BETWEEN cp.cur_date - INTERVAL '29' DAY AND cp.cur_date
    GROUP BY r.user_id
;

INSERT INTO iceberg_dws_stream.dws_trade_user_order_refund_nd_full(
    user_id,
    k1,
    order_refund_count_7d,
    order_refund_num_7d,
    order_refund_amount_7d,
    order_refund_count_30d,
    order_refund_num_30d,
    order_refund_amount_30d
)
SELECT
    ra.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    ra.order_refund_count_7d,
    ra.order_refund_num_7d,
    ra.order_refund_amount_7d,
    ra.order_refund_count_30d,
    ra.order_refund_num_30d,
    ra.order_refund_amount_30d
FROM tmp_dws_trade_user_order_refund_nd_refund_agg ra
CROSS JOIN tmp_dws_trade_user_order_refund_nd_current_date_param cp;


