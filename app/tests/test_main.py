def test_healthz_does_not_touch_the_database(client):
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json()["status"] == "alive"


def test_readyz_reports_the_database_as_reachable(client):
    response = client.get("/readyz")

    assert response.status_code == 200
    assert response.json()["database"] == "ok"


def test_create_hero_never_returns_the_secret_name(client):
    response = client.post(
        "/heroes/",
        json={"name": "Deadpond", "secret_name": "Dive Wilson", "age": 32},
    )

    assert response.status_code == 200

    body = response.json()
    assert body["name"] == "Deadpond"
    assert "secret_name" not in body


def test_hero_round_trips_through_the_database(client):
    created = client.post(
        "/heroes/",
        json={"name": "Spider-Boy", "secret_name": "Pedro Parqueador"},
    ).json()

    fetched = client.get(f"/heroes/{created['id']}")

    assert fetched.status_code == 200
    assert fetched.json()["name"] == "Spider-Boy"


def test_missing_hero_returns_404_not_500(client):
    response = client.get("/heroes/999999")

    assert response.status_code == 404
    assert response.json()["detail"] == "Hero not found"


def test_patch_only_changes_the_supplied_fields(client):
    created = client.post(
        "/heroes/",
        json={"name": "Rusty-Man", "secret_name": "Tommy Sharp", "age": 48},
    ).json()

    updated = client.patch(f"/heroes/{created['id']}", json={"age": 49}).json()

    assert updated["age"] == 49
    assert updated["name"] == "Rusty-Man"


def test_delete_removes_the_hero(client):
    created = client.post(
        "/heroes/",
        json={"name": "Black Lion", "secret_name": "Trevor Challa"},
    ).json()

    assert client.delete(f"/heroes/{created['id']}").status_code == 200
    assert client.get(f"/heroes/{created['id']}").status_code == 404


def test_openapi_schema_is_served(client):
    response = client.get("/openapi.json")

    assert response.status_code == 200
    assert "/heroes/" in response.json()["paths"]
