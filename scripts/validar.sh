#!/usr/bin/env bash
# Testa em uma instância PostgreSQL temporária, sem acessar servidores existentes.
# Requer PostgreSQL 16 (initdb, pg_ctl, createuser, createdb e psql) e Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 0 ]]; then
  echo 'Uso: scripts/validar.sh (não recebe nome de banco existente)' >&2
  exit 2
fi
for programa in initdb pg_ctl createuser createdb psql python3; do
  command -v "$programa" >/dev/null || { echo "Falta dependência: $programa" >&2; exit 1; }
done
scripts/build_sql.sh --check
TDP_TEMP=$(mktemp -d /tmp/tdp-validacao.XXXXXX)
encerrar() {
  pg_ctl -D "$TDP_TEMP/dados" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf -- "$TDP_TEMP"
}
trap encerrar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Não herdar opções de conexão, senhas ou serviços do ambiente do usuário.
unset PGHOSTADDR PGSERVICE PGSERVICEFILE PGOPTIONS PGPASSWORD PGDATABASE PGUSER PGHOST PGPORT
export PGHOST="$TDP_TEMP" PGPORT=55432 PGUSER=tdp_admin PGDATABASE=postgres
initdb -D "$TDP_TEMP/dados" -U tdp_admin -A trust --no-locale -E UTF8 > "$TDP_TEMP/initdb.log"
pg_ctl -D "$TDP_TEMP/dados" -l "$TDP_TEMP/servidor.log" \
  -o "-F -c listen_addresses='' -c unix_socket_directories='$TDP_TEMP' -p $PGPORT" -w start > /dev/null
createuser --no-superuser --no-createrole --no-createdb tdp_aluno
createdb -O tdp_aluno tdp_case
export PGUSER=tdp_aluno PGDATABASE=tdp_case
mkdir -p tmp/validacao
psql -X -At -c 'SELECT version()' > tmp/validacao/versao.txt
if ! psql -X -v ON_ERROR_STOP=1 -f sql/00_bolsa_completo.sql > tmp/validacao/execucao.log 2>&1; then
  tail -n 25 tmp/validacao/execucao.log
  exit 1
fi
# Reexecução deve falhar sem apagar ou alterar a primeira instalação.
if psql -X -v ON_ERROR_STOP=1 -f sql/00_bolsa_completo.sql > tmp/validacao/reexecucao.log 2>&1; then
  echo 'FALHA: reexecução deveria recusar esquema existente' >&2
  exit 1
fi
python3 scripts/testar_modelo.py | tee tmp/validacao/testes.log
printf '%s\n' 'OK: DDL + DML + 16 DQLs, reexecução segura e regressões em instância isolada.'
printf '%s\n' 'Evidências: tmp/validacao/. Instância temporária encerrada ao sair.'
