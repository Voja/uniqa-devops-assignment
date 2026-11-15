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


def test_parse_sql_connection_string():
    from app import parse_sql_connection_string

    # Exact shape produced by Terraform (Uid/Pwd aliases, tcp: prefix, explicit port).
    cfg = parse_sql_connection_string(
        "Server=tcp:sql-uniqa-abc12.database.windows.net,1433;Database=sqldb-uniqa-dev;"
        "Uid=sqladminuser;Pwd=s3cr=et;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    assert cfg == {"server": "sql-uniqa-abc12.database.windows.net", "port": 1433,
                   "database": "sqldb-uniqa-dev", "user": "sqladminuser", "password": "s3cr=et"}

    # "User ID"/"Password" aliases, mixed-case keys, no tcp: prefix, no port -> default 1433.
    cfg = parse_sql_connection_string(
        "SERVER=myhost.example.com; database=db1; User ID=alice; Password=pw; Encrypt=yes"
    )
    assert cfg == {"server": "myhost.example.com", "port": 1433, "database": "db1",
                   "user": "alice", "password": "pw"}

    # Non-default port and "Data Source"/"Initial Catalog" ADO.NET synonyms.
    cfg = parse_sql_connection_string("Data Source=tcp:h,1444;Initial Catalog=c;Uid=u;Pwd=p")
    assert cfg["server"] == "h" and cfg["port"] == 1444 and cfg["database"] == "c"
