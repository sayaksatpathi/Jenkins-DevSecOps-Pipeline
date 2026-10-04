from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


# ─── Root endpoint ────────────────────────────────────────────────────────────

def test_root_status_200():
    assert client.get("/").status_code == 200


def test_root_has_required_keys():
    body = client.get("/").json()
    assert "service" in body
    assert "version" in body
    assert "status" in body


def test_root_service_name():
    assert client.get("/").json()["service"] == "jenkinsforge"


def test_root_status_value():
    assert client.get("/").json()["status"] == "ok"


def test_root_version_present():
    version = client.get("/").json()["version"]
    assert version and isinstance(version, str)


# ─── Health endpoint ───────────────────────────────────────────────────────────

def test_health_status_200():
    assert client.get("/health").status_code == 200


def test_health_has_required_keys():
    body = client.get("/health").json()
    assert "service" in body
    assert "version" in body
    assert "status" in body


def test_health_status_value():
    assert client.get("/health").json()["status"] == "healthy"


def test_health_service_name():
    assert client.get("/health").json()["service"] == "jenkinsforge"


def test_health_version_present():
    version = client.get("/health").json()["version"]
    assert version and isinstance(version, str)


# ─── Consistency ──────────────────────────────────────────────────────────────

def test_root_and_health_same_service():
    root_service   = client.get("/").json()["service"]
    health_service = client.get("/health").json()["service"]
    assert root_service == health_service


def test_root_and_health_same_version():
    root_ver   = client.get("/").json()["version"]
    health_ver = client.get("/health").json()["version"]
    assert root_ver == health_ver


# ─── Negative cases ───────────────────────────────────────────────────────────

def test_unknown_path_404():
    assert client.get("/nonexistent").status_code == 404


def test_health_method_not_allowed():
    assert client.post("/health").status_code == 405
