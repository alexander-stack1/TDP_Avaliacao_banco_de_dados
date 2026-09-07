#!/usr/bin/env bash
# Cria um banco descartável, executa o script completo e falha no primeiro erro.
# Uso: scripts/validar.sh [nome_do_banco]   (usa as variáveis PG* do ambiente / .env)
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${1:-bolsa_valores_teste}"
scripts/build_sql.sh
dropdb --if-exists "$DB"
createdb "$DB"
psql -v ON_ERROR_STOP=1 -d "$DB" -f sql/00_bolsa_completo.sql
echo "OK: script executado sem erros em '$DB'"
