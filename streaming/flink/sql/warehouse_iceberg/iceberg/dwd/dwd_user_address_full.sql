SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.exec.resource.default-parallelism' = '1';
SET 'execution.runtime-mode' = 'batch';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';

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
CREATE DATABASE IF NOT EXISTS iceberg_dwd;

CREATE TABLE IF NOT EXISTS iceberg_dwd.dwd_user_address_full(
    `id` STRING COMMENT '编号',
    `k1` STRING COMMENT '分区字段',
    `user_id` STRING COMMENT '用户ID',
    `province_id` STRING COMMENT '省份ID',
    `province_name` STRING COMMENT '省份名称',
    `city_id` STRING COMMENT '城市ID',
    `city_name` STRING COMMENT '城市名称',
    `district_id` STRING COMMENT '区县ID',
    `district_name` STRING COMMENT '区县名称',
    `detail_address` STRING COMMENT '详细地址',
    `consignee` STRING COMMENT '收货人',
    `phone_num` STRING COMMENT '电话号码',
    `is_default` STRING COMMENT '是否默认地址',
    `create_time` STRING COMMENT '创建时间',
    `operate_time` STRING COMMENT '操作时间',
    `postal_code` STRING COMMENT '邮政编码',
    `full_address` STRING COMMENT '完整地址',
    PRIMARY KEY (`id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_dwd.dwd_user_address_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    id,
    k1,
    user_id,
    province_id,
    province_name,
    city_id,
    city_name,
    district_id,
    district_name,
    detail_address,
    consignee,
    phone_num,
    is_default,
    create_time,
    operate_time,
    postal_code,
    full_address
)
SELECT
    CAST(ua.id AS STRING) AS id,
    DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd') AS k1,
    COALESCE(CAST(ua.user_id AS STRING), '') AS user_id,
    COALESCE(CAST(ua.province_id AS STRING), '') AS province_id,
    COALESCE(bp.name, '') AS province_name,
    COALESCE(CAST(ua.province_id AS STRING), '') AS city_id,
    COALESCE(bp.area_code, '') AS city_name,
    COALESCE(CAST(ua.province_id AS STRING), '') AS district_id,
    COALESCE(bp.iso_code, '') AS district_name,
    COALESCE(ua.user_address, '') AS detail_address,
    COALESCE(ua.consignee, '') AS consignee,
    COALESCE(ua.phone_num, '') AS phone_num,
    COALESCE(ua.is_default, '') AS is_default,
    CONCAT(DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd'), ' 00:00:00') AS create_time,
    CONCAT(DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd'), ' 00:00:00') AS operate_time,
    CAST(NULL AS STRING) AS postal_code,
    CONCAT_WS(' ', bp.name, bp.area_code, bp.iso_code, ua.user_address) AS full_address
FROM iceberg_ods.ods_user_address_full ua
LEFT JOIN iceberg_ods.ods_base_province_full bp
    ON ua.province_id = bp.id;
