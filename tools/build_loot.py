#!/usr/bin/env python3
"""Build LootData.lua from the vmangos 1.12 database: the notable drops
inside every instance, by the creature that drops them.

A creature counts as a loot source when it is spawned inside an instance
map (creature.map) and its loot table, after following references, holds
an uncommon item at 10 % or more or a rare-or-better item at 3 % or more.
That picks the bosses and the named mini-bosses without a boss flag in
the data (Edwin VanCleef is rank 2, Rhahk'Zor rank 1) and leaves out the
trash mobs with their fractions of a percent for random world drops.
Quest drops (negative chance) are not loot.

Chance: a loot row is a straight percentage, or a group where exactly one
member drops and members without a chance share what is left equally. A
reference row (mincountOrRef < 0) pulls in another table with the row's
chance as the multiplier.

Usage: python3 -I tools/build_loot.py <mangos.sqlite> -o LootData.lua
       add --stats to print one line per instance to stderr.
"""

import argparse
import sqlite3
import sys
from collections import defaultdict

PATCH = 10  # 1.12

# Instance map ID -> dungeon key (the key field in DungeonData.lua).
MAP_KEY = {
    389: "rfc", 43: "wc", 36: "deadmines", 33: "sfk", 34: "stockade", 48: "bfd",
    90: "gnomeregan", 47: "rfk", 189: "sm", 129: "rfd", 70: "uldaman", 209: "zf",
    349: "maraudon", 109: "st", 230: "brd", 229: "brs", 289: "scholo", 329: "strat",
    429: "dm", 249: "onyxia", 409: "mc", 469: "bwl", 309: "zg", 509: "aq20",
    531: "aq40", 533: "naxx",
}

MIN_CHANCE = {2: 10.0, 3: 3.0, 4: 3.0, 5: 3.0}   # quality -> lowest chance kept
MAX_ITEMS_PER_SOURCE = 40


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def latest_rows(conn, table, key):
    """One row per key: the newest patch row not newer than PATCH."""
    cols = [r[1] for r in conn.execute(f"pragma table_info({table})")]
    rows = {}
    for r in conn.execute(f"select * from {table} where patch <= ? order by patch", (PATCH,)):
        d = dict(zip(cols, r))
        rows[d[key]] = d
    return rows


def loot_table(conn, table):
    """entry -> list of rows live in PATCH."""
    out = defaultdict(list)
    for entry, item, chance, group, ref, maxcount in conn.execute(
            f"select entry, item, ChanceOrQuestChance, groupid, mincountOrRef, maxcount from {table} "
            "where patch_min <= ? and patch_max >= ?", (PATCH, PATCH)):
        out[entry].append({"item": item, "chance": chance, "group": group, "ref": ref})
    return out


def resolve(rows, refs, multiplier=1.0, depth=0):
    """Effective drop chance per item for one loot table, references
    followed, groups spread."""
    out = defaultdict(float)
    if depth > 3:
        return out
    groups = defaultdict(list)
    for r in rows:
        if r["chance"] < 0:
            continue            # quest drop
        if r["group"]:
            groups[r["group"]].append(r)
        else:
            if r["ref"] < 0:
                for item, c in resolve(refs.get(-r["ref"], []), refs, multiplier * r["chance"] / 100.0, depth + 1).items():
                    out[item] += c
            else:
                out[r["item"]] += multiplier * r["chance"]
    for members in groups.values():
        fixed = sum(m["chance"] for m in members if m["chance"] > 0)
        free = [m for m in members if m["chance"] == 0]
        rest = max(0.0, 100.0 - fixed)
        for m in members:
            chance = m["chance"] if m["chance"] > 0 else (rest / len(free) if free else 0.0)
            if m["ref"] < 0:
                for item, c in resolve(refs.get(-m["ref"], []), refs, multiplier * chance / 100.0, depth + 1).items():
                    out[item] += c
            else:
                out[m["item"]] += multiplier * chance
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db")
    ap.add_argument("-o", "--out", default="LootData.lua")
    ap.add_argument("--stats", action="store_true")
    args = ap.parse_args()
    conn = sqlite3.connect(args.db)

    creatures = latest_rows(conn, "creature_template", "entry")
    items = latest_rows(conn, "item_template", "entry")
    creature_loot = loot_table(conn, "creature_loot_template")
    refs = loot_table(conn, "reference_loot_template")

    # Which creatures stand in which instance.
    in_map = defaultdict(set)
    for cid, map_id in conn.execute(
            "select distinct id, map from creature where patch_min <= ? and patch_max >= ?", (PATCH, PATCH)):
        if map_id in MAP_KEY:
            in_map[MAP_KEY[map_id]].add(cid)

    per_key = {}
    for key, cids in in_map.items():
        sources = []
        for cid in cids:
            ct = creatures.get(cid)
            if not ct or not ct["loot_id"]:
                continue
            drops = resolve(creature_loot.get(ct["loot_id"], []), refs)
            kept = []
            for item_id, chance in drops.items():
                it = items.get(item_id)
                if not it:
                    continue
                q = it["quality"]
                if q in MIN_CHANCE and chance >= MIN_CHANCE[q]:
                    kept.append((item_id, it, chance))
            if not kept:
                continue
            kept.sort(key=lambda t: (-t[1]["quality"], -t[2], t[1]["name"]))
            sources.append({
                "id": cid, "name": ct["name"], "level": ct["level_max"],
                "items": kept[:MAX_ITEMS_PER_SOURCE],
            })
        sources.sort(key=lambda s: (s["level"], s["name"]))
        per_key[key] = sources
        if args.stats:
            n_items = sum(len(s["items"]) for s in sources)
            print(f"{key:12s} {len(sources):3d} sources {n_items:4d} items: "
                  + ", ".join(s["name"] for s in sources[:8]) + (" ..." if len(sources) > 8 else ""), file=sys.stderr)

    out = []
    out.append("-- Loot Data: the notable drops inside every instance, by the creature\n"
               "-- that drops them. Generated by tools/build_loot.py from the vmangos\n"
               "-- 1.12 database; do not edit by hand. Forever may have retuned loot.\n"
               "--\n"
               "-- UlDC.LOOT[dungeonKey] = { { n = creature name, l = level, items = {\n"
               "--   { itemID, name, quality, chance (%), item class, subclass,\n"
               "--     inventory type, allowable class mask (-1 any) }, ... } }, ... }\n"
               "-- Creatures in level order; items by quality, then chance.\n")
    out.append("UlDC.LOOT = {")
    total_items = 0
    for key in sorted(per_key):
        out.append(f"  [{lua_str(key)}] = {{")
        for s in per_key[key]:
            out.append(f"    {{ n={lua_str(s['name'])}, l={s['level']}, items={{")
            for item_id, it, chance in s["items"]:
                total_items += 1
                out.append("      {%d,%s,%d,%d,%d,%d,%d,%d}," % (
                    item_id, lua_str(it["name"]), it["quality"], round(chance),
                    it["class"], it["subclass"], it["inventory_type"], it["allowable_class"]))
            out.append("    } },")
        out.append("  },")
    out.append("}\n")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"{len(per_key)} instances, {sum(len(v) for v in per_key.values())} loot sources, "
          f"{total_items} items written to {args.out}")


if __name__ == "__main__":
    main()
