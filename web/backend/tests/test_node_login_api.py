import os
import shutil
import tempfile

import pytest

from kubefoundry.api.routes import create_app
from kubefoundry.store.db import init_db
from kubefoundry.store.repository import Repository


@pytest.fixture()
def isolated_env():
    temp_dir = tempfile.mkdtemp(prefix="kf-node-login-")
    old_db_path = os.environ.get("KF_DB_PATH")
    old_data_dir = os.environ.get("KF_DATA_DIR")
    os.environ["KF_DATA_DIR"] = temp_dir
    os.environ["KF_DB_PATH"] = os.path.join(temp_dir, "kubefoundry.db")
    init_db()
    try:
        yield temp_dir
    finally:
        if old_db_path is None:
            os.environ.pop("KF_DB_PATH", None)
        else:
            os.environ["KF_DB_PATH"] = old_db_path
        if old_data_dir is None:
            os.environ.pop("KF_DATA_DIR", None)
        else:
            os.environ["KF_DATA_DIR"] = old_data_dir
        shutil.rmtree(temp_dir)


@pytest.fixture()
def client(isolated_env):
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


@pytest.fixture()
def repo(isolated_env):
    with Repository() as repository:
        yield repository


def test_cluster_schema_does_not_expose_install_mode(client, repo):
    response = client.post("/api/clusters", json={"name": "demo", "install_mode": "online"})
    assert response.status_code == 201
    cluster = response.get_json()
    assert "install_mode" not in cluster

    detail = client.get("/api/clusters/%s" % cluster["id"]).get_json()
    assert "install_mode" not in detail

    columns = [row["name"] for row in repo.conn.execute("PRAGMA table_info(clusters)").fetchall()]
    assert "install_mode" not in columns


def test_node_password_is_not_returned(client):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    response = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={
            "hostname": "k8s1",
            "ip": "192.168.123.139",
            "role": "control_plane",
            "password": "Secret123!",
            "ssh_user": "admin",
            "ssh_port": 2222,
            "os_type": "manual",
            "arch": "arm64",
        },
    )
    assert response.status_code == 201
    node = response.get_json()
    assert node["has_password"] is True
    assert node["ssh_user"] == "root"
    assert node["ssh_port"] == 22
    assert node["os_type"] == ""
    assert node["arch"] == ""
    assert "password" not in node
    assert "login_password_encrypted" not in node


def test_node_update_empty_password_keeps_existing_password(client, repo):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    node = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "control_plane", "password": "Secret123!"},
    ).get_json()
    before = repo.get_node_private(node["id"])["login_password_encrypted"]

    response = client.put("/api/nodes/%s" % node["id"], json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "control_plane", "password": ""})
    assert response.status_code == 200
    after = repo.get_node_private(node["id"])["login_password_encrypted"]
    assert after == before


def test_copy_nodes_creates_drafts_and_copies_password_ciphertext(client, repo):
    cluster = client.post("/api/clusters", json={"name": "demo"}).get_json()
    node = client.post(
        "/api/clusters/%s/nodes" % cluster["id"],
        json={"hostname": "k8s1", "ip": "192.168.123.139", "role": "worker", "password": "Secret123!"},
    ).get_json()

    response = client.post("/api/clusters/%s/nodes/copy" % cluster["id"], json={"node_ids": [node["id"]]})
    assert response.status_code == 201
    copied = response.get_json()["items"][0]
    assert copied["is_draft"] is True
    assert copied["hostname"] == "k8s1"
    assert copied["ip"] == "192.168.123.139"
    assert copied["has_password"] is True
    assert repo.get_node_private(copied["id"])["login_password_encrypted"] == repo.get_node_private(node["id"])["login_password_encrypted"]
