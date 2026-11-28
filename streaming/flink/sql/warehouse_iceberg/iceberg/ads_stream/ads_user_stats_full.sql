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
SET 'pipeline.name' = 'iceberg_ads_stream_ads_user_stats_full';

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

CREATE TABLE IF NOT EXISTS iceberg_ads_stream.ads_user_stats_full(
    `dt` STRING COMMENT 'stat date',
    `recent_days` BIGINT COMMENT 'recent day window',
    `new_user_count` BIGINT COMMENT 'new user count',
    `active_user_count` BIGINT COMMENT 'active user count',
    PRIMARY KEY (`dt`, `recent_days`) NOT ENFORCED
) WITH (
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_ads_user_stats_register_snapshot AS
SELECT *
FROM iceberg_dwd_stream.dwd_user_register_full /*+ OPTIONS('read.streaming.enabled' = 'false') */
;

CREATE TEMPORARY VIEW tmp_ads_user_stats_login_snapshot AS
SELECT *
FROM iceberg_dwd_stream.dwd_user_login_full /*+ OPTIONS('read.streaming.enabled' = 'false') */
;

CREATE TEMPORARY VIEW tmp_ads_user_stats_current_date_param AS
SELECT CAST(DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS DATE) AS cur_date
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
LEFT JOIN tmp_ads_user_stats_register_snapshot r
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
LEFT JOIN tmp_ads_user_stats_login_snapshot l
    ON CAST(l.k1 AS DATE) BETWEEN
        CASE
            WHEN p.recent_days = 1 THEN cp.cur_date
            WHEN p.recent_days = 7 THEN cp.cur_date - INTERVAL '6' DAY
            ELSE cp.cur_date - INTERVAL '29' DAY
        END
        AND cp.cur_date
GROUP BY p.recent_days
;

INSERT INTO iceberg_ads_stream.ads_user_stats_full(
    dt,
    recent_days,
    new_user_count,
    active_user_count
)
SELECT
    DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS dt,
    d.recent_days,
    COALESCE(n.new_user_count, 0) AS new_user_count,
    COALESCE(a.active_user_count, 0) AS active_user_count
FROM tmp_ads_user_stats_recent_days d
LEFT JOIN tmp_ads_user_stats_new_users n
    ON d.recent_days = n.recent_days
LEFT JOIN tmp_ads_user_stats_active_users a
    ON d.recent_days = a.recent_days
;


