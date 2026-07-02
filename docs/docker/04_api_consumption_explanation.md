**4. Consumo de la API — Qué pasa en cada request**

```
# Health check
curl http://localhost:8000/health
```

El request viaja: `curl` → SO del host → regla iptables de Docker → namespace de red del container → uvicorn → FastAPI router → handler de `/health` → responde `{"status": "ok"} `→ mismo camino de vuelta.

```
# Predicción
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"sepal_length": 5.1, "sepal_width": 3.5, "petal_length": 1.4, "petal_width": 0.2}'
```

**Internamente en FastAPI:**

**1.** uvicorn recibe los bytes TCP y los parsea como HTTP/1.1

**2.** FastAPI matchea la ruta `/predict` con el método POST

**3.** Pydantic valida y deserializa el JSON body al schema `IrisInput` (si algún campo falta o tiene tipo incorrecto, responde 422 antes de llegar al handler)

**4.** El handler llama al modelo scikit-learn con los 4 features

**5.** El modelo devuelve el índice de clase (`0`, `1`, o `2`)

**6.** FastAPI serializa la respuesta a JSON y uvicorn la envía de vuelta

```
# Limpieza
docker stop test-curso-mlops   # envía SIGTERM al PID 1 (uvicorn), espera graceful shutdown
docker rm test-curso-mlops     # elimina el container y su capa writable
```

La imagen `curso-mlops:v1` sigue existiendo en tu Docker local intacta — solo eliminaste el container (la instancia corriendo).