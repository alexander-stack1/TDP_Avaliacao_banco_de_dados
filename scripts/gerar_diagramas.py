#!/usr/bin/env python3
"""Gera o print (PNG) do modelo lógico (relacional, pé-de-galinha) do Case Bolsa
de Valores. O modelo conceitual é desenhado no brModelo 3 (ver gerar_brmodelo.py).

Uso:  python3 scripts/gerar_diagramas.py
Saída: docs/02-modelo-logico/modelo_logico.png
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse, FancyBboxPatch, Polygon, Rectangle

RAIZ = Path(__file__).resolve().parent.parent
plt.rcParams["font.family"] = "DejaVu Sans"

# ----------------------------------------------------------------------------
# utilidades de desenho
# ----------------------------------------------------------------------------
COR_ENT = "#dbe9ff"
COR_REL = "#ffe9b8"
COR_ATR = "#ffffff"
COR_BORDA = "#1f2937"


def entidade(ax, x, y, nome, w=14, h=6, fraca=False, associativa=False):
    ax.add_patch(Rectangle((x - w / 2, y - h / 2), w, h, fc=COR_ENT, ec=COR_BORDA, lw=1.6, zorder=3))
    if fraca:
        ax.add_patch(Rectangle((x - w / 2 + 0.6, y - h / 2 + 0.6), w - 1.2, h - 1.2,
                               fc="none", ec=COR_BORDA, lw=1.2, zorder=4))
    ax.text(x, y, nome, ha="center", va="center", fontsize=12, fontweight="bold", zorder=5)


def losango(ax, x, y, nome, w=13, h=7, identificador=False):
    pts = [(x - w / 2, y), (x, y + h / 2), (x + w / 2, y), (x, y - h / 2)]
    ax.add_patch(Polygon(pts, closed=True, fc=COR_REL, ec=COR_BORDA, lw=1.6, zorder=3))
    if identificador:
        f = 0.78
        pts2 = [(x - w * f / 2, y), (x, y + h * f / 2), (x + w * f / 2, y), (x, y - h * f / 2)]
        ax.add_patch(Polygon(pts2, closed=True, fc="none", ec=COR_BORDA, lw=1.1, zorder=4))
    ax.text(x, y, nome, ha="center", va="center", fontsize=10.5, fontstyle="italic", zorder=5)


def atributo(ax, x, y, nome, chave=False, parcial=False, w=None, h=3.0):
    w = w or max(7.5, 0.95 * len(nome) + 2.5)
    ax.add_patch(Ellipse((x, y), w, h, fc=COR_ATR, ec=COR_BORDA, lw=1.1, zorder=3))
    txt = ax.text(x, y, nome, ha="center", va="center", fontsize=8.6, zorder=5)
    if chave or parcial:
        # sublinhado (contínuo p/ chave; tracejado p/ chave parcial de entidade fraca)
        ax.plot([x - 0.42 * len(nome), x + 0.42 * len(nome)], [y - 0.95, y - 0.95],
                color=COR_BORDA, lw=1.0, ls="-" if chave else (0, (2, 2)), zorder=6)
    return txt


def liga(ax, p, q, zorder=1):
    ax.plot([p[0], q[0]], [p[1], q[1]], color=COR_BORDA, lw=1.2, zorder=zorder)


def cardinalidade(ax, x, y, texto):
    ax.text(x, y, texto, fontsize=9.5, ha="center", va="center", zorder=6,
            bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none"))


def leque(ax, cx, cy, itens, raio_x=9.0, raio_y=6.5, ang_ini=150, ang_fim=30):
    """Distribui atributos num arco acima da entidade e liga cada um ao centro."""
    import math
    n = len(itens)
    for i, (nome, chave) in enumerate(itens):
        t = ang_ini + (ang_fim - ang_ini) * (i / (n - 1) if n > 1 else 0.5)
        ax_ = cx + raio_x * math.cos(math.radians(t))
        ay_ = cy + raio_y * math.sin(math.radians(t))
        liga(ax, (cx, cy), (ax_, ay_))
        atributo(ax, ax_, ay_, nome, chave=chave)


# ----------------------------------------------------------------------------
# 2) MODELO LÓGICO (relacional, pé-de-galinha)
# ----------------------------------------------------------------------------
def tabela(ax, x, y, nome, colunas, w=24, lh=1.55):
    """Desenha uma tabela; retorna dict com as coordenadas das bordas."""
    h = lh * (len(colunas) + 1) + 0.9
    ax.add_patch(FancyBboxPatch((x, y - h), w, h, boxstyle="round,pad=0.02,rounding_size=0.6",
                                fc="white", ec=COR_BORDA, lw=1.5, zorder=3))
    ax.add_patch(Rectangle((x, y - lh - 0.4), w, lh + 0.4, fc="#1f2937", ec="none", zorder=4))
    ax.text(x + w / 2, y - (lh + 0.4) / 2, nome, color="white", ha="center", va="center",
            fontsize=11.5, fontweight="bold", zorder=5)
    for i, (marca, col, tipo) in enumerate(colunas):
        yy = y - lh - 0.4 - lh * (i + 0.7)
        ax.text(x + 0.8, yy, marca, fontsize=8.3, fontweight="bold", va="center",
                color="#b45309" if "PK" in marca else "#1d4ed8" if marca else "#111", zorder=5)
        ax.text(x + 4.2, yy, col, fontsize=8.8, va="center", zorder=5,
                fontweight="bold" if "PK" in marca else "normal")
        ax.text(x + w - 0.8, yy, tipo, fontsize=7.8, va="center", ha="right", color="#4b5563", zorder=5)
    return {"l": x, "r": x + w, "t": y, "b": y - h, "cx": x + w / 2, "cy": y - h / 2}


def pe_de_galinha(ax, p, direcao, opcional=False):
    """Desenha o símbolo 'muitos' (pé-de-galinha) no ponto p, apontando na direção dada."""
    dx, dy = direcao
    s = 1.6
    if dx:  # horizontal
        base = (p[0] - dx * s, p[1])
        for off in (-1.1, 0, 1.1):
            ax.plot([base[0], p[0]], [p[1], p[1] + off], color=COR_BORDA, lw=1.2, zorder=6)
        if opcional:
            ax.add_patch(Ellipse((base[0] - dx * 0.9, p[1]), 1.1, 1.1, fc="white", ec=COR_BORDA, lw=1.1, zorder=6))
    else:   # vertical
        base = (p[0], p[1] - dy * s)
        for off in (-1.1, 0, 1.1):
            ax.plot([p[0], p[0] + off], [base[1], p[1]], color=COR_BORDA, lw=1.2, zorder=6)
        if opcional:
            ax.add_patch(Ellipse((p[0], base[1] - dy * 0.9), 1.1, 1.1, fc="white", ec=COR_BORDA, lw=1.1, zorder=6))


def um(ax, p, direcao):
    """Traço perpendicular = 'exatamente um'."""
    dx, dy = direcao
    if dx:
        ax.plot([p[0] - dx * 1.4] * 2, [p[1] - 1.1, p[1] + 1.1], color=COR_BORDA, lw=1.4, zorder=6)
    else:
        ax.plot([p[0] - 1.1, p[0] + 1.1], [p[1] - dy * 1.4] * 2, color=COR_BORDA, lw=1.4, zorder=6)


def logico(saida: Path):
    fig, ax = plt.subplots(figsize=(22, 13.5), dpi=150)
    ax.set_xlim(0, 118)
    ax.set_ylim(-3, 66)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.text(0.5, 0.965, "Modelo Lógico Relacional — Negociações na Bolsa de Valores (esquema bolsa, PostgreSQL)",
             ha="center", fontsize=16, fontweight="bold")

    emp = tabela(ax, 2, 63, "EMPRESA", [
        ("PK", "id_empresa", "bigint identity"),
        ("UQ", "cnpj", "text"),
        ("", "nome", "text"),
        ("", "setor", "text"),
        ("", "valor_mercado", "numeric(18,2)"),
        ("", "atualizado_em", "timestamptz")], w=27)

    aca = tabela(ax, 2, 41, "ACAO", [
        ("PK", "id_acao", "bigint identity"),
        ("UQ", "ticker", "text"),
        ("FK", "id_empresa → empresa", "bigint"),
        ("", "tipo_acao", "text (ON/PN/UNIT)"),
        ("", "ativa", "boolean")], w=27)

    cot = tabela(ax, 2, 20, "COTACAO", [
        ("PK", "id_cotacao", "bigint identity"),
        ("FK", "id_acao → acao", "bigint"),
        ("UQ", "data_hora", "timestamptz"),
        ("", "valor", "numeric(12,4)")], w=27)
    ax.text(cot["cx"], cot["b"] - 1.3, "UNIQUE (id_acao, data_hora)", fontsize=8, ha="center", color="#4b5563")

    car = tabela(ax, 42, 63, "CARTEIRA", [
        ("PK,FK", "id_investidor → investidor", "bigint"),
        ("PK,FK", "id_acao → acao", "bigint"),
        ("", "quantidade", "integer ≥ 0"),
        ("", "preco_medio", "numeric(12,4)"),
        ("", "atualizado_em", "timestamptz")], w=30)
    ax.text(car["cx"], car["b"] - 1.3, "PK composta; mantida por trigger a partir de NEGOCIACAO",
            fontsize=8, ha="center", color="#4b5563")

    neg = tabela(ax, 42, 25, "NEGOCIACAO", [
        ("PK", "id_negociacao", "bigint identity"),
        ("FK", "id_investidor → investidor", "bigint"),
        ("FK", "id_acao → acao", "bigint"),
        ("", "data_hora", "timestamptz"),
        ("", "tipo_operacao", "text (COMPRA/VENDA)"),
        ("", "quantidade", "integer > 0"),
        ("", "valor_unitario", "numeric(12,4)"),
        ("", "valor_total", "numeric(18,2) gerada")], w=33)

    inv = tabela(ax, 88, 46, "INVESTIDOR", [
        ("PK", "id_investidor", "bigint identity"),
        ("UQ", "documento (CPF/CNPJ)", "text"),
        ("", "tipo_investidor", "text (PF/PJ)"),
        ("", "nome_completo", "text"),
        ("UQ", "email", "text"),
        ("", "telefone", "text"),
        ("", "criado_em", "timestamptz")], w=28)

    def rotulo(x, y, t, **kw):
        ax.text(x, y, t, fontsize=9, fontstyle="italic", zorder=7,
                bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none"), **kw)

    # EMPRESA 1 —< N ACAO (vertical)
    x = emp["cx"]
    liga(ax, (x, emp["b"]), (x, aca["t"])); um(ax, (x, emp["b"] - 1.4), (0, -1)); pe_de_galinha(ax, (x, aca["t"]), (0, -1))
    rotulo(x + 1.5, (emp["b"] + aca["t"]) / 2, "emite", va="center")

    # ACAO 1 —< N COTACAO (vertical)
    x = aca["cx"]
    liga(ax, (x, aca["b"]), (x, cot["t"])); um(ax, (x, aca["b"] - 1.4), (0, -1)); pe_de_galinha(ax, (x, cot["t"]), (0, -1))
    rotulo(x + 1.5, (aca["b"] + cot["t"]) / 2, "possui (série temporal)", va="center")

    # ACAO 1 —< N CARTEIRA  (sai pela direita, sobe, entra pela esquerda)
    ya, yc, xm = aca["t"] - 4, car["t"] - 5, 35
    liga(ax, (aca["r"], ya), (xm, ya)); liga(ax, (xm, ya), (xm, yc)); liga(ax, (xm, yc), (car["l"], yc))
    um(ax, (aca["r"] + 1.4, ya), (1, 0)); pe_de_galinha(ax, (car["l"], yc), (1, 0), opcional=True)
    rotulo(xm + 1, (ya + yc) / 2, "compõe carteira", va="center")

    # ACAO 1 —< N NEGOCIACAO (sai pela direita, desce, entra pela esquerda)
    ya2, yn = aca["t"] - 9, neg["t"] - 6
    liga(ax, (aca["r"], ya2), (xm, ya2)); liga(ax, (xm, ya2), (xm, yn)); liga(ax, (xm, yn), (neg["l"], yn))
    um(ax, (aca["r"] + 1.4, ya2), (1, 0)); pe_de_galinha(ax, (neg["l"], yn), (1, 0), opcional=True)
    rotulo(xm + 1, (ya2 + yn) / 2, "é negociada em", va="center")

    # INVESTIDOR 1 —< N CARTEIRA (sai pela esquerda, sobe, entra pela direita)
    yi, xr = inv["t"] - 4, 82
    liga(ax, (inv["l"], yi), (xr, yi)); liga(ax, (xr, yi), (xr, yc)); liga(ax, (xr, yc), (car["r"], yc))
    um(ax, (inv["l"] - 1.4, yi), (-1, 0)); pe_de_galinha(ax, (car["r"], yc), (-1, 0), opcional=True)
    rotulo(xr - 1, (yi + yc) / 2, "mantém posição em", ha="right", va="center")

    # INVESTIDOR 1 —< N NEGOCIACAO (sai pela esquerda, desce, entra pela direita)
    yi2 = inv["t"] - 9
    liga(ax, (inv["l"], yi2), (xr, yi2)); liga(ax, (xr, yi2), (xr, yn)); liga(ax, (xr, yn), (neg["r"], yn))
    um(ax, (inv["l"] - 1.4, yi2), (-1, 0)); pe_de_galinha(ax, (neg["r"], yn), (-1, 0), opcional=True)
    rotulo(xr - 1, (yi2 + yn) / 2, "realiza", ha="right", va="center")

    # legenda
    ax.text(1, 1.5, "Legenda:  PK = chave primária · FK = chave estrangeira · UQ = única (chave natural) · "
                    "—|  = exatamente um · —<  = muitos · ○—<  = zero ou muitos",
            fontsize=9.5, color="#374151")
    ax.text(1, -1.0, "Normalização: 3FN. Investidor x Ação é N:N e foi resolvido por duas tabelas: NEGOCIACAO (histórico, "
                     "muitas linhas por par) e CARTEIRA (posição atual, uma linha por par).",
            fontsize=9.5, color="#374151")

    fig.savefig(saida, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    l = RAIZ / "docs/02-modelo-logico/modelo_logico.png"
    logico(l)
    print("gerado:", l)
