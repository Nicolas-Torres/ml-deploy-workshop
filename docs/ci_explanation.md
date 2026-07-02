# CI – Iris Classifier

**1. Triggers — cuándo se ejecuta el workflow**
```yaml
on:
  push:
    branches: [main, develop]
    paths-ignore: [...]
  pull_request:
    branches: [main]
    paths-ignore: [...]
```
El workflow reacciona a dos eventos distintos, cada uno con su propia lógica:

- **`push` a `main` o `develop`**: se dispara cada vez que llegan commits directamente a esas ramas — ya sea un push normal o el merge commit que GitHub genera al aceptar un PR.
  
- **`pull_request` hacia `main`**: se dispara cuando abres un PR contra main, o cuando le agregas commits nuevos mientras sigue abierto (lo que viste hace poco con el PR de docs/).

El `paths-ignore` es un filtro que se evalúa antes de decidir si el workflow corre. Si todos los archivos modificados en ese push/PR matchean alguno de los patrones listados (`.md`, `docs/`, `k8s/`, `cd.yml`, `.gitignore`), GitHub salta el workflow entero — ni siquiera aparece en la pestaña Actions. Si se mezcla aunque sea un archivo que no matchea (como `app/main.py`), el workflow corre igual, evaluando todos los cambios del push.

**2. Variables de entorno globales**
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
```
Dos constantes reutilizables en todo el workflow. `github.repository` es una variable que GitHub provee automáticamente con el formato owner/repo — en tu caso se resuelve a `Nicolas-Torres/ml-deploy-workshop`. Definirlas acá arriba evita repetir el string en cada step y centraliza el cambio si algún día migras de registry.

**3. Job 1 — `test`**
```yaml
runs-on: ubuntu-latest
```
Cada job corre en una máquina virtual efímera nueva — se crea, ejecuta los steps, y se destruye al terminar. No hay estado compartido entre jobs a menos que lo persistas explícitamente (con artifacts, como verás abajo).

**Paso a paso:**

**1. Checkout código (`actions/checkout@v4`)**: clona tu repo dentro del runner. Sin este paso, el runner es una VM vacía sin ningún archivo tuyo.
   
**2. Instalar uv (`astral-sh/setup-uv@v3`)**: descarga e instala la versión exacta `0.11.23` de uv en el runner — la misma que usas localmente y en el Dockerfile. `enable-cache: true` con `cache-dependency-glob: "uv.lock"` le dice a GitHub Actions que guarde el caché de paquetes descargados por uv entre corridas, usando el hash de uv.lock como clave. Si `uv.lock` no cambió desde la última corrida, las dependencias se restauran desde caché en vez de descargarse de PyPI de nuevo — esto es lo que hace que corridas sucesivas del CI sean rápidas.

**3. Configurar Python**: `uv python install` lee tu archivo `.python-version` y descarga/instala esa versión exacta de Python si el runner no la tiene ya. Garantiza que el CI use la misma versión de Python que tú localmente, sin depender de lo que Ubuntu traiga preinstalado.
   
**4. Instalar dependencias**: `uv sync --locked` lee `uv.lock` y crea el `.venv` con las versiones exactas fijadas. `--locked` falla explícitamente si `uv.lock` está desincronizado de `pyproject.toml` — es una validación extra que te avisa si olvidaste correr `uv lock` después de tocar dependencias.
   
**5. Entrenar modelo**: `uv run train.py` genera `models/iris_model.pkl` desde cero en el runner. Esto es una decisión de diseño importante: el modelo no vive en el repo como artefacto versionado, se regenera en cada corrida de CI. Garantiza reproducibilidad (el modelo que se testea es siempre fresco, entrenado con el código actual) a costa de tiempo de build.
   
**6. Ejecutar tests con cobertura**: corre pytest sobre `tests/`, mide cobertura del paquete `app/`, y — el detalle importante — `--cov-fail-under=80` hace que el job falle si la cobertura baja del 80%, no solo si algún test falla individualmente. Es una puerta de calidad automática.

**7. Subir reporte de cobertura (`actions/upload-artifact@v4`)**: guarda el archivo .coverage como un artifact descargable desde la UI de GitHub Actions, para inspección manual si quieres ver el detalle. El `if: always()` es clave — hace que este paso se ejecute incluso si el step anterior (pytest) falló, así que siempre tienes el reporte disponible para diagnosticar, en vez de perderlo justo cuando más lo necesitas.

**4. Job 2 — `build-push`**
```yaml
needs: test
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```
Esta es la lógica condicional más importante del archivo, y vale la pena desglosarla en sus dos partes:

- **`needs: test`**: este job no arranca hasta que `test` termine exitosamente. Si pytest falla o la cobertura baja de 80%, `build-push` ni siquiera se intenta — nunca publicas una imagen que no pasó tests.

- **`if: github.ref == 'refs/heads/main' && github.event_name == 'push'`**: esta condición filtra cuándo corre, independientemente de que `test` haya pasado. Se cumple únicamente cuando el evento es un `push` directo a `main` — no en PRs (aunque sean hacia `main`), y no en pushes a `develop`.

La combinación de ambas reglas es lo que le da forma a tu flujo real: en un push a `develop`, solo corre test. En un PR hacia `main`, solo corre `test` (para validar antes de mergear, sin publicar nada todavía). Recién cuando el `merge commit` llega a `main` como `push`, se cumplen ambas condiciones y se dispara la publicación de imagen — que es exactamente el patrón que viste la última vez: tu PR corrió tests, y solo al hacer merge se generó el package nuevo en GHCR.

**Paso a paso:**

**1-3. Checkout, instalar uv, sync + entrenar**: mismos pasos que en `test`, porque este job corre en un runner completamente distinto y nuevo — no hereda nada del job anterior. El modelo se re-entrena acá también porque el Dockerfile lo necesita copiado en el build context (`COPY models/`).

**4. Login a GHCR (`docker/login-action@v3`)**: autentica el runner contra el registry usando `secrets.GITHUB_TOKEN` — un token que GitHub genera automáticamente por cada corrida, sin que tengas que crear ni gestionar credenciales manualmente. Los `permissions: packages: write` declarados arriba en el job son los que autorizan a ese token a publicar paquetes en tu repo.

**5. Extraer metadata (`docker/metadata-action@v5`)**: calcula automáticamente qué tags le va a poner a la imagen, según el patrón que definiste:

- `type=sha,prefix=sha-` → genera algo como `sha-7d3e21d` (el que viste en GHCR)
- `type=ref,event=branch` → agrega el nombre de la rama como tag (`main`)
- `type=raw,value=latest,enable=...` → agrega `latest` solo si la rama es `main` (la condición `enable` es redundante con el `if` del job, pero actúa como cinturón de seguridad extra)

**6. Configurar Buildx (`docker/setup-buildx-action@v3`)**: habilita el motor de build extendido de Docker (BuildKit), necesario para usar el cache remoto de GitHub Actions (`type=gha`) que configuraste en el paso siguiente.

**7. Build y push (`docker/build-push-action@v5`)**: ejecuta tu Dockerfile multi-stage tal como lo desglosamos antes, y publica el resultado directo a GHCR con los tags calculados en el paso 5. `cache-from`/`cache-to: type=gha` es la optimización de cache remota que mencioné hace unas respuestas — reutiliza capas de Docker entre corridas de CI usando el cache de Actions como almacenamiento, en vez de reconstruir todo desde cero cada vez. `build-args: APP_VERSION=${{ github.sha }}` inyecta el hash del commit como variable disponible dentro del Dockerfile (útil si en algún endpoint como `/health` quieres exponer qué versión exacta está corriendo).

**8. Resumen del build**: escribe líneas Markdown al archivo especial `$GITHUB_STEP_SUMMARY`, que GitHub renderiza como una sección visible en la página de resultados del workflow — así puedes ver de un vistazo qué tags se publicaron sin tener que abrir logs.

**Resumen:**

En una frase: el workflow separa validación (`job test`, que corre siempre que hay código relevante modificado) de publicación (job `build-push`, que solo corre cuando ese código llega a `main` vía push real). El `paths-ignore` actúa como filtro de entrada antes de todo esto — decide si vale la pena siquiera arrancar. Y la cadena `needs` + `if` en el segundo job garantiza que nunca publiques una imagen a GHCR sin que haya pasado tests primero.