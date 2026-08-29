import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@pytest.fixture(scope="module")
def client():
    if not os.getenv("DB_HOST"):
        pytest.skip("DB_HOST is not set; these tests need a live Postgres")

    from main import SQLModel, app, engine

    SQLModel.metadata.drop_all(engine)

    with TestClient(app) as test_client:
        yield test_client

    SQLModel.metadata.drop_all(engine)
