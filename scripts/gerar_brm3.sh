#!/usr/bin/env bash
# Converte docs/01-modelo-conceitual/modelo_conceitual.xml em .brM3 + PNG usando as
# classes do próprio brModelo 3.31 (https://github.com/chcandido/brModelo/releases).
# Requer Java 8+ (ex.: brew install openjdk). O jar é baixado se não existir.
set -euo pipefail
cd "$(dirname "$0")/.."
BRM_DIR="${BRMODELO_DIR:-$HOME/Applications/brModelo}"
JAR="$BRM_DIR/brModelo.jar"
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}"
[ -x /opt/homebrew/opt/openjdk/bin/java ] && export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
mkdir -p "$BRM_DIR"
if [ ! -f "$JAR" ]; then
  echo "baixando brModelo 3.31 ..."
  curl -sL -o "$JAR" https://github.com/chcandido/brModelo/releases/download/3.31/brModelo.jar
fi
python3 scripts/gerar_brmodelo.py
mkdir -p "$BRM_DIR/out"
javac -cp "$JAR" -d "$BRM_DIR/out" scripts/brmodelo/ConverteBrM3.java
DOCS="$PWD/docs/01-modelo-conceitual"
( cd "$BRM_DIR" && java -cp "$JAR:out" ConverteBrM3 \
    "$DOCS/modelo_conceitual.xml" "$DOCS/modelo_conceitual.brM3" "$DOCS/modelo_conceitual_brmodelo.png" ) \
  2>&1 | grep -v -E "^WARNING|Inspector"
