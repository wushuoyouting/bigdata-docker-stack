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
SET 'pipeline.name' = 'iceberg_ads_stream_ads_traffic_stats_by_channel_full';

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
CREATE DATABASE IF NOT EXISTS iceberg_ads_stream;

CREATE TABLE IF NOT EXISTS iceberg_ads_stream.ads_traffic_stats_by_channel_full(
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
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_ads_traffic_stats_by_channel_current_date_param AS
SELECT CAST(DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_ads_traffic_stats_by_channel_recent_days AS
SELECT CAST(1 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(7 AS BIGINT) AS recent_days
UNION ALL
SELECT CAST(30 AS BIGINT) AS recent_days
;

INSERT INTO iceberg_ads_stream.ads_traffic_stats_by_channel_full(
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
    DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS dt,
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
JOIN iceberg_dws_stream.dws_traffic_session_page_view_1d_full s
    ON CAST(s.k1 AS DATE) BETWEEN
        CASE
            WHEN p.recent_days = 1 THEN cp.cur_date
            WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
            ELSE cp.cur_date - INTERVAL '29' DAY
        END
        AND cp.cur_date
GROUP BY p.recent_days, COALESCE(s.channel, '')
;


