#!/usr/bin/env python3
"""Build LootData.lua from the vmangos 1.12 database: the notable drops
inside every instance, by the creature that drops them.

A creature counts as a loot source when it is spawned inside an instance
map (creature.map) and its loot table, after following references, holds
an uncommon item at 10 % or more or a rare-or-better item at 3 % or more.
That picks the bosses and the named mini-bosses without a boss flag in
the data (Edwin VanCleef is rank 2, Rhahk'Zor rank 1) and leaves out the
trash mobs with their fractions of a percent for random world drops.
Bosses the instance scripts spawn (Grubbis, Sneed, Mutanus, Kirtonos,
the Blackrock Depths arena) have no spawn row, so BOSSES lists them by
hand, and lists the few spawned bosses whose drops fall under the source
threshold (Rhahk'Zor, the Stockade's quest bosses); a listed boss keeps
its greens from 1 % and is written even when nothing is left. Once a creature is a source, its rare-or-better
items from 1 % and uncommon items from 3 % are kept. Quest drops
(negative chance) are not loot. Chests (gameobject type 3) spawned in
the instance go through the same sieve, with level 0.

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

SOURCE_MIN = {2: 10.0, 3: 3.0, 4: 3.0, 5: 3.0}   # quality -> chance that makes a creature a source
KEEP_MIN = {2: 3.0, 3: 1.0, 4: 1.0, 5: 1.0}       # quality -> lowest chance kept for a source
KEEP_MIN_BOSS = {2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0}  # same for a creature in BOSSES: its named greens count
MAX_ITEMS_PER_SOURCE = 40

# Creatures that belong to an instance without a spawn row there (spawned
# by the instance script or an event) or whose drops fall under the
# source threshold. creature_template entries.
BOSSES = {
    "deadmines": [643, 644],                 # Sneed, Rhahk'Zor
    "stockade": [1696, 1666, 1717, 1716, 1663],
                                             # Targorr, Kam Deepfury, Hamhock, Bazil Thredd, Dextren Ward: quest bosses
                                             # with world drops only in 1.12, listed so the instance is not empty
    "wc": [3654],                            # Mutanus the Devourer
    "gnomeregan": [7361],                    # Grubbis
    "rfd": [7355, 7356],                     # Tuten'kash, Plaguemaw the Rotting
    "zf": [7273, 7275],                      # Gahz'rilla, Shadowpriest Sezz'ziz
    "st": [8443],                            # Avatar of Hakkar
    "brd": [9027, 9028, 9029, 9030, 9031, 9032, 9537, 10076],
                                             # the arena: Gorosh, Grizzle, Eviscerator, Ok'thor, Anub'shiah, Hedrum;
                                             # Hurley Blackbreath, High Priestess of Thaurissan
    "brs": [9596, 10263, 10264, 10268, 10339, 10584],
                                             # Bannok Grimaxe, Burning Felguard, Solakar Flamewreath, Gizrul, Gyth, Urok Doomhowl
    "scholo": [1853, 10506, 14516],          # Darkmaster Gandling, Kirtonos the Herald, Death Knight Darkreaver
    "strat": [10439, 10516, 10808, 10813, 11120, 11121, 11143],
                                             # Ramstein, The Unforgiven, Timmy the Cruel, Balnazzar,
                                             # Crimson Hammersmith, Black Guard Swordsmith, Postmaster Malown
    "dm": [14506],                           # Lord Hel'nurath
    "zg": [14515, 15082, 15083, 15084, 15085],
                                             # High Priestess Arlokk; Edge of Madness: Gri'lek, Hazza'rah, Renataki, Wushoolay
    "bwl": [11583, 12463, 12464, 12465],     # Nefarian; Death Talon Flamescale, Seether, Wyrmkin
    "mc": [11502],                           # Ragnaros
    "aq40": [15517],                         # Ouro
    "naxx": [15989],                         # Sapphiron
}


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
    gameobject_loot = loot_table(conn, "gameobject_loot_template")
    refs = loot_table(conn, "reference_loot_template")
    chests = latest_rows(conn, "gameobject_template", "entry")

    # Which creatures stand in which instance.
    in_map = defaultdict(set)
    for cid, map_id in conn.execute(
            "select distinct id, map from creature where patch_min <= ? and patch_max >= ?", (PATCH, PATCH)):
        if map_id in MAP_KEY:
            in_map[MAP_KEY[map_id]].add(cid)

    # Chests spawned in each instance, keyed like the creatures.
    go_cols = [r[1] for r in conn.execute("pragma table_info(gameobject)")]
    go_where = "where patch_min <= ? and patch_max >= ?" if "patch_min" in go_cols else ""
    go_args = (PATCH, PATCH) if go_where else ()
    go_in_map = defaultdict(set)
    for gid, map_id in conn.execute(f"select distinct id, map from gameobject {go_where}", go_args):
        if map_id in MAP_KEY:
            go_in_map[MAP_KEY[map_id]].add(gid)

    per_key = {}
    for key in sorted(set(in_map) | set(BOSSES) | set(go_in_map)):
        cids = set(in_map.get(key, ())) | set(BOSSES.get(key, ()))
        sources = []
        candidates = [("c", cid) for cid in cids] + [("g", gid) for gid in go_in_map.get(key, ())]
        for kind, cid in candidates:
            if kind == "c":
                ct = creatures.get(cid)
                if not ct or not ct["loot_id"]:
                    continue
                drops = resolve(creature_loot.get(ct["loot_id"], []), refs)
            else:
                ct = chests.get(cid)
                if not ct or ct["type"] != 3 or not ct["data1"]:
                    continue
                if ct["name"].endswith((" Vein", " Deposit")):
                    continue        # mining nodes are chests too
                ct = {"name": ct["name"], "level_max": 0}
                drops = resolve(gameobject_loot.get(chests[cid]["data1"], []), refs)
            forced = kind == "c" and cid in BOSSES.get(key, ())
            is_source = forced
            keep_min = KEEP_MIN_BOSS if forced else KEEP_MIN
            kept = []
            for item_id, chance in drops.items():
                it = items.get(item_id)
                if not it:
                    continue
                q = it["quality"]
                # A chest has to hold something rare; herbs and the odd
                # green are not worth a line.
                if q in SOURCE_MIN and chance >= SOURCE_MIN[q] and (kind == "c" or q >= 3):
                    is_source = True
                if q in keep_min and chance >= keep_min[q]:
                    kept.append((item_id, it, chance))
            # A listed boss stays in the list even with nothing to show.
            if not is_source or (not kept and not forced):
                continue
            kept.sort(key=lambda t: (-t[1]["quality"], -t[2], t[1]["name"]))
            sources.append({
                "id": cid, "name": ct["name"], "level": ct["level_max"],
                "items": kept[:MAX_ITEMS_PER_SOURCE],
            })
        # Chests (level 0) after the creatures.
        sources.sort(key=lambda s: (s["level"] == 0, s["level"], s["name"]))
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
