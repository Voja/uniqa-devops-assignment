"""Minimal transactions API (Flask) used for the DevOps assignment."""
import os
import sqlite3

from flask import Flask, jsonify, request

app = Flask(__name__)

# Azure App Service exposes a "SQLServer" connection string named "TransactionsDb"
# to the app as the environment variable SQLCONNSTR_TransactionsDb.
CONN_ENV = "SQLCONNSTR_TransactionsDb"

# Module-level sqlite connection, used only when no SQL Server is configured.
_sqlite = None
_schema_ready = False


def _is_mssql():
    """True when a SQL Server connection string is configured (T-SQL dialect)."""
    return bool(os.environ.get(CONN_ENV))


def reset_db():
    """Drop the in-memory sqlite DB so every test starts from a clean state."""
    global _sqlite, _schema_ready
    if _sqlite is not None:
        _sqlite.close()
    _sqlite, _schema_ready = None, False


def get_connection():
    """Return a DB connection: pyodbc for SQL Server, sqlite3 in-memory otherwise."""
    global _sqlite, _schema_ready
    if _is_mssql():
        import pyodbc  # lazy import: tests/local runs don't need the ODBC driver

        conn = pyodbc.connect(os.environ[CONN_ENV])
    else:
        if _sqlite is None:
            _sqlite = sqlite3.connect(":memory:", check_same_thread=False)
        conn = _sqlite
    if not _schema_ready:  # create the table on first use
        if _is_mssql():
            ddl = ("IF OBJECT_ID('Transactions') IS NULL CREATE TABLE Transactions ("
                   "Id INT IDENTITY(1,1) PRIMARY KEY, Amount DECIMAL(18,2) NOT NULL, "
                   "Description NVARCHAR(200), CreatedAt DATETIME DEFAULT GETDATE())")
        else:
            ddl = ("CREATE TABLE IF NOT EXISTS Transactions ("
                   "Id INTEGER PRIMARY KEY AUTOINCREMENT, Amount DECIMAL(18,2) NOT NULL, "
                   "Description NVARCHAR(200), CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP)")
        conn.cursor().execute(ddl)
        conn.commit()
        _schema_ready = True
    return conn


def _to_dict(row):
    """Convert a DB row (Id, Amount, Description, CreatedAt) into JSON-friendly dict."""
    return {"id": row[0], "amount": float(row[1]), "description": row[2],
            "created_at": str(row[3])}


@app.get("/health")
def health():
    # Liveness/readiness probe used by App Service health check and monitoring.
    return jsonify(status="ok", env=os.environ.get("APP_ENV", "local"),
                   version=os.environ.get("APP_VERSION", "0.0.0"))


@app.get("/transactions")
def list_transactions():
    # Return the 20 most recent transactions (TOP vs LIMIT depends on dialect).
    top, limit = ("TOP 20", "") if _is_mssql() else ("", "LIMIT 20")
    cur = get_connection().cursor()
    # {top}/{limit} are hard-coded literals above, never user input -> safe to format.
    cur.execute(f"SELECT {top} Id, Amount, Description, CreatedAt "  # nosec B608
                f"FROM Transactions ORDER BY Id DESC {limit}")
    return jsonify([_to_dict(r) for r in cur.fetchall()])


@app.post("/transactions")
def create_transaction():
    # Validate input: amount is required and must be a real number (bool excluded).
    data = request.get_json(silent=True) or {}
    amount = data.get("amount")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)):
        return jsonify(error="'amount' is required and must be a number"), 400
    description = str(data.get("description", ""))[:200]
    conn = get_connection()
    cur = conn.cursor()
    # Parameterised queries prevent SQL injection; both drivers use '?' placeholders.
    if _is_mssql():  # OUTPUT returns the new identity in the same statement
        cur.execute("INSERT INTO Transactions (Amount, Description) OUTPUT INSERTED.Id "
                    "VALUES (?, ?)", (amount, description))
        new_id = int(cur.fetchone()[0])
    else:
        cur.execute("INSERT INTO Transactions (Amount, Description) VALUES (?, ?)",
                    (amount, description))
        new_id = cur.lastrowid
    conn.commit()
    cur.execute("SELECT Id, Amount, Description, CreatedAt FROM Transactions WHERE Id = ?",
                (new_id,))
    return jsonify(_to_dict(cur.fetchone())), 201


if __name__ == "__main__":
    # Bind to all interfaces: required inside the App Service / container sandbox.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))  # nosec B104
