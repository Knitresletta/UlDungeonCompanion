#!/usr/bin/env python3
"""Fetch the faction side of quests from ForeverChanges quest pages
(https://foreverchanges.pro/quest/<id>) and write tools/quest_sides.json,
which build_quests.py reads to give a side to quests the vanilla data
leaves without one (no race mask, giver with a neutral faction template).

The page's facts list has a "Side" entry: "Alliance", "Horde", or a list
of races when both sides can take it. Only quests without a side in the
generated data are fetched, unless --all. One request every 0.7 s; the
pages are cached in --cache so a rerun is free.

Usage: python3 -I tools/fetch_sides.py QuestData.lua QuestDataForever.lua --cache <dir> -o tools/quest_sides.json
"""

import argparse
import html as htmllib
import json
import os
import re
import sys
import time
import urllib.request

BASE = "https://foreverchanges.pro"
AGENT = "UlDungeonCompanion/0.13 (knitresletta)"
PAUSE = 0.7


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def page_text(html):
    s = re.sub(r"<script.*?</script>", "", html, flags=re.S)
    s = re.sub(r"<style.*?</style>", "", s, flags=re.S)
    t = re.sub(r"<[^>]+>", "\n", s)
    t = htmllib.unescape(t)
    return re.sub(r"\n\s*\n+", "\n", t)


def side_of(html):
    """'Alliance', 'Horde', 'Both', or None when the page has no Side."""
    lines = [l.strip() for l in page_text(html).split("\n")]
    for i, line in enumerate(lines):
        if line == "Side" and i + 1 < len(lines):
            value = lines[i + 1]
            if value in ("Alliance", "Horde"):
                return value
            if "," in value or value in ("Both", "Both sides"):
                return "Both"
            return None
    return None


def ids_without_side(paths):
    ids = []
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"\s+\[(\d+)\]=\{(.*)\},?$", line)
                if m and not re.search(r"\br=\d+", m.group(2)):
                    ids.append(int(m.group(1)))
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="+", help="QuestData.lua files to scan for quests without a side")
    ap.add_argument("-o", "--out", default="tools/quest_sides.json")
    ap.add_argument("--cache", required=True)
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)

    sides = {}
    if os.path.exists(args.out):
        with open(args.out, encoding="utf-8") as f:
            sides = json.load(f)
    ids = ids_without_side(args.data)
    print(f"{len(ids)} quests without a side", file=sys.stderr)
    fetched = 0
    for n, qid in enumerate(ids, 1):
        name = os.path.join(args.cache, f"quest_{qid}.html")
        if os.path.exists(name):
            with open(name, encoding="utf-8") as f:
                html = f.read()
        else:
            try:
                html = fetch(f"/quest/{qid}")
            except Exception as e:
                print(f"  {qid}: {e}", file=sys.stderr)
                time.sleep(PAUSE)
                continue
            with open(name, "w", encoding="utf-8") as f:
                f.write(html)
            fetched += 1
            time.sleep(PAUSE)
        side = side_of(html)
        if side:
            sides[str(qid)] = side
        if n % 100 == 0:
            print(f"  {n}/{len(ids)}", file=sys.stderr)
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(sides, f, indent=0, sort_keys=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(sides, f, indent=0, sort_keys=True)
    counts = {}
    for v in sides.values():
        counts[v] = counts.get(v, 0) + 1
    print(f"{fetched} pages fetched, {len(sides)} sides known: {counts}, written to {args.out}")


if __name__ == "__main__":
    main()
