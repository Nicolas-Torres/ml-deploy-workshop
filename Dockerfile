# ─── Stage 1: builder ────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project --no-dev

# Copiar código fuente y modelo
COPY app/ ./app/
COPY models/ ./models/
RUN uv sync --locked --no-dev

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
FROM python:3.12-slim

LABEL org.opencontainers.image.title="iris-classifier-api"
LABEL org.opencontainers.image.description="Servicio de inferencia Iris – Taller MLOps UNI 2026"

WORKDIR /app

# Copiar paquetes instalados del builder
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app ./app
COPY --from=builder /app/models ./models

ENV PATH="/app/.venv/bin:$PATH"

# Usuario sin privilegios (buena práctica de seguridad)
RUN adduser --disabled-password --gecos "" appuser
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
