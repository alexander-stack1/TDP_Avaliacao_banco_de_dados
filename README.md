# Case — Negociações na Bolsa de Valores

Modelagem de banco de dados (conceitual, lógico e físico) para o sistema de uma corretora que gerencia **investidores**, **ações**, **negociações**, **histórico de cotações** e **saldo de carteira**.

SGBD alvo: **PostgreSQL 16**.

## Estrutura do repositório

```
.
├── README.md
├── .gitignore                       # segredos (.env, chaves, credenciais) nunca são versionados
├── .env.example                     # modelo de variáveis de conexão (sem valores reais)
├── docs/
│   ├── 01-modelo-conceitual/
│   │   ├── modelo_conceitual.png             # print (notação Chen / brModelo)
│   │   ├── modelo_conceitual.brmodelo.json   # arquivo para importar no brModelo Web
│   │   └── modelo_conceitual.md              # descrição + roteiro p/ BR Modelo desktop
│   ├── 02-modelo-logico/
│   │   ├── modelo_logico.png                 # print (relacional, pé-de-galinha)
│   │   └── modelo_logico.md                  # notação textual, dicionário de dados, normalização
│   ├── 03-modelo-fisico/
│   │   └── modelo_fisico.md                  # guia do script SQL
│   └── Entrega_Case_Bolsa_Valores.docx       # documento Word com conceitual + lógico (entrega)
├── sql/
│   ├── 00_bolsa_completo.sql        # ARQUIVO ÚNICO DA ENTREGA: DDL + DML + DQL
│   ├── 01_ddl.sql                   # tabelas, constraints, índices, triggers, views
│   ├── 02_dml.sql                   # carga de exemplo + demonstração das regras
│   └── 03_dql.sql                   # 16 consultas analíticas
└── scripts/
    ├── build_sql.sh                 # concatena 01+02+03 → 00
    ├── validar.sh                   # cria banco descartável e executa tudo
    ├── gerar_diagramas.py           # gera os PNGs (matplotlib)
    ├── gerar_brmodelo.py            # gera o JSON do brModelo Web
    └── gerar_docx.py                # gera o Word da entrega
```

## Modelo em uma olhada

| Entidade | Papel |
|---|---|
| EMPRESA | Companhia listada (CNPJ, nome, setor, valor de mercado) |
| AÇÃO | Papel negociado, identificado pelo ticker; pertence a uma empresa |
| INVESTIDOR | Cliente PF (CPF) ou PJ (CNPJ) |
| NEGOCIAÇÃO | Compra ou venda de uma ação por um investidor (data/hora, tipo, quantidade, preço) |
| COTAÇÃO | Preço de uma ação em um instante (série temporal) |
| CARTEIRA | Posição atual por investidor e ação, derivada das negociações |

Detalhes e justificativas: [conceitual](docs/01-modelo-conceitual/modelo_conceitual.md) · [lógico](docs/02-modelo-logico/modelo_logico.md) · [físico](docs/03-modelo-fisico/modelo_fisico.md).

## Executar o modelo físico

```bash
cp .env.example .env          # ajuste usuário/senha; o .env não é versionado
createdb bolsa_valores
psql -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql
```

Validação automática em banco descartável:

```bash
scripts/validar.sh
```

## Padrões adotados

- Identificadores em `snake_case`; prefixos `pk_`, `fk_`, `uq_`, `ck_`, `ix_`, `trg_`, `fn_`, `vw_`.
- PKs `bigint IDENTITY`; chaves naturais (CPF/CNPJ, ticker, CNPJ da empresa) como `UNIQUE`.
- `text` em vez de `varchar(n)`, `numeric` para dinheiro, `timestamptz` para data/hora.
- Regras de negócio no banco: `CHECK`, `UNIQUE`, FKs com ação explícita, triggers para a carteira e para a imutabilidade das negociações.
- Toda FK indexada; índices compostos com colunas de igualdade antes das de intervalo; BRIN na série temporal.
- Papel de leitura separado (`bolsa_leitura`) para analistas.
- Nenhum segredo no repositório: conexão via `.env` (ignorado) a partir de `.env.example`.

## Regerar artefatos

```bash
python3 scripts/gerar_diagramas.py   # PNGs
python3 scripts/gerar_brmodelo.py    # JSON do brModelo Web
python3 scripts/gerar_docx.py        # Word (requer: pip install python-docx)
scripts/build_sql.sh                 # sql/00_bolsa_completo.sql
```
