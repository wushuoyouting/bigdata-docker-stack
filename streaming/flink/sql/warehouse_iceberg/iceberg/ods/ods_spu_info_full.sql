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

CREATE TABLE spu_info_full_mq (
    `id` bigint NOT NULL  COMMENT '商品id',
    `spu_name` string  NULL COMMENT '商品名称',
    `description` string  NULL COMMENT '商品描述(后台简述）',
    `category3_id` bigint  NULL COMMENT '三级分类id',
    `tm_id` bigint  NULL COMMENT '品牌id',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'spu_info',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_spu_info_full(
    `id` bigint NOT NULL  COMMENT '商品id',
    `spu_name` string  NULL COMMENT '商品名称',
    `description` string  NULL COMMENT '商品描述(后台简述）',
    `category3_id` bigint  NULL COMMENT '三级分类id',
    `tm_id` bigint  NULL COMMENT '品牌id',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_spu_info_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `spu_name`,
    `description`,
    `category3_id`,
    `tm_id`
)
select
    `id`,
    `spu_name`,
    `description`,
    `category3_id`,
    `tm_id`
from default_catalog.default_database.spu_info_full_mq;
