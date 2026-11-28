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

CREATE TABLE IF NOT EXISTS ads.ads_traffic_stats_by_channel_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `channel` STRING COMMENT 'channel',
    `uv_count` BIGINT COMMENT 'visitor count',
    `avg_duration_sec` BIGINT COMMENT 'avg session duration seconds',
    `avg_page_count` BIGINT COMMENT 'avg page count',
    `sv_count` BIGINT COMMENT 'session count',
    `bounce_rate` DECIMAL(16, 2) COMMENT 'bounce rate',
    PRIMARY KEY (`dt`, `recent_days`, `channel`) NOT ENFORCED
) WITH (
    'connector' = 'paimon',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true'
);

CREATE TEMPORARY VIEW tmp_ads_traffic_stats_by_channel_current_date_param AS
SELECT CAST(CAST(CURRENT_DATE AS STRING) AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_ads_traffic_stats_by_channel_recent_days AS
SELECT CAST(1 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(7 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(30 AS BIGINT) AS recent_days
;

INSERT INTO ads.ads_traffic_stats_by_channel_full(
    dt,
    recent_days,
    channel,
    uv_count,
    avg_duration_sec,
    avg_page_count,
    sv_count,
    bounce_rate
)
SELECT
    CAST(CURRENT_DATE AS STRING) AS dt,
    p.recent_days,
    COALESCE(s.channel, '') AS channel,
    COUNT(DISTINCT s.mid_id) AS uv_count,
    CAST(AVG(CAST(s.during_time_1d AS DOUBLE)) / 1000 AS BIGINT) AS avg_duration_sec,
    CAST(AVG(CAST(s.page_count_1d AS DOUBLE)) AS BIGINT) AS avg_page_count,
    COUNT(*) AS sv_count,
    CASE
        WHEN COUNT(*) = 0 THEN CAST(0 AS DECIMAL(16, 2))
        ELSE CAST(
            CAST(SUM(CASE WHEN s.page_count_1d = 1 THEN 1 ELSE 0 END) AS DECIMAL(16, 2))
            / CAST(COUNT(*) AS DECIMAL(16, 2))
            AS DECIMAL(16, 2)
        )
    END AS bounce_rate
FROM tmp_ads_traffic_stats_by_channel_recent_days p
CROSS JOIN tmp_ads_traffic_stats_by_channel_current_date_param cp
JOIN dws.dws_traffic_session_page_view_1d_full s
    ON CAST(s.k1 AS DATE) BETWEEN
        CASE
            WHEN p.recent_days = 1 THEN cp.cur_date
            WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
            ELSE cp.cur_date - INTERVAL '29' DAY
        END
        AND cp.cur_date
GROUP BY p.recent_days, COALESCE(s.channel, '')
;
