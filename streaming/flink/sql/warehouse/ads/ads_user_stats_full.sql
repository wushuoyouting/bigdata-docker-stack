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

CREATE TABLE IF NOT EXISTS ads.ads_user_stats_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `new_user_count` BIGINT COMMENT 'new user count',
    `active_user_count` BIGINT COMMENT 'active user count',
    PRIMARY KEY (`dt`, `recent_days`) NOT ENFORCED
) WITH (
    'connector' = 'paimon',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true'
);

CREATE TEMPORARY VIEW tmp_ads_user_stats_current_date_param AS
SELECT CAST('2026-11-24' AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_ads_user_stats_recent_days AS
SELECT CAST(1 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(7 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(30 AS BIGINT) AS recent_days
;

CREATE TEMPORARY VIEW tmp_ads_user_stats_new_users AS
SELECT
    p.recent_days,
    COUNT(DISTINCT CAST(r.user_id AS STRING)) AS new_user_count
FROM tmp_ads_user_stats_recent_days p
CROSS JOIN tmp_ads_user_stats_current_date_param cp
LEFT JOIN dwd.dwd_user_register_full r
    ON CAST(r.k1 AS DATE) BETWEEN
        CASE
            WHEN p.recent_days = 1 THEN cp.cur_date
            WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
            ELSE cp.cur_date - INTERVAL '29' DAY
        END
        AND cp.cur_date
GROUP BY p.recent_days
;

CREATE TEMPORARY VIEW tmp_ads_user_stats_active_users AS
SELECT
    p.recent_days,
    COUNT(DISTINCT CAST(l.user_id AS STRING)) AS active_user_count
FROM tmp_ads_user_stats_recent_days p
CROSS JOIN tmp_ads_user_stats_current_date_param cp
LEFT JOIN dwd.dwd_user_login_full l
    ON CAST(l.k1 AS DATE) BETWEEN
        CASE
            WHEN p.recent_days = 1 THEN cp.cur_date
            WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
            ELSE cp.cur_date - INTERVAL '29' DAY
        END
        AND cp.cur_date
GROUP BY p.recent_days
;

INSERT INTO ads.ads_user_stats_full(
    dt,
    recent_days,
    new_user_count,
    active_user_count
)
SELECT
    '2026-11-24' AS dt,
    d.recent_days,
    COALESCE(n.new_user_count, 0) AS new_user_count,
    COALESCE(a.active_user_count, 0) AS active_user_count
FROM tmp_ads_user_stats_recent_days d
LEFT JOIN tmp_ads_user_stats_new_users n
    ON d.recent_days = n.recent_days
LEFT JOIN tmp_ads_user_stats_active_users a
    ON d.recent_days = a.recent_days
;
