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

CREATE TABLE sku_attr_value_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `attr_id` bigint  NULL COMMENT '属性id（冗余)',
    `value_id` bigint  NULL COMMENT '属性值id',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `attr_name` string  NULL COMMENT '属性名',
    `value_name` string  NULL COMMENT '属性值名称',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'sku_attr_value',
    'server-time-zone' = 'Asia/Shanghai'
      );

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

use CATALOG hudi_catalog;

create  DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_sku_attr_value_full(
    `id` bigint NOT NULL  COMMENT '编号',
    `attr_id` bigint  NULL COMMENT '属性id（冗余)',
    `value_id` bigint  NULL COMMENT '属性值id',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `attr_name` string  NULL COMMENT '属性名',
    `value_name` string  NULL COMMENT '属性值名称',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
    );

INSERT INTO hudi_ods.ods_sku_attr_value_full(
    `id`,
    `attr_id`,
    `value_id`,
    `sku_id`,
    `attr_name`,
    `value_name`
)
select
    `id`,
    `attr_id`,
    `value_id`,
    `sku_id`,
    `attr_name`,
    `value_name`
from default_catalog.default_database.sku_attr_value_full_mq;
