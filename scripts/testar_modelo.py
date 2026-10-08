#!/usr/bin/env python3
"""Regressões executadas exclusivamente pelo validar.sh em seu banco temporário.
Usa psql; não requer driver Python. Fixtures adicionais terminam em ROLLBACK.
"""
import os
from pathlib import Path
import subprocess
import time

if not os.environ.get('PGHOST', '').startswith('/tmp/tdp-validacao.'):
    raise SystemExit('Use scripts/validar.sh: estes testes exigem a instância temporária.')

BASE = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']

def sql(query):
    return subprocess.check_output(BASE + ['-c', query], text=True).strip()


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print('OK:', name, flush=True)


def rejected(name, statement, state):
    # Bloco interno faz rollback da operação que deveria falhar.
    sql(f"""BEGIN;
    DO $test$ BEGIN
      BEGIN
        {statement};
        RAISE EXCEPTION 'Operação foi aceita indevidamente';
      EXCEPTION WHEN SQLSTATE '{state}' THEN NULL;
      END;
    END $test$;
    ROLLBACK;""")
    print('OK:', name, flush=True)


def trade(when, op, quantity, price, investor=2, stock=5):
    return f"""INSERT INTO bolsa.negociacao
        (id_investidor,id_acao,data_hora,tipo_operacao,quantidade,valor_unitario)
        VALUES ({investor},{stock},'{when}','{op}',{quantity},{price})"""

check('carga preservada após reexecução recusada',
      sql('SELECT (SELECT count(*) FROM bolsa.investidor), (SELECT count(*) FROM bolsa.empresa), '
          '(SELECT count(*) FROM bolsa.acao), (SELECT count(*) FROM bolsa.cotacao), '
          '(SELECT count(*) FROM bolsa.negociacao)') == '6|7|8|607|19')
check('execução sem superusuário ou CREATEROLE',
      sql('SELECT rolsuper OR rolcreaterole FROM pg_roles WHERE rolname = current_user') == 'f')
check('custo médio após venda parcial e recompra',
      sql('SELECT quantidade,preco_medio FROM bolsa.carteira WHERE id_investidor=2 AND id_acao=5') == '250|35.7333')
check('lucro da venda após recompra parcial',
      sql("SELECT resultado_realizado FROM bolsa.vw_evolucao_carteira WHERE id_investidor=2 AND data_hora='2026-09-03 14:00-03'") == '313.34')
check('recompra depois de zerar não herda custo antigo',
      sql("SELECT preco_medio_anterior,resultado_realizado FROM bolsa.vw_evolucao_carteira WHERE id_investidor=3 AND data_hora='2026-09-04 13:00-03'") == '8.0000|100.00')
check('liquidação zera quantidade e preço médio',
      sql('SELECT quantidade,preco_medio FROM bolsa.carteira WHERE id_investidor=3 AND id_acao=6') == '0|0.0000')
check('carteira coincide com reconstituição de saldo e custo', sql('''
WITH ultima AS (SELECT DISTINCT ON (id_investidor,id_acao) * FROM bolsa.vw_evolucao_carteira
               ORDER BY id_investidor,id_acao,data_hora DESC,id_negociacao DESC)
SELECT count(*) FROM bolsa.carteira c FULL JOIN ultima u USING (id_investidor,id_acao)
WHERE c.quantidade IS DISTINCT FROM u.saldo OR c.preco_medio IS DISTINCT FROM u.preco_medio
   OR c.atualizado_em IS DISTINCT FROM u.data_hora''') == '0')
check('posição histórica anterior à venda',
      sql("SELECT ticker,quantidade FROM bolsa.fn_carteira_em(1,'2026-09-02 17:00-03')") == 'PETR4|300\nVALE3|100')
check('cotação futura não vaza para análise histórica', sql('''
BEGIN;
INSERT INTO bolsa.cotacao (id_acao,data_hora,valor) VALUES (2,'2026-09-09 10:00-03',9999);
SELECT k.cotacao_na_data = (SELECT valor FROM bolsa.cotacao WHERE id_acao=2
       AND data_hora <= '2026-09-02 17:00-03' ORDER BY data_hora DESC LIMIT 1)
FROM bolsa.fn_carteira_em(1,'2026-09-02 17:00-03') k WHERE ticker='PETR4';
ROLLBACK;''') == 't')
check('posição sem cotação retorna NULL, não zero', sql('''
BEGIN;
DELETE FROM bolsa.cotacao WHERE id_acao=2 AND data_hora <= '2026-09-02 17:00-03';
SELECT quantidade,cotacao_na_data IS NULL,valor_posicao IS NULL
FROM bolsa.fn_carteira_em(1,'2026-09-02 17:00-03') WHERE ticker='PETR4';
ROLLBACK;''') == '300|t|t')
check('instante da carteira corresponde à negociação',
      sql("SELECT atualizado_em='2026-09-03 14:00-03'::timestamptz FROM bolsa.carteira WHERE id_investidor=2 AND id_acao=5") == 't')
for name, statement, state in [
    ('venda acima do saldo', trade('2026-09-10 10:00-03','VENDA',251,42), '23514'),
    ('venda sem posição prévia', trade('2026-09-10 10:00-03','VENDA',1,12,1,8), '23514'),
    ('negociação retroativa', trade('2026-09-02 10:00-03','VENDA',1,42), '23514'),
    ('instante repetido por posição', trade('2026-09-03 14:00-03','COMPRA',1,42), '23514'),
    ('preço NaN', trade('2026-09-10 10:00-03','COMPRA',1,"'NaN'"), '23514'),
    ('quantidade zero', trade('2026-09-10 10:00-03','COMPRA',0,42), '23514'),
    ('preço negativo', trade('2026-09-10 10:00-03','COMPRA',1,-1), '23514'),
    ('data infinita', trade('infinity','COMPRA',1,42), '23514'),
    ('UPDATE de negociação', 'UPDATE bolsa.negociacao SET quantidade=1 WHERE id_negociacao=1', '23001'),
    ('DELETE de negociação', 'DELETE FROM bolsa.negociacao WHERE id_negociacao=1', '23001'),
    ('TRUNCATE de negociação', 'TRUNCATE bolsa.negociacao', '23001'),
    ('edição direta de carteira', 'UPDATE bolsa.carteira SET quantidade=0', '23001'),
    ('exclusão direta de carteira', 'DELETE FROM bolsa.carteira', '23001'),
    ('TRUNCATE de carteira', 'TRUNCATE bolsa.carteira', '23001'),
    ('telefone obrigatório', 'UPDATE bolsa.investidor SET telefone=NULL WHERE id_investidor=1', '23502'),
    ('CPF incompatível com PF', "UPDATE bolsa.investidor SET documento='00000000000099' WHERE id_investidor=1", '23514'),
    ('documento único', "UPDATE bolsa.investidor SET documento='00000000001' WHERE id_investidor=2", '23505'),
    ('ticker único', "UPDATE bolsa.acao SET ticker='PETR4' WHERE id_acao=1", '23505'),
    ('cotação única por ação e instante', 'INSERT INTO bolsa.cotacao(id_acao,data_hora,valor) SELECT id_acao,data_hora,valor FROM bolsa.cotacao LIMIT 1', '23505'),
    ('ação sem empresa', "INSERT INTO bolsa.acao(ticker,id_empresa,tipo_acao) VALUES ('TEST3',9999,'ON')", '23503'),
    ('empresa com ações não pode ser apagada', 'DELETE FROM bolsa.empresa WHERE id_empresa=1', '23503'),
    ('ação com histórico preservado', 'DELETE FROM bolsa.acao WHERE id_acao=8', '23503'),
]:
    rejected(name, statement, state)

# Testa exatamente as consultas entregues, evitando duplicar sua implementação.
dql = Path('sql/03_dql.sql').read_text()
def query(number):
    piece = dql.split(f'-- Q{number:02d}.',1)[1].split(f'-- Q{number+1:02d}.',1)[0]
    return '\n'.join(line for line in piece.splitlines()[1:] if not line.startswith('--')).strip()
check('Q15 retorna zero divergências', sql(query(15)) == '')
check('Q02 separa investidores homônimos', len(sql('BEGIN; UPDATE bolsa.investidor SET nome_completo=\'Cliente teste\'; '+query(2)+' ROLLBACK;').splitlines()) == 6)
check('Q02 inclui carteira zerada com patrimônio zero',
      any(line.startswith('3|Investidor PF 03|PF|0|0|0|0|0') for line in sql(query(2)).splitlines()))
check('Q02 não soma patrimônio incompleto',
      any(line.startswith('1|Investidor PF 01|PF|2|') and line.endswith('|||1')
          for line in sql('BEGIN; DELETE FROM bolsa.cotacao WHERE id_acao=2; '+query(2)+' ROLLBACK;').splitlines()))
check('Q12 não apresenta percentuais parciais como total',
      all(line.split('|')[2] == '' for line in
          sql('BEGIN; DELETE FROM bolsa.cotacao WHERE id_acao=2; '+query(12)+' ROLLBACK;').splitlines()))
check('Q09 marca patrimônio incompleto sem cotação',
      any('||1' in line for line in sql('BEGIN; DELETE FROM bolsa.cotacao WHERE id_acao=1; '+query(9)+' ROLLBACK;').splitlines()))

# Concorrência real: A mantém o bloqueio da posição; B tenta vender o mesmo saldo.
# O sincronismo usa um advisory lock exclusivo desta instância de teste.
a_script = 'BEGIN; '+trade('2026-09-11 10:00-03','VENDA',200,42)+''';
SELECT pg_advisory_xact_lock(20261007);
SELECT pg_sleep(2);
COMMIT;'''
a = subprocess.Popen(BASE + ['-c', a_script], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
ready = False
for _ in range(80):
    if sql("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE locktype='advisory' AND objid=20261007 AND granted)") == 't':
        ready = True
        break
    time.sleep(0.02)
if not ready:
    a.communicate(timeout=10)
    raise AssertionError('sessão concorrente não obteve bloqueio')
b = subprocess.run(BASE + ['--set=VERBOSITY=verbose', '-c', trade('2026-09-11 11:00-03','VENDA',200,42)], text=True, capture_output=True)
a_out, a_err = a.communicate(timeout=10)
check('duas vendas concorrentes não usam o mesmo saldo', a.returncode == 0 and b.returncode != 0 and '23514' in b.stderr)
check('saldo após concorrência e rollback da venda rejeitada',
      sql('SELECT quantidade FROM bolsa.carteira WHERE id_investidor=2 AND id_acao=5') == '50')
check('Q15 continua sem divergências após concorrência', sql(query(15)) == '')
print('Todos os testes passaram.')
