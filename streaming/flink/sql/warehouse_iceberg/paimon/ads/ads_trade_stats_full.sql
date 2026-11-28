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
CREATE DATABASE IF NOT EXISTS ads;

CREATE TABLE IF NOT EXISTS ads.ads_trade_stats_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `order_total_amount` DECIMAL(16, 2) COMMENT 'order total amount',
    `order_count` BIGINT COMMENT 'order count',
    `order_user_count` BIGINT COMMENT 'order user count',
    `order_refund_count` BIGINT COMMENT 'refund count',
    `order_refund_user_count` BIGINT COMMENT 'refund user count',
    PRIMARY KEY (`dt`, `recent_days`) NOT ENFORCED
) PARTITIONED BY (`dt`) WITH (
    'connector' = 'paimon',
    'metastore.partitioned-table' = 'true',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true',
    'partition.expiration-time' = '1 d',
    'partition.expiration-check-interval' = '1 h',
    'partition.timestamp-formatter' = 'yyyy-MM-dd',
    'partition.timestamp-pattern' = '$dt'
);

CREATE TEMPORARY VIEW tmp_ads_trade_stats_recent_days AS
    SELECT CAST(7 AS BIGINT) AS recent_days
    UNION ALL
    SELECT CAST(30 AS BIGINT) AS recent_days
;

CREATE TEMPORARY VIEW tmp_ads_trade_stats_order_1d_stats AS
    SELECT
        COALESCE(SUM(order_total_amount_1d), CAST(0 AS DECIMAL(16, 2))) AS order_total_amount,
        COALESCE(SUM(order_count_1d), 0) AS order_count,
        COUNT(*) AS order_user_count
    FROM dws.dws_trade_user_order_1d_full
    WHERE k1 = CAST(CURRENT_DATE AS STRING)
;

CREATE TEMPORARY VIEW tmp_ads_trade_stats_order_nd_stats AS
    SELECT
        r.recent_days,
        COALESCE(SUM(CASE WHEN r.recent_days = 7 THEN o.order_total_amount_7d ELSE o.order_total_amount_30d END), CAST(0 AS DECIMAL(16, 2))) AS order_total_amount,
        COALESCE(SUM(CASE WHEN r.recent_days = 7 THEN o.order_count_7d ELSE o.order_count_30d END), 0) AS order_count,
        COALESCE(
            SUM(
                CASE
                    WHEN (CASE WHEN r.recent_days = 7 THEN o.order_count_7d ELSE o.order_count_30d END) > 0 THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS order_user_count
    FROM tmp_ads_trade_stats_recent_days r
    LEFT JOIN dws.dws_trade_user_order_nd_full o
        ON o.k1 = CAST(CURRENT_DATE AS STRING)
    GROUP BY r.recent_days
;

CREATE TEMPORARY VIEW tmp_ads_trade_stats_refund_1d_stats AS
    SELECT
        COALESCE(SUM(order_refund_count_1d), 0) AS order_refund_count,
        COUNT(*) AS order_refund_user_count
    FROM dws.dws_trade_user_order_refund_1d_full
    WHERE k1 = CAST(CURRENT_DATE AS STRING)
;

CREATE TEMPORARY VIEW tmp_ads_trade_stats_refund_nd_stats AS
    SELECT
        r.recent_days,
        COALESCE(SUM(CASE WHEN r.recent_days = 7 THEN f.order_refund_count_7d ELSE f.order_refund_count_30d END), 0) AS order_refund_count,
        COALESCE(
            SUM(
                CASE
                    WHEN (CASE WHEN r.recent_days = 7 THEN f.order_refund_count_7d ELSE f.order_refund_count_30d END) > 0 THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS order_refund_user_count
    FROM tmp_ads_trade_stats_recent_days r
    LEFT JOIN dws.dws_trade_user_order_refund_nd_full f
        ON f.k1 = CAST(CURRENT_DATE AS STRING)
    GROUP BY r.recent_days
;

INSERT INTO ads.ads_trade_stats_full(
    dt,
    recent_days,
    order_total_amount,
    order_count,
    order_user_count,
    order_refund_count,
    order_refund_user_count
)
SELECT
    CAST(CURRENT_DATE AS STRING) AS dt,
    CAST(1 AS BIGINT) AS recent_days,
    o.order_total_amount,
    o.order_count,
    o.order_user_count,
    r.order_refund_count,
    r.order_refund_user_count
FROM tmp_ads_trade_stats_order_1d_stats o
CROSS JOIN tmp_ads_trade_stats_refund_1d_stats r
UNION ALL
SELECT
    CAST(CURRENT_DATE AS STRING) AS dt,
    o.recent_days,
    o.order_total_amount,
    o.order_count,
    o.order_user_count,
    COALESCE(r.order_refund_count, 0) AS order_refund_count,
    COALESCE(r.order_refund_user_count, 0) AS order_refund_user_count
FROM tmp_ads_trade_stats_order_nd_stats o
LEFT JOIN tmp_ads_trade_stats_refund_nd_stats r
    ON o.recent_days = r.recent_days;
