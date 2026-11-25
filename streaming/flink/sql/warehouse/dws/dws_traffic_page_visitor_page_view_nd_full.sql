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
CREATE DATABASE IF NOT EXISTS dws;

CREATE TABLE IF NOT EXISTS dws.dws_traffic_page_visitor_page_view_nd_full(
    `mid_id` STRING COMMENT 'visitor id',
    `page_id` STRING COMMENT 'page id',
    `k1` STRING COMMENT 'partition field',
    `brand` STRING COMMENT 'device brand',
    `model` STRING COMMENT 'device model',
    `operate_system` STRING COMMENT 'device os',
    `during_time_7d` BIGINT COMMENT 'recent 7 day during time',
    `view_count_7d` BIGINT COMMENT 'recent 7 day view count',
    `during_time_30d` BIGINT COMMENT 'recent 30 day during time',
    `view_count_30d` BIGINT COMMENT 'recent 30 day view count',
    PRIMARY KEY (`mid_id`, `page_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'connector' = 'paimon',
    'metastore.partitioned-table' = 'true',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true',
    'partition.expiration-time' = '1 d',
    'partition.expiration-check-interval' = '1 h',
    'partition.timestamp-formatter' = 'yyyy-MM-dd',
    'partition.timestamp-pattern' = '$k1'
);

CREATE TEMPORARY VIEW tmp_dws_traffic_page_visitor_page_view_nd_current_date_param AS
    SELECT CAST('2026-11-24' AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_traffic_page_visitor_page_view_nd_page_view_1d AS
    SELECT
        mid_id,
        page_id,
        brand,
        model,
        operate_system,
        CAST(k1 AS DATE) AS dt,
        during_time_1d,
        view_count_1d
    FROM dws.dws_traffic_page_visitor_page_view_1d_full
;

CREATE TEMPORARY VIEW tmp_dws_traffic_page_visitor_page_view_nd_page_view_agg AS
    SELECT
        pv.mid_id,
        pv.page_id,
        pv.brand,
        pv.model,
        pv.operate_system,
        SUM(CASE WHEN pv.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN pv.during_time_1d ELSE 0 END) AS during_time_7d,
        SUM(CASE WHEN pv.dt BETWEEN cp.cur_date - INTERVAL '6' DAY AND cp.cur_date THEN pv.view_count_1d ELSE 0 END) AS view_count_7d,
        SUM(pv.during_time_1d) AS during_time_30d,
        SUM(pv.view_count_1d) AS view_count_30d
    FROM tmp_dws_traffic_page_visitor_page_view_nd_page_view_1d pv
    CROSS JOIN tmp_dws_traffic_page_visitor_page_view_nd_current_date_param cp
    WHERE pv.dt BETWEEN cp.cur_date - INTERVAL '29' DAY AND cp.cur_date
    GROUP BY pv.mid_id, pv.page_id, pv.brand, pv.model, pv.operate_system
;

INSERT INTO dws.dws_traffic_page_visitor_page_view_nd_full(
    mid_id,
    page_id,
    k1,
    brand,
    model,
    operate_system,
    during_time_7d,
    view_count_7d,
    during_time_30d,
    view_count_30d
)
SELECT
    pa.mid_id,
    pa.page_id,
    CAST(cp.cur_date AS STRING) AS k1,
    pa.brand,
    pa.model,
    pa.operate_system,
    pa.during_time_7d,
    pa.view_count_7d,
    pa.during_time_30d,
    pa.view_count_30d
FROM tmp_dws_traffic_page_visitor_page_view_nd_page_view_agg pa
CROSS JOIN tmp_dws_traffic_page_visitor_page_view_nd_current_date_param cp;
