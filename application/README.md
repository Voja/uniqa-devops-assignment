# Transactions API

Small Flask app exposing a health endpoint and a simple transactions API.
Uses Azure SQL (via pymssql) when a connection string is set, otherwise an in-memory SQLite DB.

## Run locally
    python -m venv .venv && . .venv/bin/activate
    pip install -r requirements-dev.txt
    python app.py            # http://localhost:8000/health

## Tests
    pytest --cov=.

## Environment variables
- `APP_ENV` (default `local`), `APP_VERSION` (default `0.0.0`), `PORT` (default `8000`)
- `SQLCONNSTR_TransactionsDb` – ADO.NET-style SQL Server connection string (App Service connection string
  "TransactionsDb"). Parsed and passed to `pymssql`, which ships as a self-contained wheel — no OS-level
  ODBC driver is needed on the App Service Linux image. Unset = in-memory SQLite (local runs and tests).
