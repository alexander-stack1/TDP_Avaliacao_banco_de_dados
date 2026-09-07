# Modelo Físico — PostgreSQL 16

O modelo físico está em [`sql/00_bolsa_completo.sql`](../../sql/00_bolsa_completo.sql) (arquivo único com DDL + DML + DQL, gerado por `scripts/build_sql.sh`). Os fontes separados ficam em `sql/01_ddl.sql`, `sql/02_dml.sql` e `sql/03_dql.sql`.

## Como executar

```bash
createdb bolsa_valores
psql -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql
```

Ou, para criar um banco descartável e validar tudo de uma vez: `scripts/validar.sh`.

## O que o script faz

### DDL
- Esquema `bolsa` com 6 tabelas (`investidor`, `empresa`, `acao`, `cotacao`, `negociacao`, `carteira`).
- Chaves primárias `bigint GENERATED ALWAYS AS IDENTITY`; chaves naturais como UNIQUE.
- Regras de negócio como CHECK: CPF/CNPJ por tipo, formato de ticker, e-mail, quantidades e preços positivos.
- Índices: todas as FKs indexadas; compostos `(id_investidor, data_hora)` e `(id_acao, data_hora)` para extratos; BRIN em `cotacao.data_hora` para varreduras de série temporal.
- Coluna gerada `negociacao.valor_total`.
- Triggers: `trg_negociacao_atualiza_carteira` (atualiza posição e preço médio; rejeita venda sem saldo) e `trg_negociacao_imutavel` (bloqueia UPDATE/DELETE em negociação).
- Função `fn_carteira_em(investidor, momento)` para análise retrospectiva.
- Views `vw_cotacao_atual`, `vw_posicao_valorizada`, `vw_extrato_negociacoes`.
- Papel `bolsa_leitura` somente-leitura (menor privilégio).
- `COMMENT ON` em todos os objetos relevantes.

### DML
- 6 investidores (4 PF, 2 PJ), 7 empresas, 8 ações.
- 600 cotações intradiárias (5 pregões × 15 instantes × 8 ações) geradas com `generate_series`, mais a abertura do pregão seguinte.
- 15 negociações em ordem cronológica: o trigger monta a carteira (inclui recompra com novo preço médio, venda parcial e liquidação total).
- UPDATE, DELETE e 4 blocos `DO` que demonstram as regras de integridade sem interromper o script.

### DQL (16 consultas)
| # | Consulta | Recursos |
|---|---|---|
| Q01 | Carteira valorizada a mercado | view + DISTINCT ON |
| Q02 | Patrimônio por investidor | GROUP BY sobre view |
| Q03 | Extrato por CPF/CNPJ | chave natural |
| Q04 | Volume por ação, compras × vendas | `FILTER (WHERE …)` |
| Q05 | OHLC diário a partir do intradiário | `FIRST_VALUE` em janela |
| Q06 | Variação entre cotações e média móvel | `LAG`, `AVG … ROWS BETWEEN` |
| Q07 | Máxima e mínima com instante | `ARRAY_AGG … ORDER BY` |
| Q08 | Carteira em data passada | função `fn_carteira_em` |
| Q09 | Evolução diária do patrimônio | `generate_series` + `LATERAL` |
| Q10 | Resultado realizado nas vendas | janela acumulada com `FILTER` |
| Q11 | Ranking de investidores | `RANK()` |
| Q12 | Exposição por setor | janela sobre agregado |
| Q13 | Ações sem negociação | `NOT EXISTS` |
| Q14 | PF × PJ | `LEFT JOIN` + agregações |
| Q15 | Conferência carteira × negociações | `FULL OUTER JOIN` (deve retornar 0 linhas) |
| Q16 | Plano de execução de consulta temporal | `EXPLAIN` (usa o índice da UNIQUE) |

## Validação

O script completo foi executado em PostgreSQL 16.13 com `ON_ERROR_STOP` ligado: zero erros, os 4 blocos de demonstração de integridade reportaram `OK`, Q15 retornou 0 linhas e Q16 mostrou `Index Scan using uq_cotacao_acao_hora`.
