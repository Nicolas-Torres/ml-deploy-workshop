# 🚀 Taller MLOps – Despliegue de Modelos ML

Proyecto completo para el taller de despliegue automatizado de modelos Machine Learning usando Docker, GitHub Actions y Kubernetes.

---

## 📁 Estructura del proyecto

```
ml-deploy-workshop/
├── app/
│   ├── __init__.py
│   ├── main.py          # FastAPI: endpoints /health y /predict
│   └── model.py         # Carga y lógica de inferencia
├── models/
│   └── iris_model.pkl   # Generado por train.py
├── tests/
│   ├── __init__.py
│   └── test_api.py      # Suite completa con pytest
├── k8s/
│   ├── deployment.yaml  # Deployment con 2 réplicas
│   ├── service.yaml     # Service LoadBalancer
│   └── hpa.yaml         # Horizontal Pod Autoscaler
├── .github/
│   └── workflows/
│       └── ci.yml       # Pipeline CI/CD completo
├── train.py             # Entrena y guarda el modelo
├── requirements.txt
└── Dockerfile           # Multi-stage build
```

---

## ⚙️ Requisitos previos

- Python 3.11+
- Docker Desktop
- minikube (`brew install minikube` o https://minikube.sigs.k8s.io)
- kubectl (`brew install kubectl`)

---

## 🐍 DÍA 1 – Docker y CI/CD

### 1. Instalar dependencias y entrenar el modelo

```bash
pip install -r requirements.txt
python train.py
# → Genera models/iris_model.pkl
```

### 2. Ejecutar el servicio localmente

```bash
uvicorn app.main:app --reload
# Abre http://localhost:8000/docs para la interfaz interactiva
```

### 3. Probar el endpoint

```bash
# Health check
curl http://localhost:8000/health

# Predicción
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{
    "sepal_length": 5.1,
    "sepal_width": 3.5,
    "petal_length": 1.4,
    "petal_width": 0.2
  }'
```

### 4. Ejecutar los tests

```bash
# Tests básicos
pytest tests/ -v --tb=short

# Con reporte de cobertura
pytest tests/ -v --cov=app --cov-report=term-missing
```

### 5. Construir y ejecutar con Docker

```bash
# Build de la imagen
docker build -t ml-api:v1 .

# Ejecutar el contenedor
docker run -p 8000:8000 ml-api:v1

# Verificar que funciona
curl http://localhost:8000/health
```

### 6. Configurar GitHub Actions

1. Sube el repositorio a GitHub
2. El workflow `.github/workflows/ci.yml` se ejecuta automáticamente en cada `push`
3. En **Settings → Actions → General** asegúrate de que los permisos de escritura de paquetes estén habilitados

---

## ☸️ DÍA 2 – Kubernetes

### 1. Iniciar minikube

```bash
minikube start --driver=docker
minikube addons enable metrics-server
```

### 2. Cargar la imagen en minikube

```bash
# Opción A: cargar imagen local
docker build -t ml-api:v1 .
minikube image load ml-api:v1

# En deployment.yaml cambia la imagen a ml-api:v1
# y imagePullPolicy a Never
```

### 3. Desplegar en Kubernetes

```bash
# Reemplaza TU_USUARIO en k8s/deployment.yaml antes de aplicar
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

### 4. Verificar el despliegue

```bash
# Ver estado de pods
kubectl get pods -w

# Ver servicios
kubectl get svc ml-api-svc

# Ver HPA
kubectl get hpa
```

### 5. Prueba de escalado

```bash
# Generar carga (en otra terminal)
kubectl run -i --tty load-gen --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://ml-api-svc/health; done"

# Observar cómo el HPA escala los pods
kubectl get hpa ml-api-hpa -w
```

### 7. Actualización sin downtime (Rolling Update)

```bash
# Actualizar a nueva versión
kubectl set image deployment/ml-api ml-api=ghcr.io/user/ml-api:v2

# Ver progreso del rollout
kubectl rollout status deployment/ml-api

# Historial
kubectl rollout history deployment/ml-api

# Rollback si algo falla
kubectl rollout undo deployment/ml-api
```

---

## 📊 Monitoreo básico

```bash
kubectl top pods          # Uso de CPU y memoria por pod
kubectl top nodes         # Uso de recursos por nodo
kubectl get events --sort-by=.lastTimestamp   # Eventos recientes
kubectl describe deployment ml-api            # Detalle del deployment
```

---

## 🧹 Limpieza

```bash
kubectl delete -f k8s/
```
