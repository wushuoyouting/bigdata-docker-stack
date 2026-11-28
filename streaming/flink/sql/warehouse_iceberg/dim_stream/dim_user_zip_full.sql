SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.dynamic-table-options.enabled' = 'true';
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
SET 'pipeline.name' = 'iceberg_dim_stream_dim_user_zip_full';

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
create DATABASE IF NOT EXISTS iceberg_dim_stream;

CREATE TABLE IF NOT EXISTS iceberg_dim_stream.dim_user_zip_full(
    `id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `login_name` STRING COMMENT 'login name',
    `nick_name` STRING COMMENT 'nick name',
    `name` STRING COMMENT 'name',
    `phone_num` STRING COMMENT 'phone num',
    `email` STRING COMMENT 'email',
    `user_level` STRING COMMENT 'user level',
    `birthday` STRING COMMENT 'birthday',
    `gender` STRING COMMENT 'gender',
    `create_time` TIMESTAMP(3) COMMENT 'create time',
    `operate_time` TIMESTAMP(3) COMMENT 'operate time',
    `start_date` CHAR(10) COMMENT 'start date',
    `end_date` CHAR(10) COMMENT 'end date',
    PRIMARY KEY (`id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

insert into iceberg_dim_stream.dim_user_zip_full(
    id,
    k1,
    login_name,
    nick_name,
    name,
    phone_num,
    email,
    user_level,
    birthday,
    gender,
    create_time,
    operate_time,
    start_date,
    end_date
)
select
    id,
    k1,
    login_name,
    nick_name,
    md5(name),
    md5(phone_num),
    md5(email),
    user_level,
    birthday,
    gender,
    create_time,
    operate_time,
    '2020-06-14' as start_date,
    '9999-12-31' as end_date
from iceberg_ods.ods_user_info_full;


