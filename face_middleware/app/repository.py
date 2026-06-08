import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class EmployeeEmbedding:
    employee_id: int
    employee_name: str | None
    embedding: np.ndarray


class EmbeddingRepository:
    def __init__(self, database_path: str):
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.database_path)

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS employee_embeddings (
                    employee_id INTEGER PRIMARY KEY,
                    employee_name TEXT,
                    embedding_json TEXT NOT NULL,
                    embedding_dimension INTEGER NOT NULL,
                    registered_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> None:
        payload = json.dumps([float(value) for value in embedding.tolist()])
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO employee_embeddings (
                    employee_id, employee_name, embedding_json, embedding_dimension, registered_at
                )
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(employee_id) DO UPDATE SET
                    employee_name = excluded.employee_name,
                    embedding_json = excluded.embedding_json,
                    embedding_dimension = excluded.embedding_dimension,
                    registered_at = CURRENT_TIMESTAMP
                """,
                (employee_id, employee_name, payload, int(embedding.shape[0])),
            )

    def delete(self, employee_id: int) -> bool:
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM employee_embeddings WHERE employee_id = ?", (employee_id,))
            return cursor.rowcount > 0

    def count(self) -> int:
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) FROM employee_embeddings").fetchone()
            return int(row[0])

    def list_embeddings(self) -> list[EmployeeEmbedding]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT employee_id, employee_name, embedding_json FROM employee_embeddings"
            ).fetchall()

        records: list[EmployeeEmbedding] = []
        for employee_id, employee_name, embedding_json in rows:
            embedding = np.array(json.loads(embedding_json), dtype=np.float32)
            records.append(EmployeeEmbedding(employee_id=employee_id, employee_name=employee_name, embedding=embedding))
        return records
