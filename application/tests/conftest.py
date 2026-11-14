import os
import sys

import pytest

# Make app.py importable when pytest is run from the application/ folder.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import app as app_module  # noqa: E402


@pytest.fixture
def client(monkeypatch):
    """Flask test client backed by a fresh in-memory sqlite DB."""
    monkeypatch.delenv("SQLCONNSTR_TransactionsDb", raising=False)
    app_module.reset_db()
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as c:
        yield c
    app_module.reset_db()
