# Modelo Físico PostgreSQL 16

Arquivo de entrega: [`sql/00_bolsa_completo.sql`](../../sql/00_bolsa_completo.sql), gerado por `scripts/build_sql.sh`. Os fontes são `01_ddl.sql`, `02_dml.sql` e `03_dql.sql`.

## Instalação

```bash
createdb bolsa_valores
psql -X -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql
```

O banco precisa ser novo ou não conter o esquema `bolsa`. A criação do esquema e dos objetos é transacional. Uma reexecução é recusada sem apagar dados. DML tem transação própria. Não há `DROP SCHEMA`, criação de papéis globais nem exigência de superusuário. O arquivo fixa o fuso `America/Sao_Paulo` para a demonstração.

## DDL

- Seis tabelas: `investidor`, `empresa`, `acao`, `cotacao`, `negociacao`, `carteira`.
- PKs `bigint GENERATED ALWAYS AS IDENTITY`, exceto a PK composta de carteira. CPF/CNPJ e ticker são chaves naturais únicas. Cotação tem UNIQUE `(id_acao, data_hora)`.
- Documento, tipo, nome, e-mail e telefone são obrigatórios. CPF/CNPJ validam somente caracteres e comprimento; e-mail tem verificação básica. Quantidades e preços são positivos, valores `NaN` e instantes infinitos são recusados nos fatos temporais.
- Índices nas FKs; compostos para consultas por investidor/ação e tempo; BRIN no histórico. A utilidade dos índices depende do volume e do plano escolhido pelo otimizador.
- `negociacao.valor_total` é gerado. A carteira é uma materialização derivada, sem edição direta de linhas.
- `trg_negociacao_atualiza_carteira`: bloqueia a posição por par, valida ordem temporal estrita e saldo, aplica compra/venda e registra o instante do evento. Uma falha desfaz toda a instrução, incluindo sua alteração de carteira.
- Bloqueios de UPDATE, DELETE e TRUNCATE em negociação; proteção de escrita direta e TRUNCATE em carteira. Administradores que desabilitam triggers continuam privilegiados.
- `fn_carteira_em`: recompõe quantidades até um instante, usando somente cotações anteriores ou iguais a ele. Sem cotação, conserva quantidade e devolve preço e valor `NULL`.
- Quatro views: `vw_cotacao_atual`, `vw_posicao_valorizada`, `vw_extrato_negociacoes`, `vw_evolucao_carteira`.

## Custo médio e ordem temporal

Compras ponderam o custo da posição remanescente com o da nova compra. Vendas mantêm o custo médio enquanto resta saldo; ao zerar, o custo médio também zera. A view de evolução recompõe a sequência com CTE recursiva e o mesmo arredondamento de quatro casas utilizado pelo trigger. O lucro por venda é calculado sobre o preço médio anterior àquela venda, com resultado arredondado a centavos.

Operações entram em instantes **estritamente crescentes por par investidor/ação**. Essa é uma premissa adicional do case, não uma exigência literal do enunciado. Uma inserção retroativa ou com instante repetido no mesmo par é recusada. Reprocessamento de histórico, estornos, taxas, tributos e eventos societários estão fora do escopo.

## DML

A carga é sintética, sem dados pessoais reais: 6 investidores (4 PF e 2 PJ), 7 empresas, 8 ações, 19 negociações e 607 cotações finais. Tickers conhecidos são rótulos ilustrativos; as empresas, documentos e valores são didáticos.

São geradas 600 cotações (5 dias úteis simulados de 31/08 a 04/09/2026 × 15 instantes × 8 ações), acrescidas de 8 preços de 08/09 e reduzidas por um DELETE demonstrativo. Há compras, vendas parciais, liquidação e recompra. UPDATE e DELETE são demonstrados em cadastros/cotações. Quatro blocos verificam rejeições esperadas e lançam exceção se a regra deixar de ser aplicada.

## DQL

| Consulta | Finalidade | Recursos |
|---|---|---|
| Q01 | Posições abertas valorizadas | View e última cotação |
| Q02 | Patrimônio de todos os investidores, inclusive zerados | LEFT JOIN, identidade do investidor e agregação |
| Q03 | Extrato por documento | Busca por chave natural |
| Q04 | Volume por ação, compras e vendas | FILTER e SUM |
| Q05 | Abertura, máxima, mínima e fechamento | FIRST_VALUE e agregação |
| Q06 | Variação intradiária e média móvel | LAG e AVG em janela |
| Q07 | Extremos e seus instantes | ARRAY_AGG com desempate temporal |
| Q08 | Carteira histórica | fn_carteira_em |
| Q09 | Evolução diária do patrimônio | generate_series e LATERAL |
| Q10 | Lucro/prejuízo por venda | Reconstituição recursiva do custo médio móvel |
| Q11 | Ranking de volume | RANK |
| Q12 | Exposição por setor | Agregação e janela |
| Q13 | Ações sem negociação | NOT EXISTS |
| Q14 | Comparação PF/PJ | LEFT JOIN e agregação |
| Q15 | Conferência entre saldo e negociações | FULL OUTER JOIN; esperado zero linhas |
| Q16 | Plano de uma consulta temporal | EXPLAIN; plano pode variar |

Q02, Q09 e Q12 indicam ausência de cotação em vez de apresentar soma incompleta como patrimônio total. Ausência de posição é diferente de ausência de preço.

## Evidência da revisão

`scripts/validar.sh` executado em 07/10/2026 com PostgreSQL **16.15**, em instância temporária sem rede TCP, usando papel sem superusuário ou CREATEROLE. DDL, DML, 16 DQLs e **42 verificações de regressão** concluíram. A tentativa de reexecutar foi recusada e preservou a carga. Q15 retornou zero linhas; nesta execução Q16 usou `uq_cotacao_acao_hora`.

Os testes incluem identidade de homônimos, telefone obrigatório, unicidade, FKs, preço inválido, instantes retroativos/iguais, proteção de histórico/carteira, recompra após venda parcial e total, preço ausente, bloqueio de preço futuro e duas vendas concorrentes. As fixtures são revertidas; a instância inteira é descartada ao concluir. Logs: `tmp/validacao/execucao.log`, `testes.log`, `reexecucao.log`, `versao.txt`.

Referências técnicas consultadas: [CTEs recursivas](https://www.postgresql.org/docs/16/queries-with.html) e [funções de trigger](https://www.postgresql.org/docs/16/plpgsql-trigger.html) da documentação oficial do PostgreSQL 16.
