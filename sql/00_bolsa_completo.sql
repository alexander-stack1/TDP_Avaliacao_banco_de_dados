-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES — MODELO FÍSICO (PostgreSQL 16)
--  Arquivo único: DDL + DML + DQL (gerado por scripts/build_sql.sh a partir
--  de sql/01_ddl.sql, sql/02_dml.sql e sql/03_dql.sql — edite os fontes).
--  Executar em banco novo: psql -X -v ON_ERROR_STOP=1 -d <banco> -f este_arquivo.sql
--  Recusa esquema bolsa existente. Não apaga dados nem cria papéis globais.
-- =====================================================================

-- =====================================================================
--  CASE: NEGOCIAÇÕES NA BOLSA DE VALORES
--  Modelo Físico — DDL (Data Definition Language)
--  SGBD alvo: PostgreSQL 16
--
--  Execução recomendada:
--      psql -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql
--
--  Convenções adotadas (padrões de banco de dados):
--    * snake_case em minúsculas para todos os identificadores.
--    * Chave primária substituta bigint IDENTITY (chaves naturais viram UNIQUE).
--    * text no lugar de varchar(n); numeric para valores monetários (nunca float);
--      timestamptz para data/hora (fuso explícito).
--    * Regras de negócio como CHECK / UNIQUE / FK — nunca só na aplicação.
--    * Toda chave estrangeira tem índice.
--    * Prefixos: pk_, fk_, uq_, ck_, ix_, trg_, fn_, vw_.
-- =====================================================================

-- Instalação em esquema novo. Nunca apaga uma instalação existente.
BEGIN;
CREATE SCHEMA bolsa;
COMMENT ON SCHEMA bolsa IS 'Corretora: investidores, ações, negociações, cotações e carteira.';

SET search_path TO bolsa, public;
SET TIME ZONE 'America/Sao_Paulo';

-- ---------------------------------------------------------------------
-- 1. INVESTIDOR
--    Identificado no negócio por CPF (PF, 11 dígitos) ou CNPJ (PJ, 14 dígitos).
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.investidor (
    id_investidor    bigint      GENERATED ALWAYS AS IDENTITY,
    documento        text        NOT NULL,   -- CPF ou CNPJ, somente dígitos
    tipo_investidor  text        NOT NULL,   -- 'PF' | 'PJ'
    nome_completo    text        NOT NULL,
    email            text        NOT NULL,
    telefone         text        NOT NULL,
    criado_em        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_investidor            PRIMARY KEY (id_investidor),
    CONSTRAINT uq_investidor_documento  UNIQUE (documento),
    CONSTRAINT uq_investidor_email      UNIQUE (email),
    CONSTRAINT ck_investidor_tipo       CHECK (tipo_investidor IN ('PF', 'PJ')),
    CONSTRAINT ck_investidor_documento  CHECK (
           (tipo_investidor = 'PF' AND documento ~ '^[0-9]{11}$')
        OR (tipo_investidor = 'PJ' AND documento ~ '^[0-9]{14}$')
    ),
    CONSTRAINT ck_investidor_email      CHECK (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT ck_investidor_telefone   CHECK (telefone ~ '^[0-9]{10,11}$'),
    CONSTRAINT ck_investidor_nome       CHECK (btrim(nome_completo) <> '')
);

COMMENT ON TABLE  bolsa.investidor                 IS 'Cliente da corretora (pessoa física ou jurídica).';
COMMENT ON COLUMN bolsa.investidor.documento       IS 'CPF (11 dígitos) quando PF; CNPJ (14 dígitos) quando PJ. Chave natural.';
COMMENT ON COLUMN bolsa.investidor.tipo_investidor IS 'PF = pessoa física; PJ = pessoa jurídica.';

-- ---------------------------------------------------------------------
-- 2. EMPRESA (companhia listada na bolsa)
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.empresa (
    id_empresa     bigint        GENERATED ALWAYS AS IDENTITY,
    cnpj           text          NOT NULL,
    nome           text          NOT NULL,
    setor          text          NOT NULL,
    valor_mercado  numeric(18,2) NOT NULL,   -- em R$
    atualizado_em  timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pk_empresa               PRIMARY KEY (id_empresa),
    CONSTRAINT uq_empresa_cnpj          UNIQUE (cnpj),
    CONSTRAINT ck_empresa_cnpj          CHECK (cnpj ~ '^[0-9]{14}$'),
    CONSTRAINT ck_empresa_valor_mercado CHECK (valor_mercado >= 0 AND valor_mercado <> 'NaN'::numeric),
    CONSTRAINT ck_empresa_nome          CHECK (btrim(nome) <> ''),
    CONSTRAINT ck_empresa_setor         CHECK (btrim(setor) <> '')
);

COMMENT ON TABLE  bolsa.empresa               IS 'Companhia aberta emissora de ações.';
COMMENT ON COLUMN bolsa.empresa.valor_mercado IS 'Capitalização de mercado em reais.';

-- ---------------------------------------------------------------------
-- 3. AÇÃO (papel negociado; identificado pelo ticker)
--    Uma empresa pode emitir mais de um papel (ex.: PETR3 ON e PETR4 PN).
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.acao (
    id_acao     bigint  GENERATED ALWAYS AS IDENTITY,
    ticker      text    NOT NULL,           -- código de negociação, ex.: PETR4
    id_empresa  bigint  NOT NULL,
    tipo_acao   text    NOT NULL,           -- 'ON' | 'PN' | 'UNIT'
    ativa       boolean NOT NULL DEFAULT true,

    CONSTRAINT pk_acao          PRIMARY KEY (id_acao),
    CONSTRAINT uq_acao_ticker   UNIQUE (ticker),
    CONSTRAINT fk_acao_empresa  FOREIGN KEY (id_empresa)
        REFERENCES bolsa.empresa (id_empresa)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_acao_ticker   CHECK (ticker ~ '^[A-Z]{4}[0-9]{1,2}$'),
    CONSTRAINT ck_acao_tipo     CHECK (tipo_acao IN ('ON', 'PN', 'UNIT'))
);

CREATE INDEX ix_acao_empresa ON bolsa.acao (id_empresa);

COMMENT ON TABLE  bolsa.acao        IS 'Papel listado na bolsa, pertencente a uma empresa.';
COMMENT ON COLUMN bolsa.acao.ticker IS 'Código de negociação (4 letras + 1 ou 2 dígitos).';

-- ---------------------------------------------------------------------
-- 4. COTAÇÃO (histórico de preços — série temporal)
--    Entidade fraca: identificada pela ação + instante.
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.cotacao (
    id_cotacao  bigint        GENERATED ALWAYS AS IDENTITY,
    id_acao     bigint        NOT NULL,
    data_hora   timestamptz   NOT NULL,
    valor       numeric(12,4) NOT NULL,

    CONSTRAINT pk_cotacao            PRIMARY KEY (id_cotacao),
    CONSTRAINT uq_cotacao_acao_hora  UNIQUE (id_acao, data_hora),  -- também serve de índice p/ (ação, período)
    CONSTRAINT fk_cotacao_acao       FOREIGN KEY (id_acao)
        REFERENCES bolsa.acao (id_acao)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_cotacao_valor      CHECK (valor > 0 AND valor <> 'NaN'::numeric),
    CONSTRAINT ck_cotacao_data       CHECK (isfinite(data_hora))
);

-- BRIN: índice compacto para varreduras por intervalo de tempo em série temporal
-- (dados inseridos em ordem cronológica).
CREATE INDEX ix_cotacao_data_hora_brin ON bolsa.cotacao USING brin (data_hora);

COMMENT ON TABLE bolsa.cotacao IS 'Histórico intradiário de cotações por ação (série temporal).';

-- ---------------------------------------------------------------------
-- 5. NEGOCIAÇÃO (compra ou venda) — resolve o N:N Investidor x Ação
--    Registro imutável (livro de negociações): não se altera nem se apaga.
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.negociacao (
    id_negociacao   bigint        GENERATED ALWAYS AS IDENTITY,
    id_investidor   bigint        NOT NULL,
    id_acao         bigint        NOT NULL,
    data_hora       timestamptz   NOT NULL DEFAULT now(),
    tipo_operacao   text          NOT NULL,   -- 'COMPRA' | 'VENDA'
    quantidade      integer       NOT NULL,
    valor_unitario  numeric(12,4) NOT NULL,   -- preço no momento da negociação
    valor_total     numeric(18,2) GENERATED ALWAYS AS (quantidade * valor_unitario) STORED,

    CONSTRAINT pk_negociacao             PRIMARY KEY (id_negociacao),
    CONSTRAINT fk_negociacao_investidor  FOREIGN KEY (id_investidor)
        REFERENCES bolsa.investidor (id_investidor)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_negociacao_acao        FOREIGN KEY (id_acao)
        REFERENCES bolsa.acao (id_acao)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_negociacao_tipo        CHECK (tipo_operacao IN ('COMPRA', 'VENDA')),
    CONSTRAINT ck_negociacao_quantidade  CHECK (quantidade > 0),
    CONSTRAINT ck_negociacao_valor       CHECK (valor_unitario > 0 AND valor_unitario <> 'NaN'::numeric),
    CONSTRAINT ck_negociacao_data        CHECK (isfinite(data_hora))
);

-- Índices compostos: igualdade primeiro, intervalo depois (extrato por investidor / por ação).
CREATE INDEX ix_negociacao_investidor_data ON bolsa.negociacao (id_investidor, data_hora);
CREATE INDEX ix_negociacao_acao_data       ON bolsa.negociacao (id_acao, data_hora);

COMMENT ON TABLE  bolsa.negociacao             IS 'Operação de compra/venda de uma ação por um investidor.';
COMMENT ON COLUMN bolsa.negociacao.valor_total IS 'Coluna gerada: quantidade x valor_unitario.';

-- ---------------------------------------------------------------------
-- 6. CARTEIRA (saldo/posição atual do investidor em cada ação)
--    Derivada das negociações; mantida automaticamente por trigger.
-- ---------------------------------------------------------------------
CREATE TABLE bolsa.carteira (
    id_investidor  bigint        NOT NULL,
    id_acao        bigint        NOT NULL,
    quantidade     integer       NOT NULL DEFAULT 0,
    preco_medio    numeric(12,4) NOT NULL DEFAULT 0,   -- custo médio de aquisição
    atualizado_em  timestamptz   NOT NULL,

    CONSTRAINT pk_carteira            PRIMARY KEY (id_investidor, id_acao),
    CONSTRAINT fk_carteira_investidor FOREIGN KEY (id_investidor)
        REFERENCES bolsa.investidor (id_investidor)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_carteira_acao       FOREIGN KEY (id_acao)
        REFERENCES bolsa.acao (id_acao)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_carteira_quantidade CHECK (quantidade >= 0),
    CONSTRAINT ck_carteira_preco      CHECK (preco_medio >= 0 AND preco_medio <> 'NaN'::numeric)
);

CREATE INDEX ix_carteira_acao ON bolsa.carteira (id_acao);

COMMENT ON TABLE  bolsa.carteira             IS 'Posição atual (quantidade e preço médio) por investidor e ação.';
COMMENT ON COLUMN bolsa.carteira.preco_medio IS 'Preço médio ponderado das compras; zera quando a posição é liquidada.';
COMMENT ON COLUMN bolsa.carteira.atualizado_em IS 'Data/hora da última negociação aplicada à posição.';

-- =====================================================================
-- 7. FUNÇÕES E TRIGGERS
-- =====================================================================

-- 7.1 Atualiza a carteira a cada negociação inserida.
--     COMPRA: soma quantidade e recalcula o preço médio ponderado.
--     VENDA : exige saldo suficiente e subtrai a quantidade.
CREATE OR REPLACE FUNCTION bolsa.fn_atualizar_carteira()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd  integer;
    v_pm   numeric(12,4);
    v_ultima timestamptz;
BEGIN
    -- garante a linha da posição (UPSERT idempotente)
    INSERT INTO bolsa.carteira (id_investidor, id_acao, atualizado_em)
    VALUES (NEW.id_investidor, NEW.id_acao, '-infinity')
    ON CONFLICT (id_investidor, id_acao) DO NOTHING;

    -- trava a linha para evitar condição de corrida entre negociações concorrentes
    SELECT quantidade, preco_medio, atualizado_em
      INTO v_qtd, v_pm, v_ultima
      FROM bolsa.carteira
     WHERE id_investidor = NEW.id_investidor
       AND id_acao       = NEW.id_acao
       FOR UPDATE;

    -- Premissa do case: cada par investidor/ação chega em ordem temporal
    -- estritamente crescente. Rejeitar atrasados evita saldo histórico negativo
    -- e preço médio calculado em uma ordem diferente da usada nas consultas.
    IF NEW.data_hora <= v_ultima THEN
        RAISE EXCEPTION 'Negociação deve ser posterior à última operação da posição (%)', v_ultima
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.tipo_operacao = 'COMPRA' THEN
        v_pm  := ((v_qtd * v_pm) + (NEW.quantidade * NEW.valor_unitario))
                 / (v_qtd + NEW.quantidade);
        v_qtd := v_qtd + NEW.quantidade;
    ELSE  -- VENDA
        IF NEW.quantidade > v_qtd THEN
            RAISE EXCEPTION
                'Saldo insuficiente: investidor % possui % ação(ões) % e tentou vender %',
                NEW.id_investidor, v_qtd, NEW.id_acao, NEW.quantidade
                USING ERRCODE = 'check_violation';
        END IF;
        v_qtd := v_qtd - NEW.quantidade;
        IF v_qtd = 0 THEN
            v_pm := 0;   -- posição liquidada
        END IF;
    END IF;

    UPDATE bolsa.carteira
       SET quantidade    = v_qtd,
           preco_medio   = v_pm,
           atualizado_em = NEW.data_hora
     WHERE id_investidor = NEW.id_investidor
       AND id_acao       = NEW.id_acao;

    RETURN NULL;   -- trigger AFTER: valor de retorno ignorado
END;
$$;

CREATE TRIGGER trg_negociacao_atualiza_carteira
AFTER INSERT ON bolsa.negociacao
FOR EACH ROW EXECUTE FUNCTION bolsa.fn_atualizar_carteira();

-- 7.2 Negociação é registro contábil: proíbe UPDATE e DELETE.
CREATE OR REPLACE FUNCTION bolsa.fn_negociacao_imutavel()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Negociação é imutável (operação % bloqueada). Correções exigem fluxo de estorno fora deste case.',
        TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER trg_negociacao_imutavel
BEFORE UPDATE OR DELETE ON bolsa.negociacao
FOR EACH ROW EXECUTE FUNCTION bolsa.fn_negociacao_imutavel();

CREATE TRIGGER trg_negociacao_nao_truncar
BEFORE TRUNCATE ON bolsa.negociacao
FOR EACH STATEMENT EXECUTE FUNCTION bolsa.fn_negociacao_imutavel();

-- Carteira é derivada: somente o trigger de negociação altera suas linhas.
-- Administradores capazes de desabilitar triggers continuam sendo privilegiados.
CREATE FUNCTION bolsa.fn_proteger_carteira()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' OR pg_trigger_depth() = 1 THEN
        RAISE EXCEPTION 'Carteira é derivada das negociações; operação direta % bloqueada', TG_OP
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carteira_derivada
BEFORE INSERT OR UPDATE OR DELETE ON bolsa.carteira
FOR EACH ROW EXECUTE FUNCTION bolsa.fn_proteger_carteira();
CREATE TRIGGER trg_carteira_nao_truncar
BEFORE TRUNCATE ON bolsa.carteira
FOR EACH STATEMENT EXECUTE FUNCTION bolsa.fn_proteger_carteira();

-- 7.3 Análise retrospectiva: reconstrói a carteira de um investidor em um
--     instante passado e a valoriza pela última cotação conhecida até ali.
CREATE OR REPLACE FUNCTION bolsa.fn_carteira_em(
    p_id_investidor bigint,
    p_momento       timestamptz
)
RETURNS TABLE (
    ticker          text,
    quantidade      bigint,
    cotacao_na_data numeric(12,4),
    valor_posicao   numeric(18,2)
)
LANGUAGE sql
STABLE
AS $$
    WITH posicao AS (
        SELECT n.id_acao,
               SUM(CASE WHEN n.tipo_operacao = 'COMPRA'
                        THEN n.quantidade ELSE -n.quantidade END) AS quantidade
          FROM bolsa.negociacao n
         WHERE n.id_investidor = p_id_investidor
           AND n.data_hora    <= p_momento
         GROUP BY n.id_acao
        HAVING SUM(CASE WHEN n.tipo_operacao = 'COMPRA'
                        THEN n.quantidade ELSE -n.quantidade END) > 0
    ),
    ultima_cotacao AS (
        SELECT DISTINCT ON (c.id_acao) c.id_acao, c.valor
          FROM bolsa.cotacao c
          JOIN posicao p ON p.id_acao = c.id_acao
         WHERE c.data_hora <= p_momento
         ORDER BY c.id_acao, c.data_hora DESC
    )
    SELECT a.ticker,
           p.quantidade,
           u.valor,
           (p.quantidade * u.valor)::numeric(18,2)
      FROM posicao p
      JOIN bolsa.acao a       ON a.id_acao = p.id_acao
      LEFT JOIN ultima_cotacao u ON u.id_acao = p.id_acao
     ORDER BY a.ticker;
$$;

COMMENT ON FUNCTION bolsa.fn_carteira_em(bigint, timestamptz)
    IS 'Posição de um investidor em um momento passado, valorizada pelo histórico de cotações.';

-- =====================================================================
-- 8. VISÕES (VIEWS)
-- =====================================================================

-- 8.1 Última cotação de cada ação.
CREATE OR REPLACE VIEW bolsa.vw_cotacao_atual AS
SELECT DISTINCT ON (c.id_acao)
       c.id_acao,
       a.ticker,
       c.data_hora AS data_hora_cotacao,
       c.valor     AS cotacao_atual
  FROM bolsa.cotacao c
  JOIN bolsa.acao a ON a.id_acao = c.id_acao
 ORDER BY c.id_acao, c.data_hora DESC;

-- 8.2 Carteira valorizada a mercado, com resultado (lucro/prejuízo) não realizado.
CREATE OR REPLACE VIEW bolsa.vw_posicao_valorizada AS
SELECT i.id_investidor,
       i.nome_completo                                   AS investidor,
       i.tipo_investidor,
       a.ticker,
       e.nome                                            AS empresa,
       e.setor,
       ca.quantidade,
       ca.preco_medio,
       ct.cotacao_atual,
       (ca.quantidade * ca.preco_medio)::numeric(18,2)   AS custo_total,
       (ca.quantidade * ct.cotacao_atual)::numeric(18,2) AS valor_mercado,
       ((ca.quantidade * ct.cotacao_atual)
        - (ca.quantidade * ca.preco_medio))::numeric(18,2) AS resultado_nao_realizado,
       CASE WHEN ca.preco_medio > 0
            THEN ROUND((ct.cotacao_atual - ca.preco_medio) / ca.preco_medio * 100, 2)
       END                                               AS variacao_pct
  FROM bolsa.carteira ca
  JOIN bolsa.investidor i        ON i.id_investidor = ca.id_investidor
  JOIN bolsa.acao a              ON a.id_acao       = ca.id_acao
  JOIN bolsa.empresa e           ON e.id_empresa    = a.id_empresa
  LEFT JOIN bolsa.vw_cotacao_atual ct ON ct.id_acao = ca.id_acao
 WHERE ca.quantidade > 0;

-- 8.3 Extrato de negociações (leitura amigável).
CREATE OR REPLACE VIEW bolsa.vw_extrato_negociacoes AS
SELECT n.id_negociacao,
       n.data_hora,
       i.nome_completo AS investidor,
       i.documento,
       a.ticker,
       e.nome          AS empresa,
       n.tipo_operacao,
       n.quantidade,
       n.valor_unitario,
       n.valor_total
  FROM bolsa.negociacao n
  JOIN bolsa.investidor i ON i.id_investidor = n.id_investidor
  JOIN bolsa.acao a       ON a.id_acao       = n.id_acao
  JOIN bolsa.empresa e    ON e.id_empresa    = a.id_empresa;

-- 8.4 Reconstitui o custo médio móvel após cada operação.
-- A venda retira custo da posição; uma liquidação zera a base para a recompra.
-- Arredondamento a 4 casas em cada compra, igual ao trigger da carteira.
CREATE VIEW bolsa.vw_evolucao_carteira AS
WITH RECURSIVE ordenadas AS (
    SELECT n.*,
           ROW_NUMBER() OVER (PARTITION BY id_investidor, id_acao
                              ORDER BY data_hora, id_negociacao) AS ordem
      FROM bolsa.negociacao n
), evolucao AS (
    SELECT n.*, n.quantidade::bigint AS saldo,
           n.valor_unitario::numeric(12,4) AS preco_medio,
           0::numeric(12,4) AS preco_medio_anterior
      FROM ordenadas n
     WHERE ordem = 1
    UNION ALL
    SELECT n.*,
           e.saldo + CASE WHEN n.tipo_operacao = 'COMPRA' THEN n.quantidade ELSE -n.quantidade END,
           (CASE WHEN n.tipo_operacao = 'COMPRA'
                 THEN (e.saldo * e.preco_medio + n.quantidade * n.valor_unitario)
                      / (e.saldo + n.quantidade)
                 WHEN e.saldo = n.quantidade THEN 0
                 ELSE e.preco_medio END)::numeric(12,4),
           e.preco_medio
      FROM evolucao e
      JOIN ordenadas n ON n.id_investidor = e.id_investidor
                      AND n.id_acao = e.id_acao AND n.ordem = e.ordem + 1
)
SELECT id_negociacao, id_investidor, id_acao, data_hora, tipo_operacao,
       quantidade, valor_unitario, saldo, preco_medio, preco_medio_anterior,
       CASE WHEN tipo_operacao = 'VENDA'
            THEN ROUND(quantidade * (valor_unitario - preco_medio_anterior), 2)
       END AS resultado_realizado
  FROM evolucao;

COMMENT ON VIEW bolsa.vw_evolucao_carteira
    IS 'Reconstituição sequencial de quantidade, custo médio móvel e resultado realizado, sem taxas ou tributos.';

-- Permissões de analistas podem ser concedidas pelo administrador à parte.
-- A entrega não cria papéis globais nem exige privilégio CREATEROLE.
COMMIT;


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
