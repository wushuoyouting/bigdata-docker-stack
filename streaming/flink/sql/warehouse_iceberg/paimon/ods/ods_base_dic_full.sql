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

CREATE TABLE base_dic_full_mq (
    `dic_code` STRING  NOT NULL COMMENT '编号',
    `dic_name` STRING  NULL COMMENT '编码名称',
    `parent_code` STRING  NULL COMMENT '父编号',
    `create_time` TIMESTAMP(3)  NULL  COMMENT '创建时间',
    `operate_time` TIMESTAMP(3)  NULL  COMMENT '修改日期',
    PRIMARY KEY(`dic_code`) NOT ENFORCED
) WITH (
      'connector' = 'mysql-cdc',
      'scan.startup.mode' = 'earliest-offset',
      'hostname' = 'host.docker.internal',
      'port' = '3306',
      'username' = 'root',
      'password' = '123456',
      'database-name' = 'gmall',
      'table-name' = 'base_dic',
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

CREATE TABLE IF NOT EXISTS ods.ods_base_dic_full(
    `dic_code` STRING  NOT NULL COMMENT '编号',
    `k1`  STRING COMMENT '分区字段',
    `dic_name` STRING  NULL COMMENT '编码名称',
    `parent_code` STRING  NULL COMMENT '父编号',
    `create_time` STRING  NULL  COMMENT '创建时间',
    `operate_time` STRING  NULL  COMMENT '修改日期',
    PRIMARY KEY (`dic_code`,`k1`) NOT ENFORCED
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

INSERT INTO ods.ods_base_dic_full(
    `dic_code`,
    `k1`,
    `dic_name`,
    `parent_code`,
    `create_time`,
    `operate_time`
)
select
    `dic_code`,
    DATE_FORMAT(create_time, 'yyyy-MM-dd') AS k1,
    `dic_name`,
    `parent_code`,
    DATE_FORMAT(create_time, 'yyyy-MM-dd HH:mm:ss') AS start_time,
    DATE_FORMAT(operate_time, 'yyyy-MM-dd HH:mm:ss') AS start_time
from default_catalog.default_database.base_dic_full_mq;
