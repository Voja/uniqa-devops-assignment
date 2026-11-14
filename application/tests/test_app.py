def test_health_returns_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_health_reports_env(monkeypatch, client):
    monkeypatch.setenv("APP_ENV", "test")
    resp = client.get("/health")
    assert resp.get_json()["env"] == "test"


def test_create_transaction_returns_201(client):
    resp = client.post("/transactions", json={"amount": 12.5, "description": "coffee"})
    assert resp.status_code == 201
    body = resp.get_json()
    assert body["id"] == 1
    assert body["amount"] == 12.5
    assert body["description"] == "coffee"


def test_create_transaction_missing_amount_returns_400(client):
    resp = client.post("/transactions", json={"description": "no amount"})
    assert resp.status_code == 400


def test_list_transactions_contains_created(client):
    client.post("/transactions", json={"amount": 99, "description": "rent"})
    resp = client.get("/transactions")
    assert resp.status_code == 200
    items = resp.get_json()
    assert any(t["description"] == "rent" and t["amount"] == 99 for t in items)
