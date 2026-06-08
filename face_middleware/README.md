# FaceAttend Middleware

FastAPI face-recognition middleware for FaceAttend Phase 1.

The service owns employee face registration and matching. It is intentionally
separate from Odoo so CPU-heavy face detection and ArcFace embedding generation
do not run inside the Odoo worker process.

## Endpoints

- `GET /health`
- `POST /register`
- `POST /match`
- `DELETE /employee/{employee_id}`

All mutating/recognition endpoints require an API key:

```http
X-API-Key: change-me
```

## Local Setup

```bash
cd face_middleware
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8019
```

InsightFace downloads its model pack on first use. For local API shape tests
without InsightFace, set:

```bash
FACE_MIDDLEWARE_EMBEDDING_BACKEND=dev
```

The dev backend is deterministic and is not suitable for production.

## Example Requests

```bash
curl http://localhost:8019/health
```

```bash
curl -X POST http://localhost:8019/register \
  -H 'X-API-Key: change-me' \
  -F employee_id=1 \
  -F employee_name='Demo Employee' \
  -F files=@frame1.jpg \
  -F files=@frame2.jpg \
  -F files=@frame3.jpg
```

```bash
curl -X POST http://localhost:8019/match \
  -H 'X-API-Key: change-me' \
  -F file=@scan.jpg
```

## Storage

The first implementation stores centroid embeddings in a local SQLite database
at `./data/face_middleware.sqlite3`. This keeps Phase 1 runnable on a local
machine before PostgreSQL/pgvector is introduced. The repository API is isolated
so PostgreSQL/pgvector can replace SQLite without changing the FastAPI routes.
