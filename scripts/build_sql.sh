#!/usr/bin/env bash
# Gera o arquivo de entrega ou verifica se ele está sincronizado com os fontes.
set -euo pipefail
cd "$(dirname "$0")/.."
TDP_SQL_TEMP=$(mktemp)
trap 'rm -f -- "$TDP_SQL_TEMP"' EXIT
{
  cat <<'HDR'
-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES — MODELO FÍSICO (PostgreSQL 16)
--  Arquivo único: DDL + DML + DQL (gerado por scripts/build_sql.sh a partir
--  de sql/01_ddl.sql, sql/02_dml.sql e sql/03_dql.sql — edite os fontes).
--  Executar em banco novo: psql -X -v ON_ERROR_STOP=1 -d <banco> -f este_arquivo.sql
--  Recusa esquema bolsa existente. Não apaga dados nem cria papéis globais.
-- =====================================================================

HDR
  cat sql/01_ddl.sql
  printf '\n\n'
  cat sql/02_dml.sql
  printf '\n\n'
  cat sql/03_dql.sql
} > "$TDP_SQL_TEMP"
if [[ "${1:-}" == '--check' ]]; then
  cmp -s "$TDP_SQL_TEMP" sql/00_bolsa_completo.sql || {
    echo 'SQL consolidado desatualizado; execute scripts/build_sql.sh' >&2; exit 1;
  }
elif [[ $# -eq 0 ]]; then
  cat "$TDP_SQL_TEMP" > sql/00_bolsa_completo.sql
  echo 'Gerado sql/00_bolsa_completo.sql'
else
  echo 'Uso: scripts/build_sql.sh [--check]' >&2
  exit 2
fi
