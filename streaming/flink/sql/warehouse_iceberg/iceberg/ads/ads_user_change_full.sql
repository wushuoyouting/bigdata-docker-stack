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
CREATE DATABASE IF NOT EXISTS iceberg_ads;

CREATE TABLE IF NOT EXISTS iceberg_ads.ads_user_change_full(
    `dt` STRING COMMENT 'stat date',
    `user_churn_count` BIGINT COMMENT 'churn user count',
    `user_back_count` BIGINT COMMENT 'backflow user count',
    PRIMARY KEY (`dt`) NOT ENFORCED
) WITH (
    'catalog-name' = 'hadoop_prod'
);

INSERT INTO iceberg_ads.ads_user_change_full /*+ OPTIONS('upsert-enabled' = 'true') */(
    dt,
    user_churn_count,
    user_back_count
)
SELECT
    churn.dt,
    churn.user_churn_count,
    back.user_back_count
FROM (
    SELECT
        CAST(CURRENT_DATE AS STRING) AS dt,
        COUNT(*) AS user_churn_count
    FROM iceberg_dws.dws_user_user_login_td_full
    WHERE k1 = CAST(CURRENT_DATE AS STRING)
      AND CAST(login_date_last AS DATE) = TIMESTAMPADD(DAY, -7, CAST(CAST(CURRENT_DATE AS STRING) AS DATE))
) churn
JOIN (
    SELECT
        CAST(CURRENT_DATE AS STRING) AS dt,
        COUNT(*) AS user_back_count
    FROM (
        SELECT
            t1.user_id
        FROM (
            SELECT
                user_id,
                CAST(login_date_last AS DATE) AS login_date_last
            FROM iceberg_dws.dws_user_user_login_td_full
            WHERE k1 = CAST(CURRENT_DATE AS STRING)
        ) t1
        JOIN (
            SELECT
                user_id,
                CAST(login_date_last AS DATE) AS login_date_previous
            FROM iceberg_dws.dws_user_user_login_td_full
            WHERE CAST(k1 AS DATE) = TIMESTAMPADD(DAY, -1, CAST(CAST(CURRENT_DATE AS STRING) AS DATE))
        ) t2
            ON t1.user_id = t2.user_id
        WHERE TIMESTAMPDIFF(DAY, t2.login_date_previous, t1.login_date_last) >= 8
    ) s
) back
    ON churn.dt = back.dt;
