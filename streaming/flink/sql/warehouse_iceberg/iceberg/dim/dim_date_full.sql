SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.exec.resource.default-parallelism' = '1';
SET 'execution.runtime-mode' = 'batch';
SET 'execution.checkpointing.interval' = '10s';
SET 'table.exec.state.ttl'= '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer'='DROP';

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
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'dim_date',
      'server-time-zone' = 'Asia/Shanghai'
      );

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
CREATE DATABASE IF NOT EXISTS iceberg_dim;

CREATE TABLE IF NOT EXISTS iceberg_dim.dim_date_full(
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
      'catalog-name' = 'hadoop_prod'
    );

INSERT INTO iceberg_dim.dim_date_full /*+ OPTIONS('upsert-enabled' = 'true') */(
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
