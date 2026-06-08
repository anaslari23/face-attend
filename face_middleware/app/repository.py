from dataclasses import dataclass
from typing import Protocol

import numpy as np
import psycopg


@dataclass(frozen=True)
class EmployeeEmbedding:
    employee_id: int
    employee_name: str | None
    embedding: np.ndarray
    score: float | None = None


class EmbeddingRepository(Protocol):
    def init_storage(self) -> None:
        ...

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> None:
        ...

    def delete(self, employee_id: int) -> bool:
        ...

    def count(self) -> int:
        ...

    def health(self) -> bool:
        ...

    def nearest(self, query: np.ndarray, limit: int = 1) -> list[EmployeeEmbedding]:
        ...


class PgVectorEmbeddingRepository:
    def __init__(self, database_url: str):
        self.database_url = database_url
        self._storage_ready = False

    def _connect(self) -> psycopg.Connection:
        return psycopg.connect(self.database_url)

    def init_storage(self) -> None:
        if self._storage_ready:
            return
        with self._connect() as conn:
            conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS employee_embeddings (
                    employee_id BIGINT PRIMARY KEY,
                    employee_name TEXT,
                    embedding VECTOR(512) NOT NULL,
                    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS employee_embeddings_embedding_hnsw
                ON employee_embeddings
                USING hnsw (embedding vector_cosine_ops)
                """
            )
        self._storage_ready = True

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> None:
        self.init_storage()
        vector = _pgvector_literal(embedding)
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO employee_embeddings (employee_id, employee_name, embedding, registered_at)
                VALUES (%s, %s, %s::vector, NOW())
                ON CONFLICT (employee_id) DO UPDATE SET
                    employee_name = EXCLUDED.employee_name,
                    embedding = EXCLUDED.embedding,
                    registered_at = NOW()
                """,
                (employee_id, employee_name, vector),
            )

    def delete(self, employee_id: int) -> bool:
        self.init_storage()
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM employee_embeddings WHERE employee_id = %s", (employee_id,))
            return cursor.rowcount > 0

    def count(self) -> int:
        self.init_storage()
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) FROM employee_embeddings").fetchone()
            return int(row[0])

    def health(self) -> bool:
        try:
            self.init_storage()
            return True
        except psycopg.Error:
            return False

    def nearest(self, query: np.ndarray, limit: int = 1) -> list[EmployeeEmbedding]:
        self.init_storage()
        vector = _pgvector_literal(query)
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT employee_id, employee_name, 1 - (embedding <=> %s::vector) AS score
                FROM employee_embeddings
                ORDER BY embedding <=> %s::vector
                LIMIT %s
                """,
                (vector, vector, limit),
            ).fetchall()

        return [
            EmployeeEmbedding(
                employee_id=int(employee_id),
                employee_name=employee_name,
                embedding=query,
                score=float(score),
            )
            for employee_id, employee_name, score in rows
        ]


def _pgvector_literal(embedding: np.ndarray) -> str:
    values = [float(value) for value in embedding.astype(np.float32).tolist()]
    if len(values) != 512:
        raise ValueError(f"pgvector storage expects 512 dimensions, got {len(values)}")
    return "[" + ",".join(f"{value:.8f}" for value in values) + "]"
