# ─── Stage 1: builder ────────────────────────────────────────────────────────
# Imagen 1 con alias "builder"
FROM python:3.12-slim AS builder

# De la imagen oficial de uv, copia los binarios uv y uvx  a la carpeta /bin
# No instala solo copia, más rápido y deterministico.
COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
# Variables propias de uv:
# UV_COMPILE_BYTECODE=1: le dice a uv que compile los archivo .py a .pyc durante la instalación
#                        esto añade un tiempo adicional en builder pero acelera el arranque en la etapa runtime
# UV_LINK_MODE=copy: le dice a uv que copie los paquetes descargados (dependencias) hacia el .venv en lugar de
#                    crear hardlinks (comportamiento default de uv), usar copy dentro de un contenedor Docker
#                    evita comportamientos raros con el cache de uv entre capas

# El cache de Docker funciona por capa:
# Capa 1: Establecer caché base
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project --no-dev
# Modificaciones en pyproject.toml o uv.lock  -> uv sync se ejecuta
# Modificaciones en app/ o algun .py          -> uv sync usa caché y solo copia el código

# --locked: rechaza correr si uv.lock no está en sync con pyproject.toml. 
#           Garantiza reproducibilidad exacta.
# --no-install-project: instala todas las dependencias del pyproject.toml pero no el propio proyecto como paquete editable.
#                       Tiene sentido porque el código aún no fue copiado.
# --no-dev: excluye las dependencias marcadas como dev (pytest, pytest-cov). 
#           No las necesitas en la imagen de producción.

# Capa 2: Registro del proyecto en sí
# Copiar código fuente, modelo y
COPY app/ ./app/
COPY models/ ./models/
RUN uv sync --locked --no-dev
# las dependencias ya fueron instaladas en el paso previo (caché)
# este segundo uv sync solo registra el proyecto

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
# Imagen 2 nueva, Docker empieza un nuevo filesystem desde cero
FROM python:3.12-slim

# Metadatos que se ven en GHCR y en docker inspect
LABEL org.opencontainers.image.title="iris-classifier-api"
LABEL org.opencontainers.image.description="Servicio de inferencia Iris – Taller MLOps UNI 2026"

WORKDIR /app

# Copiar paquetes instalados en la etapa builder
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app ./app
COPY --from=builder /app/models ./models
# El uv binario, los caches de descarga, los archivos temporales del build,
# los headers de C — todo eso quedó en el builder y no contamina la imagen final.

# Activa el venv en la imagen
ENV PATH="/app/.venv/bin:$PATH"
# equivalente a hacer source .venv/bin/activate pero persistente en la imagen

# Usuario sin privilegios (buena práctica de seguridad)
RUN adduser --disabled-password --gecos "" appuser
USER appuser
# appuser es un usuario sin contraseña, sin shell, sin permisos especiales

EXPOSE 8000
# Solo documentacional, le dice a quien lea el Dockerfile que este container espera recibir
# tráfico en el puerto 8000. No abre ningún puerto por sí solo.
# El mapeo real ocurre con -p en docker run

# Docker tiene un daemon interno de monitoreo.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
# Cada 30 segundos ejecuta este comando dentro del container

# Se ejecuta cuando arranca el container
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
# --host 0.0.0.0 es crítico: le dice a uvicorn que escuche en todas las interfaces de red del container.
#                            Si pusiera 127.0.0.1 (loopback), el servidor solo sería accesible desde dentro
#                            del container mismo — el port mapping de Docker no podría llegar a él.
