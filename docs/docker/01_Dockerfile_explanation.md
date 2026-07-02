**1. El Dockerfile — Línea a línea**

**¿Por qué dos stages?**

La idea central es separar el entorno de construcción del entorno de ejecución. En el builder tienes uv, pip, compiladores, headers de C que scikit-learn pueda necesitar — herramientas de build pesadas que jamás necesitarás en producción. El runtime solo recibe lo estrictamente necesario para correr: el .venv ya listo, el código, y el modelo. El resultado es una imagen final más pequeña, sin superficie de ataque innecesaria.

**Stage 1: `builder`**
```js
FROM python:3.12-slim AS builder
```
`python:3.12-slim` es una imagen Debian recortada con Python 3.12 ya instalado. Le das el alias `builder` para poder referenciarlo desde el Stage 2 con `--from=builder`. En este punto Docker tiene un sistema de archivos limpio de ~130MB.

```js
COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/
```

Esta es la instrucción más ingeniosa del Dockerfile. En lugar de `pip install uv` o descargar un script de instalación, Docker hace un cross-image COPY: va a GHCR, descarga la imagen oficial de uv versión exacta `0.11.23`, extrae solo los binarios `/uv` y `/uvx`, y los pega en `/bin/` de tu builder. Es quirúrgico: tomas exactamente 2 archivos de otra imagen sin ejecutar nada de ella.

El beneficio es triple: versión fijada exactamente (el mismo `0.11.23` que en tu máquina y en CI), sin instalar con `apt` ni `curl | sh`, y sin que la imagen oficial de uv traiga sus propias capas al runtime.

```js
WORKDIR /app
```
Crea el directorio `/app` y lo establece como directorio de trabajo para todos los comandos siguientes (`RUN`, `COPY`, `CMD`). Crítico: ambos stages usan `/app` — esto resuelve el bug que encontramos antes donde los shebangs del venv apuntaban a `/build/.venv/bin/python3`, una ruta que no existía en el runtime.

```js
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
```
Dos variables de entorno que le cambian el comportamiento a uv durante el sync:

- `UV_COMPILE_BYTECODE=1`: después de instalar cada paquete, compila los `.py` a `.pyc` (bytecode de CPython). Esto hace que el arranque del container sea más rápido porque Python no tiene que compilar en el primer import — ya encontrará los `.pyc` listos. El tradeoff es que el build tarda un poco más, pero eso solo pasa una vez.
  
- `UV_LINK_MODE=copy`: por defecto `uv` usa hardlinks para instalar paquetes en el venv (más rápido, comparte inodes). En Docker esto puede fallar porque cada capa tiene su propio sistema de archivos y los hardlinks no pueden cruzar capas. `copy` obliga a copiar los archivos físicamente, garantizando que el `.venv` sea autocontenido y portable.

```js
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project --no-dev
```
Aquí está la **optimización de caché de capas** más importante del Dockerfile. Copias solo los archivos de metadatos de dependencias (no el código fuente) y corres `uv sync` antes de copiar `app/`.

¿Por qué? El caché de Docker funciona por capa: si ningún input de una instrucción cambió, reutiliza la capa cacheada. Si copiaras todo el código junto y luego hicieras `uv sync`, cualquier cambio en un `.py` de `app/` invalidaría el caché de `uv sync` y Docker reinstalaría todas las dependencias desde cero. Separándolo así:

- Solo `pyproject.toml` o `uv.lock` cambia → `uv sync` se re-ejecuta ✓
- Solo un `.py` de `app/` cambia → `uv sync` usa caché y solo copia el código ✓

Los flags del `uv sync`:

- `--locked`: rechaza correr si `uv.lock` no está en sync con `pyproject.toml`. Garantiza reproducibilidad exacta.
  
- `--no-install-project`: instala todas las dependencias del `pyproject.toml` pero no el propio proyecto como paquete editable. Tiene sentido porque el código aún no fue copiado.
  
- `--no-dev`: excluye las dependencias marcadas como `dev` (pytest, pytest-cov). No las necesitas en la imagen de producción.

```js
COPY app/ ./app/
COPY models/ ./models/
RUN uv sync --locked --no-dev
```

Ahora sí copias el código fuente y el modelo `.pkl`. El segundo `uv sync` completa la instalación: ahora que el proyecto existe como directorio, `uv` puede instalarlo correctamente. Como las dependencias ya están en el `.venv` desde el sync anterior (y están cacheadas), este segundo sync es instantáneo — solo registra el proyecto en sí.

**Stage 2: `runtime`**

```js
FROM python:3.12-slim
```
Imagen limpia nueva. Todo lo del `builder` desaparece conceptualmente — Docker empieza un nuevo filesystem desde cero. El `builder` no existe en la imagen final a menos que explícitamente copies algo de él.

```js
LABEL org.opencontainers.image.title="iris-classifier-api"
```
LABEL org.opencontainers.image.description="..."
Metadatos que se ven en GHCR y en `docker inspect`. No afectan el comportamiento, son como el `README` de la imagen.

```js
WORKDIR /app


COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app ./app
COPY --from=builder /app/models ./models
```

Aquí está la magia del multi-stage: traes exactamente 3 cosas del `builder`:

**1.** El .venv completo con todas las dependencias ya instaladas.

**2.** El código de la API.

**3.** El modelo Iris.

El `uv` binario, los caches de descarga, los archivos temporales del build, los headers de C — todo eso quedó en el `builder` y no contamina la imagen final.

```js
ENV PATH="/app/.venv/bin:$PATH"
```
Activa el virtual environment sin `source activate`. Python resuelve qué binario ejecutar buscando en el PATH de izquierda a derecha. Al poner `/app/.venv/bin` primero, `python`, `uvicorn`, `fastapi` — todos resuelven a los del venv, no al Python del sistema. Es el equivalente a hacer `source .venv/bin/activate` pero persistente en la imagen.

```js
RUN adduser --disabled-password --gecos "" appuser
```
USER appuser
Principio de mínimo privilegio. Por defecto los procesos en un container corren como `root` (UID 0) — si hay alguna vulnerabilidad en tu app o en una dependencia, el atacante tiene root dentro del container. `appuser` es un usuario sin contraseña, sin shell, sin permisos especiales. Cualquier intento de modificar `/etc/`, instalar paquetes, o escalar privilegios falla. El `RUN adduser` va antes del `USER appuser` porque crear usuarios requiere root.

```js
EXPOSE 8000
```
Solo documentacional — le dice a quien lea el Dockerfile que este container espera recibir tráfico en el puerto 8000. No abre ningún puerto por sí solo. El mapeo real ocurre con `-p` en `docker run`.

```js
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
```
Docker tiene un daemon interno de monitoreo. Cada 30 segundos ejecuta este comando dentro del container. Si el endpoint `/health` responde con 200, el container es `healthy`. Si falla 3 veces consecutivas, el estado pasa a `unhealthy` y orquestadores como Kubernetes pueden reemplazarlo automáticamente. `--start-period=10s` da 10 segundos de gracia al arranque antes de empezar a contar fallos (para que uvicorn tenga tiempo de iniciar).

```js
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```
El comando que se ejecuta cuando arranca el container. Usa formato JSON array (exec form) — esto hace que `uvicorn` sea directamente PID 1, lo que permite que las señales del SO (como `SIGTERM` que manda Kubernetes al hacer rolling update) lleguen directamente al proceso correcto. Si usaras el formato shell (`CMD uvicorn ...`), habría un `sh -c` como PID 1 que podría tragarse las señales.

--`host 0.0.0.0` es crítico: le dice a uvicorn que escuche en todas las interfaces de red del container. Si pusiera `127.0.0.1` (loopback), el servidor solo sería accesible desde dentro del container mismo — el port mapping de Docker no podría llegar a él.