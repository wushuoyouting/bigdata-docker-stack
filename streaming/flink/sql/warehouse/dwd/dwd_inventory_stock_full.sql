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

CREATE TABLE IF NOT EXISTS dwd.dwd_inventory_stock_full(
    `id` STRING COMMENT '编号',
    `k1` STRING COMMENT '分区字段',
    `sku_id` STRING COMMENT '商品ID',
    `sku_name` STRING COMMENT '商品名称',
    `warehouse_id` STRING COMMENT '仓库ID',
    `warehouse_name` STRING COMMENT '仓库名称',
    `warehouse_address` STRING COMMENT '仓库地址',
    `warehouse_areacode` STRING COMMENT '仓库区域编码',
    `stock` BIGINT COMMENT '库存数量',
    `stock_name` STRING COMMENT '库存名称',
    `is_default` STRING COMMENT '是否默认仓库',
    `create_time` STRING COMMENT '创建时间',
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

INSERT INTO dwd.dwd_inventory_stock_full(
    id,
    k1,
    sku_id,
    sku_name,
    warehouse_id,
    warehouse_name,
    warehouse_address,
    warehouse_areacode,
    stock,
    stock_name,
    is_default,
    create_time
)
SELECT
    CAST(ws.id AS STRING) AS id,
    '2026-11-24' AS k1,
    COALESCE(CAST(ws.sku_id AS STRING), '') AS sku_id,
    COALESCE(si.sku_name, '') AS sku_name,
    COALESCE(CAST(ws.warehouse_id AS STRING), '') AS warehouse_id,
    COALESCE(wi.name, '') AS warehouse_name,
    COALESCE(wi.address, '') AS warehouse_address,
    COALESCE(wi.areacode, '') AS warehouse_areacode,
    COALESCE(CAST(ws.stock AS BIGINT), 0) AS stock,
    COALESCE(
        ws.stock_name,
        CASE
            WHEN ws.stock = 0 THEN '无货'
            WHEN ws.stock < 10 THEN '低库存'
            WHEN ws.stock < 50 THEN '库存正常'
            ELSE '库存充足'
        END
    ) AS stock_name,
    '0' AS is_default,
    CONCAT('2026-11-24', ' 00:00:00') AS create_time
FROM ods.ods_ware_sku_full ws
LEFT JOIN ods.ods_ware_info_full wi
    ON ws.warehouse_id = wi.id
LEFT JOIN
(
    SELECT
        id,
        sku_name
    FROM ods.ods_sku_info_full
    WHERE k1 = '2026-11-24'
) si
    ON ws.sku_id = si.id;
