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

CREATE TABLE coupon_range_full_mq (
    `id` BIGINT NOT NULL COMMENT 'id',
    `coupon_id` BIGINT NOT NULL COMMENT 'coupon id',
    `range_type` STRING NOT NULL COMMENT 'range type',
    `range_id` BIGINT NOT NULL COMMENT 'range id',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'coupon_range',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG hudi_catalog WITH (
    'type' = 'hudi',
    'mode' = 'dfs',
    'path' = 's3a://lakehouse/hudi'
);

use CATALOG hudi_catalog;

create DATABASE IF NOT EXISTS hudi_ods;

CREATE TABLE IF NOT EXISTS hudi_ods.ods_coupon_range_full(
    `id` BIGINT NOT NULL COMMENT 'id',
    `coupon_id` BIGINT NOT NULL COMMENT 'coupon id',
    `range_type` STRING NOT NULL COMMENT 'range type',
    `range_id` BIGINT NOT NULL COMMENT 'range id',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'read.streaming.enabled' = 'true',
    'read.streaming.check-interval' = '4'
);

INSERT INTO hudi_ods.ods_coupon_range_full(
    `id`,
    `coupon_id`,
    `range_type`,
    `range_id`
)
select
    id,
    coupon_id,
    range_type,
    range_id
from default_catalog.default_database.coupon_range_full_mq;
