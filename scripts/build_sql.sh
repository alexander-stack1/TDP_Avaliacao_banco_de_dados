#!/usr/bin/env bash
# Gera sql/00_bolsa_completo.sql a partir dos três arquivos-fonte.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  cat <<'HDR'
-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES — MODELO FÍSICO (PostgreSQL 16)
--  Arquivo único: DDL + DML + DQL (gerado por scripts/build_sql.sh a partir
--  de sql/01_ddl.sql, sql/02_dml.sql e sql/03_dql.sql — edite os fontes).
--  Executar: psql -v ON_ERROR_STOP=1 -d <banco> -f sql/00_bolsa_completo.sql
-- =====================================================================

HDR
  cat sql/01_ddl.sql; printf '\n\n'
  cat sql/02_dml.sql; printf '\n\n'
  cat sql/03_dql.sql
} > sql/00_bolsa_completo.sql
echo "gerado sql/00_bolsa_completo.sql ($(wc -l < sql/00_bolsa_completo.sql) linhas)"
