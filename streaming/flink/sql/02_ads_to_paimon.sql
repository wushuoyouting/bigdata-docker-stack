-- ============================================================================
-- flink/02_ads_to_paimon.sql — 从 Doris ADS 读，写回 Paimon（补位作业）
--
-- 执行方式：在本机终端手动执行（见 deploy/02-Flink与Paimon.md 第 7 节）
--   docker exec -it flink-jobmanager /opt/flink/bin/sql-client.sh embedded \
--     -f /opt/sql/02_ads_to_paimon.sql
-- 执行任务：对应 T06「写回 Paimon」；提交的是 Flink 作业，不是往 Doris 发 SQL。
--           默认路径 C 下提交动作由你手动完成，DS 的 T06 只做 curl 校验
--           （见 05 配置卡 T06），不在 DS worker 容器里跑 docker exec。
--
-- 【全案最关键的一句话】
--   原文第 5 步是 StarRocks SQL: INSERT INTO myfirstcatalog.game_db.ADS_... SELECT ...
--   Doris 的 Paimon Catalog 不支持写，所以这条链路拆成两段：
--     flink-doris-connector 读 Doris 内表 ADS  →  Paimon Connector 写 MinIO 上的湖表
--   Doris 再通过只读 Catalog 回查对账（sql/05_paimon_read.sql）。
--   闭环没变，执行者变了。详见 01-架构与平替选型.md 第 4 节。
--
-- 【两个容易写错的地址】
--   fenodes = 'doris-fe:8030'   → FE **HTTP 端口**，不是 MySQL 协议 9030
--   warehouse / s3.endpoint     → 容器内地址 http://minio:9000，不是 localhost
-- ============================================================================

SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'parallelism.default' = '2';

-- ---------------------------------------------------------------------------
-- 1) 声明 Doris 侧 ADS 结果表为 Flink Source
--    table.identifier 指向 Doris 内表的库.表；物化视图在 Doris 里也是可查表。
--    若你的 connector 版本读不了物化视图，改用等价的物化结果物理表：
--      在 Doris 里 CREATE TABLE ads_purchase_snapshot AS SELECT * FROM ADS_MV_USER_PURCHASE_TRENDS;
--      再把 table.identifier 改成 game_db.ads_purchase_snapshot。
--    （见 deploy/02-Flink与Paimon.md 第 9 节踩坑表）
-- ---------------------------------------------------------------------------
CREATE TABLE doris_ads_purchase (
    purchase_date          DATE,
    daily_purchase_events  BIGINT
) WITH (
    'connector'        = 'doris',
    'fenodes'          = 'doris-fe:8030',
    'table.identifier' = 'game_db.ADS_MV_USER_PURCHASE_TRENDS',
    'username'         = '<FE_USER>',
    'password'         = '<FE_PWD>'
);

-- ---------------------------------------------------------------------------
-- 2) 建（或复用）Paimon Catalog。若已跑过 01_paimon_catalog.sql，
--    CREATE CATALOG IF NOT EXISTS 语义以所用版本为准，重复执行报已存在可跳过本段。
-- ---------------------------------------------------------------------------
CREATE CATALOG paimon_lake WITH (
    'type'                 = 'paimon',
    'metastore'            = 'filesystem',
    'warehouse'            = 's3://lakehouse/paimon',
    's3.endpoint'          = 'http://minio:9000',
    's3.access-key'        = '<MINIO_AK>',
    's3.secret-key'        = '<MINIO_SK>',
    's3.path.style.access' = 'true'
);

-- ---------------------------------------------------------------------------
-- 3) 写回。提交后这是**常驻流式作业**，不会自己结束；
--    验证完数据后可在 Flink UI 里 Cancel，或用 -f 提交模式按版本行为处理。
-- ---------------------------------------------------------------------------
INSERT INTO paimon_lake.game_db.ADS_USER_PURCHASE_TRENDS
SELECT purchase_date, daily_purchase_events
FROM doris_ads_purchase;

-- ---------------------------------------------------------------------------
-- 复核点（按 deploy/02 第 7 节三层验证）
--   ① Flink UI /jobs/overview                       → 作业 RUNNING
--   ② mc ls --recursive lake/lakehouse/paimon/     → 有数据文件
--   ③ Flink UI 作业 → Checkpoints 页                → 至少 1 个 COMPLETED
--   然后回 Doris 执行 sql/06_check.sql 第 7 节做双向对账。
-- 若作业 RUNNING 但湖里没文件：九成是 checkpoint 没开或没触发，等一个周期再看。
-- ---------------------------------------------------------------------------
