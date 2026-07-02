**2. docker build — Qué pasa por detrás**
```
docker build -t curso-mlops:v1 .
```
**El . es el build context.** Docker comprime todo ese directorio y lo envía al Docker daemon (que puede ser local o remoto). Por eso existe `.dockerignore` — si no excluyeras .`venv/`, `__pycache__`/, `.git/` del contexto, estarías enviando cientos de MB innecesarios antes de siquiera empezar el build.

Lo que hace el daemon paso a paso:

Stage 1:

```
[1/8] FROM python:3.12-slim AS builder
```

Descarga la imagen base (si no la tiene en caché local). Las imágenes se guardan en capas, y cada capa es un hash SHA256 de su contenido. Si la ya tienes, usa la cacheada.

```
[2/8] COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/
```
Docker descarga la imagen de uv (si no la tiene), monta su filesystem temporalmente, extrae /uv y /uvx, y los agrega como una nueva capa sobre la imagen base.
```
[3/8] WORKDIR /app
[4/8] ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
```
Capas livianas — solo metadata. No transfieren archivos.
```
[5/8] COPY pyproject.toml uv.lock ./
```
Docker calcula un hash de pyproject.toml y uv.lock. Si coincide con el de la capa cacheada → CACHED, salta al siguiente. Si no → crea nueva capa.
```
[6/8] RUN uv sync --locked --no-install-project --no-dev
```
Si la capa anterior fue CACHED y esta también fue CACHED → este uv sync tarda 0 segundos. Si no → uv lee el uv.lock, descarga los paquetes, los instala en /app/.venv/, compila .pyc. Esta capa puede tardar 30-60 segundos la primera vez.
```
[7/8] COPY app/ ./app/
[8/8] COPY models/ ./models/
[9/8] RUN uv sync --locked --no-dev
```
Si cambiaste un .py → las capas 7, 8, 9 se re-ejecutan, pero la 6 (las dependencias) sigue siendo CACHED.

Stage 2: 

Nuevo FROM python:3.12-slim → capas limpias, y los 3 COPY --from=builder traen solo lo que necesitas. El daemon descarta todas las capas intermedias del builder que no fueron copiadas.

La imagen final tiene aproximadamente esta estructura de capas (de abajo a arriba):

```
[base]  python:3.12-slim         ~130 MB  (read-only, compartida entre imágenes)
[+]     LABEL                    ~0 B
[+]     WORKDIR /app             ~0 B
[+]     COPY .venv               ~400 MB  (scikit-learn + numpy + fastapi + uvicorn)
[+]     COPY app/                ~50 KB
[+]     COPY models/             ~5 KB
[+]     ENV PATH=...             ~0 B
[+]     RUN adduser              ~1 KB
[+]     EXPOSE / HEALTHCHECK     ~0 B
        ─────────────────────────────
        Total:                   ~600 MB
```

Cada capa es inmutable y se identifica por su hash. Si haces un segundo build sin cambiar nada, todas son CACHED y el build tarda < 1 segundo.