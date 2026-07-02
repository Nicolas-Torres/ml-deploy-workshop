**3. docker run — Qué pasa por detrás**
```
docker run -d -p 8000:8000 --name test-curso-mlops curso-mlops:v1
```

- **`-d` (detached)**: lanza el container en background y te devuelve el control del terminal inmediatamente. Docker te imprime el container ID completo (el SHA256) y listo.

- **`-p 8000:8000` (port mapping, formato `host:container`)**: el Docker daemon configura una regla de `iptables` en el host que redirige todo el tráfico TCP que llegue al puerto 8000 del host hacia el puerto 8000 del container. Es un NAT — desde tu perspectiva haces `curl localhost:8000` y Docker silenciosamente lo redirige adentro.

- **`--name test-curso-mlops`**: le da un nombre legible al container. Sin esto, Docker le asigna un nombre random tipo `hungry_lovelace`.

**Internamente, cuando ejecutas docker run:**

**1. Docker crea un container —** que es básicamente un proceso aislado con su propio namespace de red, filesystem, y PID. No es una VM; comparte el kernel del host.

**2. Monta las capas de la imagen** en modo read-only usando un Union Filesystem (overlay2 en Linux). Encima agrega una capa writable vacía donde el container puede escribir temporalmente (logs, archivos en /tmp, etc.). Cuando el container muere, esa capa writable desaparece.

**3. Configura el namespace de red**: el container tiene su propia IP interna (ej. 172.17.0.2) y su propio stack TCP/IP. El port mapping conecta 0.0.0.0:8000 del host a 172.17.0.2:8000 del container.

**4. Ejecuta el CMD como PID 1 dentro del container**:

```
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**5. uvicorn arranca**, importa app.main, FastAPI inicializa los routers, carga el modelo .pkl en memoria (si lo haces al startup), y empieza a escuchar en 0.0.0.0:8000.

**6. Después de --start-period=10s**, el daemon de Docker ejecuta el HEALTHCHECK cada 30 segundos.

Para ver qué está pasando mientras corre:

```
# Ver logs de uvicorn en tiempo real
docker logs -f test-curso-mlops

# Ver estado de salud
docker inspect --format='{{json .State.Health}}' test-curso-mlops

# Ver uso de CPU/RAM en tiempo real
docker stats test-curso-mlops

# Entrar al container (como appuser, no root)
docker exec -it test-curso-mlops bash
```