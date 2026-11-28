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

CREATE TABLE IF NOT EXISTS iceberg_ads.ads_new_buyer_stats_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `new_order_user_count` BIGINT COMMENT 'new order user count',
    `new_payment_user_count` BIGINT COMMENT 'new payment user count',
    PRIMARY KEY (`dt`, `recent_days`) NOT ENFORCED
) WITH (
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_ads_new_buyer_stats_current_date_param AS
SELECT CAST(CAST(CURRENT_DATE AS STRING) AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_ads_new_buyer_stats_recent_days AS
SELECT CAST(1 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(7 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(30 AS BIGINT) AS recent_days
;

CREATE TEMPORARY VIEW tmp_ads_new_buyer_stats_order AS
SELECT
    p.recent_days,
    COALESCE(
        SUM(
            CASE
                WHEN CAST(o.order_date_first AS DATE) >=
                    CASE
                        WHEN p.recent_days = 1 THEN cp.cur_date
                        WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
                        ELSE cp.cur_date - INTERVAL '29' DAY
                    END
                THEN 1
                ELSE 0
            END
        ),
        0
    ) AS new_order_user_count
FROM tmp_ads_new_buyer_stats_recent_days p
CROSS JOIN tmp_ads_new_buyer_stats_current_date_param cp
LEFT JOIN iceberg_dws.dws_trade_user_order_td_full o
    ON o.k1 = CAST(CURRENT_DATE AS STRING)
GROUP BY p.recent_days
;

CREATE TEMPORARY VIEW tmp_ads_new_buyer_stats_payment AS
SELECT
    p.recent_days,
    COALESCE(
        SUM(
            CASE
                WHEN CAST(pay.payment_date_first AS DATE) >=
                    CASE
                        WHEN p.recent_days = 1 THEN cp.cur_date
                        WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
                        ELSE cp.cur_date - INTERVAL '29' DAY
                    END
                THEN 1
                ELSE 0
            END
        ),
        0
    ) AS new_payment_user_count
FROM tmp_ads_new_buyer_stats_recent_days p
CROSS JOIN tmp_ads_new_buyer_stats_current_date_param cp
LEFT JOIN iceberg_dws.dws_trade_user_payment_td_full pay
    ON pay.k1 = CAST(CURRENT_DATE AS STRING)
GROUP BY p.recent_days
;

INSERT INTO iceberg_ads.ads_new_buyer_stats_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    dt,
    recent_days,
    new_order_user_count,
    new_payment_user_count
)
SELECT
    CAST(CURRENT_DATE AS STRING) AS dt,
    p.recent_days,
    COALESCE(o.new_order_user_count, 0) AS new_order_user_count,
    COALESCE(pay.new_payment_user_count, 0) AS new_payment_user_count
FROM tmp_ads_new_buyer_stats_recent_days p
LEFT JOIN tmp_ads_new_buyer_stats_order o
    ON p.recent_days = o.recent_days
LEFT JOIN tmp_ads_new_buyer_stats_payment pay
    ON p.recent_days = pay.recent_days
;
