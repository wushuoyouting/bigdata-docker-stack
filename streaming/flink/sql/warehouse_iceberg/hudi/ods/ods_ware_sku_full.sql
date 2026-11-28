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

CREATE TABLE ware_sku_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `sku_id` BIGINT COMMENT 'skuid',
    `warehouse_id` BIGINT COMMENT '仓库id',
    `stock` INT COMMENT '库存数',
    `stock_name` STRING COMMENT '存货名称',
    `stock_locked` INT COMMENT '锁定库存数',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'ware_sku',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

USE CATALOG hudi_catalog;

CREATE DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_ware_sku_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `sku_id` BIGINT COMMENT 'skuid',
    `warehouse_id` BIGINT COMMENT '仓库id',
    `stock` INT COMMENT '库存数',
    `stock_name` STRING COMMENT '存货名称',
    `stock_locked` INT COMMENT '锁定库存数',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_ware_sku_full(
    `id`,
    `sku_id`,
    `warehouse_id`,
    `stock`,
    `stock_name`,
    `stock_locked`
)
SELECT
    `id`,
    `sku_id`,
    `warehouse_id`,
    `stock`,
    `stock_name`,
    `stock_locked`
FROM default_catalog.default_database.ware_sku_full_mq;
