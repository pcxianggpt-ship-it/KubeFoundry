import json
import os

from kubefoundry.security.credentials import encrypt_text
from kubefoundry.store.db import connect


def _row(row):
    return dict(row) if row is not None else None


def _rows(rows):
    return [dict(item) for item in rows]


def _public_cluster(row):
    item = _row(row)
    if item is None:
        return None
    item.pop("install_mode", None)
    return item


def _public_node(row):
    item = _row(row)
    if item is None:
        return None
    password = item.pop("login_password_encrypted", "") or ""
    item["has_password"] = bool(password)
    item["is_draft"] = bool(item.get("is_draft"))
    item["ssh_user"] = "root"
    item["ssh_port"] = 22
    return item


def _public_nodes(rows):
    return [_public_node(item) for item in rows]


def _pick(data, allowed):
    result = {}
    for key in allowed:
        if key in data and data.get(key) is not None:
            result[key] = data.get(key)
    return result


class Repository(object):
    def __init__(self):
        self.conn = connect()

    def __del__(self):
        self.close()

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def list_clusters(self):
        return [
            _public_cluster(row)
            for row in self.conn.execute("SELECT * FROM clusters ORDER BY id DESC").fetchall()
        ]

    def get_cluster(self, cluster_id):
        return _public_cluster(self.conn.execute("SELECT * FROM clusters WHERE id=?", (cluster_id,)).fetchone())

    def get_cluster_private(self, cluster_id):
        return _row(self.conn.execute("SELECT * FROM clusters WHERE id=?", (cluster_id,)).fetchone())

    def create_cluster(self, data):
        allowed = [
            "name", "description", "k8s_version", "pod_subnet", "service_subnet",
            "registry_hostname", "registry_ip", "registry_port",
            "status",
        ]
        values = _pick(data, allowed)
        if not values.get("name"):
            values["name"] = "k8s-cluster"
        columns = list(values.keys())
        marks = ["?"] * len(columns)
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO clusters(%s) VALUES(%s)" % (",".join(columns), ",".join(marks)),
                [values[k] for k in columns],
            )
        return self.get_cluster(cur.lastrowid)

    def update_cluster(self, cluster_id, data):
        allowed = [
            "name", "description", "k8s_version", "pod_subnet", "service_subnet",
            "registry_hostname", "registry_ip", "registry_port",
            "status",
        ]
        values = _pick(data, allowed)
        if not values:
            return self.get_cluster(cluster_id)
        sets = ["%s=?" % key for key in values.keys()]
        params = [values[k] for k in values.keys()] + [cluster_id]
        with self.conn:
            self.conn.execute(
                "UPDATE clusters SET %s, updated_at=datetime('now') WHERE id=?"
                % ",".join(sets),
                params,
            )
        return self.get_cluster(cluster_id)

    def delete_cluster(self, cluster_id):
        with self.conn:
            cur = self.conn.execute("DELETE FROM clusters WHERE id=?", (cluster_id,))
        return cur.rowcount > 0

    def list_nodes(self, cluster_id):
        return _public_nodes(self._list_node_rows(cluster_id))

    def list_nodes_private(self, cluster_id):
        return _rows(self._list_node_rows(cluster_id))

    def _list_node_rows(self, cluster_id):
        return self.conn.execute(
            "SELECT * FROM nodes WHERE cluster_id=? ORDER BY "
            "CASE role WHEN 'control_plane' THEN 1 WHEN 'registry' THEN 2 WHEN 'worker' THEN 3 ELSE 4 END, id",
            (cluster_id,),
        ).fetchall()

    def get_node(self, node_id):
        return _public_node(self.conn.execute("SELECT * FROM nodes WHERE id=?", (node_id,)).fetchone())

    def get_node_private(self, node_id):
        return _row(self.conn.execute("SELECT * FROM nodes WHERE id=?", (node_id,)).fetchone())

    def create_node(self, cluster_id, data):
        allowed = ["hostname", "ip", "ipv6", "role", "status"]
        values = _pick(data, allowed)
        values["cluster_id"] = cluster_id
        if data.get("password"):
            values["login_password_encrypted"] = encrypt_text(data.get("password"))
        if not values.get("hostname") or not values.get("ip"):
            raise ValueError("hostname and ip are required")
        if not values.get("role"):
            values["role"] = "worker"
        columns = list(values.keys())
        marks = ["?"] * len(columns)
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO nodes(%s) VALUES(%s)" % (",".join(columns), ",".join(marks)),
                [values[k] for k in columns],
            )
            self._mark_node_config_changed(cluster_id)
        return self.get_node(cur.lastrowid)

    def update_node(self, node_id, data):
        current = self.get_node_private(node_id)
        if not current:
            return None
        allowed = ["hostname", "ip", "ipv6", "role", "status"]
        values = _pick(data, allowed)
        if data.get("password"):
            values["login_password_encrypted"] = encrypt_text(data.get("password"))
        if not values:
            return self.get_node(node_id)
        sets = ["%s=?" % key for key in values.keys()]
        params = [values[k] for k in values.keys()] + [node_id]
        with self.conn:
            self.conn.execute(
                "UPDATE nodes SET %s, updated_at=datetime('now') WHERE id=?" % ",".join(sets),
                params,
            )
            self._mark_node_config_changed(current["cluster_id"])
        return self.get_node(node_id)

    def delete_node(self, node_id):
        current = self.get_node_private(node_id)
        with self.conn:
            cur = self.conn.execute("DELETE FROM nodes WHERE id=?", (node_id,))
            if current and cur.rowcount > 0:
                self._mark_node_config_changed(current["cluster_id"])
        return cur.rowcount > 0

    def _mark_node_config_changed(self, cluster_id):
        self.conn.execute(
            "UPDATE clusters SET node_config_version=node_config_version + 1, "
            "node_test_status='stale', node_test_job_id=NULL, updated_at=datetime('now') "
            "WHERE id=?",
            (cluster_id,),
        )

    def mark_node_config_changed(self, cluster_id):
        with self.conn:
            self._mark_node_config_changed(cluster_id)
        return self.get_cluster(cluster_id)

    def copy_nodes(self, cluster_id, node_ids):
        if not node_ids:
            raise ValueError("node_ids is required")
        if len(node_ids) != len(set(node_ids)):
            raise ValueError("node_ids must not contain duplicates")
        copied_ids = []
        with self.conn:
            for node_id in node_ids:
                node = self.get_node_private(node_id)
                if not node or node["cluster_id"] != cluster_id:
                    raise ValueError("node does not belong to cluster: %s" % node_id)
                cur = self.conn.execute(
                    "INSERT INTO nodes("
                    "cluster_id, hostname, ip, ipv6, role, ssh_port, ssh_user, "
                    "os_type, os_version, arch, login_password_encrypted, is_draft, "
                    "node_test_status, node_test_message, status"
                    ") VALUES(?, ?, ?, ?, ?, 22, 'root', ?, ?, ?, ?, 1, 'stale', '', ?)",
                    (
                        cluster_id,
                        node.get("hostname") or "",
                        node.get("ip") or "",
                        node.get("ipv6") or "",
                        node.get("role") or "worker",
                        node.get("os_type") or "",
                        node.get("os_version") or "",
                        node.get("arch") or "",
                        node.get("login_password_encrypted") or "",
                        node.get("status") or "pending",
                    ),
                )
                copied_ids.append(cur.lastrowid)
            self._mark_node_config_changed(cluster_id)
        return [self.get_node(node_id) for node_id in copied_ids]

    def validate_node_configuration(self, cluster_id):
        nodes = self.list_nodes_private(cluster_id)
        problems = []
        hostnames = {}
        ips = {}
        for node in nodes:
            label = node.get("hostname") or ("node-%s" % node.get("id"))
            if node.get("is_draft"):
                problems.append({"node_id": node["id"], "hostname": label, "message": "存在未完成草稿"})
            if not (node.get("hostname") or "").strip():
                problems.append({"node_id": node["id"], "hostname": label, "message": "缺少主机名"})
            if not (node.get("ip") or "").strip():
                problems.append({"node_id": node["id"], "hostname": label, "message": "缺少 IP"})
            if not (node.get("login_password_encrypted") or ""):
                problems.append({"node_id": node["id"], "hostname": label, "message": "缺少登录密码"})
            hostname = (node.get("hostname") or "").strip()
            ip = (node.get("ip") or "").strip()
            if hostname:
                if hostname in hostnames:
                    problems.append({"node_id": node["id"], "hostname": label, "message": "主机名重复"})
                hostnames[hostname] = node["id"]
            if ip:
                if ip in ips:
                    problems.append({"node_id": node["id"], "hostname": label, "message": "IP 重复"})
                ips[ip] = node["id"]
        return problems

    def get_ssh_credentials(self, cluster_id):
        return _row(self.conn.execute("SELECT * FROM ssh_credentials WHERE cluster_id=?", (cluster_id,)).fetchone())

    def upsert_ssh_credentials(self, cluster_id, data):
        allowed = [
            "auth_type", "username", "private_key_path",
            "password_encrypted", "sudo_password_encrypted",
        ]
        values = _pick(data, allowed)
        current = self.get_ssh_credentials(cluster_id)
        if current:
            sets = ["%s=?" % key for key in values.keys()]
            params = [values[k] for k in values.keys()] + [cluster_id]
            with self.conn:
                if sets:
                    self.conn.execute(
                        "UPDATE ssh_credentials SET %s, updated_at=datetime('now') WHERE cluster_id=?"
                        % ",".join(sets),
                        params,
                    )
            return self.get_ssh_credentials(cluster_id)
        values["cluster_id"] = cluster_id
        if not values.get("username"):
            values["username"] = "root"
        columns = list(values.keys())
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO ssh_credentials(%s) VALUES(%s)"
                % (",".join(columns), ",".join(["?"] * len(columns))),
                [values[k] for k in columns],
            )
        return _row(self.conn.execute("SELECT * FROM ssh_credentials WHERE id=?", (cur.lastrowid,)).fetchone())

    def get_settings(self):
        rows = self.conn.execute("SELECT key, value FROM settings ORDER BY key").fetchall()
        result = {}
        for row in rows:
            value = row["value"]
            try:
                result[row["key"]] = json.loads(value)
            except (TypeError, ValueError):
                result[row["key"]] = value
        return result

    def upsert_settings(self, data):
        with self.conn:
            for key, value in data.items():
                stored_value = _serialize_setting(value)
                self.conn.execute(
                    "INSERT OR REPLACE INTO settings(key, value, updated_at) VALUES(?, ?, datetime('now'))",
                    (key, stored_value),
                )
        return self.get_settings()

    def get_cluster_settings(self, cluster_id):
        rows = self.conn.execute(
            "SELECT key, value FROM cluster_settings WHERE cluster_id=? ORDER BY key",
            (cluster_id,),
        ).fetchall()
        return _decode_settings(rows)

    def upsert_cluster_settings(self, cluster_id, data):
        with self.conn:
            for key, value in data.items():
                self.conn.execute(
                    "INSERT OR REPLACE INTO cluster_settings(cluster_id, key, value, updated_at) "
                    "VALUES(?, ?, ?, datetime('now'))",
                    (cluster_id, key, _serialize_setting(value)),
                )
        return self.get_cluster_settings(cluster_id)

    def create_job(self, cluster_id, job_type, snapshot, yaml_path, log_dir):
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO jobs(cluster_id, job_type, status, config_snapshot, config_yaml_path, log_dir) "
                "VALUES(?, ?, 'pending', ?, ?, ?)",
                (cluster_id, job_type, json.dumps(snapshot, ensure_ascii=False), yaml_path, log_dir),
            )
        return self.get_job(cur.lastrowid)

    def list_jobs(self, cluster_id=None):
        if cluster_id:
            return _rows(self.conn.execute("SELECT * FROM jobs WHERE cluster_id=? ORDER BY id DESC", (cluster_id,)).fetchall())
        return _rows(self.conn.execute("SELECT * FROM jobs ORDER BY id DESC").fetchall())

    def get_job(self, job_id):
        return _row(self.conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone())

    def find_active_job(self, cluster_id, job_type=None):
        sql = (
            "SELECT * FROM jobs WHERE cluster_id=? "
            "AND status IN ('pending', 'running')"
        )
        params = [cluster_id]
        if job_type:
            sql += " AND job_type=?"
            params.append(job_type)
        sql += " ORDER BY id DESC LIMIT 1"
        return _row(self.conn.execute(sql, params).fetchone())

    def fail_interrupted_jobs(self, reason):
        with self.conn:
            cur = self.conn.execute(
                "UPDATE jobs SET status='failed', finished_at=datetime('now'), "
                "failure_reason=? WHERE status IN ('pending', 'running')",
                (reason,),
            )
        return cur.rowcount

    def update_job(self, job_id, **kwargs):
        if not kwargs:
            return self.get_job(job_id)
        keys = list(kwargs.keys())
        params = [kwargs[k] for k in keys] + [job_id]
        with self.conn:
            self.conn.execute("UPDATE jobs SET %s WHERE id=?" % ",".join(["%s=?" % k for k in keys]), params)
        return self.get_job(job_id)

    def create_job_step(self, job_id, step):
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO job_steps(job_id, step_key, step_name, phase, target_scope, status) "
                "VALUES(?, ?, ?, ?, ?, 'pending')",
                (job_id, step["key"], step["name"], step.get("phase", ""), step.get("target_scope", "")),
            )
        return _row(self.conn.execute("SELECT * FROM job_steps WHERE id=?", (cur.lastrowid,)).fetchone())

    def update_job_step(self, step_id, **kwargs):
        if not kwargs:
            return None
        keys = list(kwargs.keys())
        with self.conn:
            self.conn.execute(
                "UPDATE job_steps SET %s WHERE id=?" % ",".join(["%s=?" % k for k in keys]),
                [kwargs[k] for k in keys] + [step_id],
            )

    def list_job_steps(self, job_id):
        steps = _rows(self.conn.execute("SELECT * FROM job_steps WHERE job_id=? ORDER BY id", (job_id,)).fetchall())
        for step in steps:
            step["nodes"] = _rows(
                self.conn.execute(
                    "SELECT jsn.*, n.hostname, n.ip, n.role FROM job_step_nodes jsn "
                    "JOIN nodes n ON n.id=jsn.node_id WHERE jsn.job_step_id=? ORDER BY jsn.id",
                    (step["id"],),
                ).fetchall()
            )
        return steps

    def create_job_step_node(self, job_step_id, node_id, log_path):
        with self.conn:
            cur = self.conn.execute(
                "INSERT INTO job_step_nodes(job_step_id, node_id, status, log_path) VALUES(?, ?, 'pending', ?)",
                (job_step_id, node_id, log_path),
            )
        return _row(self.conn.execute("SELECT * FROM job_step_nodes WHERE id=?", (cur.lastrowid,)).fetchone())

    def update_job_step_node(self, item_id, **kwargs):
        if not kwargs:
            return
        keys = list(kwargs.keys())
        with self.conn:
            self.conn.execute(
                "UPDATE job_step_nodes SET %s WHERE id=?" % ",".join(["%s=?" % k for k in keys]),
                [kwargs[k] for k in keys] + [item_id],
            )

    def get_job_step_node(self, item_id):
        return _row(
            self.conn.execute(
                "SELECT jsn.*, js.job_id, js.step_key, n.hostname, n.ip, n.role "
                "FROM job_step_nodes jsn "
                "JOIN job_steps js ON js.id=jsn.job_step_id "
                "JOIN nodes n ON n.id=jsn.node_id WHERE jsn.id=?",
                (item_id,),
            ).fetchone()
        )

    def add_precheck_result(self, cluster_id, job_id, node_id, check_key, check_name, severity, status, message, detail):
        with self.conn:
            self.conn.execute(
                "INSERT INTO precheck_results(cluster_id, job_id, node_id, check_key, check_name, severity, status, message, detail) "
                "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (cluster_id, job_id, node_id, check_key, check_name, severity, status, message, detail),
            )

    def list_precheck_results(self, job_id):
        return _rows(
            self.conn.execute(
                "SELECT pr.*, n.hostname, n.ip, n.role FROM precheck_results pr "
                "JOIN nodes n ON n.id=pr.node_id WHERE pr.job_id=? ORDER BY n.id, pr.id",
                (job_id,),
            ).fetchall()
        )

    def add_event(self, job_id, event_type, payload):
        with self.conn:
            self.conn.execute(
                "INSERT INTO job_events(job_id, event_type, payload) VALUES(?, ?, ?)",
                (job_id, event_type, json.dumps(payload, ensure_ascii=False)),
            )

    def list_events(self, job_id, after_id):
        events = _rows(
            self.conn.execute(
                "SELECT * FROM job_events WHERE job_id=? AND id>? ORDER BY id LIMIT 100",
                (job_id, after_id),
            ).fetchall()
        )
        for event in events:
            try:
                event["payload"] = json.loads(event.get("payload") or "{}")
            except ValueError:
                event["payload"] = {}
        return events

    def ensure_job_dirs(self, job_id):
        job = self.get_job(job_id)
        if not job:
            return
        for path in [job.get("log_dir"), os.path.dirname(job.get("config_yaml_path") or "")]:
            if path and not os.path.exists(path):
                os.makedirs(path)


def _serialize_setting(value):
    if isinstance(value, (dict, list, bool, int, float)):
        return json.dumps(value, ensure_ascii=False)
    if value is None:
        return ""
    return str(value)


def _decode_settings(rows):
    result = {}
    for row in rows:
        value = row["value"]
        try:
            result[row["key"]] = json.loads(value)
        except (TypeError, ValueError):
            result[row["key"]] = value
    return result
