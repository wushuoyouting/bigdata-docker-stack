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

CREATE TABLE favor_info_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `user_id` bigint  NULL COMMENT '用户名称',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `spu_id` bigint  NULL COMMENT '商品id',
    `is_cancel` string  NULL COMMENT '是否已取消 0 正常 1 已取消',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    `cancel_time` timestamp(3)  NULL COMMENT '修改时间',
     PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'favor_info',
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

CREATE TABLE IF NOT EXISTS ods.ods_favor_info_full(
    `id` bigint NOT NULL  COMMENT '购物券编号',
    `k1` STRING COMMENT '分区字段',
    `user_id` bigint  NULL COMMENT '用户名称',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `spu_id` bigint  NULL COMMENT '商品id',
    `is_cancel` string  NULL COMMENT '是否已取消 0 正常 1 已取消',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    `cancel_time` timestamp(3)  NULL COMMENT '修改时间',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
    ) PARTITIONED BY (`k1`) WITH (
    'connector' = 'paimon',
    'metastore.partitioned-table' = 'true',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true',
    'partition.expiration-time' = '1 d',
    'partition.expiration-check-interval' = '1 h',
    'partition.timestamp-formatter' = 'yyyy-MM-dd',
    'partition.timestamp-pattern' = '$k1'
);

INSERT INTO ods.ods_favor_info_full(
    `id`,
    `k1`,
    `user_id`,
    `sku_id`,
    `spu_id`,
    `is_cancel`,
    `create_time`,
    `cancel_time`
)
select
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `user_id`,
    `sku_id`,
    `spu_id`,
    `is_cancel`,
    `create_time`,
    `cancel_time`
from default_catalog.default_database.favor_info_full_mq
where create_time is not null;
