from dataclasses import dataclass
from typing import Protocol

import numpy as np
import psycopg


@dataclass(frozen=True)
class EmployeeEmbedding:
    embedding_id: int | None
    employee_id: int
    employee_name: str | None
    embedding: np.ndarray
    source: str = "avatar_primary"
    active: bool = True
    score: float | None = None


class EmbeddingRepository(Protocol):
    def init_storage(self) -> None:
        ...

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> int:
        ...

    def add_variant(
        self,
        employee_id: int,
        employee_name: str | None,
        embedding: np.ndarray,
        source: str,
        active: bool,
        quality_score: float | None = None,
        max_active_embeddings: int | None = None,
    ) -> int:
        ...

    def approve_variant(self, employee_id: int, embedding_id: int, max_active_embeddings: int | None = None) -> bool:
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
                CREATE TABLE IF NOT EXISTS employee_embedding_variants (
                    id BIGSERIAL PRIMARY KEY,
                    employee_id BIGINT NOT NULL,
                    employee_name TEXT,
                    source TEXT NOT NULL DEFAULT 'avatar_primary',
                    active BOOLEAN NOT NULL DEFAULT TRUE,
                    quality_score DOUBLE PRECISION,
                    embedding VECTOR(512) NOT NULL,
                    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS employee_embedding_variants_embedding_hnsw
                ON employee_embedding_variants
                USING hnsw (embedding vector_cosine_ops)
                WHERE active
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS employee_embedding_variants_employee_idx
                ON employee_embedding_variants (employee_id, active, source, registered_at)
                """
            )
            conn.execute(
                """
                INSERT INTO employee_embedding_variants (employee_id, employee_name, source, active, embedding, registered_at)
                SELECT employee_id, employee_name, 'avatar_primary', TRUE, embedding, registered_at
                FROM employee_embeddings old
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM employee_embedding_variants existing
                    WHERE existing.employee_id = old.employee_id
                      AND existing.source = 'avatar_primary'
                      AND existing.active = TRUE
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

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> int:
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
            conn.execute(
                """
                UPDATE employee_embedding_variants
                SET active = FALSE
                WHERE employee_id = %s
                  AND source = 'avatar_primary'
                  AND active = TRUE
                """,
                (employee_id,),
            )
            row = conn.execute(
                """
                INSERT INTO employee_embedding_variants
                    (employee_id, employee_name, source, active, quality_score, embedding, registered_at)
                VALUES (%s, %s, 'avatar_primary', TRUE, 1.0, %s::vector, NOW())
                RETURNING id
                """,
                (employee_id, employee_name, vector),
            ).fetchone()
            return int(row[0])

    def add_variant(
        self,
        employee_id: int,
        employee_name: str | None,
        embedding: np.ndarray,
        source: str,
        active: bool,
        quality_score: float | None = None,
        max_active_embeddings: int | None = None,
    ) -> int:
        self.init_storage()
        vector = _pgvector_literal(embedding)
        with self._connect() as conn:
            row = conn.execute(
                """
                INSERT INTO employee_embedding_variants
                    (employee_id, employee_name, source, active, quality_score, embedding, registered_at)
                VALUES (%s, %s, %s, %s, %s, %s::vector, NOW())
                RETURNING id
                """,
                (employee_id, employee_name, source, active, quality_score, vector),
            ).fetchone()
            embedding_id = int(row[0])
            if active and max_active_embeddings:
                self._prune_active_variants(conn, employee_id, max_active_embeddings)
            return embedding_id

    def approve_variant(self, employee_id: int, embedding_id: int, max_active_embeddings: int | None = None) -> bool:
        self.init_storage()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE employee_embedding_variants
                SET active = TRUE,
                    source = 'adaptive_scan',
                    registered_at = NOW()
                WHERE id = %s
                  AND employee_id = %s
                  AND active = FALSE
                  AND source = 'review_candidate'
                """,
                (embedding_id, employee_id),
            )
            if cursor.rowcount and max_active_embeddings:
                self._prune_active_variants(conn, employee_id, max_active_embeddings)
            return bool(cursor.rowcount)

    def delete(self, employee_id: int) -> bool:
        self.init_storage()
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM employee_embeddings WHERE employee_id = %s", (employee_id,))
            variant_cursor = conn.execute(
                "DELETE FROM employee_embedding_variants WHERE employee_id = %s",
                (employee_id,),
            )
            return cursor.rowcount > 0 or variant_cursor.rowcount > 0

    def count(self) -> int:
        self.init_storage()
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) FROM employee_embedding_variants WHERE active = TRUE").fetchone()
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
                SELECT id, employee_id, employee_name, embedding::text, source, active, 1 - (embedding <=> %s::vector) AS score
                FROM employee_embedding_variants
                WHERE active = TRUE
                ORDER BY embedding <=> %s::vector
                LIMIT %s
                """,
                (vector, vector, limit),
            ).fetchall()

        return [
            EmployeeEmbedding(
                embedding_id=int(embedding_id),
                employee_id=int(employee_id),
                employee_name=employee_name,
                embedding=np.array([float(value) for value in embedding_text.strip("[]").split(",")], dtype=np.float32),
                source=source,
                active=bool(active),
                score=float(score),
            )
            for embedding_id, employee_id, employee_name, embedding_text, source, active, score in rows
        ]

    def _prune_active_variants(self, conn: psycopg.Connection, employee_id: int, max_active_embeddings: int) -> None:
        conn.execute(
            """
            DELETE FROM employee_embedding_variants
            WHERE id IN (
                SELECT id
                FROM employee_embedding_variants
                WHERE employee_id = %s
                  AND active = TRUE
                  AND source != 'avatar_primary'
                ORDER BY registered_at DESC
                OFFSET GREATEST(%s - (
                    SELECT COUNT(*)
                    FROM employee_embedding_variants
                    WHERE employee_id = %s
                      AND active = TRUE
                      AND source = 'avatar_primary'
                ), 0)
            )
            """,
            (employee_id, max_active_embeddings, employee_id),
        )


def _pgvector_literal(embedding: np.ndarray) -> str:
    values = [float(value) for value in embedding.astype(np.float32).tolist()]
    if len(values) != 512:
        raise ValueError(f"pgvector storage expects 512 dimensions, got {len(values)}")
    return "[" + ",".join(f"{value:.8f}" for value in values) + "]"
