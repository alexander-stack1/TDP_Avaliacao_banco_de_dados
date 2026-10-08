-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES
--  Modelo Físico — DQL (Data Query Language): consultas analíticas
-- =====================================================================

SET search_path TO bolsa, public;
SET TIME ZONE 'America/Sao_Paulo';

-- ---------------------------------------------------------------------
-- Q01. Carteira atual de cada investidor, valorizada a mercado
--      (view sobre carteira + última cotação).
-- ---------------------------------------------------------------------
SELECT investidor, tipo_investidor, ticker, quantidade, preco_medio,
       cotacao_atual, custo_total, valor_mercado, resultado_nao_realizado, variacao_pct
  FROM bolsa.vw_posicao_valorizada
 ORDER BY investidor, ticker;

-- ---------------------------------------------------------------------
-- Q02. Patrimônio total em ações por investidor, incluindo posições zeradas.
--      Sem cotação, o total é desconhecido; sem posição, o total é zero.
-- ---------------------------------------------------------------------
SELECT i.id_investidor, i.nome_completo AS investidor,
       i.tipo_investidor,
       COUNT(v.ticker) AS qtd_papeis,
       COALESCE(SUM(v.custo_total), 0) AS custo_total,
       CASE WHEN COUNT(v.ticker) = COUNT(v.cotacao_atual)
            THEN COALESCE(SUM(v.valor_mercado), 0) END AS valor_mercado,
       CASE WHEN COUNT(v.ticker) = COUNT(v.cotacao_atual)
            THEN COALESCE(SUM(v.resultado_nao_realizado), 0) END AS resultado_nao_realizado,
       COUNT(v.ticker) FILTER (WHERE v.cotacao_atual IS NULL) AS papeis_sem_cotacao
  FROM bolsa.investidor i
  LEFT JOIN bolsa.vw_posicao_valorizada v ON v.id_investidor = i.id_investidor
 GROUP BY i.id_investidor, i.nome_completo, i.tipo_investidor
 ORDER BY valor_mercado DESC NULLS LAST;

-- ---------------------------------------------------------------------
-- Q03. Extrato de negociações de um investidor (busca pela chave natural).
-- ---------------------------------------------------------------------
SELECT data_hora, ticker, empresa, tipo_operacao, quantidade, valor_unitario, valor_total
  FROM bolsa.vw_extrato_negociacoes
 WHERE documento = '00000000001'
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
       AND c.data_hora >= timestamptz '2026-08-31 00:00-03'
       AND c.data_hora <  timestamptz '2026-09-05 00:00-03'
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
   AND c.data_hora::date = date '2026-09-02'
WINDOW w AS (PARTITION BY c.id_acao ORDER BY c.data_hora)
 ORDER BY c.data_hora;

-- ---------------------------------------------------------------------
-- Q07. Maior e menor cotação de cada ação no período, com o instante em que ocorreram.
-- ---------------------------------------------------------------------
SELECT a.ticker,
       MIN(c.valor)                                            AS minima,
       (ARRAY_AGG(c.data_hora ORDER BY c.valor ASC, c.data_hora ASC))[1]        AS instante_minima,
       MAX(c.valor)                                            AS maxima,
       (ARRAY_AGG(c.data_hora ORDER BY c.valor DESC, c.data_hora ASC))[1]       AS instante_maxima,
       ROUND((MAX(c.valor) - MIN(c.valor)) / MIN(c.valor) * 100, 2) AS amplitude_pct
  FROM bolsa.cotacao c
  JOIN bolsa.acao a ON a.id_acao = c.id_acao
 WHERE c.data_hora >= timestamptz '2026-08-31 00:00-03'
   AND c.data_hora <  timestamptz '2026-09-05 00:00-03'
 GROUP BY a.ticker
 ORDER BY amplitude_pct DESC;

-- ---------------------------------------------------------------------
-- Q08. Análise retrospectiva: como estava a carteira de um investidor
--      no fim do pregão de 02/09/2026, valorizada pela cotação daquele momento.
-- ---------------------------------------------------------------------
SELECT *
  FROM bolsa.fn_carteira_em(
           (SELECT id_investidor FROM bolsa.investidor WHERE documento = '00000000001'),
           timestamptz '2026-09-02 17:00-03'
       );

-- ---------------------------------------------------------------------
-- Q09. Evolução diária do patrimônio de um investidor (série retrospectiva
--      construída com generate_series + função de análise).
-- ---------------------------------------------------------------------
SELECT d::date                        AS data_referencia,
       CASE WHEN COUNT(k.ticker) = COUNT(k.cotacao_na_data)
            THEN COALESCE(SUM(k.valor_posicao), 0) END AS patrimonio_em_acoes,
       COUNT(k.ticker) FILTER (WHERE k.cotacao_na_data IS NULL) AS papeis_sem_cotacao
  FROM generate_series(timestamptz '2026-08-31 17:00-03',
                       timestamptz '2026-09-04 17:00-03',
                       interval '1 day') AS d
  LEFT JOIN LATERAL bolsa.fn_carteira_em(
           (SELECT id_investidor FROM bolsa.investidor WHERE documento = '00000000000001'),
           d
       ) AS k ON true
 GROUP BY d
 ORDER BY d;

-- ---------------------------------------------------------------------
-- Q10. Resultado REALIZADO nas vendas (preço de venda x preço médio de compra
--      até o momento da venda) — lucro/prejuízo efetivo por operação.
-- ---------------------------------------------------------------------
SELECT i.nome_completo AS investidor,
       a.ticker,
       e.data_hora AS data_venda,
       e.quantidade,
       e.valor_unitario AS preco_venda,
       e.preco_medio_anterior AS preco_medio_compra,
       e.resultado_realizado
  FROM bolsa.vw_evolucao_carteira e
  JOIN bolsa.investidor i ON i.id_investidor = e.id_investidor
  JOIN bolsa.acao a ON a.id_acao = e.id_acao
 WHERE e.tipo_operacao = 'VENDA'
 ORDER BY e.data_hora, e.id_negociacao;

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
       CASE WHEN COUNT(*) = COUNT(cotacao_atual) THEN SUM(valor_mercado) END AS exposicao,
       CASE WHEN SUM(COUNT(*) - COUNT(cotacao_atual)) OVER () = 0
            THEN ROUND(SUM(valor_mercado) * 100.0 / NULLIF(SUM(SUM(valor_mercado)) OVER (), 0), 2)
       END AS participacao_pct,
       COUNT(*) FILTER (WHERE cotacao_atual IS NULL) AS papeis_sem_cotacao
  FROM bolsa.vw_posicao_valorizada
 GROUP BY setor
 ORDER BY exposicao DESC NULLS LAST;

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
SELECT COALESCE(ca.id_investidor, r.id_investidor) AS id_investidor,
       COALESCE(ca.id_acao, r.id_acao) AS id_acao, ca.quantidade AS qtd_carteira, r.qtd_recalculada
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
--      plano escolhido pelo otimizador para (id_acao, data_hora) definido pela restrição UNIQUE.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
SELECT data_hora, valor
  FROM bolsa.cotacao
 WHERE id_acao = (SELECT id_acao FROM bolsa.acao WHERE ticker = 'PETR4')
   AND data_hora BETWEEN timestamptz '2026-09-01 00:00-03' AND timestamptz '2026-09-02 00:00-03'
 ORDER BY data_hora;
