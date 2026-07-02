**Un trade-off que vale la pena que decidas conscientemente**

En `ci.yml`:

```
on:
  push:
    branches: [main, develop]
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - 'k8s/**'     
      - '.github/workflows/cd.yml'
      - '.gitignore'
```

Ignorar `k8s/**` en `ci.yml` significa que un YAML de Kubernetes con sintaxis rota no se detecta hasta que ejecutes cd.yml manualmente contra el clúster real — no hay ninguna validación automática en el camino. Hoy eso es aceptable porque tu único consumidor de esos manifiestos es un `workflow_dispatch (cd.yml)` que tú disparas a propósito y revisas. Pero si en algún momento quieres una red de seguridad más temprana sin acoplarlo al pipeline de build/test, la solución típica es un job de lint separado, disparado solo por cambios en `k8s/**`, corriendo algo como `kubectl apply --dry-run=client -f k8s/` o `kubeval`. No es necesario ahora — solo señalo que excluir `k8s/**` de `ci.yml` no es gratis, es una decisión consciente de "esto lo reviso yo manualmente, no el CI".