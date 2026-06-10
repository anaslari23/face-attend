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

## PostgreSQL + pgvector

Production embeddings are stored in PostgreSQL with the `pgvector` extension.
Create a database and user, then set:

```bash
FACE_MIDDLEWARE_DATABASE_URL=postgresql://face_attend:face_attend@127.0.0.1:5433/face_attend
```

The middleware creates the `vector` extension, embedding table, and HNSW index
on startup when the configured database user has permission.

## Example Requests

```bash
curl http://localhost:8019/health
```

```bash
curl -X POST http://localhost:8019/register \
  -H 'X-API-Key: change-me' \
  -F employee_id=1 \
  -F employee_name='Demo Employee' \
  -F files=@face.jpg
```

```bash
curl -X POST http://localhost:8019/match \
  -H 'X-API-Key: change-me' \
  -F file=@scan.jpg
```

## Anti-Spoofing

`FACE_MIDDLEWARE_ANTI_SPOOFING_ENABLED=true` makes `/match` and `/match/faces`
fail closed unless passive liveness passes. Place the production ONNX model at
`FACE_MIDDLEWARE_ANTISPOOF_MODEL_PATH` and keep
`FACE_MIDDLEWARE_ALLOW_ANTISPOOF_STUB=false` for real attendance use. Avatar
registration through `/register` intentionally skips anti-spoofing because Odoo
avatars are stored photos.
