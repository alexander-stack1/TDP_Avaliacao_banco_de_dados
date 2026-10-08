# Revisão do trabalho de banco de dados

Revisão local realizada em **07/10/2026**, a partir do PDF **TDP - Atividade Avaliativa**, páginas 2 e 3, e do clone na branch `main` (base `63f541e`). O diretório estava sem alterações locais no início. O objetivo foi preservar o modelo existente que atende ao case e corrigir inconsistências de comportamento, documentação e entrega.

## Cobertura do enunciado

| Requisito | Evidência na versão revisada | Situação |
|---|---|---|
| Investidor com CPF/CNPJ, nome, tipo, e-mail e telefone | Tabela investidor; documento único e campos obrigatórios | Atendido |
| Ação, ticker e empresa com nome, setor e valor de mercado | Tabelas acao e empresa; empresa pode emitir vários papéis | Atendido |
| Compras e vendas com data/hora, quantidade e preço | Entidade negociacao com FKs para investidor e ação | Atendido |
| Várias negociações do mesmo par ao longo do tempo | PK própria para cada negociação | Atendido |
| Histórico de cotações intradiárias | cotacao; UNIQUE da ação e instante; Q05 a Q07 | Atendido |
| Saldo atualizado pelas negociações | Trigger, bloqueio da posição e carteira derivada | Atendido |
| Análise retrospectiva com histórico de preços | fn_carteira_em; Q08 e Q09; teste contra preços futuros | Atendido |
| Conceitual no brModelo com arquivo e print | .brM3 reaberto com as classes do brModelo e PNG nativo | Atendido |
| Lógico textual ou gráfico com arquivo e print | modelo_logico.md e modelo_logico.png | Atendido |
| Arquivo SQL com DDL, DML e DQL | 00_bolsa_completo.sql sincronizado com os três fontes | Atendido |
| Word sugerido | Relatório atualizado; PDF complementar | Preparado; falta preencher a capa |
| Entrega via Classroom e grupo de até cinco | Pacote local e checklist; nenhuma publicação executada | Envio manual pendente |

O enunciado informa prazo **18/10**, sem ano explícito. As instruções de envio foram tratadas como requisitos da atividade; não como autorização para publicar arquivos ou contatar o professor.

## Correções realizadas

| Problema observado | Correção e efeito |
|---|---|
| DDL executava `DROP SCHEMA ... CASCADE`; validador apagava um banco de nome fixo | DDL recusa esquema existente; validador cria instância própria, sem TCP, e remove somente sua área temporária |
| Q10 calculava média de todas as compras, desconsiderando o custo retirado nas vendas | Reconstituição recursiva do preço médio móvel, incluindo recompra após venda parcial e após liquidação |
| Operação retroativa podia gerar histórico incompatível com o saldo atual | Ordem temporal estrita por par, verificada após bloqueio da posição; premissa adicional documentada |
| Carteira registrava `now()` como data da última negociação | `atualizado_em` recebe o instante da negociação |
| Carteira podia ser alterada diretamente e negociação podia sofrer TRUNCATE | Triggers impedem esses caminhos normais de DML; administradores ainda podem desabilitar proteções |
| Telefone era opcional apesar de constar entre os atributos exigidos | Campo obrigatório e fixture ajustada |
| Preços `NaN` e instantes infinitos passavam por parte das verificações | Restrições explícitas nos fatos temporais e valores monetários |
| Q02 agrupava homônimos e omitia investidores com carteira zerada | Agregação pela identidade com LEFT JOIN a todos os investidores |
| Somas podiam ocultar posições sem cotação | Q02, Q09 e Q12 distinguem total incompleto (`NULL`) de posição inexistente (zero) |
| Mínimos 1:N dos desenhos não correspondiam ao cadastro permitido pelo SQL | Empresa antes dos papéis e ação antes de cotação representadas como 0:N, com justificativa |
| Afirmação de 3FN ignorava atributos derivados armazenados | Separação entre dados normalizados e materializações de valor_total/carteira |
| Dados apresentados como inventados incluíam nomes e identificadores de empresas reais | Fixtures substituídas por identificadores sintéticos, nomes genéricos e domínio example.invalid |
| Série de cinco pregões incluía um sábado | Carga simulada em cinco dias úteis de 31/08 a 04/09/2026 |
| Criação de papel global exigia privilégio adicional | Removida do script de entrega; execução verificada sem CREATEROLE |
| Demonstrações apenas imprimiam aviso quando uma regra falhava | Lançam exceção se a operação indevida for aceita |
| Documentação de conexão sugeria carregamento automático de `.env` | Mecanismo real de conexão explicado; exemplo sem senha |
| Word mantinha campos vazios de sumário/listas e quebras de linhas de tabela | Índices preenchidos a partir da paginação renderizada; tabelas e layout revisados |

## Validação executada

| Comando | Resultado |
|---|---|
| `scripts/build_sql.sh` | Arquivo consolidado regenerado |
| `scripts/build_sql.sh --check` | Consolidado corresponde exatamente aos fontes |
| `scripts/validar.sh` | PostgreSQL 16.15; DDL, DML e 16 consultas concluíram; 42 verificações passaram |
| `scripts/gerar_brm3.sh` | Arquivo nativo gravado e reaberto: 79 itens, versão de formato 3.2.0; PNG 1510 × 776 |
| `python3 scripts/gerar_diagramas.py` | Diagramas lógico e Chen anotado regenerados |
| `python3 scripts/gerar_docx.py` e renderizador DOCX | Word e PDF regenerados; revisão visual das páginas e índices |
| `bash -n scripts/build_sql.sh scripts/validar.sh scripts/gerar_brm3.sh` | Sintaxe dos scripts válida |
| `git diff --check` | Sem erros de whitespace |

O teste SQL roda em instância criada por `initdb`, com socket Unix privado e papel sem superusuário ou CREATEROLE. Não usa conexão com banco existente. A reexecução do script completo é recusada e a carga original permanece com **6 investidores, 7 empresas, 8 ações, 607 cotações e 19 negociações**. As regressões usam transações revertidas; o cenário concorrente é executado por duas sessões reais antes de descartar a instância.

Resultados selecionados da carga:

- Recompra após venda parcial: preço médio de ITUB4 **35,7333** e lucro da venda subsequente **313,34**.
- Recompra após zerar MGLU3: custo médio anterior à venda **8,0000**, lucro **100,00**, posição final zero.
- Carteira histórica do investidor PF 01 em 02/09/2026 às 17h: **300 PETR4 e 100 VALE3**, total **17.172,60**.
- Nove posições abertas; Q02 inclui também o investidor com saldo zero.
- Q15 retorna zero divergências; a conferência adicional valida também preço médio e instante.
- Venda concorrente que reutilizaria saldo já vendido é rejeitada; carteira mantém o saldo correto.

Os registros completos estão em `tmp/validacao/`, ignorados pelo Git. Para reproduzir, execute o validador com PostgreSQL 16 e Python 3 no PATH. Os geradores de Word e a verificação visual foram executados com o Python do runtime do Codex; a biblioteca matplotlib foi disponibilizada temporariamente para os diagramas.

## Limites e pendências

**Pendente para entrega:** instituição, nome exato do curso, cidade e integrantes. O relatório mantém esses campos sinalizados. A disciplina e o professor foram preenchidos a partir do enunciado. Não houve commit, stage, push, publicação ou envio ao Classroom.

São premissas adicionais do projeto: impedir venda descoberta, manter negociação imutável e exigir instantes estritamente crescentes por par investidor/ação. Atrasos ou duas operações do mesmo par no mesmo instante não são suportados. O case não implementa estorno contábil, integração real com bolsa, taxas, tributos, eventos societários, validação de dígitos verificadores ou calendário oficial de pregões. Valores de mercado e cotações são sintéticos. O preço médio é arredondado a quatro casas a cada compra.

A view de evolução recompõe o histórico inteiro e não foi submetida a teste de escala. Os testes confirmam a correção dos cenários do trabalho; não constituem homologação de um sistema financeiro de produção. Planos de execução podem variar conforme ambiente e volume.

Referências técnicas: [PostgreSQL 16 — consultas recursivas](https://www.postgresql.org/docs/16/queries-with.html), [PostgreSQL 16 — funções de gatilho](https://www.postgresql.org/docs/16/plpgsql-trigger.html), [brModelo 3.31](https://github.com/chcandido/brModelo/releases/tag/3.31).
