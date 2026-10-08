# Case Negociações na Bolsa de Valores

Trabalho de modelagem conceitual, lógica e física para a disciplina **Transformando Dados em Percepção**, revisado conforme as páginas 2 e 3 do PDF da atividade. SGBD: **PostgreSQL 16**.

A entrega reúne investidores, empresas, ações, negociações, histórico de cotações e carteira atualizada pelas negociações. O Word documenta as escolhas; o SQL demonstra DDL, DML e 16 consultas. O prazo informado no PDF é **18/10**, sem ano explícito, e o grupo pode ter até cinco integrantes.

## Arquivos para a entrega

| Exigência do PDF | Arquivos |
|---|---|
| Conceitual no brModelo, arquivo e print | `docs/01-modelo-conceitual/modelo_conceitual.brM3` e `modelo_conceitual_brmodelo.png` |
| Lógico textual ou gráfico, arquivo e print | `docs/02-modelo-logico/modelo_logico.md` e `modelo_logico.png` |
| Físico com DDL, DML e DQL | `sql/00_bolsa_completo.sql` |
| Word sugerido com os resultados | `docs/Entrega_Case_Bolsa_Valores.docx` |
| PDF complementar | `docs/Entrega_Case_Bolsa_Valores.pdf` |

**Antes do envio:** preencher instituição, curso, cidade e integrantes da capa. A disciplina e o professor foram identificados no enunciado. Não foram presumidos os integrantes ou o nome exato do curso.

Para preencher os metadados sem editar o gerador, copie `docs/metadados.example.json` para `docs/metadados.local.json`, complete os campos e gere novamente o Word e o PDF. O arquivo local de metadados é ignorado pelo Git. A geração do Word sozinha não atualiza o PDF; exporte a mesma versão antes de empacotar.

## Estrutura e decisões

| Entidade | Papel |
|---|---|
| EMPRESA | Companhia emissora, com nome, setor e valor de mercado |
| ACAO | Papel identificado por ticker, associado a uma empresa |
| INVESTIDOR | Pessoa física ou jurídica identificada por documento único |
| NEGOCIACAO | Ocorrência de compra ou venda com instante, quantidade e preço |
| COTACAO | Preço de uma ação em um instante, com unicidade do par |
| CARTEIRA | Posição materializada por investidor e ação |

As descrições ficam em [conceitual](docs/01-modelo-conceitual/modelo_conceitual.md), [lógico](docs/02-modelo-logico/modelo_logico.md) e [físico](docs/03-modelo-fisico/modelo_fisico.md). A [revisão](docs/REVISAO.md) registra a cobertura do enunciado, correções e validações.

Premissas adicionais do projeto, distintas das exigências do professor:

- Sem venda descoberta; negociações não aceitam UPDATE, DELETE ou TRUNCATE.
- Para cada par investidor/ação, os instantes das negociações são estritamente crescentes. Operações retroativas ou com o mesmo instante no mesmo par são rejeitadas. Pares diferentes têm ordem independente.
- Carteira só é alterada pelo trigger de negociação; a linha é preservada com quantidade e preço médio zero após liquidação.
- Preço médio móvel arredondado a quatro casas a cada compra, sem taxas, tributos, estornos ou eventos societários. É uma extensão didática.
- CPF/CNPJ têm validação de tamanho e caracteres, sem dígitos verificadores; ticker e telefone também usam formatos simplificados. Os dados são sintéticos e os preços não representam o mercado real.
- Empresa pode existir antes da primeira ação, e ação antes da primeira cotação. Uma posição sem cotação tem valor desconhecido (`NULL`).
- O esquema cadastral é normalizado; `valor_total` e CARTEIRA são materializações derivadas explicitamente documentadas.

## Executar em PostgreSQL

Use um **banco novo** e um usuário que possa criar esquema nele. Não é necessário superusuário nem `CREATEROLE`. O SQL não exclui dados e recusa o esquema `bolsa` se ele já existir.

```bash
createdb bolsa_valores
psql -X -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql
```

A conexão usa os mecanismos nativos do PostgreSQL (`PGHOST`, `PGPORT`, `PGUSER`, prompt de senha ou `.pgpass`). `.env.example` é somente uma referência de variáveis: **os scripts não carregam `.env` automaticamente**. Não é necessário preencher credenciais para a validação isolada.

## Validar sem acessar bancos existentes

Requer os executáveis do PostgreSQL 16 (`initdb`, `pg_ctl`, `createuser`, `createdb`, `psql`) e Python 3 no PATH. Execute com usuário comum do sistema, pois `initdb` não funciona como root.

```bash
scripts/build_sql.sh
scripts/validar.sh
```

O validador cria uma instância temporária com socket Unix exclusivo, sem acesso TCP, executa com um usuário sem superprivilégios, testa reexecução segura e executa regressões de integridade, custo médio, histórico e concorrência. Encerra e remove apenas essa instância ao sair. **Não recebe nome de banco e não usa servidores já instalados.** Evidências ficam em `tmp/validacao/` (ignorado pelo Git).

A revisão de 07/10/2026 passou em PostgreSQL 16.15. A carga tem 6 investidores, 7 empresas, 8 ações, 607 cotações e 19 negociações. O período de demonstração contém cinco dias úteis de 31/08 a 04/09/2026 e oito preços adicionais em 08/09.

## Regerar os artefatos

Os fontes SQL são `sql/01_ddl.sql`, `sql/02_dml.sql` e `sql/03_dql.sql`. Edite-os e depois gere o consolidado.

```bash
scripts/build_sql.sh
scripts/build_sql.sh --check
python3 scripts/gerar_diagramas.py      # requer matplotlib
scripts/gerar_brm3.sh                   # requer Java e brModelo 3.31
python3 scripts/gerar_docx.py           # requer python-docx e Pillow
```

O gerador cria sumário e listas com os títulos atuais. Para preencher seus números de página, exporte uma primeira versão do Word para PDF e execute:

```bash
python3 scripts/gerar_docx.py --indice-pdf docs/Entrega_Case_Bolsa_Valores.pdf
```

Esse passo requer `pypdf`. Exporte novamente o Word para o mesmo PDF e confira a paginação; se uma mudança alterar o número de páginas, repita o passo. Os índices são estáticos e precisam dessa atualização após mudanças de conteúdo. Verifique a diagramação e gere o pacote:

```bash
python3 scripts/gerar_entrega.py
```

O ZIP fica em `output/entrega/Entrega_Case_Bolsa_Valores.zip`. O `.xml` conceitual e a visualização Chen anotada permanecem como fontes auxiliares no repositório; o arquivo oficial editável do conceitual é o `.brM3`.

## Origem

A base foi clonada do projeto [TDP_Avaliacao_banco_de_dados](https://github.com/alexander-stack1/TDP_Avaliacao_banco_de_dados). Esta versão é uma revisão local; os arquivos do repositório de origem podem divergir dela. Não foram realizados commit, push ou envio ao Classroom.
