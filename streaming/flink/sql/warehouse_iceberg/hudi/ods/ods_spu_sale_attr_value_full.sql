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

CREATE TABLE spu_sale_attr_value_full_mq (
    `id` BIGINT NOT NULL COMMENT '销售属性值编号',
    `spu_id` BIGINT COMMENT '商品id',
    `base_sale_attr_id` BIGINT COMMENT '销售属性id',
    `sale_attr_value_name` STRING COMMENT '销售属性值名称',
    `sale_attr_name` STRING COMMENT '销售属性名称(冗余)',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'spu_sale_attr_value',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

USE CATALOG hudi_catalog;

CREATE DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_spu_sale_attr_value_full(
    `id` BIGINT NOT NULL COMMENT '销售属性值编号',
    `spu_id` BIGINT COMMENT '商品id',
    `base_sale_attr_id` BIGINT COMMENT '销售属性id',
    `sale_attr_value_name` STRING COMMENT '销售属性值名称',
    `sale_attr_name` STRING COMMENT '销售属性名称(冗余)',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_spu_sale_attr_value_full(
    `id`,
    `spu_id`,
    `base_sale_attr_id`,
    `sale_attr_value_name`,
    `sale_attr_name`
)
SELECT
    `id`,
    `spu_id`,
    `base_sale_attr_id`,
    `sale_attr_value_name`,
    `sale_attr_name`
FROM default_catalog.default_database.spu_sale_attr_value_full_mq;
