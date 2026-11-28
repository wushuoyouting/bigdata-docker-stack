SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.dynamic-table-options.enabled' = 'true';
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '10s';
SET 'table.exec.state.ttl'= '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer'='DROP';
SET 'pipeline.name' = 'paimon_dim_stream_dim_date_full';

CREATE TABLE dim_date_full (
    `date_id`    VARCHAR(255) COMMENT '日期ID',
    `week_id`    int COMMENT '周ID,一年中的第几周',
    `week_day`   int COMMENT '周几',
    `day`        int COMMENT '每月的第几天',
    `month`      int COMMENT '一年中的第几月',
    `quarter`    int COMMENT '一年中的第几季度',
    `year`       int COMMENT '年份',
    `is_workday` int COMMENT '是否是工作日',
    `holiday_id` VARCHAR(255) COMMENT '节假日',
    PRIMARY KEY(`date_id`) NOT ENFORCED
) WITH (
    'connector' = 'paimon',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true'
);

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
create  DATABASE IF NOT EXISTS dim_stream;

CREATE TABLE IF NOT EXISTS dim_stream.dim_date_full(
    `date_id`    VARCHAR(255) COMMENT '日期ID',
    `week_id`    int COMMENT '周ID,一年中的第几周',
    `week_day`   int COMMENT '周几',
    `day`        int COMMENT '每月的第几天',
    `month`      int COMMENT '一年中的第几月',
    `quarter`    int COMMENT '一年中的第几季度',
    `year`       int COMMENT '年份',
    `is_workday` int COMMENT '是否是工作日',
    `holiday_id` VARCHAR(255) COMMENT '节假日',
    PRIMARY KEY (`date_id` ) NOT ENFORCED
    ) WITH (
      'connector' = 'paimon',
      'file.format' = 'parquet',
      'write-buffer-size' = '512mb',
      'write-buffer-spillable' = 'true'
    );

INSERT INTO dim_stream.dim_date_full(
    `date_id`,
    `week_id`,
    `week_day`,
    `day`,
    `month`,
    `quarter`,
    `year`,
    `is_workday`,
    `holiday_id`
    )
select
    `date_id`,
    `week_id`,
    `week_day`,
    `day`,
    `month`,
    `quarter`,
    `year`,
    `is_workday`,
    `holiday_id`
from default_catalog.default_database.dim_date_full;


