SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
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

CREATE TABLE IF NOT EXISTS dwd.dwd_marketing_seckill_full(
    `id` STRING COMMENT '编号',
    `k1` STRING COMMENT '分区字段',
    `seckill_id` STRING COMMENT '秒杀活动ID',
    `spu_id` STRING COMMENT 'SPU ID',
    `sku_id` STRING COMMENT 'SKU ID',
    `sku_name` STRING COMMENT '商品名称',
    `sku_default_img` STRING COMMENT '商品图片',
    `original_price` DECIMAL(16, 2) COMMENT '原价',
    `seckill_price` DECIMAL(16, 2) COMMENT '秒杀价',
    `create_time` STRING COMMENT '创建时间',
    `check_time` STRING COMMENT '审核时间',
    `status` STRING COMMENT '状态',
    `start_time` STRING COMMENT '开始时间',
    `end_time` STRING COMMENT '结束时间',
    `total_num` BIGINT COMMENT '总数量',
    `stock_count` BIGINT COMMENT '剩余库存',
    `sku_desc` STRING COMMENT '商品描述',
    PRIMARY KEY (`id`, `k1`) NOT ENFORCED
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

INSERT INTO dwd.dwd_marketing_seckill_full(
    id,
    k1,
    seckill_id,
    spu_id,
    sku_id,
    sku_name,
    sku_default_img,
    original_price,
    seckill_price,
    create_time,
    check_time,
    status,
    start_time,
    end_time,
    total_num,
    stock_count,
    sku_desc
)
SELECT
    CAST(sg.id AS STRING) AS id,
    sg.k1,
    CAST(sg.id AS STRING) AS seckill_id,
    COALESCE(CAST(sg.spu_id AS STRING), '') AS spu_id,
    COALESCE(CAST(sg.sku_id AS STRING), '') AS sku_id,
    COALESCE(sg.sku_name, si.sku_name, '') AS sku_name,
    COALESCE(sg.sku_default_img, si.sku_default_img, '') AS sku_default_img,
    CAST(COALESCE(sg.price, 0) AS DECIMAL(16, 2)) AS original_price,
    CAST(COALESCE(sg.cost_price, 0) AS DECIMAL(16, 2)) AS seckill_price,
    DATE_FORMAT(sg.create_time, 'yyyy-MM-dd HH:mm:ss') AS create_time,
    DATE_FORMAT(sg.check_time, 'yyyy-MM-dd HH:mm:ss') AS check_time,
    COALESCE(sg.status, '') AS status,
    DATE_FORMAT(sg.start_time, 'yyyy-MM-dd HH:mm:ss') AS start_time,
    DATE_FORMAT(sg.end_time, 'yyyy-MM-dd HH:mm:ss') AS end_time,
    COALESCE(CAST(sg.num AS BIGINT), 0) AS total_num,
    COALESCE(CAST(sg.stock_count AS BIGINT), 0) AS stock_count,
    COALESCE(sg.sku_desc, '') AS sku_desc
FROM ods.ods_seckill_goods_full sg
LEFT JOIN
(
    SELECT
        id,
        sku_name,
        sku_default_img
    FROM ods.ods_sku_info_full
    WHERE k1 = '2026-11-24'
) si
    ON sg.sku_id = si.id
WHERE sg.k1 = '2026-11-24';
