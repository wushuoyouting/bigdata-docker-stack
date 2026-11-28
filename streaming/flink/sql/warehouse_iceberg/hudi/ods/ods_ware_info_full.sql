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

CREATE TABLE ware_info_full_mq (
    `id` BIGINT NOT NULL COMMENT 'id',
    `name` STRING COMMENT 'name',
    `address` STRING COMMENT 'address',
    `areacode` STRING COMMENT 'areacode',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'ware_info',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

USE CATALOG hudi_catalog;

CREATE DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_ware_info_full(
    `id` BIGINT NOT NULL COMMENT 'id',
    `name` STRING COMMENT 'name',
    `address` STRING COMMENT 'address',
    `areacode` STRING COMMENT 'areacode',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_ware_info_full(
    `id`,
    `name`,
    `address`,
    `areacode`
)
SELECT
    `id`,
    `name`,
    `address`,
    `areacode`
FROM default_catalog.default_database.ware_info_full_mq;
