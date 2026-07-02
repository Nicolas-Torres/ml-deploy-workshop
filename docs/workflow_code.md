# Flujo de trabajo
### 1. Asegúrate de arrancar desde develop actualizado
```
git checkout develop
git pull origin develop
```

### 2. Trabaja tus cambios (código, docs, lo que sea)
```
git add <archivos>
git commit -m "..."
```

### 3. Push a develop
```
git push origin develop
```

### 4. En GitHub: 
- Abrir PR develop → main
- Revisar diff, título, descripción, esperar CI si aplica

### 5. Merge del PR en GitHub 
- Botón "Merge pull request"

### 6. Sincronizar tu main local con el merge que acaba de pasar en remoto
```
git checkout main
git pull origin main
```

### 7. Volver a develop para seguir trabajando
```
git checkout develop
```
