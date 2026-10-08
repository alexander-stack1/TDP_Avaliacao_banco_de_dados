#!/usr/bin/env python3
"""Empacota somente os artefatos acadêmicos da versão local; não publica arquivos."""
from pathlib import Path
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED

RAIZ = Path(__file__).resolve().parent.parent
ARQUIVOS = [
    'docs/Entrega_Case_Bolsa_Valores.docx',
    'docs/Entrega_Case_Bolsa_Valores.pdf',
    'docs/01-modelo-conceitual/modelo_conceitual.brM3',
    'docs/01-modelo-conceitual/modelo_conceitual_brmodelo.png',
    'docs/01-modelo-conceitual/modelo_conceitual.md',
    'docs/02-modelo-logico/modelo_logico.md',
    'docs/02-modelo-logico/modelo_logico.png',
    'sql/00_bolsa_completo.sql',
]
subprocess.run([str(RAIZ/'scripts/build_sql.sh'), '--check'], check=True)
for nome in ARQUIVOS:
    if not (RAIZ/nome).is_file():
        raise SystemExit(f'Arquivo ausente: {nome}')
saida = RAIZ/'output/entrega/Entrega_Case_Bolsa_Valores.zip'
saida.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(saida, 'w', ZIP_DEFLATED) as z:
    for nome in ARQUIVOS:
        z.write(RAIZ/nome, nome)
    z.writestr('LEIA-ME.txt', '''TRABALHO DE MODELAGEM DE BANCO DE DADOS

O pacote inclui Word, PDF complementar, modelo conceitual no brModelo com
print, modelo lógico textual com print e arquivo SQL (DDL + DML + DQL).

Confira e preencha instituição, curso, cidade e integrantes no Word antes
do envio. Se alterar o Word, atualize o PDF e confira a paginação dos índices.
O PDF da atividade informa entrega até 18/10 (sem ano explícito) via
Classroom e permite equipes de até cinco integrantes. O envio é manual.

Execute o SQL em PostgreSQL 16 em um banco novo:
psql -X -v ON_ERROR_STOP=1 -d bolsa_valores -f sql/00_bolsa_completo.sql

A instalação recusa esquema bolsa existente e não apaga dados. A demonstração
usa dados sintéticos. Negociações de cada par investidor/ação precisam entrar
em instantes estritamente crescentes; venda sem saldo é rejeitada.

Os fontes de geração e a revisão técnica estão no projeto local.
''')
with ZipFile(saida) as z:
    if z.testzip() is not None:
        raise SystemExit('Falha na integridade do ZIP')
print(saida)
