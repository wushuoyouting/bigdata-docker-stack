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

CREATE TABLE spu_poster_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `spu_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '文件名称',
    `img_url` STRING COMMENT '文件路径',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `update_time` TIMESTAMP(3) NOT NULL COMMENT '更新时间',
    `is_deleted` INT NOT NULL COMMENT '逻辑删除 1（true）已删除， 0（false）未删除',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'spu_poster',
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

CREATE TABLE IF NOT EXISTS ods.ods_spu_poster_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `k1` STRING COMMENT 'partition field',
    `spu_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '文件名称',
    `img_url` STRING COMMENT '文件路径',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `update_time` TIMESTAMP(3) NOT NULL COMMENT '更新时间',
    `is_deleted` INT NOT NULL COMMENT '逻辑删除 1（true）已删除， 0（false）未删除',
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

INSERT INTO ods.ods_spu_poster_full(
    `id`,
    `k1`,
    `spu_id`,
    `img_name`,
    `img_url`,
    `create_time`,
    `update_time`,
    `is_deleted`
)
SELECT
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `spu_id`,
    `img_name`,
    `img_url`,
    `create_time`,
    `update_time`,
    `is_deleted`
FROM default_catalog.default_database.spu_poster_full_mq
WHERE create_time IS NOT NULL;

