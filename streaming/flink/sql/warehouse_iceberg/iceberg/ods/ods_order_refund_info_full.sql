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

CREATE TABLE order_refund_info_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `user_id` bigint  NULL COMMENT '用户id',
    `order_id` bigint  NULL COMMENT '订单id',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `refund_type` string  NULL COMMENT '退款类型',
    `refund_num` bigint  NULL COMMENT '退货件数',
    `refund_amount` decimal(16,2)  NULL COMMENT '退款金额',
    `refund_reason_type` string  NULL COMMENT '原因类型',
    `refund_reason_txt` string  NULL COMMENT '原因内容',
    `refund_status` string  NULL COMMENT '退款状态（0：待审批 1：已退款）',
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
      'table-name' = 'order_refund_info',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_order_refund_info_full(
    `id` bigint NOT NULL  COMMENT '购物券编号',
    `k1` STRING COMMENT '分区字段',
    `user_id` bigint  NULL COMMENT '用户id',
    `order_id` bigint  NULL COMMENT '订单id',
    `sku_id` bigint  NULL COMMENT 'skuid',
    `refund_type` string  NULL COMMENT '退款类型',
    `refund_num` bigint  NULL COMMENT '退货件数',
    `refund_amount` decimal(16,2)  NULL COMMENT '退款金额',
    `refund_reason_type` string  NULL COMMENT '原因类型',
    `refund_reason_txt` string  NULL COMMENT '原因内容',
    `refund_status` string  NULL COMMENT '退款状态（0：待审批 1：已退款）',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
    ) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_order_refund_info_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `k1`,
    `user_id`,
    `order_id`,
    `sku_id`,
    `refund_type`,
    `refund_num`,
    `refund_amount`,
    `refund_reason_type`,
    `refund_reason_txt`,
    `refund_status`,
    `create_time`
)
select
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `user_id`,
    `order_id`,
    `sku_id`,
    `refund_type`,
    `refund_num`,
    `refund_amount`,
    `refund_reason_type`,
    `refund_reason_txt`,
    `refund_status`,
    `create_time`
from default_catalog.default_database.order_refund_info_full_mq
where create_time is not null;
