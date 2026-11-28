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

CREATE TABLE ware_order_task_full_mq (
    `id` BIGINT NOT NULL COMMENT '编号',
    `order_id` BIGINT COMMENT '订单编号',
    `consignee` STRING COMMENT '收货人',
    `consignee_tel` STRING COMMENT '收货人电话',
    `delivery_address` STRING COMMENT '送货地址',
    `order_comment` STRING COMMENT '订单备注',
    `payment_way` STRING COMMENT '付款方式 1:在线付款 2:货到付款',
    `task_status` STRING COMMENT '工作单状态',
    `order_body` STRING COMMENT '订单描述',
    `tracking_no` STRING COMMENT '物流单号',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `ware_id` BIGINT COMMENT '仓库编号',
    `task_comment` STRING COMMENT '工作单备注',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'ware_order_task',
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

CREATE TABLE IF NOT EXISTS iceberg_ods.ods_ware_order_task_full(
    `id` BIGINT NOT NULL COMMENT '编号',
    `k1` STRING COMMENT 'partition field',
    `order_id` BIGINT COMMENT '订单编号',
    `consignee` STRING COMMENT '收货人',
    `consignee_tel` STRING COMMENT '收货人电话',
    `delivery_address` STRING COMMENT '送货地址',
    `order_comment` STRING COMMENT '订单备注',
    `payment_way` STRING COMMENT '付款方式 1:在线付款 2:货到付款',
    `task_status` STRING COMMENT '工作单状态',
    `order_body` STRING COMMENT '订单描述',
    `tracking_no` STRING COMMENT '物流单号',
    `create_time` TIMESTAMP(3) NOT NULL COMMENT '创建时间',
    `ware_id` BIGINT COMMENT '仓库编号',
    `task_comment` STRING COMMENT '工作单备注',
    PRIMARY KEY (`id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ods.ods_ware_order_task_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    `id`,
    `k1`,
    `order_id`,
    `consignee`,
    `consignee_tel`,
    `delivery_address`,
    `order_comment`,
    `payment_way`,
    `task_status`,
    `order_body`,
    `tracking_no`,
    `create_time`,
    `ware_id`,
    `task_comment`
)
SELECT
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `order_id`,
    `consignee`,
    `consignee_tel`,
    `delivery_address`,
    `order_comment`,
    `payment_way`,
    `task_status`,
    `order_body`,
    `tracking_no`,
    `create_time`,
    `ware_id`,
    `task_comment`
FROM default_catalog.default_database.ware_order_task_full_mq
WHERE create_time IS NOT NULL;

