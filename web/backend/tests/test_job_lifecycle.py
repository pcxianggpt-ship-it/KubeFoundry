import os
import shutil
import sqlite3
import tempfile
import unittest

from kubefoundry.api.routes import create_app
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


class JobLifecycleTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="kf-lifecycle-")
        self.old_db_path = os.environ.get("KF_DB_PATH")
        self.old_data_dir = os.environ.get("KF_DATA_DIR")
        os.environ["KF_DATA_DIR"] = self.temp_dir
        os.environ["KF_DB_PATH"] = os.path.join(self.temp_dir, "kubefoundry.db")
        init_db()

    def tearDown(self):
        if self.old_db_path is None:
            os.environ.pop("KF_DB_PATH", None)
        else:
            os.environ["KF_DB_PATH"] = self.old_db_path
        if self.old_data_dir is None:
            os.environ.pop("KF_DATA_DIR", None)
        else:
            os.environ["KF_DATA_DIR"] = self.old_data_dir
        shutil.rmtree(self.temp_dir)

    def test_find_active_install_job_for_cluster(self):
        with Repository() as repo:
            cluster = repo.create_cluster({"name": "demo"})
            active = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
            repo.create_job(cluster["id"], "precheck", {}, "", self.temp_dir)
            found = repo.find_active_job(cluster["id"], "install")

        self.assertEqual(active["id"], found["id"])

    def test_recover_interrupted_jobs(self):
        with Repository() as repo:
            cluster = repo.create_cluster({"name": "demo"})
            pending = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
            running = repo.create_job(cluster["id"], "precheck", {}, "", self.temp_dir)
            finished = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)
            repo.update_job(running["id"], status="running")
            repo.update_job(finished["id"], status="success")

            recovered = repo.fail_interrupted_jobs("backend restarted")

            self.assertEqual(2, recovered)
            self.assertEqual("failed", repo.get_job(pending["id"])["status"])
            self.assertEqual("backend restarted", repo.get_job(pending["id"])["failure_reason"])
            self.assertEqual("failed", repo.get_job(running["id"])["status"])
            self.assertEqual("success", repo.get_job(finished["id"])["status"])

    def test_init_db_migrates_existing_jobs_table(self):
        db_path = os.environ["KF_DB_PATH"]
        os.remove(db_path)
        conn = sqlite3.connect(db_path)
        try:
            conn.execute(
                "CREATE TABLE jobs ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "cluster_id INTEGER NOT NULL, "
                "job_type TEXT NOT NULL, "
                "status TEXT NOT NULL DEFAULT 'pending'"
                ")"
            )
            conn.commit()
        finally:
            conn.close()

        init_db()

        conn = sqlite3.connect(db_path)
        try:
            columns = [row[1] for row in conn.execute("PRAGMA table_info(jobs)").fetchall()]
        finally:
            conn.close()
        self.assertIn("failure_reason", columns)

    def test_install_api_rejects_second_active_job(self):
        app = create_app()
        app.config["TESTING"] = True
        with Repository() as repo:
            cluster = repo.create_cluster({"name": "demo"})
            repo.create_node(
                cluster["id"],
                {"hostname": "master-1", "ip": "10.0.0.10", "role": "control_plane"},
            )
            active = repo.create_job(cluster["id"], "install", {}, "", self.temp_dir)

        response = app.test_client().post("/api/clusters/%s/install" % cluster["id"])

        self.assertEqual(409, response.status_code)
        self.assertEqual(active["id"], response.get_json()["job_id"])


if __name__ == "__main__":
    unittest.main()
