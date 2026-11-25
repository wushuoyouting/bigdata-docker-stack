SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl'= '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer'='DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';

CREATE CATALOG paimon_minio WITH (
    'type' = 'paimon',
    'metastore' = 'filesystem',
    'warehouse' = 's3://lakehouse/paimon',
    's3.endpoint' = 'http://minio:9000',
    's3.access-key' = 'ak6c52d75066d96ddd',
    's3.secret-key' = '5cf0fa1d0e1fd9bf182be642beca1a15',
    's3.path.style.access' = 'true'
);
USE CATALOG paimon_minio;
CREATE DATABASE IF NOT EXISTS dwd;

CREATE TABLE IF NOT EXISTS dwd.dwd_tool_coupon_get_full(
    `id`        BIGINT COMMENT '编号',
    `k1`        STRING COMMENT '分区字段',
    `coupon_id` BIGINT COMMENT '优惠券ID',
    `user_id`   BIGINT COMMENT 'userid',
    `date_id`   STRING COMMENT '日期ID',
    `get_time`  timestamp(3) COMMENT '领取时间',
    PRIMARY KEY (`id`,`k1` ) NOT ENFORCED
    ) PARTITIONED BY (`k1`) WITH (
    'connector' = 'paimon',
    'metastore.partitioned-table' = 'true',
    'file.format' = 'parquet',
    'write-buffer-size' = '512mb',
    'write-buffer-spillable' = 'true',
    'partition.expiration-time' = '1 d',
    'partition.expiration-check-interval' = '1 h',
    'partition.timestamp-formatter' = 'yyyy-MM-dd',
    'partition.timestamp-pattern' = '$k1'
);


insert into dwd.dwd_tool_coupon_get_full(
    id,
    k1,
    coupon_id,
    user_id,
    date_id,
    get_time
)
select
    id,
    k1,
    coupon_id,
    user_id,
    date_format(get_time,'yyyy-MM-dd') date_id,
    get_time
from ods.ods_coupon_use_full;
