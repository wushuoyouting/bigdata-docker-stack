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

CREATE TABLE base_trademark_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `tm_name` STRING NOT NULL COMMENT '属性值',
    `logo_url` STRING NULL COMMENT '品牌logo的图片路径',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'base_trademark',
      'server-time-zone' = 'Asia/Shanghai'
      );

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

use CATALOG hudi_catalog;

create  DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_base_trademark_full(
    `id` bigint NOT NULL  COMMENT '编号',
    `tm_name` STRING NOT NULL COMMENT '属性值',
    `logo_url` STRING NULL COMMENT '品牌logo的图片路径',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
    );

INSERT INTO hudi_ods.ods_base_trademark_full(
    `id` ,
    `tm_name` ,
    `logo_url`
)
select
    `id` ,
    `tm_name` ,
    `logo_url`
from default_catalog.default_database.base_trademark_full_mq;
