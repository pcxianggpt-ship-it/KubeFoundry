ALTER TABLE job_steps
    ADD COLUMN component_group_key VARCHAR(64);

CREATE INDEX idx_job_steps_component_group
    ON job_steps (job_id, component_group_key);
