SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'execution.checkpointing.interval' = '10s';
SET 'table.exec.state.ttl'= '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer'='DROP';

CREATE TABLE activity_info_full_mq (
    `id` bigint NOT NULL COMMENT '活动id',
    `activity_name` STRING NULL COMMENT '活动名称',
    `activity_type` STRING NULL COMMENT '活动类型',
    `activity_desc` STRING NULL COMMENT '活动描述',
    `start_time` TIMESTAMP(3) NULL COMMENT '开始时间',
    `end_time` TIMESTAMP(3) NULL COMMENT '结束时间',
    `create_time` TIMESTAMP(3) NULL  COMMENT '创建时间',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'activity_info',
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
CREATE DATABASE IF NOT EXISTS iceberg_ods;

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_activity_info_full(
    `id`            BIGINT COMMENT '活动id',
    `k1`            STRING COMMENT '分区字段',
    `activity_name` STRING COMMENT '活动名称',
    `activity_type` STRING COMMENT '活动类型',
    `activity_desc` STRING COMMENT '活动描述',
    `start_time`    STRING COMMENT '开始时间',
    `end_time`      STRING COMMENT '结束时间',
    `create_time`   STRING COMMENT '创建时间',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_activity_info_full /*+ OPTIONS('upsert-enabled' = 'true') */(`id`, `k1` , `activity_name`, `activity_type`, `activity_desc`, `start_time`, `end_time`, `create_time`)
select
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    activity_name,
    activity_type,
    activity_desc,
    DATE_FORMAT(start_time, 'yyyy-MM-dd HH:mm:ss') AS start_time,
    DATE_FORMAT(end_time, 'yyyy-MM-dd HH:mm:ss') AS end_time,
    DATE_FORMAT(create_time, 'yyyy-MM-dd HH:mm:ss') AS create_time
from default_catalog.default_database.activity_info_full_mq
where create_time is not null;
