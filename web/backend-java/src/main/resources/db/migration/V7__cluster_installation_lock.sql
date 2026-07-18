ALTER TABLE clusters ADD COLUMN installation_locked BOOLEAN DEFAULT FALSE NOT NULL;

UPDATE clusters
SET installation_locked = TRUE
WHERE EXISTS (
    SELECT 1
    FROM jobs
    WHERE jobs.cluster_id = clusters.id
      AND jobs.job_type = 'install'
);
