SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.dynamic-table-options.enabled' = 'true';
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl'= '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer'='DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
SET 'pipeline.name' = 'iceberg_dwd_stream_dwd_interaction_comment_full';

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
create  DATABASE IF NOT EXISTS iceberg_dwd_stream;

CREATE TABLE IF NOT EXISTS iceberg_dwd_stream.dwd_interaction_comment_full(
    `id`            BIGINT COMMENT '编号',
    `k1`            STRING COMMENT '分区字段',
    `user_id`       BIGINT COMMENT '用户ID',
    `sku_id`        BIGINT COMMENT 'sku_id',
    `order_id`      BIGINT COMMENT '订单ID',
    `date_id`       STRING COMMENT '日期ID',
    `create_time`   timestamp(3) COMMENT '评价时间',
    `appraise_code` STRING COMMENT '评价编码',
    `appraise_name` STRING COMMENT '评价名称',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
    ) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);


insert into iceberg_dwd_stream.dwd_interaction_comment_full(
    id,
    k1,
    user_id,
    sku_id,
    order_id,
    date_id,
    create_time,
    appraise_code,
    appraise_name
)
select
    id,
    k1,
    user_id,
    sku_id,
    order_id,
    date_format(create_time,'yyyy-MM-dd') date_id,
    create_time,
    appraise,
    dic_name
from
    (
        select
            id,
            k1,
            user_id,
            sku_id,
            order_id,
            create_time,
            appraise
        from iceberg_ods.ods_comment_info_full
    )ci
        left join
    (
        select
            dic_code,
            dic_name
        from iceberg_ods.ods_base_dic_full
    )dic
    on ci.appraise=dic.dic_code;


