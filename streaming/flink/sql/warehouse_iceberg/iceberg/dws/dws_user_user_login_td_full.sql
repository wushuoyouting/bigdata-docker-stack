SET 'execution.target' = 'remote';
SET 'rest.address' = 'localhost';
SET 'rest.port' = '8081';
SET 'table.exec.resource.default-parallelism' = '1';
SET 'execution.checkpointing.interval' = '100s';
SET 'table.exec.state.ttl' = '8640000';
SET 'table.exec.mini-batch.enabled' = 'true';
SET 'table.exec.mini-batch.allow-latency' = '60s';
SET 'table.exec.mini-batch.size' = '10000';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'DROP';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
SET 'execution.runtime-mode' = 'batch';

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
CREATE DATABASE IF NOT EXISTS iceberg_dws;

CREATE TABLE IF NOT EXISTS iceberg_dws.dws_user_user_login_td_full(
    `user_id` BIGINT COMMENT 'user id',
    `k1` STRING COMMENT 'partition field',
    `login_date_last` STRING COMMENT 'last login date',
    `login_count_td` BIGINT COMMENT 'to date login count',
    PRIMARY KEY (`user_id`, `k1`) NOT ENFORCED
) PARTITIONED BY (`k1`) WITH (
    'catalog-name' = 'hadoop_prod'
);

CREATE TEMPORARY VIEW tmp_dws_user_user_login_td_current_date_param AS
    SELECT CAST(CAST(CURRENT_DATE AS STRING) AS DATE) AS cur_date
;

CREATE TEMPORARY VIEW tmp_dws_user_user_login_td_user_dim AS
    SELECT
        id AS user_id,
        create_time
    FROM iceberg_dim.dim_user_zip_full
    CROSS JOIN tmp_dws_user_user_login_td_current_date_param cp
    WHERE CAST(k1 AS DATE) = cp.cur_date
;

CREATE TEMPORARY VIEW tmp_dws_user_user_login_td_login_agg AS
    SELECT
        CAST(user_id AS BIGINT) AS user_id,
        MAX(CAST(k1 AS DATE)) AS login_date_last_dt,
        COUNT(*) AS login_count_td
    FROM iceberg_dwd.dwd_user_login_full
    CROSS JOIN tmp_dws_user_user_login_td_current_date_param cp
    WHERE CAST(k1 AS DATE) <= cp.cur_date
    GROUP BY CAST(user_id AS BIGINT)
;

INSERT INTO iceberg_dws.dws_user_user_login_td_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    user_id,
    k1,
    login_date_last,
    login_count_td
)
SELECT
    ud.user_id,
    CAST(cp.cur_date AS STRING) AS k1,
    COALESCE(CAST(la.login_date_last_dt AS STRING), DATE_FORMAT(ud.create_time, 'yyyy-MM-dd')) AS login_date_last,
    COALESCE(la.login_count_td, CAST(1 AS BIGINT)) AS login_count_td
FROM tmp_dws_user_user_login_td_user_dim ud
CROSS JOIN tmp_dws_user_user_login_td_current_date_param cp
LEFT JOIN tmp_dws_user_user_login_td_login_agg la
    ON ud.user_id = la.user_id;
