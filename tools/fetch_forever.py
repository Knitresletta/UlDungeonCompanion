#!/usr/bin/env python3
"""Build QuestDataForever.lua from saved ForeverChanges quest pages.

ForeverChanges (https://foreverchanges.pro) documents the quests Forever
added on top of vanilla, with givers and map positions read from the beta
client and Wowhead's Forever database. The vanilla data in QuestData.lua
comes from vmangos and does not know these quests, so this script fills
the gap for quests whose ID is not in vmangos.

Usage:
  python3 -I tools/fetch_forever.py fetch <dir>      download pages listed on /dungeon-quests (and chains) into <dir>
  python3 -I tools/fetch_forever.py build <dir> -o QuestDataForever.lua

Pages are Next.js "flight" payloads; the quest facts are React elements,
the map pins are plain JSON. Only positions as map percentages on retail
map IDs are available, so the addon converts them to world positions at
load time (see Quests.lua).
"""
import json
import os
import re
import sys
import time
import urllib.request

SITE = "https://foreverchanges.pro"
UA = "UlDungeonCompanion data build (contact: github.com/Knitresletta/UlDungeonCompanion)"
PAUSE = 0.7

# Dungeon names as ForeverChanges writes them in page titles -> DungeonData keys.
DUNGEON_KEY = {
    "The Hall of Thanes": "hot", "Hall of Thanes": "hot",
    "Ruins of Lordaeron": "rol",
    "Excavation Site: Wetlands": "excav", "Excavation Site": "excav",
    "City of Dalaran": "dalaran",
    "Ragefire Chasm": "rfc", "Wailing Caverns": "wc", "The Deadmines": "deadmines", "Deadmines": "deadmines",
    "Shadowfang Keep": "sfk", "The Stockade": "stockade", "Stormwind Stockade": "stockade",
    "Blackfathom Deeps": "bfd", "Gnomeregan": "gnomeregan", "Razorfen Kraul": "rfk",
    "Scarlet Monastery": "sm", "Razorfen Downs": "rfd", "Uldaman": "uldaman", "Zul'Farrak": "zf",
    "Maraudon": "maraudon", "Sunken Temple": "st", "The Temple of Atal'Hakkar": "st",
    "Blackrock Depths": "brd", "Blackrock Spire": "brs", "Lower Blackrock Spire": "brs", "Upper Blackrock Spire": "brs",
    "Dire Maul": "dm", "Scholomance": "scholo", "Stratholme": "strat",
}
RAID_KEYS = {"onyxia", "mc", "bwl", "zg", "aq20", "aq40", "naxx"}

# Zone names as written on /dungeon-quests -> retail map IDs (the ones the
# Forever client uses; Stormwind 1453 and Westfall 1436 verified in game).
ZONE_MAP = {
    "Dun Morogh": 1426, "Ironforge": 1455, "Elwynn Forest": 1429, "Stormwind City": 1453, "Westfall": 1436,
    "Redridge Mountains": 1433, "Duskwood": 1431, "Loch Modan": 1432, "Wetlands": 1437, "Arathi Highlands": 1417,
    "Hillsbrad Foothills": 1424, "Alterac Mountains": 1416, "Silverpine Forest": 1421, "Tirisfal Glades": 1420,
    "Undercity": 1458, "Stranglethorn Vale": 1434, "Badlands": 1418, "Swamp of Sorrows": 1435, "The Hinterlands": 1425,
    "Searing Gorge": 1427, "Burning Steppes": 1428, "Blasted Lands": 1419, "Western Plaguelands": 1422,
    "Eastern Plaguelands": 1423, "Deadwind Pass": 1430,
    "Durotar": 1411, "Orgrimmar": 1454, "Mulgore": 1412, "Thunder Bluff": 1456, "The Barrens": 1413,
    "Teldrassil": 1438, "Darnassus": 1457, "Darkshore": 1439, "Ashenvale": 1440, "Stonetalon Mountains": 1442,
    "Desolace": 1443, "Thousand Needles": 1441, "Dustwallow Marsh": 1445, "Feralas": 1444, "Tanaris": 1446,
    "Azshara": 1447, "Felwood": 1448, "Un'Goro Crater": 1449, "Moonglade": 1450, "Silithus": 1451, "Winterspring": 1452,
}
SIDE_MASK = {"Alliance": 77, "Horde": 178, "Both": 0}


def fetch(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    with open(dest, "wb") as f:
        f.write(data)
    time.sleep(PAUSE)


def payload_of(html):
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', html)
    return "".join(json.loads('"' + c + '"') for c in chunks)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse(html, qid):
    """Return a dict for one quest page, or None if the page has no quest."""
    p = payload_of(html)
    m = re.search(r'"children":"([^"]+?): level (\d+) quest(?: in ([^"·]+?))? · WoW Forever', p)
    if not m:
        return None
    title, level, where = m.group(1), int(m.group(2)), (m.group(3) or "").strip()
    q = {"id": qid, "t": title, "l": level}
    desc = re.search(r'"description","content":"([^"]*)"', p)
    desc = desc.group(1) if desc else ""
    mm = re.search(r"from level (\d+)", desc)
    q["m"] = int(mm.group(1)) if mm else None

    # Side and type are stated in the meta description ("A level 33 dungeon
    # quest for the Alliance, from level 24."); the facts list is split
    # across payload chunks and not safe to read.
    sm = re.search(r"A level \d+ (dungeon |elite |group |raid )?quest for (the Alliance|the Horde|both factions)", desc)
    side = {"the Alliance": "Alliance", "the Horde": "Horde", "both factions": "Both"}.get(sm.group(2)) if sm else ""
    q["r"] = SIDE_MASK.get(side)
    q["side"] = side
    q["type"] = (sm.group(1) or "").strip().capitalize() if sm else ""
    q["where"] = where
    q["d"] = DUNGEON_KEY.get(where)

    # Chain: the route is an ordered list of steps (li keyed by quest ID),
    # each step holding one or more quests (div.qp-route-quest keyed by ID).
    steps = []
    for li in re.finditer(r'\["\$","li","(\d+)",\{"className":(.*?)(?=\["\$","li","\d+",\{"className":|"qp-section-sub"|$)', p, re.S):
        ids = [int(x) for x in re.findall(r'\["\$","div","(\d+)",\{"className":"qp-route-quest', li.group(2))]
        if ids:
            steps.append(ids)
    q["steps"] = steps
    q["chain"] = [cid for step in steps for cid in step]
    mine = next((i for i, step in enumerate(steps) if qid in step), None)
    q["step"] = mine
    q["p"] = steps[mine - 1][0] if mine else None

    # Givers: zones JSON with start pins.
    givers = []
    zm = re.search(r'"zones":(\[\{.*?\}\]),"spawns"', p)
    for zone in re.finditer(r'\{"id":(\d+),"name":"([^"]*)","slug":"[^"]*","link":[^,]*,"pins":(\[[^\]]*\])', p):
        map_id, zone_name, pins = int(zone.group(1)), zone.group(2), json.loads(zone.group(3))
        for pin in pins:
            if pin.get("start"):
                givers.append({"n": pin.get("name", "?"), "map": map_id, "x": pin["x"], "y": pin["y"], "zone": zone_name})
    q["g"] = givers
    start = re.search(r'"Start"\]\}\],\["\$","dd",null,\{"children":\[\["\$","span","0",\{"children":\[false,"([^"]+)"', p)
    q["start"] = start.group(1) if start else None
    return q


def cmd_fetch(d):
    os.makedirs(d, exist_ok=True)
    index = os.path.join(d, "dungeon-quests.html")
    fetch(SITE + "/dungeon-quests", index)
    html = open(index, encoding="utf-8").read()
    todo = sorted({int(x) for x in re.findall(r'href="/quest/(\d+)"', html)})
    seen = set()
    while todo:
        qid = todo.pop(0)
        if qid in seen:
            continue
        seen.add(qid)
        dest = os.path.join(d, f"{qid}.html")
        if not os.path.exists(dest):
            fetch(f"{SITE}/quest/{qid}", dest)
        page = open(dest, encoding="utf-8").read()
        q = parse(page, qid)
        if q:
            for cid in q["chain"]:
                if cid not in seen:
                    todo.append(cid)
    print(f"{len(seen)} quest pages in {d}")


def overview_givers(d):
    """Giver name, zone and coordinates per quest from the /dungeon-quests
    table ("Where to take it"), for quest pages that carry no map pin."""
    path = os.path.join(d, "dungeon-quests.html")
    if not os.path.exists(path):
        return {}
    p = payload_of(open(path, encoding="utf-8").read())
    out = {}
    rows = re.split(r'(?="href":"/quest/\d+","lang")', p)
    for row in rows:
        m = re.match(r'"href":"/quest/(\d+)"', row)
        if not m:
            continue
        qid = int(m.group(1))
        w = re.search(r'"Where to take it","children":\[\["\$","a",null,\{"href":"[^"]*","children":"([^"]+)"\}\],\["\$","small",null,\{"children":\["([^"]+)",", ([0-9.]+), ([0-9.]+)"\]', row)
        if w and qid not in out:
            name, zone, x, y = w.group(1), w.group(2), float(w.group(3)), float(w.group(4))
            if zone in ZONE_MAP:
                out[qid] = {"n": name, "map": ZONE_MAP[zone], "x": x, "y": y, "zone": zone}
            else:
                print(f"  zone without map ID: {zone} (quest {qid})")
            continue
        # Giver named but without a map position (stands inside the instance).
        w = re.search(r'"Where to take it","children":\[\["\$","a",null,\{"href":"[^"]*","children":"([^"]+)"\}\]', row)
        if w and qid not in out:
            out[qid] = {"n": w.group(1)}
    return out


def cmd_build(d, out, vanilla_ids):
    quests = {}
    fallback = overview_givers(d)
    for name in os.listdir(d):
        if not re.fullmatch(r"\d+\.html", name):
            continue
        qid = int(name[:-5])
        q = parse(open(os.path.join(d, name), encoding="utf-8").read(), qid)
        if q:
            if not q["g"] and qid in fallback:
                if "map" in fallback[qid]:
                    q["g"] = [fallback[qid]]
                elif not q["start"]:
                    q["start"] = fallback[qid]["n"]
            quests[qid] = q
    new = {qid: q for qid, q in quests.items() if qid not in vanilla_ids}

    # Chain flags: walk forward through "chain" lists to find the dungeons a chain leads to.
    # A chain leads to a dungeon only through the quests from this step on;
    # follow-ups after the dungeon quest do not need the instance.
    chain_d = {}
    for q in new.values():
        keys = set()
        start = q["step"] or 0
        for step in q["steps"][start:]:
            for cid in step:
                cq = quests.get(cid)
                if cq and cq["d"] and cq["type"]:
                    keys.add(cq["d"])
        if q["d"] and q["type"]:
            keys.add(q["d"])
        chain_d[q["id"]] = keys

    lines = [
        "-- Quest Data, Forever additions: quests that exist on WoW: Forever but",
        "-- not in the vanilla database. Generated by tools/fetch_forever.py from",
        "-- ForeverChanges (https://foreverchanges.pro), which reads the beta",
        "-- client and Wowhead's Forever database; do not edit by hand.",
        "--",
        "-- Same fields as QuestData.lua, except giver positions are map",
        "-- percentages: mp = { mapID, x, y } (retail map IDs, 0 to 100).",
        "-- Quests.lua converts them to world positions when the addon loads.",
        "",
        "UlDC.QUESTS_FOREVER = {",
    ]
    n_dungeon = 0
    for qid in sorted(new):
        q = new[qid]
        f = 1 if q["type"] == "Dungeon" else (2 if q["type"] in ("Elite", "Group") else 0)
        keys = chain_d[qid]
        cf = 1 if keys else 0
        if f:
            n_dungeon += 1
        parts = [f"t={lua_str(q['t'])}", f"l={q['l']}"]
        if q["m"]:
            parts.append(f"m={q['m']}")
        if f:
            parts.append(f"f={f}")
        if cf:
            parts.append(f"cf={cf}")
        if q["d"]:
            parts.append(f'd={{"{q["d"]}"}}')
        if keys:
            parts.append("cd={" + ",".join(f'"{k}"' for k in sorted(keys)) + "}")
        if q["r"]:
            parts.append(f"r={q['r']}")
        if q["p"]:
            parts.append(f"p={q['p']}")
        if q["g"]:
            gs = ",".join("{n=%s,k=\"c\",mp={{%d,%.1f,%.1f}}}" % (lua_str(g["n"]), g["map"], g["x"], g["y"]) for g in q["g"])
            parts.append("g={" + gs + "}")
        elif q["start"]:
            parts.append(f"g={{{{n={lua_str(q['start'])},k=\"c\"}}}}")
            if q["d"]:
                parts.append(f'gi="{q["d"]}"')
        elif q["d"]:
            # No giver on any map and none named: starts from an item or
            # object found inside the instance.
            parts.append('g={{n="Item found inside",k="i"}}')
            parts.append(f'gi="{q["d"]}"')
        lines.append(f"  [{qid}]={{{','.join(parts)}}},")
    lines.append("}")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    sides = sorted({q["side"] for q in new.values()})
    types = sorted({q["type"] for q in new.values()})
    wheres = sorted({q["where"] for q in new.values()})
    nogiver = [q["id"] for q in new.values() if not q["g"]]
    print(f"{len(quests)} pages parsed, {len(new)} not in vanilla data, {n_dungeon} dungeon/elite, written to {out}")
    print("sides:", sides, "types:", types)
    print("places:", wheres)
    print("without map giver:", nogiver)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd, d = sys.argv[1], sys.argv[2]
    if cmd == "fetch":
        cmd_fetch(d)
    elif cmd == "build":
        out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else "QuestDataForever.lua"
        vanilla = set()
        here = os.path.dirname(os.path.abspath(__file__))
        qd = os.path.join(here, "..", "QuestData.lua")
        if os.path.exists(qd):
            vanilla = {int(x) for x in re.findall(r"^\s*\[(\d+)\]=", open(qd, encoding="utf-8").read(), re.M)}
        cmd_build(d, out, vanilla)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
