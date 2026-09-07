-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES
--  Modelo Físico — DML (Data Manipulation Language): carga de exemplo
--  Todos os dados abaixo são fictícios (CPF/CNPJ/e-mails inventados).
-- =====================================================================

SET search_path TO bolsa, public;

BEGIN;

-- ---------------------------------------------------------------------
-- 1. INVESTIDORES (4 PF + 2 PJ)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.investidor (documento, tipo_investidor, nome_completo, email, telefone) VALUES
    ('52998224725',     'PF', 'Ana Paula Ribeiro',          'ana.ribeiro@exemplo.com',      '11987650001'),
    ('11144477735',     'PF', 'Bruno Carvalho Lima',        'bruno.lima@exemplo.com',       '21987650002'),
    ('35652325304',     'PF', 'Carla Mendes Souza',         'carla.souza@exemplo.com',      '31987650003'),
    ('20385364008',     'PF', 'Diego Nascimento Alves',     'diego.alves@exemplo.com',      NULL),
    ('11222333000181',  'PJ', 'Horizonte Participações S.A.','contato@horizonte.exemplo',   '1133330004'),
    ('45678901000123',  'PJ', 'Vale Verde Investimentos Ltda','financeiro@valeverde.exemplo','4133330005');

-- ---------------------------------------------------------------------
-- 2. EMPRESAS LISTADAS (7)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.empresa (cnpj, nome, setor, valor_mercado) VALUES
    ('33000167000101', 'Petróleo Brasileiro S.A.',  'Petróleo e Gás',      480000000000.00),
    ('33592510000154', 'Vale S.A.',                 'Mineração',           280000000000.00),
    ('60746948000112', 'Banco Bradesco S.A.',       'Financeiro',          150000000000.00),
    ('60872504000123', 'Itaú Unibanco Holding S.A.','Financeiro',          320000000000.00),
    ('47960950000121', 'Magazine Luiza S.A.',       'Varejo',               8000000000.00),
    ('02558157000162', 'WEG S.A.',                  'Bens Industriais',    170000000000.00),
    ('07526557000100', 'Ambev S.A.',                'Bebidas',             190000000000.00);

-- ---------------------------------------------------------------------
-- 3. AÇÕES (8 papéis; uma empresa pode ter mais de um)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.acao (ticker, id_empresa, tipo_acao) VALUES
    ('PETR3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '33000167000101'), 'ON'),
    ('PETR4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '33000167000101'), 'PN'),
    ('VALE3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '33592510000154'), 'ON'),
    ('BBDC4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '60746948000112'), 'PN'),
    ('ITUB4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '60872504000123'), 'PN'),
    ('MGLU3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '47960950000121'), 'ON'),
    ('WEGE3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '02558157000162'), 'ON'),
    ('ABEV3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '07526557000100'), 'ON');   -- listada, sem negociação

-- ---------------------------------------------------------------------
-- 4. HISTÓRICO DE COTAÇÕES
--    Série intradiária: 5 pregões (01 a 05/09/2026), a cada 30 min das
--    10:00 às 17:00, para cada ação. Preço = base x oscilação determinística
--    (função seno) para simular o comportamento do mercado.
-- ---------------------------------------------------------------------
INSERT INTO bolsa.cotacao (id_acao, data_hora, valor)
SELECT a.id_acao,
       t.instante,
       ROUND(
           ( b.preco_base
             * (1 + 0.012 * sin(extract(epoch FROM t.instante) / 5400.0 + a.id_acao))
             * (1 + 0.004 * (extract(day FROM t.instante) - 3))
           )::numeric,
           4
       )
  FROM bolsa.acao a
  JOIN (VALUES
          ('PETR3', 38.20), ('PETR4', 36.85), ('VALE3', 61.40),
          ('BBDC4', 14.10), ('ITUB4', 33.75), ('MGLU3', 9.80), ('WEGE3', 52.30),
          ('ABEV3', 12.40)
       ) AS b (ticker, preco_base) ON b.ticker = a.ticker
  CROSS JOIN LATERAL (
      SELECT d + (h * interval '30 minutes') AS instante
        FROM generate_series(timestamptz '2026-09-01 10:00-03',
                             timestamptz '2026-09-05 10:00-03',
                             interval '1 day') AS d
        CROSS JOIN generate_series(0, 14) AS h   -- 10:00 .. 17:00, de 30 em 30 min
  ) AS t;

-- Cotação de abertura do pregão seguinte (usada nas consultas "atual")
INSERT INTO bolsa.cotacao (id_acao, data_hora, valor)
SELECT id_acao, timestamptz '2026-09-08 10:00-03', v.preco
  FROM bolsa.acao a
  JOIN (VALUES
          ('PETR3', 38.95), ('PETR4', 37.40), ('VALE3', 60.10),
          ('BBDC4', 14.55), ('ITUB4', 34.20), ('MGLU3', 9.15), ('WEGE3', 53.80),
          ('ABEV3', 12.65)
       ) AS v (ticker, preco) ON v.ticker = a.ticker;

-- ---------------------------------------------------------------------
-- 5. NEGOCIAÇÕES (em ordem cronológica — o trigger monta a carteira)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.negociacao (id_investidor, id_acao, data_hora, tipo_operacao, quantidade, valor_unitario)
SELECT i.id_investidor, a.id_acao, n.data_hora, n.tipo_operacao, n.quantidade, n.valor_unitario
  FROM (VALUES
        -- documento         ticker   data/hora                          op        qtd   preço
        ('52998224725',     'PETR4', timestamptz '2026-09-01 10:15-03', 'COMPRA',  200,  36.70),
        ('52998224725',     'VALE3', timestamptz '2026-09-01 11:05-03', 'COMPRA',  100,  61.10),
        ('11144477735',     'ITUB4', timestamptz '2026-09-01 14:30-03', 'COMPRA',  300,  33.60),
        ('35652325304',     'MGLU3', timestamptz '2026-09-02 10:40-03', 'COMPRA', 1000,   9.75),
        ('11222333000181',  'PETR3', timestamptz '2026-09-02 11:00-03', 'COMPRA', 5000,  38.05),
        ('11222333000181',  'WEGE3', timestamptz '2026-09-02 15:20-03', 'COMPRA', 2000,  52.10),
        ('52998224725',     'PETR4', timestamptz '2026-09-03 10:05-03', 'COMPRA',  100,  37.10),  -- 2ª compra: novo preço médio
        ('20385364008',     'BBDC4', timestamptz '2026-09-03 12:00-03', 'COMPRA',  500,  14.05),
        ('45678901000123',  'VALE3', timestamptz '2026-09-03 13:45-03', 'COMPRA', 3000,  61.50),
        ('11144477735',     'ITUB4', timestamptz '2026-09-04 10:30-03', 'VENDA',   100,  34.05),  -- venda parcial
        ('35652325304',     'MGLU3', timestamptz '2026-09-04 11:15-03', 'VENDA',  1000,   9.90),  -- liquida a posição
        ('52998224725',     'VALE3', timestamptz '2026-09-04 16:00-03', 'VENDA',    50,  60.80),
        ('45678901000123',  'PETR4', timestamptz '2026-09-05 10:10-03', 'COMPRA', 4000,  36.95),
        ('20385364008',     'MGLU3', timestamptz '2026-09-05 14:00-03', 'COMPRA', 2000,   9.60),
        ('11222333000181',  'PETR3', timestamptz '2026-09-05 16:30-03', 'VENDA',  1500,  38.60)
       ) AS n (documento, ticker, data_hora, tipo_operacao, quantidade, valor_unitario)
  JOIN bolsa.investidor i ON i.documento = n.documento
  JOIN bolsa.acao a       ON a.ticker    = n.ticker
 ORDER BY n.data_hora;

-- ---------------------------------------------------------------------
-- 6. UPDATE — atualização cadastral (valor de mercado e telefone)
-- ---------------------------------------------------------------------
UPDATE bolsa.empresa
   SET valor_mercado = 495000000000.00,
       atualizado_em = now()
 WHERE cnpj = '33000167000101';

UPDATE bolsa.investidor
   SET telefone = '61987650004'
 WHERE documento = '20385364008';

-- ---------------------------------------------------------------------
-- 7. DELETE — exclusão permitida (cotação duplicada/errada de um instante)
-- ---------------------------------------------------------------------
DELETE FROM bolsa.cotacao
 WHERE id_acao   = (SELECT id_acao FROM bolsa.acao WHERE ticker = 'WEGE3')
   AND data_hora = timestamptz '2026-09-05 17:00-03';

COMMIT;

-- ---------------------------------------------------------------------
-- 8. DEMONSTRAÇÃO DAS REGRAS DE INTEGRIDADE (cada bloco captura o erro
--    esperado e o exibe como NOTICE, sem interromper o script)
-- ---------------------------------------------------------------------

-- 8.1 Venda acima do saldo → bloqueada pelo trigger
DO $$
BEGIN
    INSERT INTO bolsa.negociacao (id_investidor, id_acao, tipo_operacao, quantidade, valor_unitario)
    VALUES ((SELECT id_investidor FROM bolsa.investidor WHERE documento = '52998224725'),
            (SELECT id_acao FROM bolsa.acao WHERE ticker = 'PETR4'),
            'VENDA', 999999, 37.00);
    RAISE NOTICE 'FALHA: a venda acima do saldo deveria ter sido rejeitada';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK (regra 8.1): %', SQLERRM;
END;
$$;

-- 8.2 Alterar/apagar negociação → bloqueado (registro imutável)
DO $$
BEGIN
    DELETE FROM bolsa.negociacao WHERE id_negociacao = 1;
    RAISE NOTICE 'FALHA: o DELETE de negociação deveria ter sido rejeitado';
EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'OK (regra 8.2): %', SQLERRM;
END;
$$;

-- 8.3 CPF com tamanho de CNPJ → viola CHECK
DO $$
BEGIN
    INSERT INTO bolsa.investidor (documento, tipo_investidor, nome_completo, email)
    VALUES ('12345678000199', 'PF', 'Documento Inválido', 'invalido@exemplo.com');
    RAISE NOTICE 'FALHA: documento incompatível com o tipo deveria ter sido rejeitado';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK (regra 8.3): %', SQLERRM;
END;
$$;

-- 8.4 Excluir empresa que possui ações → bloqueado por FK RESTRICT
DO $$
BEGIN
    DELETE FROM bolsa.empresa WHERE cnpj = '33592510000154';
    RAISE NOTICE 'FALHA: empresa com ações não deveria ser excluída';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK (regra 8.4): %', SQLERRM;
END;
$$;
