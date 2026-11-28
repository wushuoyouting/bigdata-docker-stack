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

CREATE TABLE spu_image_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `spu_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '图片名称',
    `img_url` STRING COMMENT '图片路径',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'spu_image',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

USE CATALOG hudi_catalog;

CREATE DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_spu_image_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `spu_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '图片名称',
    `img_url` STRING COMMENT '图片路径',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_spu_image_full(
    `id`,
    `spu_id`,
    `img_name`,
    `img_url`
)
SELECT
    `id`,
    `spu_id`,
    `img_name`,
    `img_url`
FROM default_catalog.default_database.spu_image_full_mq;
