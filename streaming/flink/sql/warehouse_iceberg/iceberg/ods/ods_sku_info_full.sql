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

CREATE TABLE sku_info_full_mq (
    `id` bigint NOT NULL  COMMENT '库存id(itemID)',
    `spu_id` bigint  NULL COMMENT '商品id',
    `price` decimal(10,0)  NULL COMMENT '价格',
    `sku_name` string  NULL COMMENT 'sku名称',
    `sku_desc` string  NULL COMMENT '商品规格描述',
    `weight` decimal(10,2)  NULL COMMENT '重量',
    `tm_id` bigint  NULL COMMENT '品牌(冗余)',
    `category3_id` bigint  NULL COMMENT '三级分类id（冗余)',
    `sku_default_img` string NULL COMMENT '默认显示图片(冗余)',
    `is_sale` int NOT NULL   COMMENT '是否销售（1：是 0：否）',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
     PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'sku_info',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_sku_info_full(
    `id` bigint NOT NULL  COMMENT '购物券编号',
    `k1` STRING COMMENT '分区字段',
    `spu_id` bigint  NULL COMMENT '商品id',
    `price` decimal(10,0)  NULL COMMENT '价格',
    `sku_name` string  NULL COMMENT 'sku名称',
    `sku_desc` string NULL COMMENT '商品规格描述',
    `weight` decimal(10,2)  NULL COMMENT '重量',
    `tm_id` bigint  NULL COMMENT '品牌(冗余)',
    `category3_id` bigint  NULL COMMENT '三级分类id（冗余)',
    `sku_default_img` string NULL COMMENT '默认显示图片(冗余)',
    `is_sale` int NOT NULL  COMMENT '是否销售（1：是 0：否）',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
    ) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_sku_info_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `k1`,
    `spu_id`,
    `price`,
    `sku_name`,
    `sku_desc`,
    `weight`,
    `tm_id`,
    `category3_id`,
    `sku_default_img`,
    `is_sale`,
    `create_time`
)
select
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `spu_id`,
    `price`,
    `sku_name`,
    `sku_desc`,
    `weight`,
    `tm_id`,
    `category3_id`,
    `sku_default_img`,
    `is_sale`,
    `create_time`
from default_catalog.default_database.sku_info_full_mq
where create_time is not null;
