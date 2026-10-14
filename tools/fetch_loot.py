#!/usr/bin/env python3
"""Build LootDataForever.lua from the ForeverChanges dungeon pages
(https://foreverchanges.pro/dungeons/<slug>): every boss and rare spawn
with its drops as the beta shows them, Forever's own additions included
("New"). Dungeons only; the site has no raid pages, so the raids keep the
vanilla data from build_loot.py.

The pages are Next.js: the data sits in the self.__next_f.push payload as
JSON. Each page has "bosses": [ { name, kind (boss or rare), level,
items: [ { i item ID, n name, q quality, l item level, r required level,
s slot text, c item class, u subclass, t status (new, changed, ...),
z drop chance in percent when the site knows it } ] } ].

Usage: python3 -I tools/fetch_loot.py -o LootDataForever.lua
       --cache <dir> keeps the downloaded pages (default: no cache),
       --from <dir> builds from pages saved earlier instead of fetching.
robots.txt allows /dungeons; one request every 0.7 s.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request

BASE = "https://foreverchanges.pro"
AGENT = "UlDungeonCompanion/0.11 (knitresletta)"
PAUSE = 0.7

# Page slug -> (DungeonData key, wing name or None). Wings share a key and
# their bosses are listed with the wing name.
SLUG_KEY = {
    "ragefire-chasm": ("rfc", None), "wailing-caverns": ("wc", None), "the-deadmines": ("deadmines", None),
    "shadowfang-keep": ("sfk", None), "the-stockade": ("stockade", None), "blackfathom-deeps": ("bfd", None),
    "gnomeregan": ("gnomeregan", None), "razorfen-kraul": ("rfk", None),
    "scarlet-monastery-graveyard": ("sm", "Graveyard"), "scarlet-monastery-library": ("sm", "Library"),
    "scarlet-monastery-armory": ("sm", "Armory"), "scarlet-monastery-cathedral": ("sm", "Cathedral"),
    "razorfen-downs": ("rfd", None), "uldaman": ("uldaman", None), "zulfarrak": ("zf", None),
    "maraudon": ("maraudon", None), "sunken-temple": ("st", None), "blackrock-depths": ("brd", None),
    "lower-blackrock-spire": ("brs", "Lower"), "upper-blackrock-spire": ("brs", "Upper"),
    "scholomance": ("scholo", None),
    "stratholme-main-gate": ("strat", "Main gate"), "stratholme-service-gate": ("strat", "Service gate"),
    "dire-maul-east": ("dm", "East"), "dire-maul-north": ("dm", "North"), "dire-maul-west": ("dm", "West"),
    # Forever's own. The last five have no DungeonData entry yet; the keys
    # are reserved so the loot is ready when the entrances are.
    "hall-of-thanes": ("hot", None), "ruins-of-lordaeron": ("rol", None), "excavation-site": ("excav", None),
    "city-of-dalaran": ("dalaran", None), "the-drowned-city": ("drowned", None),
    "kroldok-stronghold": ("kroldok", None), "alcaz-prison": ("alcaz", None),
    "blackmaw-hold": ("blackmaw", None), "shapers-terrace": ("shapers", None),
}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def payload(html):
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', html)
    return "".join(json.loads('"' + c + '"') for c in chunks)


def bosses_from(html):
    text = payload(html)
    i = text.find('"bosses":[{"name"')
    if i < 0:
        return []
    start = text.index("[", i)
    depth = 0
    in_str = False
    esc = False
    for j in range(start, len(text)):
        ch = text[j]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return json.loads(text[start:j + 1])
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="LootDataForever.lua")
    ap.add_argument("--cache", help="directory to keep the downloaded pages in")
    ap.add_argument("--from", dest="src", help="build from pages saved in this directory, no download")
    args = ap.parse_args()

    def page(slug):
        name = f"dungeons_{slug}.html"
        if args.src:
            with open(os.path.join(args.src, name), encoding="utf-8") as f:
                return f.read()
        html = fetch(f"/dungeons/{slug}")
        if args.cache:
            os.makedirs(args.cache, exist_ok=True)
            with open(os.path.join(args.cache, name), "w", encoding="utf-8") as f:
                f.write(html)
        time.sleep(PAUSE)
        return html

    if args.src:
        slugs = [f[len("dungeons_"):-len(".html")] for f in sorted(os.listdir(args.src)) if f.startswith("dungeons_")]
    else:
        index = fetch("/dungeons")
        time.sleep(PAUSE)
        slugs = sorted(set(re.findall(r'href="/dungeons/([a-z0-9-]+)"', index)))
    unknown = [s for s in slugs if s not in SLUG_KEY]
    if unknown:
        print("slugs without a key, skipped: " + ", ".join(unknown), file=sys.stderr)

    per_key = {}
    seen = {}
    for slug in slugs:
        if slug not in SLUG_KEY:
            continue
        key, wing = SLUG_KEY[slug]
        bosses = bosses_from(page(slug))
        if not bosses:
            print(f"{slug}: no bosses found", file=sys.stderr)
            continue
        lst = per_key.setdefault(key, [])
        for b in bosses:
            name = b.get("name", "?")
            if (key, name) in seen:
                continue
            seen[(key, name)] = True
            items = []
            for it in b.get("items", []):
                # The site lists everything ever seen: quest items, junk,
                # and world drops at a fraction of a percent. Keep what a
                # player would go there for; a missing chance is kept,
                # that is where the new items are.
                if it.get("s") == "Quest" or (it.get("q") or 0) < 2:
                    continue
                # Equipment and recipes only, unless it is epic (mounts, trinkets without a slot text).
                if not it.get("s") and (it.get("c") or 0) not in (2, 4, 9) and (it.get("q") or 0) < 4:
                    continue
                chance = it.get("z") or 0
                if 0 < chance < 1:
                    continue
                it["z"] = round(chance, 1)
                items.append(it)
            level = b.get("level") or 0
            if isinstance(level, list):     # a range, [45, 46]
                level = max(level)
            lst.append({"name": name, "kind": b.get("kind") or "boss", "level": level,
                        "wing": wing, "items": items})
        print(f"{slug}: {len(bosses)} bosses", file=sys.stderr)

    total = 0
    out = ["-- Loot Data (Forever): the drops inside every dungeon as the beta shows\n"
           "-- them, by boss, from the ForeverChanges dungeon pages. Generated by\n"
           "-- tools/fetch_loot.py; do not edit by hand. Raids are not on the site and\n"
           "-- keep the vanilla data in LootData.lua.\n"
           "--\n"
           "-- UlDC.LOOT_FOREVER[dungeonKey] = { { n = boss, l = level, kind = boss|rare,\n"
           "--   w = wing or nil, items = { { itemID, name, quality, chance (0 unknown),\n"
           "--   item class, subclass, 0, -1, slot text, status (new|changed|same) } } } }\n"
           "-- The first eight item fields match LootData.lua. Quest items, junk\n-- and drops under 1 % are left out; an unknown chance is written as 0.\n"]
    out.append("UlDC.LOOT_FOREVER = {")
    for key in sorted(per_key):
        out.append(f"  [{lua_str(key)}] = {{")
        for b in per_key[key]:
            wing = f", w={lua_str(b['wing'])}" if b["wing"] else ""
            out.append(f"    {{ n={lua_str(b['name'])}, l={int(b['level'] or 0)}, kind={lua_str(b['kind'])}{wing}, items={{")
            for it in b["items"]:
                total += 1
                chance = it.get("z") or 0
                out.append("      {%d,%s,%d,%s,%d,%d,0,-1,%s,%s}," % (
                    int(it.get("i") or 0), lua_str(it.get("n") or "?"), int(it.get("q") or 1),
                    ("%g" % chance), int(it.get("c", 0) or 0), int(it.get("u", 0) or 0),
                    lua_str(it.get("s") or ""), lua_str(it.get("t") or "same")))
            out.append("    } },")
        out.append("  },")
    out.append("}\n")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"{len(per_key)} dungeons, {sum(len(v) for v in per_key.values())} bosses, {total} items written to {args.out}")


if __name__ == "__main__":
    main()
