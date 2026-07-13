CREATE INDEX idx_jobs_cluster_type_status_id
    ON jobs (cluster_id, job_type, status, id);

CREATE INDEX idx_precheck_results_job_node_id
    ON precheck_results (job_id, node_id, id);
