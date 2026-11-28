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

CREATE TABLE activity_rule_full_mq (
   `id` int NOT NULL  COMMENT '编号',
   `activity_id` int  NULL COMMENT '类型',
   `activity_type` STRING  NULL COMMENT '活动类型',
   `condition_amount` decimal(16,2)  NULL COMMENT '满减金额',
   `condition_num` BIGINT  NULL COMMENT '满减件数',
   `benefit_amount` decimal(16,2)  NULL COMMENT '优惠金额',
   `benefit_discount` decimal(10,2)  NULL COMMENT '优惠折扣',
   `benefit_level` BIGINT  NULL COMMENT '优惠级别',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'activity_rule',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_activity_rule_full(
    `id`               INT COMMENT '编号',
    `activity_id`      INT COMMENT '类型',
    `activity_type`    STRING COMMENT '活动类型',
    `condition_amount` DECIMAL(16, 2) COMMENT '满减金额',
    `condition_num`    BIGINT COMMENT '满减件数',
    `benefit_amount`   DECIMAL(16, 2) COMMENT '优惠金额',
    `benefit_discount` DECIMAL(16, 2) COMMENT '优惠折扣',
    `benefit_level`    BIGINT COMMENT '优惠级别',
    PRIMARY KEY (`id`) NOT ENFORCED
    ) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_activity_rule_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `activity_id`,
    `activity_type`,
    `condition_amount`,
    `condition_num`,
    `benefit_amount`,
    `benefit_discount`,
    `benefit_level`
)
select
    `id`,
    `activity_id`,
    `activity_type`,
    `condition_amount`,
    `condition_num`,
    `benefit_amount`,
    `benefit_discount`,
    `benefit_level`
from default_catalog.default_database.activity_rule_full_mq;
