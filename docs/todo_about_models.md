### Consideraciones a revisar

Una cosa a tener en cuenta: el modelo se entrena dos veces, una en test y otra en build-push, en jobs separados que no comparten archivos entre sí (cada job arranca en una VM limpia). Esto funciona, pero es redundante en tiempo de cómputo, y si train.py tuviera algo no determinístico (semilla aleatoria no fijada, por ejemplo) el modelo que terminó dentro de la imagen Docker podría no ser exactamente el mismo que pasó los tests. Si quisieras evitar esa duplicación, podrías subir models/iris_model.pkl como artifact en el job test y descargarlo en build-push en vez de reentrenar.

Ya que el CI reentrena el modelo dos veces, si train.py tarda o consume muchos recursos, vale la pena optimizarlo pasando el artefacto entre jobs en vez de reentrenar.
