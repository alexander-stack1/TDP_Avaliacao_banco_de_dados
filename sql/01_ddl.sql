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

DROP SCHEMA IF EXISTS bolsa CASCADE;
CREATE SCHEMA bolsa;
COMMENT ON SCHEMA bolsa IS 'Corretora: investidores, ações, negociações, cotações e carteira.';

SET search_path TO bolsa, public;

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
    telefone         text,
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
    CONSTRAINT ck_investidor_telefone   CHECK (telefone IS NULL OR telefone ~ '^[0-9]{10,11}$')
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
    CONSTRAINT ck_empresa_valor_mercado CHECK (valor_mercado >= 0)
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
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_cotacao_valor      CHECK (valor > 0)
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
    CONSTRAINT ck_negociacao_valor       CHECK (valor_unitario > 0)
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
    atualizado_em  timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pk_carteira            PRIMARY KEY (id_investidor, id_acao),
    CONSTRAINT fk_carteira_investidor FOREIGN KEY (id_investidor)
        REFERENCES bolsa.investidor (id_investidor)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_carteira_acao       FOREIGN KEY (id_acao)
        REFERENCES bolsa.acao (id_acao)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_carteira_quantidade CHECK (quantidade >= 0),
    CONSTRAINT ck_carteira_preco      CHECK (preco_medio >= 0)
);

CREATE INDEX ix_carteira_acao ON bolsa.carteira (id_acao);

COMMENT ON TABLE  bolsa.carteira             IS 'Posição atual (quantidade e preço médio) por investidor e ação.';
COMMENT ON COLUMN bolsa.carteira.preco_medio IS 'Preço médio ponderado das compras; zera quando a posição é liquidada.';

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
BEGIN
    -- garante a linha da posição (UPSERT idempotente)
    INSERT INTO bolsa.carteira (id_investidor, id_acao)
    VALUES (NEW.id_investidor, NEW.id_acao)
    ON CONFLICT (id_investidor, id_acao) DO NOTHING;

    -- trava a linha para evitar condição de corrida entre negociações concorrentes
    SELECT quantidade, preco_medio
      INTO v_qtd, v_pm
      FROM bolsa.carteira
     WHERE id_investidor = NEW.id_investidor
       AND id_acao       = NEW.id_acao
       FOR UPDATE;

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
           atualizado_em = now()
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
        'Negociação é imutável (operação % bloqueada). Registre uma operação inversa.',
        TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER trg_negociacao_imutavel
BEFORE UPDATE OR DELETE ON bolsa.negociacao
FOR EACH ROW EXECUTE FUNCTION bolsa.fn_negociacao_imutavel();

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

-- =====================================================================
-- 9. SEGURANÇA — papel de leitura para analistas (princípio do menor privilégio)
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bolsa_leitura') THEN
        CREATE ROLE bolsa_leitura NOLOGIN;
    END IF;
END;
$$;

GRANT USAGE ON SCHEMA bolsa TO bolsa_leitura;
GRANT SELECT ON ALL TABLES IN SCHEMA bolsa TO bolsa_leitura;
ALTER DEFAULT PRIVILEGES IN SCHEMA bolsa GRANT SELECT ON TABLES TO bolsa_leitura;
