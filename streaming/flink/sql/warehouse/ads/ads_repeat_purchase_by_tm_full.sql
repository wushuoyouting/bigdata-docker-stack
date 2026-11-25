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
CREATE DATABASE IF NOT EXISTS ads;

CREATE TABLE IF NOT EXISTS ads.ads_repeat_purchase_by_tm_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `tm_id` STRING COMMENT 'trademark id',
    `tm_name` STRING COMMENT 'trademark name',
    `order_repeat_rate` DECIMAL(16, 2) COMMENT 'repeat purchase rate',
    PRIMARY KEY (`dt`, `recent_days`, `tm_id`) NOT ENFORCED
) WITH (
    'connector' = 'paimon',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true'
);

CREATE TEMPORARY VIEW tmp_ads_repeat_purchase_by_tm_recent_days AS
SELECT CAST(7 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(30 AS BIGINT) AS recent_days
;

CREATE TEMPORARY VIEW tmp_ads_repeat_purchase_by_tm_user_tm_order AS
SELECT
    p.recent_days,
    CAST(o.tm_id AS STRING) AS tm_id,
    COALESCE(o.tm_name, '') AS tm_name,
    CAST(o.user_id AS STRING) AS user_id,
    SUM(
        CASE
            WHEN p.recent_days = 7 THEN o.order_count_7d
            ELSE o.order_count_30d
        END
    ) AS order_count
FROM tmp_ads_repeat_purchase_by_tm_recent_days p
JOIN dws.dws_trade_user_sku_order_nd_full o
    ON o.k1 = '2026-11-24'
WHERE o.tm_id IS NOT NULL
GROUP BY
    p.recent_days,
    CAST(o.tm_id AS STRING),
    COALESCE(o.tm_name, ''),
    CAST(o.user_id AS STRING)
;

INSERT INTO ads.ads_repeat_purchase_by_tm_full(
    dt,
    recent_days,
    tm_id,
    tm_name,
    order_repeat_rate
)
SELECT
    '2026-11-24' AS dt,
    recent_days,
    tm_id,
    tm_name,
    CASE
        WHEN SUM(CASE WHEN order_count >= 1 THEN 1 ELSE 0 END) = 0 THEN CAST(0 AS DECIMAL(16, 2))
        ELSE CAST(
            CAST(SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) AS DECIMAL(16, 2))
            / CAST(SUM(CASE WHEN order_count >= 1 THEN 1 ELSE 0 END) AS DECIMAL(16, 2))
            AS DECIMAL(16, 2)
        )
    END AS order_repeat_rate
FROM tmp_ads_repeat_purchase_by_tm_user_tm_order
GROUP BY recent_days, tm_id, tm_name
;
