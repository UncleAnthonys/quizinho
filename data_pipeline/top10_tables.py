"""Reads the ranked tables in the record articles lists_fetch.py saved:
each table's caption or nearest heading, its column headers, and per row the
first linked player we know (by Wikidata id) and the row's figure. Shared by
top10_build.py; run on its own to print every table (for picking lists)."""
from __future__ import annotations

import gzip
import json
import pathlib
import re

HERE = pathlib.Path(__file__).parent
LINK = re.compile(r"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]")
ROWSPAN = re.compile(r'rowspan\s*=\s*"?(\d+)', re.I)
HEADING = re.compile(r"^(=+)\s*(.*?)\s*\1\s*$", re.M)


def load():
    doc = json.load(gzip.open(HERE / "raw" / "lists_wikitext.json.gz", "rt", encoding="utf-8"))
    players = json.loads((HERE / "seed" / "players.json").read_text(encoding="utf-8"))["players"]
    by_qid = {p["wikidata"]: p for p in players}
    return doc["pages"], doc["qids"], by_qid


def tables(text: str):
    """Yield (heading path, caption, headers, rows) per wikitable; each row is
    its list of raw cell strings."""
    pos = 0
    while (i := text.find("{|", pos)) != -1:
        j = text.find("\n|}", i)
        if j == -1:
            break
        body = text[i:j]
        pos = j + 3
        if "wikitable" not in body[:200]:
            continue
        heads = [h for _, h in HEADING.findall(text[:i])][-2:]
        cap = (re.search(r"^\|\+\s*(.*)$", body, re.M) or [None, ""])[1]
        headers = [re.sub(r".*\|", "", h).strip() for h in re.findall(r"^!\s*(.*)$", body, re.M)]
        rows = []
        # A cell spanning rows ("|rowspan=3 align=center|10" for three players
        # level on 14) is copied into the rows below it, in the same column.
        spans: dict[int, list] = {}  # column -> [rows left, cell]
        for chunk in re.split(r"\n\|-[^\n]*", body)[1:]:
            lines = chunk.strip("\n").split("\n")
            # A header row is all "!" cells; a data row has at least one "|" cell.
            if not any(l.startswith("|") and not l.startswith(("|}", "|+")) for l in lines):
                continue
            cells = []
            for line in lines:
                if line.startswith("|") and not line.startswith("|}") and not line.startswith("|+"):
                    cells += [c for c in re.split(r"\|\|", line[1:])]
                elif line.startswith("!"):
                    cells += [c for c in re.split(r"!!", line[1:])]
            if cells:
                full, col = [], 0
                for cell in cells:
                    while col in spans:
                        full.append(spans[col][1])
                        spans[col][0] -= 1
                        if spans[col][0] == 0:
                            del spans[col]
                        col += 1
                    full.append(cell)
                    if (m := ROWSPAN.search(cell.split("|")[0] if "|" in cell and "[[" not in cell.split("|")[0] else "")) and int(m.group(1)) > 1:
                        spans[col] = [int(m.group(1)) - 1, cell]
                    col += 1
                while col in spans:
                    full.append(spans[col][1])
                    spans[col][0] -= 1
                    if spans[col][0] == 0:
                        del spans[col]
                    col += 1
                rows.append(full)
        yield " > ".join(heads), cap, headers, rows


def strip_attr(cell: str) -> str:
    # 'style="..."|value' -> 'value' (not inside links/templates)
    m = re.match(r'^\s*(?:[a-z-]+\s*=\s*(?:"[^"]*"|[^\s|"]+)\s*)+\|(.*)$', cell, re.S)
    return (m.group(1) if m else cell).strip()


def player_rows(rows, qids, by_qid):
    """[(player, figure text, rank text)] for rows naming a player we know."""
    out = []
    for cells in rows:
        cells = [strip_attr(c) for c in cells]
        hit = None
        for k, c in enumerate(cells):
            for l in LINK.findall(c):
                q = qids.get(l.strip().replace("_", " "))
                if q in by_qid:
                    hit = (k, by_qid[q])
                    break
            if hit:
                break
        if not hit:
            continue
        k, p = hit
        figure = next((re.sub(r"'''|''", "", c).strip() for c in cells[k + 1:]
                       if re.fullmatch(r"(?:'''|'')?\s*[\d,.]+\s*(?:'''|'')?\s*(?:<ref.*)?", c.strip(), re.S)), "")
        figure = re.sub(r"<ref.*", "", figure).strip()
        out.append((p, figure, cells[0] if k > 0 else ""))
    return out


if __name__ == "__main__":
    pages, qids, by_qid = load()
    for title, text in pages.items():
        print("=" * 8, title)
        for n, (heads, cap, headers, rows) in enumerate(tables(text)):
            pr = player_rows(rows, qids, by_qid)
            if len(pr) < 10:
                continue
            print(f"  [{n}] {heads} | {cap[:60]} | {headers[:6]}")
            print("      ", "; ".join(f"{p['name']} {f}" for p, f, _ in pr[:10]))
