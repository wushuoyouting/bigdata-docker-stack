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

CREATE TABLE sku_image_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `sku_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '图片名称（冗余）',
    `img_url` STRING COMMENT '图片路径(冗余)',
    `spu_img_id` BIGINT COMMENT '商品图片id',
    `is_default` STRING COMMENT '是否默认',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'sku_image',
    'server-time-zone' = 'Asia/Shanghai'
);

CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-impl' = 'org.apache.iceberg.jdbc.JdbcCatalog',
    'uri' = 'jdbc:postgresql://host.docker.internal:5432/iceberg_meta',
    'jdbc.user' = 'root',
    'jdbc.password' = '123456',
    'warehouse' = 's3://lakehouse/iceberg/',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minio:9000',
    's3.access-key-id' = 'ak6c52d75066d96ddd',
    's3.secret-access-key' = '5cf0fa1d0e1fd9bf182be642beca1a15',
    's3.region' = 'us-east-1',
    's3.path-style-access' = 'true'
);
USE CATALOG iceberg_catalog;
CREATE DATABASE IF NOT EXISTS iceberg_ods;

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_sku_image_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `sku_id` BIGINT COMMENT '商品id',
    `img_name` STRING COMMENT '图片名称（冗余）',
    `img_url` STRING COMMENT '图片路径(冗余)',
    `spu_img_id` BIGINT COMMENT '商品图片id',
    `is_default` STRING COMMENT '是否默认',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_sku_image_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `sku_id`,
    `img_name`,
    `img_url`,
    `spu_img_id`,
    `is_default`
)
SELECT
    `id`,
    `sku_id`,
    `img_name`,
    `img_url`,
    `spu_img_id`,
    `is_default`
FROM default_catalog.default_database.sku_image_full_mq;

