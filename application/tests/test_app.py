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
    assert cfg == {
        "server": "sql-uniqa-abc12.database.windows.net",
        "port": 1433,
        "database": "sqldb-uniqa-dev",
        "user": "sqladminuser",
        "password": "s3cr=et",
    }

    # "User ID"/"Password" aliases, mixed-case keys, no tcp: prefix, no port -> default 1433.
    cfg = parse_sql_connection_string(
        "SERVER=myhost.example.com; database=db1; User ID=alice; Password=pw; Encrypt=yes"
    )
    assert cfg == {
        "server": "myhost.example.com",
        "port": 1433,
        "database": "db1",
        "user": "alice",
        "password": "pw",
    }

    # Non-default port and "Data Source"/"Initial Catalog" ADO.NET synonyms.
    cfg = parse_sql_connection_string("Data Source=tcp:h,1444;Initial Catalog=c;Uid=u;Pwd=p")
    assert cfg["server"] == "h" and cfg["port"] == 1444 and cfg["database"] == "c"


def test_index_renders_env(monkeypatch, client):
    monkeypatch.setenv("APP_ENV", "test")
    resp = client.get("/")
    assert resp.status_code == 200
    html = resp.get_data(as_text=True)
    assert "Transactions Service" in html
    assert 'data-env="test"' in html and ">test<" in html  # env badge
    assert "Request path" in html and "Private Endpoint" in html  # request-path strip


def test_form_create_redirects(client):
    resp = client.post("/transactions/form", data={"amount": "42.10", "description": "lunch"})
    assert resp.status_code == 302
    assert resp.headers["Location"].endswith("/")
    page = client.get("/").get_data(as_text=True)
    assert "lunch" in page and "42.10" in page
    assert "Transaction #1 added." in page  # success flash shown once after redirect


def test_form_invalid_amount_shows_error(client):
    resp = client.post("/transactions/form", data={"amount": "abc", "description": "x"})
    assert resp.status_code == 302
    page = client.get("/").get_data(as_text=True)
    assert "Amount is required and must be a number." in page
    assert client.get("/transactions").get_json() == []  # nothing was inserted


def test_health_deep_ok(client):
    body = client.get("/health/deep").get_json()
    assert body["status"] == "ok"
    assert body["db"]["ok"] is True
    assert body["db"]["backend"] == "sqlite"
    assert isinstance(body["db"]["latency_ms"], int)
