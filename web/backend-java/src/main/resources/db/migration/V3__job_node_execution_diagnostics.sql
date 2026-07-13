ALTER TABLE job_step_nodes ADD COLUMN log_path VARCHAR(512);
ALTER TABLE job_step_nodes ADD COLUMN exit_code INTEGER;
ALTER TABLE job_step_nodes ADD COLUMN message VARCHAR(1024);
