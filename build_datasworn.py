#!/usr/bin/env python3
"""Transform vendored Datasworn JSON into compact per-ruleset assets.

Self-verifies: known roll types only, every oracle row well-formed
(min <= max within the dice range), no empty move/oracle sets.
Run: python3 build_datasworn.py   (writes assets/ruleset_<id>.json)
"""
import json
import os
import sys

SRC = {
    "starforged": "data/datasworn/starforged.json",
    "classic": "data/datasworn/classic.json",
    "delve": "data/datasworn/delve.json",
    "sundered_isles": "data/datasworn/sundered_isles.json",
}
ROLL_TYPES = {"no_roll", "action_roll", "progress_roll", "special_track"}


def transform_moves(moves):
    cats = []
    for cat in moves.values():
        entries = []
        for mv in (cat.get("contents") or {}).values():
            outcomes = mv.get("outcomes") or {}
            entries.append({
                "name": mv["name"],
                "rollType": mv["roll_type"],
                "trigger": (mv.get("trigger") or {}).get("text", ""),
                "text": mv.get("text", ""),
                "outcomes": {
                    k: (outcomes.get(k) or {}).get("text", "")
                    for k in ("strong_hit", "weak_hit", "miss")
                    if outcomes.get(k)
                },
            })
        if entries:
            cats.append({"name": cat["name"], "moves": entries})
    return cats


def _row_min_max(r):
    """Extract (min, max) from a row, handling both Datasworn schema variants.

    Most rulesets (0.0.10): r['min'], r['max'] at top level.
    Sundered Isles (0.1.0): r['roll']['min'], r['roll']['max'] nested.
    """
    if "min" in r and "max" in r:
        return r["min"], r["max"]
    roll = r.get("roll") or {}
    mn, mx = roll.get("min"), roll.get("max")
    if mn is not None and mx is not None:
        return mn, mx
    return None, None


def flatten_oracles(collections, prefix=""):
    out = []
    for coll in collections.values():
        name = f"{prefix}{coll['name']}"
        tables = []
        for table in (coll.get("contents") or {}).values():
            rows = []
            for r in (table.get("rows") or []):
                mn, mx = _row_min_max(r)
                if mn is not None and mx is not None:
                    rows.append([mn, mx, r.get("text") or ""])
            if rows:
                tables.append({
                    "name": table["name"],
                    "dice": table.get("dice", "1d100"),
                    "rows": rows,
                })
        if tables:
            out.append({"name": name, "tables": tables})
        if coll.get("collections"):
            out.extend(flatten_oracles(coll["collections"], prefix=f"{name} / "))
    return out


def verify(ruleset_id, data):
    failures = []
    if not data["move_categories"]:
        failures.append(f"{ruleset_id}: no move categories")
    for cat in data["move_categories"]:
        for mv in cat["moves"]:
            if mv["rollType"] not in ROLL_TYPES:
                failures.append(f"{ruleset_id}: unknown roll type {mv['rollType']}")
            if not mv["name"]:
                failures.append(f"{ruleset_id}: unnamed move")
    if not data["oracle_collections"]:
        failures.append(f"{ruleset_id}: no oracle collections")
    for coll in data["oracle_collections"]:
        for table in coll["tables"]:
            sides = int(table["dice"].split("d")[-1])
            for mn, mx, _text in table["rows"]:
                if not (1 <= mn <= mx <= sides):
                    failures.append(
                        f"{ruleset_id}: bad row [{mn},{mx}] in {table['name']}")
    return failures


def main():
    all_failures = []
    for rid, path in SRC.items():
        with open(path) as f:
            src = json.load(f)
        data = {
            "meta": {
                "id": rid,
                "title": src.get("title", rid),
                "license": src.get("license", ""),
                "authors": [a.get("name", "") for a in src.get("authors", [])],
                "url": src.get("url", ""),
            },
            "move_categories": transform_moves(src.get("moves") or {}),
            "oracle_collections": flatten_oracles(src.get("oracles") or {}),
        }
        all_failures += verify(rid, data)
        out = f"assets/ruleset_{rid}.json"
        with open(out, "w") as f:
            json.dump(data, f, ensure_ascii=False)
        n_moves = sum(len(c["moves"]) for c in data["move_categories"])
        n_tables = sum(len(c["tables"]) for c in data["oracle_collections"])
        print(f"{out}: {n_moves} moves, {n_tables} oracle tables")
    if all_failures:
        print("VERIFICATION FAILED:")
        for f_ in all_failures:
            print("  -", f_)
        sys.exit(1)
    print("All datasworn verifications passed.")


if __name__ == "__main__":
    main()
