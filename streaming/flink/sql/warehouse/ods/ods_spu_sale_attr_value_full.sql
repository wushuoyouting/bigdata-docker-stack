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
CREATE DATABASE IF NOT EXISTS ods;

CREATE TABLE IF NOT EXISTS ods.ods_spu_sale_attr_value_full(
    `id` BIGINT NOT NULL COMMENT '销售属性值编号',
    `spu_id` BIGINT COMMENT '商品id',
    `base_sale_attr_id` BIGINT COMMENT '销售属性id',
    `sale_attr_value_name` STRING COMMENT '销售属性值名称',
    `sale_attr_name` STRING COMMENT '销售属性名称(冗余)',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'paimon',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true'
);

INSERT INTO ods.ods_spu_sale_attr_value_full(
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

