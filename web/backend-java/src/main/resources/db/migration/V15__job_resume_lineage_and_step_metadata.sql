ALTER TABLE jobs ADD COLUMN source_job_id BIGINT;
ALTER TABLE jobs ADD COLUMN run_mode VARCHAR(16) NOT NULL DEFAULT 'normal';

ALTER TABLE jobs ADD CONSTRAINT fk_jobs_source_job
    FOREIGN KEY (source_job_id) REFERENCES jobs (id) ON DELETE RESTRICT;

CREATE INDEX idx_jobs_source_job_id ON jobs (source_job_id);

ALTER TABLE job_steps ADD COLUMN step_key VARCHAR(128);
ALTER TABLE job_steps ADD COLUMN stage_key VARCHAR(128);
ALTER TABLE job_steps ADD COLUMN stage_name VARCHAR(128);
ALTER TABLE job_steps ADD COLUMN stage_order INTEGER;
ALTER TABLE job_steps ADD COLUMN step_order_in_stage INTEGER;

UPDATE job_steps
SET step_key = 'legacy-' || CAST(id AS VARCHAR),
    stage_key = 'legacy',
    stage_name = '历史任务',
    stage_order = 1,
    step_order_in_stage = step_order;

ALTER TABLE job_steps ALTER COLUMN step_key SET NOT NULL;
ALTER TABLE job_steps ALTER COLUMN stage_key SET NOT NULL;
ALTER TABLE job_steps ALTER COLUMN stage_name SET NOT NULL;
ALTER TABLE job_steps ALTER COLUMN stage_order SET NOT NULL;
ALTER TABLE job_steps ALTER COLUMN step_order_in_stage SET NOT NULL;

CREATE UNIQUE INDEX uk_job_steps_job_step_key ON job_steps (job_id, step_key);
CREATE INDEX idx_job_steps_job_stage_order
    ON job_steps (job_id, stage_order, step_order_in_stage);
