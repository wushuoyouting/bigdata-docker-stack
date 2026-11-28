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

CREATE TABLE base_category2_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `name` STRING  NOT NULL COMMENT '二级分类名称',
    `category1_id` bigint NULL COMMENT '一级分类编号',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'base_category2',
      'server-time-zone' = 'Asia/Shanghai'
      );

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

use CATALOG hudi_catalog;

create  DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_base_category2_full(
    `id` bigint NOT NULL  COMMENT '编号',
    `name` STRING  NOT NULL COMMENT '二级分类名称',
    `category1_id` bigint NULL COMMENT '一级分类编号',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
    );

INSERT INTO hudi_ods.ods_base_category2_full(`id`, `name`, `category1_id`)
select
    id,
    name,
    category1_id
from default_catalog.default_database.base_category2_full_mq;
