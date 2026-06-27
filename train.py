"""
train.py – Entrena un clasificador Iris y guarda el modelo con joblib.
Ejecutar una vez antes de levantar el servicio:
    python train.py
"""
from pathlib import Path

import joblib
import numpy as np
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

MODELS_DIR = Path("models")
MODEL_PATH = MODELS_DIR / "iris_model.pkl"

CLASSES = ["setosa", "versicolor", "virginica"]


def train() -> None:
    print("🔄 Cargando datos...")
    iris = load_iris()
    print(iris.data)      # array con las 150 muestras y sus 4 features
    print(iris.target)    # array con las etiquetas (0, 1, 2) de cada muestra

    print(iris.feature_names)   # ['sepal length (cm)', 'sepal width (cm)', ...]
    print(iris.target_names)    # ['setosa' 'versicolor' 'virginica']
   

    X, y = iris.data, iris.target

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print("🏋️  Entrenando RandomForestClassifier...")
    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        ("clf", RandomForestClassifier(n_estimators=100, random_state=42)),
    ])
    pipeline.fit(X_train, y_train)

    y_pred = pipeline.predict(X_test)
    print("\n📊 Resultados en test set:")
    print(classification_report(y_test, y_pred, target_names=CLASSES))

    MODELS_DIR.mkdir(exist_ok=True)
    joblib.dump(pipeline, MODEL_PATH)
    print(f"✅ Modelo guardado en: {MODEL_PATH}")

    # Sanity check
    sample = np.array([[5.1, 3.5, 1.4, 0.2]])
    pred = pipeline.predict(sample)[0]
    proba = pipeline.predict_proba(sample)[0]
    print(f"\n🔍 Sanity check – input={sample[0].tolist()}")
    print(f"   Predicción: {CLASSES[pred]} (confianza: {proba[pred]:.2%})")


if __name__ == "__main__":
    train()
