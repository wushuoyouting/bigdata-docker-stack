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

CREATE TABLE seckill_goods_full_mq (
    `id` BIGINT NOT NULL COMMENT 'id',
    `spu_id` BIGINT COMMENT 'spu_id',
    `sku_id` BIGINT COMMENT 'sku_id',
    `sku_name` STRING COMMENT '标题',
    `sku_default_img` STRING COMMENT '商品图片',
    `price` DECIMAL(10,2) COMMENT '原价格',
    `cost_price` DECIMAL(10,2) COMMENT '秒杀价格',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `check_time` TIMESTAMP(3) COMMENT '审核日期',
    `status` STRING COMMENT '审核状态',
    `start_time` TIMESTAMP(3) COMMENT '开始时间',
    `end_time` TIMESTAMP(3) COMMENT '结束时间',
    `num` INT COMMENT '秒杀商品数',
    `stock_count` INT COMMENT '剩余库存数',
    `sku_desc` STRING COMMENT '描述',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'seckill_goods',
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

CREATE TABLE IF NOT EXISTS ods.ods_seckill_goods_full(
    `id` BIGINT NOT NULL COMMENT 'id',
    `k1` STRING COMMENT 'partition field',
    `spu_id` BIGINT COMMENT 'spu_id',
    `sku_id` BIGINT COMMENT 'sku_id',
    `sku_name` STRING COMMENT '标题',
    `sku_default_img` STRING COMMENT '商品图片',
    `price` DECIMAL(10,2) COMMENT '原价格',
    `cost_price` DECIMAL(10,2) COMMENT '秒杀价格',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `check_time` TIMESTAMP(3) COMMENT '审核日期',
    `status` STRING COMMENT '审核状态',
    `start_time` TIMESTAMP(3) COMMENT '开始时间',
    `end_time` TIMESTAMP(3) COMMENT '结束时间',
    `num` INT COMMENT '秒杀商品数',
    `stock_count` INT COMMENT '剩余库存数',
    `sku_desc` STRING COMMENT '描述',
    PRIMARY KEY (`id`, `k1`) NOT ENFORCED
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

INSERT INTO ods.ods_seckill_goods_full(
    `id`,
    `k1`,
    `spu_id`,
    `sku_id`,
    `sku_name`,
    `sku_default_img`,
    `price`,
    `cost_price`,
    `create_time`,
    `check_time`,
    `status`,
    `start_time`,
    `end_time`,
    `num`,
    `stock_count`,
    `sku_desc`
)
SELECT
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `spu_id`,
    `sku_id`,
    `sku_name`,
    `sku_default_img`,
    `price`,
    `cost_price`,
    `create_time`,
    `check_time`,
    `status`,
    `start_time`,
    `end_time`,
    `num`,
    `stock_count`,
    `sku_desc`
FROM default_catalog.default_database.seckill_goods_full_mq
WHERE create_time IS NOT NULL;

