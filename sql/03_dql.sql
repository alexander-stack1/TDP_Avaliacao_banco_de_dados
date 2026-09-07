-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES
--  Modelo Físico — DQL (Data Query Language): consultas analíticas
-- =====================================================================

SET search_path TO bolsa, public;

-- ---------------------------------------------------------------------
-- Q01. Carteira atual de cada investidor, valorizada a mercado
--      (view sobre carteira + última cotação).
-- ---------------------------------------------------------------------
SELECT investidor, tipo_investidor, ticker, quantidade, preco_medio,
       cotacao_atual, custo_total, valor_mercado, resultado_nao_realizado, variacao_pct
  FROM bolsa.vw_posicao_valorizada
 ORDER BY investidor, ticker;

-- ---------------------------------------------------------------------
-- Q02. Patrimônio total em ações por investidor (agregação sobre a view).
-- ---------------------------------------------------------------------
SELECT investidor,
       tipo_investidor,
       COUNT(*)                     AS qtd_papeis,
       SUM(custo_total)             AS custo_total,
       SUM(valor_mercado)           AS valor_mercado,
       SUM(resultado_nao_realizado) AS resultado_nao_realizado
  FROM bolsa.vw_posicao_valorizada
 GROUP BY investidor, tipo_investidor
 ORDER BY valor_mercado DESC;

-- ---------------------------------------------------------------------
-- Q03. Extrato de negociações de um investidor (busca pela chave natural).
-- ---------------------------------------------------------------------
SELECT data_hora, ticker, empresa, tipo_operacao, quantidade, valor_unitario, valor_total
  FROM bolsa.vw_extrato_negociacoes
 WHERE documento = '52998224725'
 ORDER BY data_hora;

-- ---------------------------------------------------------------------
-- Q04. Volume financeiro negociado por ação, separado em compras e vendas.
-- ---------------------------------------------------------------------
SELECT a.ticker,
       e.nome AS empresa,
       COUNT(*)                                                          AS qtd_negociacoes,
       SUM(n.quantidade)                                                 AS acoes_negociadas,
       SUM(n.valor_total) FILTER (WHERE n.tipo_operacao = 'COMPRA')      AS volume_compras,
       SUM(n.valor_total) FILTER (WHERE n.tipo_operacao = 'VENDA')       AS volume_vendas,
       SUM(n.valor_total)                                                AS volume_total
  FROM bolsa.negociacao n
  JOIN bolsa.acao a    ON a.id_acao    = n.id_acao
  JOIN bolsa.empresa e ON e.id_empresa = a.id_empresa
 GROUP BY a.ticker, e.nome
 ORDER BY volume_total DESC;

-- ---------------------------------------------------------------------
-- Q05. Série temporal diária (OHLC) de uma ação a partir do histórico
--      intradiário: abertura, máxima, mínima, fechamento e variação do dia.
-- ---------------------------------------------------------------------
WITH intradiario AS (
    SELECT c.data_hora::date AS pregao,
           c.valor,
           FIRST_VALUE(c.valor) OVER (PARTITION BY c.data_hora::date ORDER BY c.data_hora)      AS abertura,
           FIRST_VALUE(c.valor) OVER (PARTITION BY c.data_hora::date ORDER BY c.data_hora DESC) AS fechamento
      FROM bolsa.cotacao c
      JOIN bolsa.acao a ON a.id_acao = c.id_acao
     WHERE a.ticker = 'PETR4'
       AND c.data_hora >= timestamptz '2026-09-01 00:00-03'
       AND c.data_hora <  timestamptz '2026-09-06 00:00-03'
)
SELECT pregao,
       MIN(abertura)    AS abertura,
       MAX(valor)       AS maxima,
       MIN(valor)       AS minima,
       MIN(fechamento)  AS fechamento,
       ROUND((MIN(fechamento) - MIN(abertura)) / MIN(abertura) * 100, 2) AS variacao_dia_pct
  FROM intradiario
 GROUP BY pregao
 ORDER BY pregao;

-- ---------------------------------------------------------------------
-- Q06. Variação percentual entre cotações consecutivas (função de janela LAG)
--      e média móvel de 5 períodos — análise de comportamento do mercado.
-- ---------------------------------------------------------------------
SELECT a.ticker,
       c.data_hora,
       c.valor,
       LAG(c.valor) OVER w                                                   AS valor_anterior,
       ROUND((c.valor - LAG(c.valor) OVER w) / LAG(c.valor) OVER w * 100, 3) AS variacao_pct,
       ROUND(AVG(c.valor) OVER (w ROWS BETWEEN 4 PRECEDING AND CURRENT ROW), 4) AS media_movel_5
  FROM bolsa.cotacao c
  JOIN bolsa.acao a ON a.id_acao = c.id_acao
 WHERE a.ticker = 'VALE3'
   AND c.data_hora::date = date '2026-09-03'
WINDOW w AS (PARTITION BY c.id_acao ORDER BY c.data_hora)
 ORDER BY c.data_hora;

-- ---------------------------------------------------------------------
-- Q07. Maior e menor cotação de cada ação no período, com o instante em que ocorreram.
-- ---------------------------------------------------------------------
SELECT a.ticker,
       MIN(c.valor)                                            AS minima,
       (ARRAY_AGG(c.data_hora ORDER BY c.valor ASC))[1]        AS instante_minima,
       MAX(c.valor)                                            AS maxima,
       (ARRAY_AGG(c.data_hora ORDER BY c.valor DESC))[1]       AS instante_maxima,
       ROUND((MAX(c.valor) - MIN(c.valor)) / MIN(c.valor) * 100, 2) AS amplitude_pct
  FROM bolsa.cotacao c
  JOIN bolsa.acao a ON a.id_acao = c.id_acao
 WHERE c.data_hora >= timestamptz '2026-09-01 00:00-03'
   AND c.data_hora <  timestamptz '2026-09-06 00:00-03'
 GROUP BY a.ticker
 ORDER BY amplitude_pct DESC;

-- ---------------------------------------------------------------------
-- Q08. Análise retrospectiva: como estava a carteira de um investidor
--      no fim do pregão de 03/09/2026, valorizada pela cotação daquele momento.
-- ---------------------------------------------------------------------
SELECT *
  FROM bolsa.fn_carteira_em(
           (SELECT id_investidor FROM bolsa.investidor WHERE documento = '52998224725'),
           timestamptz '2026-09-03 17:00-03'
       );

-- ---------------------------------------------------------------------
-- Q09. Evolução diária do patrimônio de um investidor (série retrospectiva
--      construída com generate_series + função de análise).
-- ---------------------------------------------------------------------
SELECT d::date                        AS data_referencia,
       COALESCE(SUM(k.valor_posicao), 0) AS patrimonio_em_acoes
  FROM generate_series(timestamptz '2026-09-01 17:00-03',
                       timestamptz '2026-09-05 17:00-03',
                       interval '1 day') AS d
  LEFT JOIN LATERAL bolsa.fn_carteira_em(
           (SELECT id_investidor FROM bolsa.investidor WHERE documento = '11222333000181'),
           d
       ) AS k ON true
 GROUP BY d
 ORDER BY d;

-- ---------------------------------------------------------------------
-- Q10. Resultado REALIZADO nas vendas (preço de venda x preço médio de compra
--      até o momento da venda) — lucro/prejuízo efetivo por operação.
-- ---------------------------------------------------------------------
WITH compras_acumuladas AS (
    SELECT n.id_negociacao,
           n.id_investidor,
           n.id_acao,
           n.data_hora,
           n.tipo_operacao,
           n.quantidade,
           n.valor_unitario,
           SUM(n.quantidade * n.valor_unitario)
               FILTER (WHERE n.tipo_operacao = 'COMPRA')
               OVER (PARTITION BY n.id_investidor, n.id_acao ORDER BY n.data_hora
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS custo_acum,
           SUM(n.quantidade)
               FILTER (WHERE n.tipo_operacao = 'COMPRA')
               OVER (PARTITION BY n.id_investidor, n.id_acao ORDER BY n.data_hora
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS qtd_comprada_acum
      FROM bolsa.negociacao n
)
SELECT i.nome_completo AS investidor,
       a.ticker,
       c.data_hora     AS data_venda,
       c.quantidade,
       c.valor_unitario                                       AS preco_venda,
       ROUND(c.custo_acum / c.qtd_comprada_acum, 4)           AS preco_medio_compra,
       ROUND(c.quantidade * (c.valor_unitario - c.custo_acum / c.qtd_comprada_acum), 2)
                                                              AS resultado_realizado
  FROM compras_acumuladas c
  JOIN bolsa.investidor i ON i.id_investidor = c.id_investidor
  JOIN bolsa.acao a       ON a.id_acao       = c.id_acao
 WHERE c.tipo_operacao = 'VENDA'
 ORDER BY c.data_hora;

-- ---------------------------------------------------------------------
-- Q11. Ranking de investidores por volume negociado (função de janela RANK).
-- ---------------------------------------------------------------------
SELECT RANK() OVER (ORDER BY SUM(n.valor_total) DESC) AS posicao,
       i.nome_completo,
       i.tipo_investidor,
       COUNT(*)           AS negociacoes,
       SUM(n.valor_total) AS volume_negociado
  FROM bolsa.negociacao n
  JOIN bolsa.investidor i ON i.id_investidor = n.id_investidor
 GROUP BY i.id_investidor, i.nome_completo, i.tipo_investidor
 ORDER BY posicao;

-- ---------------------------------------------------------------------
-- Q12. Exposição da corretora por setor: soma das posições dos clientes
--      a valor de mercado e participação percentual.
-- ---------------------------------------------------------------------
SELECT setor,
       SUM(valor_mercado)                                                  AS exposicao,
       ROUND(SUM(valor_mercado) * 100.0 / SUM(SUM(valor_mercado)) OVER (), 2) AS participacao_pct
  FROM bolsa.vw_posicao_valorizada
 GROUP BY setor
 ORDER BY exposicao DESC;

-- ---------------------------------------------------------------------
-- Q13. Ações listadas que NÃO tiveram nenhuma negociação (anti-join com NOT EXISTS).
-- ---------------------------------------------------------------------
SELECT a.ticker, e.nome AS empresa, e.setor
  FROM bolsa.acao a
  JOIN bolsa.empresa e ON e.id_empresa = a.id_empresa
 WHERE a.ativa
   AND NOT EXISTS (SELECT 1 FROM bolsa.negociacao n WHERE n.id_acao = a.id_acao)
 ORDER BY a.ticker;

-- ---------------------------------------------------------------------
-- Q14. Comparativo PF x PJ: quantidade de clientes, negociações e ticket médio.
-- ---------------------------------------------------------------------
SELECT i.tipo_investidor,
       COUNT(DISTINCT i.id_investidor)      AS investidores,
       COUNT(n.id_negociacao)               AS negociacoes,
       COALESCE(SUM(n.valor_total), 0)      AS volume,
       ROUND(AVG(n.valor_total), 2)         AS ticket_medio
  FROM bolsa.investidor i
  LEFT JOIN bolsa.negociacao n ON n.id_investidor = i.id_investidor
 GROUP BY i.tipo_investidor
 ORDER BY i.tipo_investidor;

-- ---------------------------------------------------------------------
-- Q15. Conferência de integridade: a carteira mantida pelo trigger deve
--      bater com o saldo recalculado a partir das negociações (deve retornar 0 linhas).
-- ---------------------------------------------------------------------
SELECT ca.id_investidor, ca.id_acao, ca.quantidade AS qtd_carteira, r.qtd_recalculada
  FROM bolsa.carteira ca
  FULL OUTER JOIN (
        SELECT id_investidor, id_acao,
               SUM(CASE WHEN tipo_operacao = 'COMPRA' THEN quantidade ELSE -quantidade END) AS qtd_recalculada
          FROM bolsa.negociacao
         GROUP BY id_investidor, id_acao
       ) r ON r.id_investidor = ca.id_investidor AND r.id_acao = ca.id_acao
 WHERE ca.quantidade IS DISTINCT FROM r.qtd_recalculada;

-- ---------------------------------------------------------------------
-- Q16. Plano de execução de uma consulta de série temporal — evidência de
--      uso do índice (id_acao, data_hora) definido pela restrição UNIQUE.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
SELECT data_hora, valor
  FROM bolsa.cotacao
 WHERE id_acao = 2
   AND data_hora BETWEEN timestamptz '2026-09-02 00:00-03' AND timestamptz '2026-09-03 00:00-03'
 ORDER BY data_hora;
