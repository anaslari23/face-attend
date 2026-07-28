FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY template_worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY template_worker/app.py .
COPY face_attend_app/assets/models/w600k_r50.onnx /models/w600k_r50.onnx

RUN useradd --system worker && chown -R worker:worker /app /models
USER worker
EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
