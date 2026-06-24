import os
import sqlite3

SCHEMA_VERSION = "0.1.2"


def project_root():
    here = os.path.abspath(__file__)
    return os.path.abspath(os.path.join(os.path.dirname(here), "..", "..", "..", ".."))


def data_dir():
    path = os.environ.get("KF_DATA_DIR")
    if path:
        return os.path.abspath(path)
    return os.path.join(project_root(), "data")


def get_db_path():
    return os.environ.get("KF_DB_PATH", os.path.join(data_dir(), "kubefoundry.db"))


def connect():
    path = get_db_path()
    parent = os.path.dirname(path)
    if parent and not os.path.exists(parent):
        os.makedirs(parent)
    conn = sqlite3.connect(path, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    conn = connect()
    try:
        with conn:
            conn.executescript(SCHEMA_SQL)
            _migrate_schema(conn)
            conn.execute(
                "INSERT OR REPLACE INTO schema_migrations(version, applied_at) "
                "VALUES (?, datetime('now'))",
                (SCHEMA_VERSION,),
            )
    finally:
        conn.close()


def _migrate_schema(conn):
    job_columns = [
        row["name"]
        for row in conn.execute("PRAGMA table_info(jobs)").fetchall()
    ]
    if "failure_reason" not in job_columns:
        conn.execute(
            "ALTER TABLE jobs ADD COLUMN failure_reason TEXT DEFAULT ''"
        )
    cluster_columns = [
        row["name"]
        for row in conn.execute("PRAGMA table_info(clusters)").fetchall()
    ]
    if "api_server_port" in cluster_columns or "install_mode" in cluster_columns:
        _rebuild_clusters_table(conn)
        cluster_columns = [
            row["name"]
            for row in conn.execute("PRAGMA table_info(clusters)").fetchall()
        ]
    _add_missing_columns(
        conn,
        "clusters",
        cluster_columns,
        {
            "node_config_version": "INTEGER NOT NULL DEFAULT 1",
            "node_test_status": "TEXT NOT NULL DEFAULT 'pending'",
            "node_tested_at": "TEXT",
            "node_test_job_id": "INTEGER",
        },
    )
    node_columns = [
        row["name"]
        for row in conn.execute("PRAGMA table_info(nodes)").fetchall()
    ]
    _add_missing_columns(
        conn,
        "nodes",
        node_columns,
        {
            "login_password_encrypted": "TEXT NOT NULL DEFAULT ''",
            "is_draft": "INTEGER NOT NULL DEFAULT 0",
            "os_version": "TEXT NOT NULL DEFAULT ''",
            "node_test_status": "TEXT NOT NULL DEFAULT 'pending'",
            "node_tested_at": "TEXT",
            "node_test_message": "TEXT NOT NULL DEFAULT ''",
            "node_test_config_version": "INTEGER",
        },
    )


def _add_missing_columns(conn, table, existing_columns, column_defs):
    for name, definition in column_defs.items():
        if name not in existing_columns:
            conn.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, name, definition))


def _rebuild_clusters_table(conn):
    conn.commit()
    conn.execute("PRAGMA foreign_keys = OFF")
    try:
        conn.executescript(
            """
BEGIN IMMEDIATE;

DROP TABLE IF EXISTS clusters_without_api_server_port;

CREATE TABLE clusters_without_api_server_port (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    k8s_version TEXT NOT NULL DEFAULT '1.30.14',
    pod_subnet TEXT NOT NULL DEFAULT '10.244.0.0/16',
    service_subnet TEXT NOT NULL DEFAULT '10.96.0.0/16',
    registry_hostname TEXT DEFAULT 'registry',
    registry_ip TEXT DEFAULT '',
    registry_port INTEGER NOT NULL DEFAULT 5000,
    status TEXT NOT NULL DEFAULT 'draft',
    node_config_version INTEGER NOT NULL DEFAULT 1,
    node_test_status TEXT NOT NULL DEFAULT 'pending',
    node_tested_at TEXT,
    node_test_job_id INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO clusters_without_api_server_port (
    id, name, description, k8s_version, pod_subnet, service_subnet,
    registry_hostname, registry_ip, registry_port, status,
    node_config_version, node_test_status, node_tested_at, node_test_job_id,
    created_at, updated_at
)
SELECT
    id, name, description, k8s_version, pod_subnet, service_subnet,
    registry_hostname, registry_ip, registry_port, status,
    1, 'pending', NULL, NULL,
    created_at, updated_at
FROM clusters;

DROP TABLE clusters;
ALTER TABLE clusters_without_api_server_port RENAME TO clusters;

COMMIT;
"""
        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.execute("PRAGMA foreign_keys = ON")


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS clusters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    k8s_version TEXT NOT NULL DEFAULT '1.30.14',
    pod_subnet TEXT NOT NULL DEFAULT '10.244.0.0/16',
    service_subnet TEXT NOT NULL DEFAULT '10.96.0.0/16',
    registry_hostname TEXT DEFAULT 'registry',
    registry_ip TEXT DEFAULT '',
    registry_port INTEGER NOT NULL DEFAULT 5000,
    status TEXT NOT NULL DEFAULT 'draft',
    node_config_version INTEGER NOT NULL DEFAULT 1,
    node_test_status TEXT NOT NULL DEFAULT 'pending',
    node_tested_at TEXT,
    node_test_job_id INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cluster_id INTEGER NOT NULL,
    hostname TEXT NOT NULL,
    ip TEXT NOT NULL,
    ipv6 TEXT DEFAULT '',
    role TEXT NOT NULL,
    ssh_port INTEGER NOT NULL DEFAULT 22,
    ssh_user TEXT NOT NULL DEFAULT 'root',
    os_type TEXT DEFAULT '',
    os_version TEXT NOT NULL DEFAULT '',
    arch TEXT DEFAULT '',
    login_password_encrypted TEXT NOT NULL DEFAULT '',
    is_draft INTEGER NOT NULL DEFAULT 0,
    node_test_status TEXT NOT NULL DEFAULT 'pending',
    node_tested_at TEXT,
    node_test_message TEXT NOT NULL DEFAULT '',
    node_test_config_version INTEGER,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ssh_credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cluster_id INTEGER NOT NULL UNIQUE,
    auth_type TEXT NOT NULL DEFAULT 'key',
    username TEXT NOT NULL DEFAULT 'root',
    private_key_path TEXT DEFAULT '~/.ssh/id_rsa',
    password_encrypted TEXT DEFAULT '',
    sudo_password_encrypted TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS cluster_settings (
    cluster_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value TEXT DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY(cluster_id, key),
    FOREIGN KEY(cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cluster_id INTEGER NOT NULL,
    job_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    current_step_key TEXT DEFAULT '',
    config_snapshot TEXT DEFAULT '',
    config_yaml_path TEXT DEFAULT '',
    log_dir TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    started_at TEXT DEFAULT '',
    finished_at TEXT DEFAULT '',
    failure_reason TEXT DEFAULT '',
    FOREIGN KEY(cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS job_steps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL,
    step_key TEXT NOT NULL,
    step_name TEXT NOT NULL,
    phase TEXT DEFAULT '',
    target_scope TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending',
    started_at TEXT DEFAULT '',
    finished_at TEXT DEFAULT '',
    exit_code INTEGER,
    message TEXT DEFAULT '',
    FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS job_step_nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_step_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    started_at TEXT DEFAULT '',
    finished_at TEXT DEFAULT '',
    exit_code INTEGER,
    log_path TEXT DEFAULT '',
    message TEXT DEFAULT '',
    FOREIGN KEY(job_step_id) REFERENCES job_steps(id) ON DELETE CASCADE,
    FOREIGN KEY(node_id) REFERENCES nodes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS precheck_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cluster_id INTEGER NOT NULL,
    job_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL,
    check_key TEXT NOT NULL,
    check_name TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'error',
    status TEXT NOT NULL,
    message TEXT DEFAULT '',
    detail TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(cluster_id) REFERENCES clusters(id) ON DELETE CASCADE,
    FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE,
    FOREIGN KEY(node_id) REFERENCES nodes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS job_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    payload TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
);
"""
