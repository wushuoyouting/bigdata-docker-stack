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

CREATE TABLE base_category1_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `name` STRING  NOT NULL COMMENT '分类名称',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'base_category1',
      'server-time-zone' = 'Asia/Shanghai'
      );

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

use CATALOG hudi_catalog;

create  DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_base_category1_full(
    `id`   bigint COMMENT '编号',
    `name` STRING COMMENT '分类名称',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
    );

INSERT INTO hudi_ods.ods_base_category1_full(`id`, `name`)
select
    id,
    name
from default_catalog.default_database.base_category1_full_mq;
