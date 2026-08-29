"""Hero API.

Application code is FastAPI's official SQL databases tutorial, taken from
https://fastapi.tiangolo.com/tutorial/sql-databases/ (docs_src/sql_databases/
tutorial002_an_py310.py). The models and CRUD routes below are unmodified.

Changes made to deploy it: the engine reads Postgres settings from the
environment instead of using a local SQLite file, and /healthz and /readyz
were added because the load balancer needs a target health check.
"""

import os
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query
from sqlalchemy import text
from sqlmodel import Field, Session, SQLModel, create_engine, select


class HeroBase(SQLModel):
    name: str = Field(index=True)
    age: int | None = Field(default=None, index=True)


class Hero(HeroBase, table=True):
    id: int | None = Field(default=None, primary_key=True)
    secret_name: str


class HeroPublic(HeroBase):
    id: int


class HeroCreate(HeroBase):
    secret_name: str


class HeroUpdate(HeroBase):
    name: str | None = None
    age: int | None = None
    secret_name: str | None = None


DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "tasksdb")
DB_USER = os.getenv("DB_USER", "tasks")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
BUILD_SHA = os.getenv("BUILD_SHA", "dev")

database_url = f"postgresql+psycopg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_engine(database_url, pool_pre_ping=True)


def create_db_and_tables():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]
app = FastAPI(title="hero-api", version=BUILD_SHA)


@app.on_event("startup")
def on_startup():
    create_db_and_tables()


@app.get("/healthz")
def healthz():
    return {"status": "alive", "build": BUILD_SHA}


@app.get("/readyz")
def readyz(session: SessionDep):
    session.exec(text("SELECT 1"))
    return {"status": "ready", "database": "ok", "build": BUILD_SHA}


@app.post("/heroes/", response_model=HeroPublic)
def create_hero(hero: HeroCreate, session: SessionDep):
    db_hero = Hero.model_validate(hero)
    session.add(db_hero)
    session.commit()
    session.refresh(db_hero)
    return db_hero


@app.get("/heroes/", response_model=list[HeroPublic])
def read_heroes(
    session: SessionDep,
    offset: int = 0,
    limit: Annotated[int, Query(le=100)] = 100,
):
    heroes = session.exec(select(Hero).offset(offset).limit(limit)).all()
    return heroes


@app.get("/heroes/{hero_id}", response_model=HeroPublic)
def read_hero(hero_id: int, session: SessionDep):
    hero = session.get(Hero, hero_id)
    if not hero:
        raise HTTPException(status_code=404, detail="Hero not found")
    return hero


@app.patch("/heroes/{hero_id}", response_model=HeroPublic)
def update_hero(hero_id: int, hero: HeroUpdate, session: SessionDep):
    hero_db = session.get(Hero, hero_id)
    if not hero_db:
        raise HTTPException(status_code=404, detail="Hero not found")
    hero_data = hero.model_dump(exclude_unset=True)
    hero_db.sqlmodel_update(hero_data)
    session.add(hero_db)
    session.commit()
    session.refresh(hero_db)
    return hero_db


@app.delete("/heroes/{hero_id}")
def delete_hero(hero_id: int, session: SessionDep):
    hero = session.get(Hero, hero_id)
    if not hero:
        raise HTTPException(status_code=404, detail="Hero not found")
    session.delete(hero)
    session.commit()
    return {"ok": True}
