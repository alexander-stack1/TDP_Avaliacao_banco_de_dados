#!/usr/bin/env python3
"""Gera o arquivo de modelo conceitual no formato JSON do brModelo Web
(https://app.brmodeloweb.com → Importar). O conteúdo espelha exatamente o
diagrama de docs/01-modelo-conceitual/modelo_conceitual.png.

Uso:  python3 scripts/gerar_brmodelo.py
Saída: docs/01-modelo-conceitual/modelo_conceitual.brmodelo.json
"""
import json
import uuid
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "docs/01-modelo-conceitual/modelo_conceitual.brmodelo.json"

cells = []
z = 0


def novo(tipo, texto, x, y, w, h, extra=None):
    global z
    z += 1
    cell = {
        "type": tipo,
        "position": {"x": x, "y": y},
        "size": {"width": w, "height": h},
        "angle": 0,
        "id": str(uuid.uuid4()),
        "z": z,
        "attrs": {"text": {"text": texto}},
    }
    if extra:
        cell.update(extra)
    cells.append(cell)
    return cell["id"]


def entidade(nome, x, y, fraca=False):
    return novo("erd.WeakEntity" if fraca else "erd.Entity", nome, x, y, 110, 50)


def relacionamento(nome, x, y, identificador=False):
    return novo("erd.IdentifyingRelationship" if identificador else "erd.Relationship", nome, x, y, 110, 60)


def atributo(nome, x, y, chave=False, parcial=False):
    tipo = "erd.Key" if chave else "erd.Attribute"
    extra = {"attrs": {"text": {"text": nome}, ".outer": {"stroke-dasharray": "4 2"}}} if parcial else None
    return novo(tipo, nome, x, y, 90, 30, extra)


def liga(origem, destino, rotulo=None):
    global z
    z += 1
    link = {
        "type": "erd.Line",
        "source": {"id": origem},
        "target": {"id": destino},
        "id": str(uuid.uuid4()),
        "z": z,
        "attrs": {},
    }
    if rotulo:
        link["labels"] = [{"position": 0.2, "attrs": {"text": {"text": rotulo}}}]
    cells.append(link)


# ---------------- entidades e relacionamentos (mesmo layout do PNG) ----------------
EMP = entidade("EMPRESA", 60, 300)
EMI = relacionamento("emite", 250, 295)
ACA = entidade("AÇÃO", 440, 300)
MAN = relacionamento("mantém (carteira)", 650, 295)
INV = entidade("INVESTIDOR", 860, 300)
POS = relacionamento("possui", 440, 470, identificador=True)
COT = entidade("COTAÇÃO", 440, 640, fraca=True)
REA = relacionamento("realiza", 860, 470)
NEG = entidade("NEGOCIAÇÃO", 860, 640)
REF = relacionamento("refere-se a", 650, 640)

# ---------------- ligações com cardinalidade (min,max) do lado da entidade ----------------
liga(EMP, EMI, "(1,n)"); liga(ACA, EMI, "(1,1)")
liga(ACA, MAN, "(0,n)"); liga(INV, MAN, "(0,n)")
liga(ACA, POS, "(1,n)"); liga(COT, POS, "(1,1)")
liga(INV, REA, "(0,n)"); liga(NEG, REA, "(1,1)")
liga(ACA, REF, "(0,n)"); liga(NEG, REF, "(1,1)")

# ---------------- atributos ----------------
def atrs(dono, itens, x0, y0, dx=0, dy=40):
    for i, item in enumerate(itens):
        nome, chave = item[0], item[1]
        parcial = item[2] if len(item) > 2 else False
        a = atributo(nome, x0 + i * dx, y0 + i * dy, chave=chave, parcial=parcial)
        liga(dono, a)

atrs(EMP, [("id_empresa", True), ("cnpj", False), ("nome", False), ("setor", False), ("valor_mercado", False)],
     40, 60, dx=0, dy=40)
atrs(ACA, [("id_acao", True), ("ticker", False), ("tipo_acao", False), ("ativa", False)], 420, 100, dy=40)
atrs(INV, [("id_investidor", True), ("documento (CPF/CNPJ)", False), ("tipo_investidor", False),
           ("nome_completo", False), ("email", False), ("telefone", False)], 1040, 60, dy=40)
atrs(MAN, [("quantidade", False), ("preco_medio", False)], 600, 400, dx=110, dy=0)
atrs(COT, [("data_hora", False, True), ("valor", False)], 300, 640, dx=0, dy=40)
atrs(NEG, [("id_negociacao", True), ("data_hora", False), ("tipo_operacao", False),
           ("quantidade", False), ("valor_unitario", False)], 1040, 600, dy=40)

modelo = {
    "type": "conceptual",
    "name": "Case Bolsa de Valores - Modelo Conceitual",
    "model": {"cells": cells},
}
SAIDA.write_text(json.dumps(modelo, ensure_ascii=False, indent=2), encoding="utf-8")
print("gerado:", SAIDA, f"({len(cells)} elementos)")
