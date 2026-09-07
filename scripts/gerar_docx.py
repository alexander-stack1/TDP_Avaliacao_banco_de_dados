#!/usr/bin/env python3
"""Gera docs/Entrega_Case_Bolsa_Valores.docx — relatório de resultados no padrão ABNT.

Normas aplicadas:
  NBR 14724 (estrutura e apresentação), NBR 6024 (numeração progressiva),
  NBR 6027 (sumário), NBR 6028 (resumo), NBR 10520 (citações), NBR 6023
  (referências) e Normas de Apresentação Tabular do IBGE (quadros/tabelas).

Formatação: A4; margens 3 cm (sup./esq.) e 2 cm (inf./dir.); Times New Roman 12;
entrelinhas 1,5; recuo de 1,25 cm na primeira linha; texto justificado;
títulos numerados à esquerda; paginação no canto superior direito a partir da
Introdução (pré-textuais contadas, não numeradas); legendas de figuras/quadros
acima do objeto e fonte abaixo, em 10 pt.

Os campos SUMÁRIO / LISTA DE FIGURAS / LISTA DE QUADROS são campos do Word:
o documento pede a atualização automática ao ser aberto (updateFields).

Uso: python3 scripts/gerar_docx.py      (requer: pip install python-docx)
"""
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT, WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "docs/Entrega_Case_Bolsa_Valores.docx"
PNG_CONC = RAIZ / "docs/01-modelo-conceitual/modelo_conceitual.png"
PNG_LOG = RAIZ / "docs/02-modelo-logico/modelo_logico.png"

# ------------------------------------------------------------------ metadados
# Preencha antes de entregar. Os colchetes sinalizam o que falta.
INSTITUICAO = "[NOME DA INSTITUIÇÃO DE ENSINO]"
CURSO = "[NOME DO CURSO]"
DISCIPLINA = "Banco de Dados"
PROFESSOR = "[Nome do(a) Professor(a)]"
AUTORES = ["[NOME DO(A) ALUNO(A) 1]", "[NOME DO(A) ALUNO(A) 2]", "[NOME DO(A) ALUNO(A) 3]"]
TITULO = "NEGOCIAÇÕES NA BOLSA DE VALORES"
SUBTITULO = "modelagem conceitual, lógica e física de banco de dados para uma corretora"
CIDADE = "[Cidade]"
ANO = "2026"
DATA_ACESSO = "7 set. 2026"

FONTE = "Times New Roman"
LARGURA_UTIL_CM = 16.0          # 21 - 3 - 2
LARGURA_UTIL_PAISAGEM_CM = 24.7  # 29,7 - 3 - 2

doc = Document()

# ------------------------------------------------------------------ estilos base
def _fonte(run, tamanho=12, negrito=None, italico=None, cor=None, nome=FONTE):
    run.font.name = nome
    run._element.rPr.rFonts.set(qn("w:eastAsia"), nome)
    run.font.size = Pt(tamanho)
    if negrito is not None:
        run.font.bold = negrito
    if italico is not None:
        run.font.italic = italico
    run.font.color.rgb = cor or RGBColor(0, 0, 0)


def _paragrafo_base(p, alinhamento=WD_ALIGN_PARAGRAPH.JUSTIFY, recuo=True, antes=0, depois=0, linha=1.5):
    pf = p.paragraph_format
    pf.alignment = alinhamento
    pf.first_line_indent = Cm(1.25) if recuo else Cm(0)
    pf.space_before = Pt(antes)
    pf.space_after = Pt(depois)
    if linha == 1.5:
        pf.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    else:
        pf.line_spacing_rule = WD_LINE_SPACING.SINGLE
    return p


normal = doc.styles["Normal"]
normal.font.name = FONTE
normal.element.rPr.rFonts.set(qn("w:eastAsia"), FONTE)
normal.font.size = Pt(12)
normal.paragraph_format.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
normal.paragraph_format.space_after = Pt(0)
normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

# Títulos (NBR 6024): primária = CAIXA ALTA negrito; secundária = negrito; terciária = itálico
for nivel, cfg in {1: dict(tam=12, negrito=True, italico=False, antes=0, depois=18),
                   2: dict(tam=12, negrito=True, italico=False, antes=18, depois=12),
                   3: dict(tam=12, negrito=False, italico=True, antes=12, depois=12)}.items():
    st = doc.styles[f"Heading {nivel}"]
    st.font.name = FONTE
    st.element.rPr.rFonts.set(qn("w:eastAsia"), FONTE)
    st.font.size = Pt(cfg["tam"])
    st.font.bold = cfg["negrito"]
    st.font.italic = cfg["italico"]
    st.font.color.rgb = RGBColor(0, 0, 0)
    st.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
    st.paragraph_format.first_line_indent = Cm(0)
    st.paragraph_format.space_before = Pt(cfg["antes"])
    st.paragraph_format.space_after = Pt(cfg["depois"])
    st.paragraph_format.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    st.paragraph_format.keep_with_next = True

# ------------------------------------------------------------------ utilidades XML
def _campo(paragrafo, instrucao, texto_inicial="", tamanho=12, negrito=None):
    """Insere um campo do Word (PAGE, SEQ, TOC...) com resultado provisório."""
    r1 = paragrafo.add_run(); _fonte(r1, tamanho, negrito)
    b = OxmlElement("w:fldChar"); b.set(qn("w:fldCharType"), "begin"); b.set(qn("w:dirty"), "true")
    r1._r.append(b)
    r2 = paragrafo.add_run(); _fonte(r2, tamanho, negrito)
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = f" {instrucao} "
    r2._r.append(it)
    r3 = paragrafo.add_run(); _fonte(r3, tamanho, negrito)
    s = OxmlElement("w:fldChar"); s.set(qn("w:fldCharType"), "separate"); r3._r.append(s)
    r4 = paragrafo.add_run(texto_inicial); _fonte(r4, tamanho, negrito)
    r5 = paragrafo.add_run(); _fonte(r5, tamanho, negrito)
    e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), "end"); r5._r.append(e)


def _atualizar_campos_ao_abrir():
    settings = doc.settings.element
    uf = OxmlElement("w:updateFields"); uf.set(qn("w:val"), "true")
    settings.append(uf)


def _margens(section, sup=3, esq=3, inf=2, dir_=2):
    section.top_margin, section.left_margin = Cm(sup), Cm(esq)
    section.bottom_margin, section.right_margin = Cm(inf), Cm(dir_)
    section.header_distance = Cm(2)
    section.footer_distance = Cm(1.5)


def _a4(section, paisagem=False):
    if paisagem:
        section.orientation = WD_ORIENT.LANDSCAPE
        section.page_width, section.page_height = Cm(29.7), Cm(21.0)
    else:
        section.orientation = WD_ORIENT.PORTRAIT
        section.page_width, section.page_height = Cm(21.0), Cm(29.7)
    _margens(section)


def _numeracao_cabecalho(section, mostrar):
    """Número da página no canto superior direito (NBR 14724, 5.4)."""
    section.header.is_linked_to_previous = False
    hdr = section.header
    p = hdr.paragraphs[0]
    for r in list(p.runs):
        r._r.getparent().remove(r._r)
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p.paragraph_format.first_line_indent = Cm(0)
    if mostrar:
        _campo(p, "PAGE", "1", tamanho=10)


def _iniciar_numeracao(section, inicio):
    sectPr = section._sectPr
    pg = sectPr.find(qn("w:pgNumType"))
    if pg is None:
        pg = OxmlElement("w:pgNumType"); sectPr.append(pg)
    pg.set(qn("w:start"), str(inicio))


# ------------------------------------------------------------------ blocos de texto
def texto(conteudo, recuo=True, alinhamento=WD_ALIGN_PARAGRAPH.JUSTIFY, tamanho=12, negrito=None,
          italico=None, antes=0, depois=0, linha=1.5):
    p = doc.add_paragraph()
    _paragrafo_base(p, alinhamento, recuo, antes, depois, linha)
    r = p.add_run(conteudo); _fonte(r, tamanho, negrito, italico)
    return p


_NUM = [0, 0, 0]


def titulo_numerado(nivel, conteudo, quebra=True):
    """Título com numeração progressiva (NBR 6024). Seção primária inicia em nova página."""
    _NUM[nivel - 1] += 1
    for k in range(nivel, 3):
        _NUM[k] = 0
    numero = ".".join(str(n) for n in _NUM[:nivel])
    p = doc.add_heading(level=nivel)
    if nivel == 1 and quebra:
        p.paragraph_format.page_break_before = True
    r = p.add_run(f"{numero} " + (conteudo.upper() if nivel == 1 else conteudo))
    _fonte(r, 12, nivel in (1, 2), nivel == 3)
    return p


def titulo_sem_numero(conteudo, quebra_antes=True):
    """Título de seção não numerada (RESUMO, SUMÁRIO, REFERÊNCIAS...): centralizado, negrito, caixa alta."""
    p = doc.add_paragraph()
    _paragrafo_base(p, WD_ALIGN_PARAGRAPH.CENTER, recuo=False, depois=18)
    if quebra_antes:
        p.paragraph_format.page_break_before = True
    r = p.add_run(conteudo.upper()); _fonte(r, 12, True)
    return p


def lista(itens, estilo="List Bullet"):
    for it in itens:
        p = doc.add_paragraph(style=estilo)
        _paragrafo_base(p, WD_ALIGN_PARAGRAPH.JUSTIFY, recuo=False)
        p.paragraph_format.left_indent = Cm(1.25)
        r = p.add_run(it); _fonte(r, 12)


_SEQ = {"Figura": 0, "Quadro": 0}


def legenda(tipo, titulo_):
    """Legenda ACIMA do objeto: 'Figura 1 – Título' (NBR 14724, 5.8/5.9)."""
    _SEQ[tipo] += 1
    p = doc.add_paragraph()
    _paragrafo_base(p, WD_ALIGN_PARAGRAPH.CENTER, recuo=False, antes=12, depois=6, linha=1)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(f"{tipo} "); _fonte(r, 10, True)
    _campo(p, f"SEQ {tipo} \\* ARABIC", str(_SEQ[tipo]), tamanho=10, negrito=True)
    r = p.add_run(f" – {titulo_}"); _fonte(r, 10, True)


def fonte_rodape(txt="Fonte: elaborado pelos autores (2026)."):
    p = doc.add_paragraph()
    _paragrafo_base(p, WD_ALIGN_PARAGRAPH.CENTER, recuo=False, antes=6, depois=18, linha=1)
    r = p.add_run(txt); _fonte(r, 10)


def codigo(linhas):
    for ln in linhas:
        p = doc.add_paragraph()
        _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, linha=1)
        p.paragraph_format.left_indent = Cm(1.0)
        r = p.add_run(ln); _fonte(r, 8, nome="Courier New")
    doc.add_paragraph()


def quadro(numero_titulo, cabecalho, linhas, larguras_cm, fonte_txt=None):
    """Quadro no padrão IBGE: sem bordas laterais; linha no topo, sob o cabeçalho e no rodapé."""
    legenda("Quadro", numero_titulo)
    t = doc.add_table(rows=1, cols=len(cabecalho))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    tblPr = t._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for lado, val in (("top", "single"), ("bottom", "single"), ("insideH", "single"),
                      ("left", "nil"), ("right", "nil"), ("insideV", "nil")):
        b = OxmlElement(f"w:{lado}"); b.set(qn("w:val"), val)
        b.set(qn("w:sz"), "6"); b.set(qn("w:space"), "0"); b.set(qn("w:color"), "000000")
        borders.append(b)
    tblPr.append(borders)

    def preencher(cells, valores, negrito):
        for i, v in enumerate(valores):
            c = cells[i]
            c.width = Cm(larguras_cm[i])
            p = c.paragraphs[0]
            _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, antes=2, depois=2, linha=1)
            r = p.add_run(str(v)); _fonte(r, 10, negrito)

    preencher(t.rows[0].cells, cabecalho, True)
    # repetir cabeçalho em quebra de página
    trPr = t.rows[0]._tr.get_or_add_trPr()
    th = OxmlElement("w:tblHeader"); th.set(qn("w:val"), "true"); trPr.append(th)
    for linha in linhas:
        preencher(t.add_row().cells, linha, False)
    for row in t.rows:
        for i, w in enumerate(larguras_cm):
            row.cells[i].width = Cm(w)
    fonte_rodape(fonte_txt or "Fonte: elaborado pelos autores (2026).")


def figura(caminho, titulo_, largura_cm, altura_max_cm=13.5):
    from PIL import Image
    with Image.open(caminho) as im:
        prop = im.height / im.width
    largura = min(largura_cm, altura_max_cm / prop)
    legenda("Figura", titulo_)
    p = doc.add_paragraph()
    _paragrafo_base(p, WD_ALIGN_PARAGRAPH.CENTER, recuo=False, linha=1)
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(caminho), width=Cm(largura))
    fonte_rodape()


def nova_secao(paisagem=False, mostrar_numero=True):
    s = doc.add_section(WD_SECTION.NEW_PAGE)
    pg = s._sectPr.find(qn("w:pgNumType"))
    if pg is not None:                      # herdado da seção anterior: numeração deve CONTINUAR
        s._sectPr.remove(pg)
    _a4(s, paisagem)
    _numeracao_cabecalho(s, mostrar_numero)
    return s


# =====================================================================================
# ELEMENTOS PRÉ-TEXTUAIS
# =====================================================================================
# ---- Seção 1: CAPA (não numerada, não contada)
sec = doc.sections[0]
_a4(sec)
_numeracao_cabecalho(sec, False)

for i, linha in enumerate([INSTITUICAO, CURSO]):
    texto(linha, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER, negrito=True)
for _ in range(4):
    doc.add_paragraph()
for a in AUTORES:
    texto(a, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
for _ in range(6):
    doc.add_paragraph()
texto(TITULO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER, negrito=True)
texto(SUBTITULO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
for _ in range(11):
    doc.add_paragraph()
texto(CIDADE.upper(), recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
texto(ANO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)

# ---- Seção 2: pré-textuais contadas (folha de rosto = 1), sem número visível
sec = nova_secao(mostrar_numero=False)
_iniciar_numeracao(sec, 1)

# Folha de rosto
for a in AUTORES:
    texto(a, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
for _ in range(7):
    doc.add_paragraph()
texto(TITULO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER, negrito=True)
texto(SUBTITULO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
for _ in range(3):
    doc.add_paragraph()
p = texto(
    f"Relatório de resultados apresentado à disciplina de {DISCIPLINA} do {CURSO}, "
    f"{INSTITUICAO}, como requisito parcial de avaliação: modelagem conceitual, lógica e física "
    "do caso “Negociações na Bolsa de Valores”.",
    recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.JUSTIFY, tamanho=12, linha=1)
p.paragraph_format.left_indent = Cm(8)
doc.add_paragraph()
p = texto(f"Professor(a): {PROFESSOR}", recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.LEFT, linha=1)
p.paragraph_format.left_indent = Cm(8)
for _ in range(9):
    doc.add_paragraph()
texto(CIDADE.upper(), recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)
texto(ANO, recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.CENTER)

# Resumo (NBR 6028)
titulo_sem_numero("Resumo")
texto(
    "Este relatório apresenta a modelagem de banco de dados para o sistema de uma corretora que gerencia "
    "investidores, ações, negociações, histórico de cotações e saldo de carteira. O trabalho foi conduzido "
    "nas três etapas clássicas do projeto de bancos de dados: modelo conceitual, em notação "
    "Entidade-Relacionamento (Chen) elaborada com a ferramenta brModelo; modelo lógico relacional, obtido "
    "pelas regras de mapeamento ER-relacional e verificado até a terceira forma normal; e modelo físico, "
    "implementado em PostgreSQL 16 por meio de um script com instruções de definição (DDL), manipulação (DML) "
    "e consulta (DQL) de dados. Foram identificadas cinco entidades e cinco relacionamentos, dos quais um "
    "relacionamento muitos-para-muitos com atributos (carteira) e uma entidade fraca (cotação). O modelo "
    "físico implementa as regras de negócio no próprio SGBD, com restrições de integridade, gatilhos que "
    "mantêm a carteira a partir das negociações e impedem vendas sem saldo, e uma função para análise "
    "retrospectiva com base no histórico de cotações. O script foi executado integralmente sem erros e as "
    "dezesseis consultas analíticas produziram os resultados esperados.",
    recuo=False, linha=1)
doc.add_paragraph()
p = texto("Palavras-chave: ", recuo=False, alinhamento=WD_ALIGN_PARAGRAPH.LEFT, negrito=True, linha=1)
r = p.add_run("modelagem de dados; modelo entidade-relacionamento; modelo relacional; PostgreSQL; bolsa de valores.")
_fonte(r, 12)

# Listas de figuras e quadros (campos TOC por rótulo)
titulo_sem_numero("Lista de figuras")
p = doc.add_paragraph(); _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, linha=1)
_campo(p, 'TOC \\h \\z \\c "Figura"', "(atualize os campos: F9)")

titulo_sem_numero("Lista de quadros")
p = doc.add_paragraph(); _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, linha=1)
_campo(p, 'TOC \\h \\z \\c "Quadro"', "(atualize os campos: F9)")

# Sumário (NBR 6027)
titulo_sem_numero("Sumário")
p = doc.add_paragraph(); _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, linha=1)
_campo(p, 'TOC \\o "1-3" \\h \\z \\u', "(atualize os campos: F9)")

# =====================================================================================
# ELEMENTOS TEXTUAIS (numeração visível a partir daqui)
# =====================================================================================
nova_secao(mostrar_numero=True)

titulo_numerado(1, "Introdução", quebra=False)
texto(
    "O projeto de um banco de dados relacional é tradicionalmente dividido em três níveis de abstração: o "
    "conceitual, que descreve o domínio de forma independente de tecnologia; o lógico, que traduz esse "
    "domínio para o modelo de dados do SGBD escolhido; e o físico, que define como os dados serão "
    "efetivamente armazenados, restringidos e consultados (HEUSER, 2009; ELMASRI; NAVATHE, 2018). Este "
    "relatório documenta a aplicação dessas três etapas ao caso de uma corretora de valores.")
texto(
    "O objetivo geral é produzir um esquema de banco de dados completo, correto e executável para o "
    "gerenciamento de investidores, ações, negociações, histórico de cotações e saldo de carteira. Como "
    "objetivos específicos, buscou-se: (a) representar o domínio em um diagrama Entidade-Relacionamento; "
    "(b) derivar o esquema relacional normalizado; (c) implementar o esquema em PostgreSQL com as regras "
    "de negócio expressas no próprio banco; e (d) demonstrar, por meio de consultas, que o modelo atende "
    "às análises requeridas, inclusive as de séries temporais e as retrospectivas.")
texto(
    "O documento está organizado da seguinte forma: a seção 2 descreve o problema e os requisitos "
    "extraídos do enunciado; a seção 3 apresenta o modelo conceitual; a seção 4, o modelo lógico; a "
    "seção 5, o modelo físico; a seção 6 relata a validação e os resultados obtidos; e a seção 7 traz as "
    "considerações finais. O script SQL completo acompanha este relatório como arquivo anexo.")

titulo_numerado(1, "Descrição do problema")
titulo_numerado(2, "Enunciado")
texto(
    "Uma corretora deseja criar um sistema para gerenciar investidores, ações e suas negociações na bolsa "
    "de valores. Cada investidor é identificado por CPF ou CNPJ e possui nome completo, tipo (pessoa "
    "física ou jurídica), e-mail e telefone. Cada ação pertence a uma empresa listada na bolsa, "
    "identificada por seu ticker, com nome da empresa, setor de atuação e valor de mercado. Os "
    "investidores realizam negociações de compra ou venda, registrando-se data e hora, tipo de operação, "
    "quantidade e valor unitário no momento da transação. A corretora mantém ainda o histórico de "
    "cotações de cada ação (data, hora e valor) para análises de séries temporais, e acompanha o saldo "
    "de carteira de cada investidor, atualizado a partir das negociações e passível de análise "
    "retrospectiva com base no histórico de cotações.")

titulo_numerado(2, "Requisitos identificados")
texto("Da leitura do enunciado foram extraídos os requisitos funcionais (RF) e as regras de negócio (RN) "
      "relacionados no Quadro 1.")
quadro("Requisitos funcionais e regras de negócio",
       ["Código", "Descrição"],
       [("RF01", "Cadastrar investidores pessoa física (CPF) e jurídica (CNPJ), sem duplicidade de documento."),
        ("RF02", "Cadastrar empresas listadas e seus papéis; uma empresa pode ter mais de um ticker."),
        ("RF03", "Registrar negociações de compra e venda com data/hora, quantidade e preço do momento."),
        ("RF04", "Armazenar o histórico intradiário de cotações de cada ação."),
        ("RF05", "Manter a posição (carteira) de cada investidor atualizada a partir das negociações."),
        ("RF06", "Permitir análise retrospectiva: valor da carteira em qualquer instante passado."),
        ("RN01", "Um investidor não pode vender mais ações do que possui."),
        ("RN02", "A negociação é registro contábil: não pode ser alterada nem excluída."),
        ("RN03", "Existe no máximo uma cotação por ação em cada instante.")],
       [2.0, 14.0])

titulo_numerado(2, "Metodologia e ferramentas")
texto(
    "Adotou-se a metodologia de projeto em três níveis (conceitual, lógico e físico). O modelo conceitual "
    "foi construído em notação de Chen com a ferramenta brModelo (CÂNDIDO, 2021); o modelo lógico foi "
    "derivado pelas regras de mapeamento ER-relacional e verificado quanto às formas normais; o modelo "
    "físico foi implementado e testado no PostgreSQL 16 (POSTGRESQL GLOBAL DEVELOPMENT GROUP, 2024). "
    "Os diagramas foram gerados por scripts versionados, de modo que qualquer alteração no modelo pode "
    "ser reproduzida.")

# ---------------------------------------------------------------- 3. CONCEITUAL
titulo_numerado(1, "Modelo conceitual")
texto(
    "O modelo conceitual (Figura 1) representa o domínio por meio de entidades, relacionamentos e "
    "atributos, sem compromisso com a tecnologia de armazenamento. Foram identificadas cinco entidades e "
    "cinco relacionamentos, descritos nos Quadros 2 e 3.")

# figura em página paisagem
nova_secao(paisagem=True)
figura(PNG_CONC, "Modelo conceitual em notação Entidade-Relacionamento (Chen)", LARGURA_UTIL_PAISAGEM_CM)
nova_secao(paisagem=False)

titulo_numerado(2, "Entidades e atributos")
quadro("Entidades e atributos do modelo conceitual",
       ["Entidade", "Descrição", "Atributos (identificador em caixa alta)"],
       [("EMPRESA", "Companhia listada na bolsa", "ID_EMPRESA, cnpj, nome, setor, valor_mercado"),
        ("AÇÃO", "Papel negociado, identificado pelo ticker", "ID_ACAO, ticker, tipo_acao, ativa"),
        ("INVESTIDOR", "Cliente da corretora, PF ou PJ",
         "ID_INVESTIDOR, documento (CPF/CNPJ), tipo_investidor, nome_completo, email, telefone"),
        ("NEGOCIAÇÃO", "Compra ou venda de uma ação por um investidor",
         "ID_NEGOCIACAO, data_hora, tipo_operacao, quantidade, valor_unitario"),
        ("COTAÇÃO (fraca)", "Preço de uma ação em um instante", "data_hora (chave parcial), valor")],
       [3.2, 5.0, 7.8])

titulo_numerado(2, "Relacionamentos e cardinalidades")
quadro("Relacionamentos e cardinalidades (mínimo, máximo)",
       ["Relacionamento", "Entidades", "Cardinalidade", "Atributos"],
       [("emite", "EMPRESA – AÇÃO", "EMPRESA (1,n); AÇÃO (1,1)", "–"),
        ("possui (identificador)", "AÇÃO – COTAÇÃO", "AÇÃO (1,n); COTAÇÃO (1,1)", "–"),
        ("realiza", "INVESTIDOR – NEGOCIAÇÃO", "INVESTIDOR (0,n); NEGOCIAÇÃO (1,1)", "–"),
        ("refere-se a", "AÇÃO – NEGOCIAÇÃO", "AÇÃO (0,n); NEGOCIAÇÃO (1,1)", "–"),
        ("mantém (carteira)", "INVESTIDOR – AÇÃO", "INVESTIDOR (0,n); AÇÃO (0,n)", "quantidade, preco_medio")],
       [3.6, 4.2, 5.2, 3.0])

titulo_numerado(2, "Decisões de modelagem")
texto(
    "Negociação foi modelada como entidade, e não como relacionamento muitos-para-muitos entre Investidor "
    "e Ação. O enunciado afirma que um mesmo investidor pode negociar várias ações ao longo do tempo: o "
    "mesmo par (investidor, ação) ocorre muitas vezes, cada uma com data e hora, tipo, quantidade e preço "
    "próprios. Um relacionamento admitiria apenas uma ocorrência por par, o que não representaria o domínio.")
texto(
    "A carteira, por sua vez, é exatamente um relacionamento muitos-para-muitos com atributos, pois a "
    "posição atual é única por par (investidor, ação). Trata-se de informação derivada das negociações, e "
    "essa derivação é implementada no modelo físico por um gatilho, garantindo consistência.")
texto(
    "Cotação é uma entidade fraca de Ação: não existe cotação sem ação e sua identificação depende do par "
    "(ação, data_hora), razão pela qual o relacionamento possui é identificador. Empresa foi separada de "
    "Ação porque nome, setor e valor de mercado pertencem à companhia, que pode emitir mais de um papel, "
    "como PETR3 e PETR4. Por fim, o investidor guarda CPF ou CNPJ em um único atributo documento, "
    "qualificado pelo tipo de investidor; no modelo físico essa regra torna-se uma restrição de unicidade "
    "e uma restrição de verificação de onze ou catorze dígitos.")

# ---------------------------------------------------------------- 4. LÓGICO
titulo_numerado(1, "Modelo lógico")
texto(
    "O modelo lógico relacional (Figura 2) foi obtido a partir do conceitual pelas regras de mapeamento "
    "ER-relacional: cada entidade tornou-se uma tabela; relacionamentos um-para-muitos tornaram-se chaves "
    "estrangeiras no lado muitos; o relacionamento muitos-para-muitos com atributos tornou-se uma tabela "
    "associativa com chave primária composta; e a entidade fraca herdou a chave da entidade proprietária.")

nova_secao(paisagem=True)
figura(PNG_LOG, "Modelo lógico relacional (esquema bolsa)", LARGURA_UTIL_PAISAGEM_CM)
nova_secao(paisagem=False)

titulo_numerado(2, "Esquema relacional em notação textual")
codigo([
    "EMPRESA (id_empresa, cnpj, nome, setor, valor_mercado, atualizado_em)",
    "           PK: id_empresa   UQ: cnpj",
    "ACAO (id_acao, ticker, id_empresa, tipo_acao, ativa)",
    "           PK: id_acao   UQ: ticker   FK: id_empresa -> EMPRESA",
    "INVESTIDOR (id_investidor, documento, tipo_investidor, nome_completo,",
    "            email, telefone, criado_em)",
    "           PK: id_investidor   UQ: documento   UQ: email",
    "COTACAO (id_cotacao, id_acao, data_hora, valor)",
    "           PK: id_cotacao   UQ: (id_acao, data_hora)   FK: id_acao -> ACAO",
    "NEGOCIACAO (id_negociacao, id_investidor, id_acao, data_hora, tipo_operacao,",
    "            quantidade, valor_unitario, valor_total)",
    "           PK: id_negociacao   FK: id_investidor -> INVESTIDOR",
    "           FK: id_acao -> ACAO",
    "CARTEIRA (id_investidor, id_acao, quantidade, preco_medio, atualizado_em)",
    "           PK: (id_investidor, id_acao)   FK: id_investidor -> INVESTIDOR",
    "           FK: id_acao -> ACAO",
])

titulo_numerado(2, "Mapeamento do modelo conceitual para o lógico")
quadro("Regras de mapeamento aplicadas",
       ["Elemento conceitual", "Resultado lógico", "Regra"],
       [("Entidades EMPRESA, AÇÃO, INVESTIDOR, NEGOCIAÇÃO", "Uma tabela cada, com chave substituta id_*", "Entidade → tabela"),
        ("emite (1:N)", "Chave estrangeira acao.id_empresa", "1:N → FK no lado N"),
        ("COTAÇÃO (fraca) + possui", "Tabela cotacao com FK id_acao e UNIQUE (id_acao, data_hora)", "Entidade fraca herda a chave do dono"),
        ("realiza e refere-se a (1:N)", "FKs negociacao.id_investidor e negociacao.id_acao", "1:N → FK no lado N"),
        ("mantém (N:N com atributos)", "Tabela carteira, PK composta (id_investidor, id_acao) e atributos", "N:N → tabela associativa"),
        ("Atributo derivado valor_total", "Coluna gerada quantidade × valor_unitario", "Derivado → calculado no SGBD")],
       [5.2, 6.4, 4.4])

titulo_numerado(2, "Dicionário de dados")
texto("Os Quadros 5 a 10 detalham as colunas, os tipos e as restrições de cada tabela do esquema.")
dicionario = [
    ("Tabela EMPRESA", [
        ("id_empresa", "bigint identity", "Chave primária"), ("cnpj", "text", "Não nulo; único; 14 dígitos"),
        ("nome", "text", "Não nulo"), ("setor", "text", "Não nulo"),
        ("valor_mercado", "numeric(18,2)", "Não nulo; ≥ 0"), ("atualizado_em", "timestamptz", "Não nulo; padrão now()")]),
    ("Tabela ACAO", [
        ("id_acao", "bigint identity", "Chave primária"), ("ticker", "text", "Não nulo; único; 4 letras e 1–2 dígitos"),
        ("id_empresa", "bigint", "Não nulo; FK → empresa (RESTRICT)"), ("tipo_acao", "text", "ON, PN ou UNIT"),
        ("ativa", "boolean", "Não nulo; padrão verdadeiro")]),
    ("Tabela INVESTIDOR", [
        ("id_investidor", "bigint identity", "Chave primária"),
        ("documento", "text", "Não nulo; único; 11 dígitos (PF) ou 14 (PJ)"),
        ("tipo_investidor", "text", "PF ou PJ"), ("nome_completo", "text", "Não nulo"),
        ("email", "text", "Não nulo; único; formato válido"), ("telefone", "text", "Opcional; 10–11 dígitos"),
        ("criado_em", "timestamptz", "Não nulo; padrão now()")]),
    ("Tabela COTACAO", [
        ("id_cotacao", "bigint identity", "Chave primária"), ("id_acao", "bigint", "Não nulo; FK → acao (CASCADE)"),
        ("data_hora", "timestamptz", "Não nulo; único com id_acao"), ("valor", "numeric(12,4)", "Não nulo; > 0")]),
    ("Tabela NEGOCIACAO", [
        ("id_negociacao", "bigint identity", "Chave primária"),
        ("id_investidor", "bigint", "Não nulo; FK → investidor (RESTRICT)"),
        ("id_acao", "bigint", "Não nulo; FK → acao (RESTRICT)"), ("data_hora", "timestamptz", "Não nulo; padrão now()"),
        ("tipo_operacao", "text", "COMPRA ou VENDA"), ("quantidade", "integer", "Não nulo; > 0"),
        ("valor_unitario", "numeric(12,4)", "Não nulo; > 0"),
        ("valor_total", "numeric(18,2)", "Coluna gerada: quantidade × valor_unitario")]),
    ("Tabela CARTEIRA", [
        ("id_investidor", "bigint", "PK; FK → investidor (CASCADE)"), ("id_acao", "bigint", "PK; FK → acao (RESTRICT)"),
        ("quantidade", "integer", "Não nulo; ≥ 0"), ("preco_medio", "numeric(12,4)", "Não nulo; ≥ 0"),
        ("atualizado_em", "timestamptz", "Não nulo")]),
]
for nome, cols in dicionario:
    quadro(nome, ["Coluna", "Tipo", "Restrições"], cols, [4.2, 4.0, 7.8])

titulo_numerado(2, "Normalização")
texto(
    "O esquema encontra-se na terceira forma normal. Na primeira forma normal, todos os atributos são "
    "atômicos: há um único telefone e um único documento por investidor, sem listas em coluna. Na segunda "
    "forma normal, a única chave primária composta é a de CARTEIRA, e seus atributos quantidade, "
    "preco_medio e atualizado_em dependem do par completo (investidor e ação). Na terceira forma normal, "
    "nenhum atributo depende de outro atributo não chave: os dados da companhia ficam em EMPRESA e não se "
    "repetem por papel. O atributo valor_total é derivado, mas materializado como coluna gerada pelo "
    "SGBD, o que elimina o risco de inconsistência.")

# ---------------------------------------------------------------- 5. FÍSICO
titulo_numerado(1, "Modelo físico")
texto(
    "O modelo físico foi implementado em PostgreSQL 16 no arquivo 00_bolsa_completo.sql, anexo a este "
    "relatório, que reúne as instruções de definição (DDL), manipulação (DML) e consulta (DQL) de dados. "
    "Os padrões adotados estão resumidos no Quadro 11.")
quadro("Padrões adotados no modelo físico",
       ["Aspecto", "Decisão"],
       [("Nomenclatura", "Identificadores em snake_case; prefixos pk_, fk_, uq_, ck_, ix_, trg_, fn_, vw_."),
        ("Chaves", "Chave primária bigint IDENTITY; chaves naturais (CPF/CNPJ, ticker) como UNIQUE."),
        ("Tipos", "text em vez de varchar(n); numeric para valores monetários; timestamptz para data e hora."),
        ("Integridade", "Regras de negócio no banco: CHECK, UNIQUE, FKs com ação explícita e gatilhos."),
        ("Índices", "Toda FK indexada; compostos (igualdade antes de intervalo); BRIN na série temporal."),
        ("Segurança", "Papel bolsa_leitura somente-leitura para analistas (menor privilégio)."),
        ("Documentação", "COMMENT ON em esquema, tabelas, colunas e funções.")],
       [3.2, 12.8])

titulo_numerado(2, "Definição de dados (DDL)")
texto(
    "O esquema bolsa contém seis tabelas. As regras de negócio foram traduzidas em restrições: o CPF de "
    "pessoa física deve ter onze dígitos e o CNPJ de pessoa jurídica, catorze; o ticker segue o padrão de "
    "quatro letras e um ou dois dígitos; quantidades e preços são positivos; e cada ação tem no máximo "
    "uma cotação por instante. Um gatilho AFTER INSERT em negociacao atualiza a carteira, recalculando "
    "o preço médio nas compras e rejeitando vendas sem saldo (RN01); outro gatilho bloqueia UPDATE e "
    "DELETE em negociacao (RN02). A função fn_carteira_em reconstrói a posição de um investidor em "
    "qualquer instante passado e a valoriza pela última cotação conhecida até aquele momento (RF06). "
    "Três visões (vw_cotacao_atual, vw_posicao_valorizada e vw_extrato_negociacoes) simplificam as "
    "consultas de uso frequente. O trecho a seguir ilustra a definição da tabela negociacao.")
codigo([
    "CREATE TABLE bolsa.negociacao (",
    "    id_negociacao   bigint        GENERATED ALWAYS AS IDENTITY,",
    "    id_investidor   bigint        NOT NULL,",
    "    id_acao         bigint        NOT NULL,",
    "    data_hora       timestamptz   NOT NULL DEFAULT now(),",
    "    tipo_operacao   text          NOT NULL,",
    "    quantidade      integer       NOT NULL,",
    "    valor_unitario  numeric(12,4) NOT NULL,",
    "    valor_total     numeric(18,2)",
    "        GENERATED ALWAYS AS (quantidade * valor_unitario) STORED,",
    "    CONSTRAINT pk_negociacao            PRIMARY KEY (id_negociacao),",
    "    CONSTRAINT fk_negociacao_investidor FOREIGN KEY (id_investidor)",
    "        REFERENCES bolsa.investidor (id_investidor)",
    "        ON UPDATE CASCADE ON DELETE RESTRICT,",
    "    CONSTRAINT fk_negociacao_acao       FOREIGN KEY (id_acao)",
    "        REFERENCES bolsa.acao (id_acao)",
    "        ON UPDATE CASCADE ON DELETE RESTRICT,",
    "    CONSTRAINT ck_negociacao_tipo       CHECK (tipo_operacao IN ('COMPRA','VENDA')),",
    "    CONSTRAINT ck_negociacao_quantidade CHECK (quantidade > 0),",
    "    CONSTRAINT ck_negociacao_valor      CHECK (valor_unitario > 0)",
    ");",
])

titulo_numerado(2, "Manipulação de dados (DML)")
texto(
    "A carga de exemplo, com dados fictícios, contém seis investidores (quatro pessoas físicas e duas "
    "jurídicas), sete empresas, oito ações, seiscentas cotações intradiárias geradas com generate_series "
    "para cinco pregões e quinze negociações inseridas em ordem cronológica, de modo que o gatilho "
    "constrói a carteira. O bloco inclui ainda instruções UPDATE e DELETE e quatro blocos anônimos que "
    "demonstram as regras de integridade, capturando o erro esperado sem interromper o script.")

titulo_numerado(2, "Consultas (DQL)")
texto("Foram elaboradas dezesseis consultas que cobrem os requisitos de análise do enunciado (Quadro 12).")
quadro("Consultas analíticas do modelo físico",
       ["Nº", "Consulta", "Recursos de SQL"],
       [("Q01", "Carteira valorizada a mercado", "Visão; DISTINCT ON"),
        ("Q02", "Patrimônio total por investidor", "GROUP BY sobre visão"),
        ("Q03", "Extrato de negociações por CPF/CNPJ", "Busca pela chave natural"),
        ("Q04", "Volume por ação, compras e vendas", "Agregação com FILTER"),
        ("Q05", "Série diária OHLC a partir do intradiário", "FIRST_VALUE em janela"),
        ("Q06", "Variação entre cotações e média móvel", "LAG; AVG com ROWS BETWEEN"),
        ("Q07", "Máxima e mínima com instante de ocorrência", "ARRAY_AGG ordenado"),
        ("Q08", "Carteira em data passada", "Função fn_carteira_em"),
        ("Q09", "Evolução diária do patrimônio", "generate_series; LATERAL"),
        ("Q10", "Resultado realizado nas vendas", "Janela acumulada com FILTER"),
        ("Q11", "Ranking de investidores por volume", "RANK()"),
        ("Q12", "Exposição da corretora por setor", "Janela sobre agregado"),
        ("Q13", "Ações listadas sem negociação", "NOT EXISTS"),
        ("Q14", "Comparativo pessoa física e jurídica", "LEFT JOIN; agregações"),
        ("Q15", "Conferência carteira × negociações", "FULL OUTER JOIN"),
        ("Q16", "Plano de execução de consulta temporal", "EXPLAIN")],
       [1.4, 7.6, 7.0])

# ---------------------------------------------------------------- 6. RESULTADOS
titulo_numerado(1, "Validação e resultados")
texto(
    "O script completo foi executado em PostgreSQL 16.13, com a opção ON_ERROR_STOP ativada, em um banco "
    "criado exclusivamente para o teste. Não houve erro em nenhuma instrução. Os quatro blocos de "
    "demonstração das regras de integridade produziram o resultado esperado: a venda acima do saldo foi "
    "rejeitada pelo gatilho; a exclusão de uma negociação foi bloqueada; um documento com tamanho de CNPJ "
    "cadastrado como pessoa física violou a restrição de verificação; e a exclusão de uma empresa com "
    "ações foi impedida pela chave estrangeira.")
texto("O Quadro 13 resume os principais resultados numéricos das consultas sobre a carga de exemplo.")
quadro("Resultados selecionados das consultas",
       ["Consulta", "Resultado observado"],
       [("Q01/Q02", "Nove posições em carteira; maior patrimônio em ações: R$ 329.900,00 (Vale Verde Investimentos)."),
        ("Q04", "Ação de maior volume negociado: PETR3, R$ 248.150,00."),
        ("Q05", "Cinco pregões consolidados em abertura, máxima, mínima e fechamento para PETR4."),
        ("Q08", "Carteira de Ana Paula Ribeiro em 03/09/2026 às 17h: 300 PETR4 e 100 VALE3, R$ 17.268,82."),
        ("Q10", "Resultado realizado nas quatro vendas: três com lucro e uma com prejuízo de R$ 15,00."),
        ("Q13", "Uma ação listada sem negociação (ABEV3), confirmando o anti-join."),
        ("Q15", "Zero divergências entre a carteira mantida pelo gatilho e o saldo recalculado."),
        ("Q16", "Plano de execução com Index Scan sobre o índice da restrição UNIQUE (id_acao, data_hora).")],
       [2.4, 13.6])

# ---------------------------------------------------------------- 7. CONCLUSÃO
titulo_numerado(1, "Considerações finais")
texto(
    "O trabalho cumpriu os objetivos propostos: o domínio da corretora foi representado em um modelo "
    "conceitual coerente com o enunciado, traduzido para um esquema relacional normalizado e implementado "
    "em um script executável, cujas regras de negócio residem no próprio banco de dados. As decisões de "
    "maior impacto foram tratar a negociação como entidade histórica e a carteira como relacionamento "
    "derivado, mantido por gatilho, o que permitiu conciliar o registro imutável das operações com a "
    "consulta imediata da posição atual.")
texto(
    "Como evolução, o modelo pode receber o particionamento da tabela de cotações por período, adequado "
    "ao crescimento contínuo de séries temporais, e a inclusão de eventos societários (desdobramentos e "
    "grupamentos) que afetam quantidades e preços médios.")

# ---------------------------------------------------------------- REFERÊNCIAS (NBR 6023)
titulo_sem_numero("Referências")
referencias = [
    ("ASSOCIAÇÃO BRASILEIRA DE NORMAS TÉCNICAS. ", "NBR 14724", ": informação e documentação: trabalhos "
     "acadêmicos: apresentação. Rio de Janeiro: ABNT, 2011."),
    ("ASSOCIAÇÃO BRASILEIRA DE NORMAS TÉCNICAS. ", "NBR 6023", ": informação e documentação: referências: "
     "elaboração. Rio de Janeiro: ABNT, 2018."),
    ("ASSOCIAÇÃO BRASILEIRA DE NORMAS TÉCNICAS. ", "NBR 6024", ": informação e documentação: numeração "
     "progressiva das seções de um documento: apresentação. Rio de Janeiro: ABNT, 2012."),
    ("CÂNDIDO, Carlos Henrique. ", "brModelo", ": ferramenta para modelagem conceitual de bancos de dados. "
     f"Versão 3. 2021. Disponível em: http://www.sis4.com/brModelo/. Acesso em: {DATA_ACESSO}."),
    ("DATE, Christopher J. ", "Introdução a sistemas de bancos de dados", ". 8. ed. Rio de Janeiro: "
     "Elsevier, 2004."),
    ("ELMASRI, Ramez; NAVATHE, Shamkant B. ", "Sistemas de banco de dados", ". 7. ed. São Paulo: Pearson, 2018."),
    ("HEUSER, Carlos Alberto. ", "Projeto de banco de dados", ". 6. ed. Porto Alegre: Bookman, 2009."),
    ("POSTGRESQL GLOBAL DEVELOPMENT GROUP. ", "PostgreSQL 16 documentation", ". 2024. Disponível em: "
     f"https://www.postgresql.org/docs/16/. Acesso em: {DATA_ACESSO}."),
]
for antes, destaque, depois in referencias:
    p = doc.add_paragraph()
    _paragrafo_base(p, WD_ALIGN_PARAGRAPH.LEFT, recuo=False, depois=12, linha=1)
    r = p.add_run(antes); _fonte(r, 12)
    r = p.add_run(destaque); _fonte(r, 12, True)
    r = p.add_run(depois); _fonte(r, 12)

# ---------------------------------------------------------------- ANEXO
titulo_sem_numero("Apêndice A – Script SQL do modelo físico")
texto(
    "O arquivo 00_bolsa_completo.sql, entregue junto a este relatório, contém o modelo físico completo "
    "(DDL, DML e DQL) e pode ser executado com o comando a seguir.", recuo=False)
codigo(["psql -v ON_ERROR_STOP=1 -d bolsa_valores -f 00_bolsa_completo.sql"])
texto("Os arquivos-fonte, os diagramas e os scripts de geração estão disponíveis no repositório "
      "https://github.com/alexander-stack1/TDP_Avaliacao_banco_de_dados.", recuo=False)

_atualizar_campos_ao_abrir()
SAIDA.parent.mkdir(parents=True, exist_ok=True)
doc.save(SAIDA)
print("gerado:", SAIDA)
