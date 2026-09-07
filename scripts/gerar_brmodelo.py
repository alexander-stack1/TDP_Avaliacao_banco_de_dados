#!/usr/bin/env python3
"""Gera o modelo conceitual no formato XML nativo do brModelo 3 (chcandido/brModelo).

O brModelo 3 abre este XML diretamente (Arquivo → Abrir) e salva como .brM3.
A conversão automática para .brM3 + PNG é feita por scripts/brmodelo/ConverteBrM3.java.

Formato (lido de controlador.Diagrama.LoadFromXML e das classes do pacote
diagramas.conceitual): raiz <DIAGRAMA TIPO="tpConceitual">, um elemento por
forma (Entidade, Relacionamento, Atributo, Ligacao), identificado por ID.
Cardinalidade: 0=(1,1) 1=(0,1) 2=(1,n) 3=(0,n). Ligação com Largura=2 é a
linha dupla de entidade fraca.

Uso:  python3 scripts/gerar_brmodelo.py
Saída: docs/01-modelo-conceitual/modelo_conceitual.xml
"""
from pathlib import Path
from xml.sax.saxutils import escape

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "docs/01-modelo-conceitual/modelo_conceitual.xml"

C11, C01, C1N, C0N = 0, 1, 2, 3
LEFT, RIGHT = 0, 1          # lado do círculo do atributo (DirecaoFromInspector)

_id = 0
elementos = []
formas = {}                  # nome -> (id, cx, cy)


def novo_id():
    global _id
    _id += 1
    return _id


def _forma(tag, nome, x, y, w, h, extras=""):
    i = novo_id()
    elementos.append(
        f'<{tag} ID="{i}">'
        f'<Bounds Left="{x}" Top="{y}" Width="{w}" Height="{h}"/>'
        f'<DisablePainted Valor="false"/>'
        f'<Texto>{escape(nome)}</Texto><Observacao></Observacao><Dicionario></Dicionario>'
        f'<Fonte Nome="Arial" Estilo="0" Tamanho="12"/>'
        f'<Ancorado Valor="false"/>{extras}</{tag}>'
    )
    formas[nome] = (i, x + w // 2, y + h // 2)
    return i


def entidade(nome, x, y, w=130, h=50):
    return _forma("Entidade", nome, x, y, w, h, '<AtributosOcultos Valor=""/>')


def relacionamento(nome, x, y, w=120, h=60):
    return _forma("Relacionamento", nome, x, y, w, h)


def atributo(nome, x, y, chave=False, lado=LEFT, chave_parcial=False):
    w = 8 * len(nome) + 24
    extras = (f'<DirecaoFromInspector Valor="{lado}"/><Autosize Valor="true"/>'
              f'<Identificador Valor="{str(chave).lower()}"/><Opcional Valor="false"/>'
              f'<Multivalorado Valor="false"/><CardMinFromString Valor="1"/>'
              f'<CardMaxFromString Valor="1"/><TipoAtributo Valor=""/>')
    return _forma("Atributo", nome, x, y, w, 20, extras)


formas_bounds = {}           # nome -> (x, y, w, h)


def _registra(nome, x, y, w, h):
    formas_bounds[nome] = (x, y, w, h)


def borda(nome, lado, frac=0.5):
    """Ponto sobre a borda de uma forma retangular: lado 'E' (esquerda), 'D' (direita),
    'T' (topo) ou 'B' (base); frac = posição ao longo da borda (0..1)."""
    x, y, w, h = formas_bounds[nome]
    return {"E": (x, y + int(h * frac)), "D": (x + w, y + int(h * frac)),
            "T": (x + int(w * frac), y), "B": (x + int(w * frac), y + h)}[lado]


def circulo(nome):
    """Ponto do círculo do atributo (lado da ligação principal)."""
    x, y, w, h = formas_bounds[nome]
    lado = atributos_lado[nome]
    return (x + 8, y + h // 2) if lado == LEFT else (x + w - 8, y + h // 2)


atributos_lado = {}


def ligacao(a, b, card=None, dupla=False, papel="", pa=None, pb=None):
    """Ligação entre duas formas. `card` (int) põe a cardinalidade do lado da forma `a`
    (que deve ser a entidade). `dupla` = linha dupla (entidade fraca).
    pa/pb: pontos de ancoragem (o brModelo escolhe a borda mais próxima e mantém a outra coordenada)."""
    ia, ax, ay = formas[a]
    ib, bx, by = formas[b]
    if pa: ax, ay = pa
    if pb: bx, by = pb
    i = novo_id()
    xml_card = ""
    if card is not None:
        ic = novo_id()
        xml_card = (f'<Cardinalidade ID="{ic}">'
                    f'<Bounds Left="{ax}" Top="{ay}" Width="40" Height="16"/>'
                    f'<DisablePainted Valor="false"/><Observacao></Observacao><Dicionario></Dicionario>'
                    f'<Ancorado Valor="false"/><TamanhoAutmatico Valor="true"/>'
                    f'<Card Valor="{card}"/><MovimentacaoManual Valor="false"/>'
                    f'<Papel Valor="{escape(papel)}"/></Cardinalidade>')
    elementos.append(
        f'<Ligacao ID="{i}"><DisablePainted Valor="false"/>'
        f'<Tag LinhaMestre="-1"/><Dashed Valor="false"/><Ancorado Valor="false"/>'   # SuperLinha
        f'<Inteligente Valor="false"/>'
        f'<Largura Valor="{2 if dupla else 1}"/>'
        f'<Ligacoes PontaA="{ia}" PontaB="{ib}"/>'
        f'<Pontos><Ponto Left="{ax}" Top="{ay}"/><Ponto Left="{bx}" Top="{by}"/></Pontos>'
        f'{xml_card}</Ligacao>'
    )
    return i


def coluna(dono, itens, x_circulo, y0, lado_dono, dy=28, lado=LEFT, fracs=None):
    """Coluna de atributos ao lado de `dono`. x_circulo = x do círculo; o texto fica do
    lado oposto ao círculo. As linhas chegam à borda `lado_dono` do dono, espalhadas."""
    n = len(itens)
    for k, (nome, chave) in enumerate(itens):
        w = 8 * len(nome) + 24
        x = x_circulo - 8 if lado == LEFT else x_circulo + 8 - w
        atributo(nome, x, y0 + k * dy, chave=chave, lado=lado)
        atributos_lado[nome] = lado
        _registra(nome, x, y0 + k * dy, w, 20)
        frac = fracs[k] if fracs else (0.15 + 0.7 * k / max(n - 1, 1))
        ligacao(nome, dono, pa=circulo(nome), pb=borda(dono, lado_dono, frac))


# ------------------------------------------------------------------ entidades e relacionamentos
def ent(nome, x, y, w=130, h=50):
    entidade(nome, x, y, w, h); _registra(nome, x, y, w, h)


def rel(nome, x, y, w=120, h=60):
    relacionamento(nome, x, y, w, h); _registra(nome, x, y, w, h)


ent("EMPRESA", 260, 320)
rel("emite", 455, 315)
ent("AÇÃO", 640, 320)
rel("mantém", 860, 310, w=150, h=70)
ent("INVESTIDOR", 1100, 320, w=140)
rel("possui", 645, 490)
ent("COTAÇÃO", 640, 660)
rel("realiza", 1110, 490)
ent("NEGOCIAÇÃO", 1100, 660, w=140)
rel("refere-se a", 850, 655, w=140)

# ------------------------------------------------------------------ ligações com cardinalidade
# (a cardinalidade fica do lado da ENTIDADE — primeiro argumento; o brModelo a posiciona
#  automaticamente junto ao ponto de ancoragem)
ligacao("EMPRESA", "emite", C1N, pa=borda("EMPRESA", "D"), pb=borda("emite", "E"))
ligacao("AÇÃO", "emite", C11, pa=borda("AÇÃO", "E"), pb=borda("emite", "D"))
ligacao("AÇÃO", "mantém", C0N, pa=borda("AÇÃO", "D"), pb=borda("mantém", "E"))
ligacao("INVESTIDOR", "mantém", C0N, pa=borda("INVESTIDOR", "E"), pb=borda("mantém", "D"))
ligacao("AÇÃO", "possui", C1N, pa=borda("AÇÃO", "B", 0.35), pb=borda("possui", "T"))
ligacao("COTAÇÃO", "possui", C11, dupla=True, pa=borda("COTAÇÃO", "T"), pb=borda("possui", "B"))
ligacao("INVESTIDOR", "realiza", C0N, pa=borda("INVESTIDOR", "B"), pb=borda("realiza", "T"))
ligacao("NEGOCIAÇÃO", "realiza", C11, pa=borda("NEGOCIAÇÃO", "T"), pb=borda("realiza", "B"))
ligacao("AÇÃO", "refere-se a", C0N, pa=borda("AÇÃO", "B", 0.8), pb=borda("refere-se a", "T"))
ligacao("NEGOCIAÇÃO", "refere-se a", C11, pa=borda("NEGOCIAÇÃO", "E"), pb=borda("refere-se a", "D"))

# ------------------------------------------------------------------ atributos
coluna("EMPRESA", [("id_empresa", True), ("cnpj", False), ("nome", False),
                   ("setor", False), ("valor_mercado", False)],
       x_circulo=230, y0=279, lado_dono="E", lado=RIGHT)
coluna("AÇÃO", [("id_acao", True), ("ticker", False), ("tipo_acao", False), ("ativa", False)],
       x_circulo=630, y0=150, lado_dono="T", lado=RIGHT, fracs=[0.66, 0.48, 0.3, 0.12])
coluna("INVESTIDOR", [("id_investidor", True), ("documento (CPF/CNPJ)", False), ("tipo_investidor", False),
                      ("nome_completo", False), ("email", False), ("telefone", False)],
       x_circulo=1270, y0=262, lado_dono="D", lado=LEFT)
coluna("mantém", [("quantidade", False)], x_circulo=905, y0=420, lado_dono="B", lado=RIGHT, fracs=[0.4])
coluna("mantém", [("preco_medio", False)], x_circulo=965, y0=420, lado_dono="B", lado=LEFT, fracs=[0.6])
coluna("NEGOCIAÇÃO", [("id_negociacao", True), ("data_hora", False), ("tipo_operacao", False),
                      ("quantidade ", False), ("valor_unitario", False)],
       x_circulo=1270, y0=604, lado_dono="D", lado=LEFT)
coluna("COTAÇÃO", [("data_hora ", True), ("valor", False)],
       x_circulo=610, y0=655, lado_dono="E", lado=RIGHT, fracs=[0.3, 0.7])   # data_hora = chave parcial

xml = ('<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
       '<DIAGRAMA TIPO="tpConceitual" ID="0" UniversalUnicID="case-bolsa-valores-conceitual">\n'
       + "\n".join(elementos) + "\n</DIAGRAMA>\n")
SAIDA.write_text(xml, encoding="utf-8")
print("gerado:", SAIDA, f"({len(elementos)} elementos)")
