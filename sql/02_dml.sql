-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES
--  Modelo Físico — DML (Data Manipulation Language): carga de exemplo
--  Dados sintéticos: documentos sem validação de dígitos verificadores,
--  nomes genéricos e e-mails no domínio reservado example.invalid.
--  Tickers são rótulos ilustrativos; preços e empresas não são dados de mercado.
-- =====================================================================

SET search_path TO bolsa, public;
SET TIME ZONE 'America/Sao_Paulo';

BEGIN;

-- ---------------------------------------------------------------------
-- 1. INVESTIDORES (4 PF + 2 PJ)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.investidor (documento, tipo_investidor, nome_completo, email, telefone) VALUES
    ('00000000001',     'PF', 'Investidor PF 01',          'pf01@example.invalid',      '11987650001'),
    ('00000000002',     'PF', 'Investidor PF 02',        'pf02@example.invalid',       '21987650002'),
    ('00000000003',     'PF', 'Investidor PF 03',         'pf03@example.invalid',      '31987650003'),
    ('00000000004',     'PF', 'Investidor PF 04',     'pf04@example.invalid',      '11900000004'),
    ('00000000000001',  'PJ', 'Investidor PJ 01','pj01@example.invalid',   '1133330004'),
    ('00000000000002',  'PJ', 'Investidor PJ 02','pj02@example.invalid','4133330005');

-- ---------------------------------------------------------------------
-- 2. EMPRESAS LISTADAS (7)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.empresa (cnpj, nome, setor, valor_mercado) VALUES
    ('10000000000001', 'Empresa Didática 01',  'Petróleo e Gás',      480000000000.00),
    ('10000000000002', 'Empresa Didática 02',                 'Mineração',           280000000000.00),
    ('10000000000003', 'Empresa Didática 03',       'Financeiro',          150000000000.00),
    ('10000000000004', 'Empresa Didática 04','Financeiro',          320000000000.00),
    ('10000000000005', 'Empresa Didática 05',       'Varejo',               8000000000.00),
    ('10000000000006', 'Empresa Didática 06',                  'Bens Industriais',    170000000000.00),
    ('10000000000007', 'Empresa Didática 07',                'Bebidas',             190000000000.00);

-- ---------------------------------------------------------------------
-- 3. AÇÕES (8 papéis; uma empresa pode ter mais de um)
-- ---------------------------------------------------------------------
INSERT INTO bolsa.acao (ticker, id_empresa, tipo_acao) VALUES
    ('PETR3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000001'), 'ON'),
    ('PETR4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000001'), 'PN'),
    ('VALE3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000002'), 'ON'),
    ('BBDC4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000003'), 'PN'),
    ('ITUB4', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000004'), 'PN'),
    ('MGLU3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000005'), 'ON'),
    ('WEGE3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000006'), 'ON'),
    ('ABEV3', (SELECT id_empresa FROM bolsa.empresa WHERE cnpj = '10000000000007'), 'ON');   -- listada, sem negociação

-- ---------------------------------------------------------------------
-- 4. HISTÓRICO DE COTAÇÕES
--    Série intradiária: 5 dias úteis simulados (31/08 a 04/09/2026), a cada 30 min das
--    10:00 às 17:00, para cada ação. Preço = base x oscilação determinística
--    (função seno) para simular o comportamento do mercado.
-- ---------------------------------------------------------------------
INSERT INTO bolsa.cotacao (id_acao, data_hora, valor)
SELECT a.id_acao,
       t.instante,
       ROUND(
           ( b.preco_base
             * (1 + 0.012 * sin(extract(epoch FROM t.instante) / 5400.0 + a.id_acao))
             * (1 + 0.004 * ((t.instante AT TIME ZONE 'America/Sao_Paulo')::date - date '2026-09-02'))
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
        FROM generate_series(timestamptz '2026-08-31 10:00-03',
                             timestamptz '2026-09-04 10:00-03',
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
        ('00000000001',     'PETR4', timestamptz '2026-08-31 10:15-03', 'COMPRA',  200,  36.70),
        ('00000000001',     'VALE3', timestamptz '2026-08-31 11:05-03', 'COMPRA',  100,  61.10),
        ('00000000002',     'ITUB4', timestamptz '2026-08-31 14:30-03', 'COMPRA',  300,  33.60),
        ('00000000003',     'MGLU3', timestamptz '2026-09-01 10:40-03', 'COMPRA', 1000,   9.75),
        ('00000000000001',  'PETR3', timestamptz '2026-09-01 11:00-03', 'COMPRA', 5000,  38.05),
        ('00000000000001',  'WEGE3', timestamptz '2026-09-01 15:20-03', 'COMPRA', 2000,  52.10),
        ('00000000001',     'PETR4', timestamptz '2026-09-02 10:05-03', 'COMPRA',  100,  37.10),  -- 2ª compra: novo preço médio
        ('00000000004',     'BBDC4', timestamptz '2026-09-02 12:00-03', 'COMPRA',  500,  14.05),
        ('00000000000002',  'VALE3', timestamptz '2026-09-02 13:45-03', 'COMPRA', 3000,  61.50),
        ('00000000002',     'ITUB4', timestamptz '2026-09-03 10:30-03', 'VENDA',   100,  34.05),  -- venda parcial
        ('00000000003',     'MGLU3', timestamptz '2026-09-03 11:15-03', 'VENDA',  1000,   9.90),  -- liquida a posição
        ('00000000001',     'VALE3', timestamptz '2026-09-03 16:00-03', 'VENDA',    50,  60.80),
        ('00000000000002',  'PETR4', timestamptz '2026-09-04 10:10-03', 'COMPRA', 4000,  36.95),
        ('00000000004',     'MGLU3', timestamptz '2026-09-04 14:00-03', 'COMPRA', 2000,   9.60),
        ('00000000000001',  'PETR3', timestamptz '2026-09-04 16:30-03', 'VENDA',  1500,  38.60),
        -- Recompra após venda parcial: a média usa somente o saldo remanescente.
        ('00000000002', 'ITUB4', timestamptz '2026-09-03 12:00-03', 'COMPRA', 100, 40.00),
        ('00000000002', 'ITUB4', timestamptz '2026-09-03 14:00-03', 'VENDA',   50, 42.00),
        -- Nova posição após liquidação: o custo anterior não pode contaminar a recompra.
        ('00000000003', 'MGLU3', timestamptz '2026-09-04 11:00-03', 'COMPRA', 100,  8.00),
        ('00000000003', 'MGLU3', timestamptz '2026-09-04 13:00-03', 'VENDA',  100,  9.00)
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
 WHERE cnpj = '10000000000001';

UPDATE bolsa.investidor
   SET telefone = '61987650004'
 WHERE documento = '00000000004';

-- ---------------------------------------------------------------------
-- 7. DELETE — exclusão permitida (cotação duplicada/errada de um instante)
-- ---------------------------------------------------------------------
DELETE FROM bolsa.cotacao
 WHERE id_acao   = (SELECT id_acao FROM bolsa.acao WHERE ticker = 'WEGE3')
   AND data_hora = timestamptz '2026-09-04 17:00-03';

COMMIT;

-- ---------------------------------------------------------------------
-- 8. DEMONSTRAÇÃO DAS REGRAS DE INTEGRIDADE (cada bloco captura o erro
--    esperado e o exibe como NOTICE, sem interromper o script)
-- ---------------------------------------------------------------------

-- 8.1 Venda acima do saldo → bloqueada pelo trigger
DO $$
BEGIN
    INSERT INTO bolsa.negociacao (id_investidor, id_acao, tipo_operacao, quantidade, valor_unitario)
    VALUES ((SELECT id_investidor FROM bolsa.investidor WHERE documento = '00000000001'),
            (SELECT id_acao FROM bolsa.acao WHERE ticker = 'PETR4'),
            'VENDA', 999999, 37.00);
    RAISE EXCEPTION 'FALHA: a venda acima do saldo deveria ter sido rejeitada';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK (regra 8.1): %', SQLERRM;
END;
$$;

-- 8.2 Alterar/apagar negociação → bloqueado (registro imutável)
DO $$
BEGIN
    DELETE FROM bolsa.negociacao WHERE id_negociacao = 1;
    RAISE EXCEPTION 'FALHA: o DELETE de negociação deveria ter sido rejeitado';
EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'OK (regra 8.2): %', SQLERRM;
END;
$$;

-- 8.3 CPF com tamanho de CNPJ → viola CHECK
DO $$
BEGIN
    INSERT INTO bolsa.investidor (documento, tipo_investidor, nome_completo, email, telefone)
    VALUES ('12345678000199', 'PF', 'Documento Inválido', 'invalido@example.invalid', '11900000000');
    RAISE EXCEPTION 'FALHA: documento incompatível com o tipo deveria ter sido rejeitado';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK (regra 8.3): %', SQLERRM;
END;
$$;

-- 8.4 Excluir empresa que possui ações → bloqueado por FK RESTRICT
DO $$
BEGIN
    DELETE FROM bolsa.empresa WHERE cnpj = '10000000000002';
    RAISE EXCEPTION 'FALHA: empresa com ações não deveria ser excluída';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK (regra 8.4): %', SQLERRM;
END;
$$;
