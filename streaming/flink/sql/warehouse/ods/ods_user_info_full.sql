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

CREATE TABLE user_info_full_mq (
    `id` bigint NOT NULL  COMMENT '编号',
    `login_name` STRING  NULL COMMENT '用户名称',
    `nick_name` STRING  NULL COMMENT '用户昵称',
    `passwd` STRING  NULL COMMENT '用户密码',
    `name` STRING  NULL COMMENT '用户姓名',
    `phone_num` STRING  NULL COMMENT '手机号',
    `email` STRING  NULL COMMENT '邮箱',
    `head_img` STRING  NULL COMMENT '头像',
    `user_level` STRING  NULL COMMENT '用户级别',
    `birthday` STRING  NULL COMMENT '用户生日',
    `gender` STRING  NULL COMMENT '性别 M男,F女',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    `operate_time` timestamp(3) NOT NULL   COMMENT '修改时间',
    `status` STRING  NULL COMMENT '状态',
    PRIMARY KEY(`id`) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'scan.startup.mode' = 'earliest-offset',
    'hostname' = 'host.docker.internal',
    'port' = '3306',
    'username' = 'root',
    'password' = '123456',
    'database-name' = 'gmall',
    'table-name' = 'user_info',
    'server-time-zone' = 'Asia/Shanghai'
);

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
CREATE DATABASE IF NOT EXISTS ods;

CREATE TABLE IF NOT EXISTS ods.ods_user_info_full(
    `id` BIGINT COMMENT '活动id',
    `k1` STRING COMMENT '分区字段',
    `login_name` STRING  NULL COMMENT '用户名称',
    `nick_name` STRING  NULL COMMENT '用户昵称',
    `passwd` STRING  NULL COMMENT '用户密码',
    `name` STRING  NULL COMMENT '用户姓名',
    `phone_num` STRING  NULL COMMENT '手机号',
    `email` STRING  NULL COMMENT '邮箱',
    `head_img` STRING  NULL COMMENT '头像',
    `user_level` STRING  NULL COMMENT '用户级别',
    `birthday` STRING  NULL COMMENT '用户生日',
    `gender` STRING  NULL COMMENT '性别 M男,F女',
    `create_time` timestamp(3) NOT NULL   COMMENT '创建时间',
    `operate_time` timestamp(3) NOT NULL   COMMENT '修改时间',
    `status` STRING  NULL COMMENT '状态',
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

INSERT INTO ods.ods_user_info_full(
    `id`,
    `k1`,
    `login_name`,
    `nick_name`,
    `passwd`,
    `name`,
    `phone_num`,
    `email`,
    `head_img`,
    `user_level`,
    `birthday`,
    `gender`,
    `create_time`,
    `operate_time`,
    `status`
)select
    id,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `login_name`,
    `nick_name`,
    `passwd`,
    `name`,
    `phone_num`,
    `email`,
    `head_img`,
    `user_level`,
    `birthday`,
    `gender`,
    `create_time`,
    `operate_time`,
    `status`
from default_catalog.default_database.user_info_full_mq
where create_time is not null;
