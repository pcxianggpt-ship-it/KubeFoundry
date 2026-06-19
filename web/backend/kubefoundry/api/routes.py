import json
import os
import time

from flask import Flask, Response, jsonify, request, stream_with_context

from kubefoundry.installer.context import build_cluster_context, export_cluster_yaml, import_cluster_yaml
from kubefoundry.installer.precheck import start_precheck_job
from kubefoundry.installer.runner import start_install_job
from kubefoundry.store.db import get_db_path, init_db
from kubefoundry.store.repository import Repository


def create_app():
    app = Flask(__name__)
    init_db()

    def repo():
        return Repository()

    def payload():
        data = request.get_json(silent=True)
        return data if isinstance(data, dict) else {}

    @app.route("/api/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok", "database": get_db_path()})

    @app.route("/api/init-db", methods=["POST"])
    def initialize_database():
        init_db()
        return jsonify({"status": "ok", "database": get_db_path()})

    @app.route("/api/clusters", methods=["GET"])
    def list_clusters():
        return jsonify({"items": repo().list_clusters()})

    @app.route("/api/clusters", methods=["POST"])
    def create_cluster():
        item = repo().create_cluster(payload())
        return jsonify(item), 201

    @app.route("/api/clusters/<int:cluster_id>", methods=["GET"])
    def get_cluster(cluster_id):
        item = repo().get_cluster(cluster_id)
        if not item:
            return jsonify({"error": "cluster not found"}), 404
        item["nodes"] = repo().list_nodes(cluster_id)
        item["ssh_credentials"] = _public_ssh_credentials(repo().get_ssh_credentials(cluster_id))
        return jsonify(item)

    @app.route("/api/clusters/<int:cluster_id>", methods=["PUT"])
    def update_cluster(cluster_id):
        item = repo().update_cluster(cluster_id, payload())
        if not item:
            return jsonify({"error": "cluster not found"}), 404
        return jsonify(item)

    @app.route("/api/clusters/<int:cluster_id>", methods=["DELETE"])
    def delete_cluster(cluster_id):
        if not repo().delete_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        return jsonify({"status": "ok"})

    @app.route("/api/clusters/<int:cluster_id>/nodes", methods=["GET"])
    def list_nodes(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        return jsonify({"items": repo().list_nodes(cluster_id)})

    @app.route("/api/clusters/<int:cluster_id>/nodes", methods=["POST"])
    def create_node(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        try:
            item = repo().create_node(cluster_id, payload())
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400
        return jsonify(item), 201

    @app.route("/api/nodes/<int:node_id>", methods=["PUT"])
    def update_node(node_id):
        item = repo().update_node(node_id, payload())
        if not item:
            return jsonify({"error": "node not found"}), 404
        return jsonify(item)

    @app.route("/api/nodes/<int:node_id>", methods=["DELETE"])
    def delete_node(node_id):
        if not repo().delete_node(node_id):
            return jsonify({"error": "node not found"}), 404
        return jsonify({"status": "ok"})

    @app.route("/api/clusters/<int:cluster_id>/ssh-credentials", methods=["PUT"])
    def upsert_ssh_credentials(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        data = payload()
        if data.get("auth_type", "key") != "key":
            return jsonify({"error": "v0.1.0 only supports SSH key authentication"}), 400
        safe_data = {
            "auth_type": "key",
            "username": data.get("username"),
            "private_key_path": data.get("private_key_path"),
        }
        return jsonify(_public_ssh_credentials(repo().upsert_ssh_credentials(cluster_id, safe_data)))

    @app.route("/api/settings", methods=["GET"])
    def get_settings():
        return jsonify(repo().get_settings())

    @app.route("/api/settings", methods=["PUT"])
    def upsert_settings():
        return jsonify(repo().upsert_settings(payload()))

    @app.route("/api/clusters/<int:cluster_id>/settings", methods=["GET"])
    def get_cluster_settings(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        return jsonify(repo().get_cluster_settings(cluster_id))

    @app.route("/api/clusters/<int:cluster_id>/settings", methods=["PUT"])
    def upsert_cluster_settings(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        return jsonify(repo().upsert_cluster_settings(cluster_id, payload()))

    @app.route("/api/clusters/<int:cluster_id>/context", methods=["GET"])
    def get_context(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        return jsonify(build_cluster_context(cluster_id))

    @app.route("/api/clusters/<int:cluster_id>/import-yaml", methods=["POST"])
    def import_yaml(cluster_id):
        data = payload()
        yaml_path = data.get("path")
        yaml_text = data.get("content")
        try:
            result = import_cluster_yaml(cluster_id, yaml_path=yaml_path, yaml_text=yaml_text)
            return jsonify(result)
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/clusters/<int:cluster_id>/export-yaml", methods=["POST"])
    def export_yaml(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        data = payload()
        path = data.get("path")
        try:
            return jsonify({"path": export_cluster_yaml(cluster_id, path)})
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/clusters/<int:cluster_id>/precheck", methods=["POST"])
    def create_precheck(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        if not repo().list_nodes(cluster_id):
            return jsonify({"error": "cluster has no nodes"}), 400
        job = start_precheck_job(cluster_id)
        return jsonify(job), 202

    @app.route("/api/clusters/<int:cluster_id>/install", methods=["POST"])
    def create_install(cluster_id):
        if not repo().get_cluster(cluster_id):
            return jsonify({"error": "cluster not found"}), 404
        if not repo().list_nodes(cluster_id):
            return jsonify({"error": "cluster has no nodes"}), 400
        data = payload()
        job = start_install_job(cluster_id, selected_steps=data.get("steps"))
        return jsonify(job), 202

    @app.route("/api/jobs", methods=["GET"])
    def list_jobs():
        cluster_id = request.args.get("cluster_id")
        return jsonify({"items": repo().list_jobs(cluster_id)})

    @app.route("/api/jobs/<int:job_id>", methods=["GET"])
    def get_job(job_id):
        item = repo().get_job(job_id)
        if not item:
            return jsonify({"error": "job not found"}), 404
        return jsonify(item)

    @app.route("/api/jobs/<int:job_id>/steps", methods=["GET"])
    def get_job_steps(job_id):
        if not repo().get_job(job_id):
            return jsonify({"error": "job not found"}), 404
        return jsonify({"items": repo().list_job_steps(job_id)})

    @app.route("/api/jobs/<int:job_id>/precheck-results", methods=["GET"])
    def get_precheck_results(job_id):
        if not repo().get_job(job_id):
            return jsonify({"error": "job not found"}), 404
        return jsonify({"items": repo().list_precheck_results(job_id)})

    @app.route("/api/jobs/<int:job_id>/logs", methods=["GET"])
    def get_job_logs(job_id):
        job = repo().get_job(job_id)
        if not job:
            return jsonify({"error": "job not found"}), 404
        log_dir = job.get("log_dir")
        log_path = os.path.join(log_dir, "job.log") if log_dir else ""
        if not log_path or not os.path.exists(log_path):
            return jsonify({"content": ""})
        with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
            return jsonify({"content": fh.read()})

    @app.route("/api/jobs/<int:job_id>/config-yaml", methods=["GET"])
    def get_job_config_yaml(job_id):
        job = repo().get_job(job_id)
        if not job:
            return jsonify({"error": "job not found"}), 404
        path = job.get("config_yaml_path")
        if not path or not os.path.exists(path):
            return jsonify({"error": "config yaml not found"}), 404
        with open(path, "r", encoding="utf-8") as fh:
            return Response(fh.read(), mimetype="text/yaml")

    @app.route("/api/jobs/<int:job_id>/config-snapshot", methods=["GET"])
    def get_job_config_snapshot(job_id):
        job = repo().get_job(job_id)
        if not job:
            return jsonify({"error": "job not found"}), 404
        try:
            return jsonify(json.loads(job.get("config_snapshot") or "{}"))
        except ValueError:
            return jsonify({"error": "invalid config snapshot"}), 500

    @app.route("/api/jobs/<int:job_id>/events", methods=["GET"])
    def job_events(job_id):
        if not repo().get_job(job_id):
            return jsonify({"error": "job not found"}), 404
        try:
            initial_last_id = int(request.args.get("last_id", "0"))
        except ValueError:
            return jsonify({"error": "last_id must be an integer"}), 400

        @stream_with_context
        def stream():
            last_id = initial_last_id
            idle_count = 0
            while True:
                events = repo().list_events(job_id, last_id)
                for event in events:
                    last_id = event["id"]
                    yield "id: %s\n" % event["id"]
                    yield "event: %s\n" % event["event_type"]
                    yield "data: %s\n\n" % json.dumps(event, ensure_ascii=False)
                job = repo().get_job(job_id)
                if job and job.get("status") in ("success", "failed", "canceled") and not events:
                    idle_count += 1
                    if idle_count >= 2:
                        break
                else:
                    idle_count = 0
                time.sleep(1)

        return Response(stream(), mimetype="text/event-stream")

    return app


def _public_ssh_credentials(credentials):
    if not credentials:
        return None
    return {
        "id": credentials.get("id"),
        "cluster_id": credentials.get("cluster_id"),
        "auth_type": credentials.get("auth_type"),
        "username": credentials.get("username"),
        "private_key_path": credentials.get("private_key_path"),
        "created_at": credentials.get("created_at"),
        "updated_at": credentials.get("updated_at"),
    }
