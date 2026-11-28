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

CREATE TABLE user_address_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `user_id` BIGINT COMMENT '用户id',
    `province_id` BIGINT COMMENT '省份id',
    `user_address` STRING COMMENT '用户地址',
    `consignee` STRING COMMENT '收件人',
    `phone_num` STRING COMMENT '联系方式',
    `is_default` STRING COMMENT '是否是默认',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'user_address',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_user_address_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `user_id` BIGINT COMMENT '用户id',
    `province_id` BIGINT COMMENT '省份id',
    `user_address` STRING COMMENT '用户地址',
    `consignee` STRING COMMENT '收件人',
    `phone_num` STRING COMMENT '联系方式',
    `is_default` STRING COMMENT '是否是默认',
    PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_user_address_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `user_id`,
    `province_id`,
    `user_address`,
    `consignee`,
    `phone_num`,
    `is_default`
)
SELECT
    `id`,
    `user_id`,
    `province_id`,
    `user_address`,
    `consignee`,
    `phone_num`,
    `is_default`
FROM default_catalog.default_database.user_address_full_mq;

