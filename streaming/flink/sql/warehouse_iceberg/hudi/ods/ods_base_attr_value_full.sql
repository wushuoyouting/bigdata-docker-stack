SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'execution.checkpointing.interval' = '10s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';

CREATE TABLE base_attr_value_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `value_name` STRING NOT NULL COMMENT '属性值名称',
    `attr_id` BIGINT COMMENT '属性id',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'base_attr_value',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

USE CATALOG hudi_catalog;

CREATE DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_base_attr_value_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `value_name` STRING NOT NULL COMMENT '属性值名称',
    `attr_id` BIGINT COMMENT '属性id',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_base_attr_value_full(
    `id`,
    `value_name`,
    `attr_id`
)
SELECT
    `id`,
    `value_name`,
    `attr_id`
FROM default_catalog.default_database.base_attr_value_full_mq;
