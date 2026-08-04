ALTER TABLE clusters
    ADD COLUMN component_config_version BIGINT DEFAULT 0 NOT NULL;

ALTER TABLE clusters
    ADD COLUMN component_precheck_status VARCHAR(32) DEFAULT 'pending' NOT NULL;

ALTER TABLE clusters
    ADD CONSTRAINT ck_clusters_component_precheck_status
    CHECK (component_precheck_status IN ('pending', 'running', 'success', 'failed', 'stale'));
