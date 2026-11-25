-- ============================================================================
-- flink/01_paimon_catalog.sql — Flink SQL 侧建 Paimon Catalog 与目标表
--
-- 执行方式：在本机终端手动执行（同 deploy/02-Flink与Paimon.md 第 5.3 节）
--   docker exec -it flink-jobmanager /opt/flink/bin/sql-client.sh embedded \
--     -f /opt/sql/01_paimon_catalog.sql
-- 执行任务：对应 T06「写回 Paimon」的前置初始化；提交动作由你手动完成，
--           不是 DolphinScheduler 的 SQL 任务。默认路径 C 下 DS 的 T06
--           只做 curl 校验（见 05 配置卡 T06），不在 worker 容器里跑 docker exec。
--
-- 【为什么这个文件存在】
--   Doris 的 Paimon Catalog 只读，原文那条 INSERT INTO paimon_catalog 跑不通。
--   写湖改由 Flink 承担：先在 Flink 侧建好 Paimon Catalog 与目标表，
--   再由 02_ads_to_paimon.sql 把 Doris ADS 结果读出来写进去。
--
-- 【参数名与 Doris 侧不同】
--   Flink/Paimon 侧：s3.access-key / s3.secret-key（连字符）
--   Doris Catalog 侧：s3.access_key / s3.secret_key（下划线）
--   两边 warehouse 必须完全一致，都是 s3://lakehouse/paimon，
--   否则会出现「Flink 写成功了、Doris 查不到表」这种最典型的假故障。
--
-- 【jar 前提】
--   JM 与 TM 都要放 paimon-flink / flink-doris-connector / S3 支持三个 jar，
--   详见 deploy/02-Flink与Paimon.md 第 2 节。
-- ============================================================================

-- 开 checkpoint：Paimon 的 commit 绑定 checkpoint，不开会「作业在跑、湖里没文件」。
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- ---------------------------------------------------------------------------
-- 1) 建 filesystem 类型 Paimon Catalog
--    metastore=filesystem 表示元数据就落在 warehouse 目录里，无需 HMS / DLF。
-- ---------------------------------------------------------------------------
CREATE CATALOG paimon_lake WITH (
    'type'                    = 'paimon',
    'metastore'               = 'filesystem',
    'warehouse'               = 's3://lakehouse/paimon',
    's3.endpoint'             = 'http://minio:9000',
    's3.access-key'           = '<MINIO_AK>',
    's3.secret-key'           = '<MINIO_SK>',
    's3.path.style.access'    = 'true'
);

USE CATALOG paimon_lake;

CREATE DATABASE IF NOT EXISTS game_db;

-- ---------------------------------------------------------------------------
-- 2) ADS 目标表：表名与列序对齐原案例 ADS_USER_PURCHASE_TRENDS，
--    计数列用 BIGINT 承接 Doris COUNT() 的返回类型（原文写的是 INT）。
--    本方案只写回这一张购买趋势结果表，其余三张 ADS 视图不落湖。
--    PRIMARY KEY(purchase_date) NOT ENFORCED：主键表支持幂等重跑，
--    同一天重跑写回会覆盖而不是追加出两份。
--    不建分区：ADS 结果只有几十行，分区反而制造小文件。
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS game_db.ADS_USER_PURCHASE_TRENDS (
    purchase_date          DATE,
    daily_purchase_events  BIGINT,
    PRIMARY KEY (purchase_date) NOT ENFORCED
) WITH (
    'bucket' = '1'
);

-- ---------------------------------------------------------------------------
-- 3) 校验
-- ---------------------------------------------------------------------------
SHOW CATALOGS;
SHOW TABLES FROM game_db;

-- ---------------------------------------------------------------------------
-- 复核点
--   SHOW CATALOGS;                → 含 paimon_lake
--   SHOW TABLES FROM game_db;     → 含 ADS_USER_PURCHASE_TRENDS
-- 若报 No FileSystem for scheme "s3"：缺 S3 支持 jar，回 deploy/02 第 2 节。
-- 若报 AccessDenied：核对连字符参数名与 endpoint 是否写成容器内地址。
-- ---------------------------------------------------------------------------
