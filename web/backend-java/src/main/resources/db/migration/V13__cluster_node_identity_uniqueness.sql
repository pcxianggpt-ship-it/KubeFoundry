ALTER TABLE nodes ADD COLUMN hostname_normalized VARCHAR(128);
ALTER TABLE nodes ADD COLUMN ip_normalized VARCHAR(15);

UPDATE nodes
SET hostname_normalized = CASE
        WHEN is_draft OR name IS NULL OR TRIM(name) = '' THEN NULL
        ELSE REGEXP_REPLACE(LOWER(TRIM(name)), '\.$', '')
    END,
    ip_normalized = CASE
        WHEN is_draft OR host IS NULL OR TRIM(host) = '' THEN NULL
        ELSE REGEXP_REPLACE(TRIM(host), '(^|\.)0+([0-9])', '$1$2')
    END;

CREATE UNIQUE INDEX uk_nodes_cluster_hostname_normalized
    ON nodes (cluster_id, hostname_normalized);

CREATE UNIQUE INDEX uk_nodes_cluster_ip_normalized
    ON nodes (cluster_id, ip_normalized);
