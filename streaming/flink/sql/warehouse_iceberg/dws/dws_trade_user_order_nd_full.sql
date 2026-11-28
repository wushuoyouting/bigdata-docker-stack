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

CREATE TABLE IF NOT EXISTS iceberg_dws.dws_trade_user_order_nd_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `order_count_7d` BIGINT COMMENT 'recent 7 day order count',
    `order_num_7d` BIGINT COMMENT 'recent 7 day sku count',
    `order_original_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day original amount',
    `activity_reduce_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day activity reduce amount',
    `coupon_reduce_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day coupon reduce amount',
    `order_total_amount_7d` DECIMAL(16, 2) COMMENT 'recent 7 day order total amount',
    `order_count_30d` BIGINT COMMENT 'recent 30 day order count',
    `order_num_30d` BIGINT COMMENT 'recent 30 day sku count',
    `order_original_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day original amount',
    `activity_reduce_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day activity reduce amount',
    `coupon_reduce_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day coupon reduce amount',
    `order_total_amount_30d` DECIMAL(16, 2) COMMENT 'recent 30 day order total amount',
    PRIMARY KEY (`user_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_nd_current_date_param AS
    SELECT CAST(CAST(CURRENT_DATE AS STRING) AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_nd_order_1d AS
    SELECT
        user_id,
        CAST(k1 AS DATE) AS dt,
        order_count_1d,
        order_num_1d,
        order_original_amount_1d,
        activity_reduce_amount_1d,
        coupon_reduce_amount_1d,
        order_total_amount_1d
    FROM iceberg_dws.dws_trade_user_order_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_trade_user_order_nd_order_agg AS
    SELECT
        o.user_id,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.order_count_1d ELSE 0 END) AS order_count_7d,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.order_num_1d ELSE 0 END) AS order_num_7d,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.order_original_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS order_original_amount_7d,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.activity_reduce_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS activity_reduce_amount_7d,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.coupon_reduce_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS coupon_reduce_amount_7d,
        SUM(CASE WHEN o.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN o.order_total_amount_1d ELSE CAST(0 AS DECIMAL(16, 2)) END) AS order_total_amount_7d,
        SUM(o.order_count_1d) AS order_count_30d,
        SUM(o.order_num_1d) AS order_num_30d,
        SUM(o.order_original_amount_1d) AS order_original_amount_30d,
        SUM(o.activity_reduce_amount_1d) AS activity_reduce_amount_30d,
        SUM(o.coupon_reduce_amount_1d) AS coupon_reduce_amount_30d,
        SUM(o.order_total_amount_1d) AS order_total_amount_30d
    FROM tmp_dws_trade_user_order_nd_order_1d o
    CROSS JOIN tmp_dws_trade_user_order_nd_current_date_param cp
    WHERE o.dt BETWEEN cp.cur_date - INTERVAL '29' DAY AND cp.cur_date
    GROUP BY o.user_id
;

INSERT INTO iceberg_dws.dws_trade_user_order_nd_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    user_id,
    k1,
    order_count_7d,
    order_num_7d,
    order_original_amount_7d,
    activity_reduce_amount_7d,
    coupon_reduce_amount_7d,
    order_total_amount_7d,
    order_count_30d,
    order_num_30d,
    order_original_amount_30d,
    activity_reduce_amount_30d,
    coupon_reduce_amount_30d,
    order_total_amount_30d
)
SELECT
    oa.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    oa.order_count_7d,
    oa.order_num_7d,
    oa.order_original_amount_7d,
    oa.activity_reduce_amount_7d,
    oa.coupon_reduce_amount_7d,
    oa.order_total_amount_7d,
    oa.order_count_30d,
    oa.order_num_30d,
    oa.order_original_amount_30d,
    oa.activity_reduce_amount_30d,
    oa.coupon_reduce_amount_30d,
    oa.order_total_amount_30d
FROM tmp_dws_trade_user_order_nd_order_agg oa
CROSS JOIN tmp_dws_trade_user_order_nd_current_date_param cp;
