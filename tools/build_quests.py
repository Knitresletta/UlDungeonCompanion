#!/usr/bin/env python3
"""Build QuestData.lua: the dungeon quests and elite quests, their chains
and where they start.

Source is the vmangos world database as SQLite (mangos.sqlite from the
db-sqlite release zip of github.com/vmangos/core, tag db_latest). It is
vanilla 1.12 data, so quests that are new in Forever are not in it; the
addon learns those in play.

Usage:
    python3 -I tools/build_quests.py /path/mangos.sqlite -o QuestData.lua

A quest counts as a dungeon quest when any of these hold:
  - its Type is 81 (the client's "Dungeon" tag),
  - its quest log sort (ZoneOrSort) is an instance area,
  - a creature or object it needs is spawned (mostly) inside an instance,
  - an item it needs drops (mostly) from creatures or objects inside one,
  - the quest giver stands inside an instance.
An elite quest is Type 1 (the "Group" tag), a raid quest Type 62 or one
whose objectives are in a raid. Every prerequisite of a selected quest is
shipped too, so the addon can walk a chain back to the first undone step.
"""

import argparse
import os
import json
import sqlite3
import sys
from collections import Counter, defaultdict

PATCH = 10  # 1.12

# Instance map ID -> dungeon key (the key field in DungeonData.lua).
MAP_KEY = {
    389: "rfc", 43: "wc", 36: "deadmines", 33: "sfk", 34: "stockade", 48: "bfd",
    90: "gnomeregan", 47: "rfk", 189: "sm", 129: "rfd", 70: "uldaman", 209: "zf",
    349: "maraudon", 109: "st", 230: "brd", 229: "brs", 289: "scholo", 329: "strat",
    429: "dm", 249: "onyxia", 409: "mc", 469: "bwl", 309: "zg", 509: "aq20",
    531: "aq40", 533: "naxx",
}
RAID_KEYS = {"onyxia", "mc", "bwl", "zg", "aq20", "aq40", "naxx"}

# Quest log sort (ZoneOrSort, positive = area ID) -> dungeon key, for the
# instance areas. Cross-checked against the objectives by --check. Two
# outdoor areas sort under the instance's name in the quest log and hold
# nothing but its quests: 133 Gnomeregan (the surface area in Dun Morogh,
# where Tinkmaster Overspark's chains live) and 19 Zul'Gurub.
AREA_KEY = {
    133: "gnomeregan", 19: "zg",
    2437: "rfc", 718: "wc", 1581: "deadmines", 209: "sfk", 717: "stockade", 719: "bfd",
    721: "gnomeregan", 1717: "rfk", 796: "sm", 722: "rfd", 1517: "uldaman", 978: "zf",
    2100: "maraudon", 1417: "st", 1584: "brd", 1583: "brs", 2057: "scholo", 2017: "strat",
    2557: "dm", 2159: "onyxia", 2717: "mc", 2677: "bwl", 1977: "zg", 3429: "aq20",
    3428: "aq40", 3456: "naxx",
}

# Faction templates of quest givers that are clearly one side, used to
# give a quest with no race mask the mask of its giver's side. Read off
# the givers in the data (Marshal McBride is 12, Deathguard Linnea 68).
ALLIANCE_FACTIONS = {11, 12, 53, 55, 57, 64, 80, 84, 96, 122, 123, 124, 231, 534, 694, 875, 894, 1077, 1078}
HORDE_FACTIONS = {29, 68, 83, 104, 118, 125, 126, 876, 995, 1174}
RACES_ALLIANCE, RACES_HORDE = 77, 178
SIDE_MASK = {"Alliance": RACES_ALLIANCE, "Horde": RACES_HORDE}

# Quest -> creature that gives it, for quests the relation tables miss
# (given through gossip scripts). Disciple of Naralex stands inside the
# Wailing Caverns.
GIVER_OVERRIDES = {
    1500: 3678,   # Waking Naralex
    999: 3678,    # When Dreams Turn to Nightmares
}

TYPE_ELITE, TYPE_RAID, TYPE_DUNGEON = 1, 62, 81
FLAG_DUNGEON, FLAG_ELITE, FLAG_RAID = 1, 2, 4

MAX_POSITIONS = 3


def latest_rows(conn, table, key, patch_col="patch"):
    """Rows of a table that has one row per (key, patch): the newest row
    not newer than PATCH for each key, as dicts."""
    cols = [r[1] for r in conn.execute(f"pragma table_info({table})")]
    rows = {}
    for row in conn.execute(f"select * from {table} where {patch_col} <= ? order by {key}, {patch_col}", (PATCH,)):
        d = dict(zip(cols, row))
        rows[d[key]] = d
    return rows


def active(where=""):
    return f"patch_min <= {PATCH} and patch_max >= {PATCH}" + (f" and {where}" if where else "")


def load_spawns(conn):
    """creature entry -> Counter of map IDs, and entry -> positions on the
    continents (map 0/1) as (map, x, y). Same for game objects."""
    cmaps, cpos = defaultdict(Counter), defaultdict(list)
    for row in conn.execute(f"select id, id2, id3, id4, id5, map, position_x, position_y from creature where {active()}"):
        ids = [i for i in row[:5] if i]
        m, x, y = row[5], row[6], row[7]
        for cid in ids:
            cmaps[cid][m] += 1
            if m in (0, 1):
                cpos[cid].append((m, x, y))
    gmaps, gpos = defaultdict(Counter), defaultdict(list)
    for gid, m, x, y in conn.execute(f"select id, map, position_x, position_y from gameobject where {active()}"):
        gmaps[gid][m] += 1
        if m in (0, 1):
            gpos[gid].append((m, x, y))
    return cmaps, cpos, gmaps, gpos


def load_loot(conn, go_templates):
    """item -> list of (kind, entry) that drop it, through creature and
    object loot with references resolved one level deep."""
    refs = defaultdict(list)
    for entry, item, ref in conn.execute(f"select entry, item, mincountOrRef from reference_loot_template where {active()}"):
        refs[entry].append((item, ref))

    def expand(entry_items, out, owner):
        for item, ref in entry_items:
            if ref < 0:
                for ritem, rref in refs.get(-ref, ()):
                    if rref >= 0:
                        out[ritem].append(owner)
            else:
                out[item].append(owner)

    droppers = defaultdict(list)
    by_entry = defaultdict(list)
    for entry, item, ref in conn.execute(f"select entry, item, mincountOrRef from creature_loot_template where {active()}"):
        by_entry[entry].append((item, ref))
    for entry, items in by_entry.items():
        expand(items, droppers, ("c", entry))

    # Object loot templates are keyed by the loot ID in data1 of chest-type
    # objects (type 3); map loot ID -> object entries.
    loot_to_go = defaultdict(list)
    for entry, t in go_templates.items():
        if t["type"] == 3 and t["data1"]:
            loot_to_go[t["data1"]].append(entry)
    by_loot = defaultdict(list)
    for entry, item, ref in conn.execute(f"select entry, item, mincountOrRef from gameobject_loot_template where {active()}"):
        by_loot[entry].append((item, ref))
    for loot_id, items in by_loot.items():
        for go in loot_to_go.get(loot_id, ()):
            expand(items, droppers, ("g", go))
    return droppers


def instance_share(counter):
    """(instance map counts, outdoor count) for a spawn Counter."""
    inst = Counter()
    outdoor = 0
    for m, n in counter.items():
        if m in MAP_KEY:
            inst[MAP_KEY[m]] += n
        else:
            outdoor += n
    return inst, outdoor


def dominant_instance(counters):
    """Given spawn Counters of everything that provides an objective, the
    dungeon key most of it lives in, or None when most of it is outdoors."""
    inst, outdoor = Counter(), 0
    for c in counters:
        i, o = instance_share(c)
        inst.update(i)
        outdoor += o
    if not inst:
        return None
    key, n = inst.most_common(1)[0]
    return key if n >= outdoor else None


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db")
    ap.add_argument("-o", "--output", default="QuestData.lua")
    ap.add_argument("--check", action="store_true", help="print the area to dungeon cross-check")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    quests = latest_rows(conn, "quest_template", "entry")
    creatures = latest_rows(conn, "creature_template", "entry")
    objects = latest_rows(conn, "gameobject_template", "entry")
    items = latest_rows(conn, "item_template", "entry")
    cmaps, cpos, gmaps, gpos = load_spawns(conn)
    droppers = load_loot(conn, objects)

    starters = defaultdict(list)  # quest -> [(kind, entry)]
    for cid, q in conn.execute(f"select id, quest from creature_questrelation where {active()}"):
        starters[q].append(("c", cid))
    for gid, q in conn.execute(f"select id, quest from gameobject_questrelation where {active()}"):
        starters[q].append(("g", gid))
    for entry, it in items.items():
        if it["start_quest"]:
            starters[it["start_quest"]].append(("i", entry))
    for quest, creature in GIVER_OVERRIDES.items():
        if not starters.get(quest):
            starters[quest].append(("c", creature))

    if args.check:
        by_area = defaultdict(Counter)
        for q in quests.values():
            if q["Type"] != TYPE_DUNGEON:
                continue
            counters = []
            for i in range(1, 5):
                r = q[f"ReqCreatureOrGOId{i}"]
                if r > 0:
                    counters.append(cmaps.get(r, Counter()))
                elif r < 0:
                    counters.append(gmaps.get(-r, Counter()))
                it = q[f"ReqItemId{i}"]
                if it:
                    for kind, e in droppers.get(it, ()):
                        counters.append((cmaps if kind == "c" else gmaps).get(e, Counter()))
            key = dominant_instance(counters)
            by_area[q["ZoneOrSort"]][key] += 1
        for area in sorted(by_area):
            print(area, AREA_KEY.get(area, "-"), dict(by_area[area]), file=sys.stderr)
        return

    # Classify every quest.
    info = {}
    for qid, q in quests.items():
        keys = set()
        flags = 0
        if q["Type"] == TYPE_DUNGEON:
            flags |= FLAG_DUNGEON
        if q["Type"] == TYPE_ELITE:
            flags |= FLAG_ELITE
        if q["Type"] == TYPE_RAID:
            flags |= FLAG_RAID
        if q["ZoneOrSort"] in AREA_KEY:
            keys.add(AREA_KEY[q["ZoneOrSort"]])

        counters = []
        for i in range(1, 5):
            r = q[f"ReqCreatureOrGOId{i}"]
            if r > 0:
                counters.append(cmaps.get(r, Counter()))
            elif r < 0:
                counters.append(gmaps.get(-r, Counter()))
            it = q[f"ReqItemId{i}"]
            if it:
                for kind, e in droppers.get(it, ()):
                    counters.append((cmaps if kind == "c" else gmaps).get(e, Counter()))
        key = dominant_instance(counters)
        if key:
            keys.add(key)

        giver_inside = None
        for kind, e in starters.get(qid, ()):
            if kind == "c":
                inst, outdoor = instance_share(cmaps.get(e, Counter()))
            elif kind == "g":
                inst, outdoor = instance_share(gmaps.get(e, Counter()))
            else:
                continue
            if inst and outdoor == 0:
                giver_inside = inst.most_common(1)[0][0]
                keys.add(giver_inside)

        if keys:
            if keys & RAID_KEYS:
                flags |= FLAG_RAID
            if keys - RAID_KEYS:
                flags |= FLAG_DUNGEON
        info[qid] = {"flags": flags, "keys": keys, "giver_inside": giver_inside}

    # Placeholder quests ("<UNUSED>", "<NYI> <TXT> ...") exist in the
    # database but not on a live server. Skip them, and stop chains there.
    def placeholder(qid):
        return (quests[qid]["Title"] or "").startswith("<")

    # Select: dungeon, elite and raid quests, then every prerequisite.
    selected = {qid for qid, i in info.items() if i["flags"] and not placeholder(qid)}
    stack = list(selected)
    while stack:
        qid = stack.pop()
        prev = abs(quests[qid]["PrevQuestId"])
        if prev and prev in quests and prev not in selected and not placeholder(prev):
            selected.add(prev)
            stack.append(prev)

    # Chain membership: walk prev links to the root, so the addon knows
    # which dungeons a chain leads to without walking forward.
    def root_of(qid, seen=None):
        seen = seen or set()
        while True:
            prev = abs(quests[qid]["PrevQuestId"])
            if not prev or prev not in quests or prev in seen:
                return qid
            seen.add(qid)
            qid = prev

    chain_keys = defaultdict(set)
    chain_flags = defaultdict(int)
    for qid in selected:
        r = root_of(qid)
        chain_keys[r] |= info[qid]["keys"]
        chain_flags[r] |= info[qid]["flags"]

    out = []
    out.append("-- Quest Data: dungeon quests, elite quests, raid quests and every\n"
               "-- quest leading up to them. Generated by tools/build_quests.py from the\n"
               "-- vmangos 1.12 database; do not edit by hand.\n"
               "--\n"
               "-- [questID] = {\n"
               "--   t = title, l = quest level, m = minimum level,\n"
               "--   f = flags (1 dungeon, 2 elite, 4 raid) of this quest,\n"
               "--   cf = flags of the whole chain, d = dungeon keys of this quest,\n"
               "--   cd = dungeon keys of the whole chain (DungeonData keys),\n"
               "--   r = race mask (0 any; Alliance 77, Horde 178; a quest without a mask\n"
               "--       gets its giver's side), c = class mask (0 any),\n"
               "--   p = previous quest in the chain, x = exclusive group,\n"
               "--   g = givers { n = name, k = kind (c creature, g object, i item),\n"
               "--                c = continent, x, y = world position } (up to three\n"
               "--                positions each; none when the giver is inside an instance),\n"
               "--   gi = dungeon key when the giver stands inside that instance.\n"
               "-- }\n")
    out.append("UlDC.QUESTS = {")
    count = 0
    derived_races = 0
    sided_from_site = 0
    quest_sides = {}
    sides_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "quest_sides.json")
    if os.path.exists(sides_path):
        with open(sides_path, encoding="utf-8") as f:
            quest_sides = json.load(f)
    for qid in sorted(selected):
        q = quests[qid]
        i = info[qid]
        root = root_of(qid)
        fields = [
            f"t={lua_str(q['Title'] or '')}",
            f"l={q['QuestLevel']}",
            f"m={q['MinLevel']}",
        ]
        if i["flags"]:
            fields.append(f"f={i['flags']}")
        if chain_flags[root]:
            fields.append(f"cf={chain_flags[root]}")
        if i["keys"]:
            fields.append("d={" + ",".join(lua_str(k) for k in sorted(i["keys"])) + "}")
        if chain_keys[root]:
            fields.append("cd={" + ",".join(lua_str(k) for k in sorted(chain_keys[root])) + "}")
        races = q["RequiredRaces"]
        if not races:
            sides = set()
            for kind, e in starters.get(qid, ()):
                if kind == "c":
                    fac = creatures.get(e, {}).get("faction")
                    if fac in ALLIANCE_FACTIONS:
                        sides.add(RACES_ALLIANCE)
                    elif fac in HORDE_FACTIONS:
                        sides.add(RACES_HORDE)
            if len(sides) == 1:
                races = sides.pop()
                derived_races += 1
            # ForeverChanges knows the side of the rest (tools/quest_sides.json,
            # see fetch_sides.py); Alliance or Horde there wins, "Both" keeps
            # whatever the giver said.
            known = SIDE_MASK.get(quest_sides.get(str(qid)))
            if known:
                if races != known:
                    races = known
                    sided_from_site += 1
        if races:
            fields.append(f"r={races}")
        if q["RequiredClasses"]:
            fields.append(f"c={q['RequiredClasses']}")
        prev = abs(q["PrevQuestId"])
        if prev and prev in quests:
            fields.append(f"p={prev}")
        if q["ExclusiveGroup"]:
            fields.append(f"x={q['ExclusiveGroup']}")
        if i["giver_inside"]:
            fields.append(f"gi={lua_str(i['giver_inside'])}")
        givers = []
        for kind, e in starters.get(qid, ()):
            if kind == "c":
                name = creatures.get(e, {}).get("name", "?")
                positions = cpos.get(e, [])
            elif kind == "g":
                name = objects.get(e, {}).get("name", "?")
                positions = gpos.get(e, [])
            else:
                name = items.get(e, {}).get("name", "?")
                positions = []
            parts = [f"n={lua_str(name)}", f"k={lua_str(kind)}", f"id={e}"]
            seen = []
            for m, x, y in positions:
                # Skip positions within 50 yards of one already kept.
                if any(abs(x - sx) < 50 and abs(y - sy) < 50 for sm, sx, sy in seen if sm == m):
                    continue
                seen.append((m, x, y))
                if len(seen) >= MAX_POSITIONS:
                    break
            if seen:
                parts.append("pos={" + ",".join(f"{{{m},{x:.1f},{y:.1f}}}" for m, x, y in seen) + "}")
            givers.append("{" + ",".join(parts) + "}")
        if givers:
            fields.append("g={" + ",".join(givers) + "}")
        out.append(f"  [{qid}]={{{','.join(fields)}}},")
        count += 1
    out.append("}")

    with open(args.output, "w") as f:
        f.write("\n".join(out) + "\n")

    flagged = Counter()
    for qid in selected:
        fl = info[qid]["flags"]
        flagged["dungeon" if fl & FLAG_DUNGEON else "elite" if fl & FLAG_ELITE else "raid" if fl & FLAG_RAID else "prerequisite"] += 1
    print(f"{count} quests written to {args.output}: {dict(flagged)}", file=sys.stderr)
    no_giver = [qid for qid in selected if not starters.get(qid)]
    print(f"{len(no_giver)} without a known giver, {derived_races} given a side from their giver, "
          f"{sided_from_site} from ForeverChanges", file=sys.stderr)


if __name__ == "__main__":
    main()
