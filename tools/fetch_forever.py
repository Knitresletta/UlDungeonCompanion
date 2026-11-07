#!/usr/bin/env python3
"""Build QuestData.lua from ForeverChanges (https://foreverchanges.pro).

Forever changed quests, chains, levels and givers against vanilla 1.12,
so the addon's quest data comes from Forever sources only (Jonatan,
06.11.2026): ForeverChanges reads the Forever client and what the users
of its addon see in game. Nothing is taken from vanilla databases.

Usage:
  python3 -I tools/fetch_forever.py fetch [<cache>]   every quest page in the site's sitemap, plus the dungeon pages
  python3 -I tools/fetch_forever.py build [<cache>] -o QuestData.lua

<cache> (default ~/.cache/foreverchanges) keeps one HTML file per quest
(quest/<id>.html) and per dungeon (dungeons/<slug>.html). A file already
there is not fetched again, so a refresh only downloads what the sitemap
lists as new; delete a file to refetch it. The first fetch is about 5200
pages at 0.7 s each.

What is read, and from where:
  quest page   title, level, minimum level, side, type (dungeon, elite,
               raid), class, the instance it is for, the chain, start and
               end NPC, objective text, givers with map pins (map
               percentages on retail map IDs).
  dungeon page the quests of each instance (ids), the quest before each
               (prev) and the item that starts it, for quest pages that
               carry no chain or pin.
Pages are Next.js "flight" payloads: facts are React elements, map pins
plain JSON.
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
DEFAULT_CACHE = os.path.expanduser("~/.cache/foreverchanges")

# ForeverChanges dungeon page slug -> DungeonData key (wings share a key).
SLUG_KEY = {
    "hall-of-thanes": "hot", "ragefire-chasm": "rfc", "ruins-of-lordaeron": "rol",
    "wailing-caverns": "wc", "the-deadmines": "deadmines", "shadowfang-keep": "sfk",
    "blackfathom-deeps": "bfd", "the-stockade": "stockade", "excavation-site": "excav",
    "city-of-dalaran": "dalaran", "gnomeregan": "gnomeregan", "razorfen-kraul": "rfk",
    "scarlet-monastery-graveyard": "sm", "scarlet-monastery-library": "sm",
    "scarlet-monastery-armory": "sm", "scarlet-monastery-cathedral": "sm",
    "the-drowned-city": "drowned", "razorfen-downs": "rfd", "kroldok-stronghold": "kroldok",
    "uldaman": "uldaman", "zulfarrak": "zf", "maraudon": "maraudon", "alcaz-prison": "alcaz",
    "sunken-temple": "st", "blackrock-depths": "brd", "dire-maul-east": "dm",
    "dire-maul-north": "dm", "dire-maul-west": "dm", "blackmaw-hold": "blackmaw",
    "lower-blackrock-spire": "brs", "upper-blackrock-spire": "brs", "scholomance": "scholo",
    "shapers-terrace": "shapers", "stratholme-main-gate": "strat", "stratholme-service-gate": "strat",
}

# Instance names as quest page titles write them ("... quest in X") -> key.
NAME_KEY = {
    "The Hall of Thanes": "hot", "Hall of Thanes": "hot", "Ragefire Chasm": "rfc",
    "Ruins of Lordaeron": "rol", "Wailing Caverns": "wc", "The Deadmines": "deadmines",
    "Deadmines": "deadmines", "Shadowfang Keep": "sfk", "Blackfathom Deeps": "bfd",
    "The Stockade": "stockade", "Stormwind Stockade": "stockade",
    "Excavation Site: Wetlands": "excav", "Excavation Site": "excav", "City of Dalaran": "dalaran",
    "Gnomeregan": "gnomeregan", "Razorfen Kraul": "rfk", "Scarlet Monastery": "sm",
    "The Drowned City": "drowned", "Razorfen Downs": "rfd", "Krol'dok Stronghold": "kroldok",
    "Uldaman": "uldaman", "Zul'Farrak": "zf", "Maraudon": "maraudon", "Alcaz Prison": "alcaz",
    "Sunken Temple": "st", "The Temple of Atal'Hakkar": "st", "Blackrock Depths": "brd",
    "Dire Maul": "dm", "Blackmaw Hold": "blackmaw", "Blackrock Spire": "brs",
    "Lower Blackrock Spire": "brs", "Upper Blackrock Spire": "brs", "Scholomance": "scholo",
    "Shaper's Terrace": "shapers", "Stratholme": "strat",
    # Raids: the site has no dungeon pages for them, but quest pages name them.
    "Onyxia's Lair": "onyxia", "Molten Core": "mc", "Blackwing Lair": "bwl", "Zul'Gurub": "zg",
    "Ruins of Ahn'Qiraj": "aq20", "Ahn'Qiraj": "aq40", "Temple of Ahn'Qiraj": "aq40", "Naxxramas": "naxx",
}
RAID_KEYS = {"onyxia", "mc", "bwl", "zg", "aq20", "aq40", "naxx"}
# Quest list categories (/quests/<slug>) that are raids.
RAID_CAT = {"onyxias-lair": "onyxia", "molten-core": "mc", "molten-core-dungeon": "mc", "blackwing-lair": "bwl",
            "zulgurub": "zg", "ruins-of-ahnqiraj": "aq20", "ahnqiraj": "aq40", "naxxramas": "naxx"}

SIDE_MASK = {"Alliance": 77, "Horde": 178, "Both": 0}
CLASS_BIT = {"Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16, "Shaman": 64,
             "Mage": 128, "Warlock": 256, "Druid": 1024}

# Quests started by an item ForeverChanges knows no source for: a giver
# of kind "i" named after the item, with a position only when a Forever
# source says where it drops: "mp" (retail map ID, percent). Without one
# the hub says where the chain starts and sets no mark. Never a guess
# from vanilla spawns (Jonatan, 16.10.2026: the Dark Iron dwarves at the
# Stonewrought Dam had nothing).
ITEM_STARTS = {
    # Underground Map (Hall of Thanes chain). ForeverChanges and Wowhead list no
    # drop; the community guides agree (60forever, wowhandbook, Icy Veins,
    # MMONerds, Zockify, 16.10.2026): Dark Iron Spies at Ironband's Compound,
    # south-east Dun Morogh, 77.8, 61.0 (60forever). Seen in game 16.10.2026
    # (dropped from a Dark Iron Spy).
    96391: {"n": "Dark Iron Map, from Dark Iron Spies at Ironband's Compound",
            "mp": (1426, 77.8, 61.0)},
}

BREADCRUMB = re.compile(r"^(Speak|Talk) (with|to) ", re.I)


# ----------------------------------------------------------------------
# Fetching
# ----------------------------------------------------------------------

def fetch(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    with open(dest, "wb") as f:
        f.write(data)
    time.sleep(PAUSE)


def cmd_fetch(cache):
    qdir, ddir = os.path.join(cache, "quest"), os.path.join(cache, "dungeons")
    os.makedirs(qdir, exist_ok=True)
    os.makedirs(ddir, exist_ok=True)
    for slug in SLUG_KEY:
        dest = os.path.join(ddir, f"{slug}.html")
        if not os.path.exists(dest):
            fetch(f"{SITE}/dungeons/{slug}", dest)
    sitemap = os.path.join(cache, "quest-sitemap.xml")
    fetch(f"{SITE}/quest/sitemap.xml", sitemap)
    urls = re.findall(r"<loc>([^<]+)</loc>", open(sitemap, encoding="utf-8").read())
    done = failed = 0
    for i, url in enumerate(urls):
        qid = re.search(r"/quest/(\d+)", url).group(1)
        dest = os.path.join(qdir, f"{qid}.html")
        if os.path.exists(dest) and os.path.getsize(dest) > 1000:
            continue
        try:
            fetch(url, dest)
            done += 1
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"  {qid}: {e}")
            time.sleep(5)
        if (i + 1) % 250 == 0:
            print(f"  {i + 1} of {len(urls)} pages, {done} fetched", flush=True)
    print(f"{len(urls)} quest pages in the sitemap, {done} fetched now, {failed} failed, {len(SLUG_KEY)} dungeon pages")


# ----------------------------------------------------------------------
# Parsing
# ----------------------------------------------------------------------

def payload_of(html):
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', html)
    return "".join(json.loads('"' + c + '"') for c in chunks)


def json_objects(p, start_pat):
    """Every JSON object in the payload that starts at a match of start_pat."""
    out = []
    for m in re.finditer(start_pat, p):
        j = m.start()
        depth, instr, esc = 0, False, False
        for k in range(j, len(p)):
            c = p[k]
            if instr:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    instr = False
                continue
            if c == '"':
                instr = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    try:
                        out.append(json.loads(p[j:k + 1]))
                    except ValueError:
                        pass
                    break
    return out


def fact(p, name):
    """The plain-text dd of a facts-list dt, or None."""
    m = re.search(r'"children":"' + re.escape(name) + r'"\}\],\["\$","dd",null,\{"children":(?:\[)?"([^"]*)"', p)
    return m.group(1) if m else None


def npc_fact(p, name):
    m = re.search(r'"' + name + r'"\]\}\],\["\$","dd",null,\{"children":\[\["\$","span","0",\{"children":\[false,"([^"]+)"', p)
    return m.group(1) if m else None


def parse_quest(html, qid):
    """A dict for one quest page, or None when the page holds no quest."""
    p = payload_of(html)
    m = re.search(r'"children":"([^"]+?): level (\d+) quest(?: in ([^"·]+?))? · WoW Forever', p)
    if not m:
        return None
    q = {"id": qid, "t": m.group(1), "l": int(m.group(2)), "where": (m.group(3) or "").strip()}
    desc = re.search(r'"description","content":"([^"]*)"', p)
    desc = desc.group(1) if desc else ""
    mm = re.search(r"from level (\d+)", desc)
    q["m"] = int(mm.group(1)) if mm else None
    sm = re.search(r"A level \d+ (dungeon |elite |group |raid )?quest for (the Alliance|the Horde|both factions)", desc)
    side = {"the Alliance": "Alliance", "the Horde": "Horde", "both factions": "Both"}.get(sm.group(2)) if sm else ""
    q["side"] = side
    q["r"] = SIDE_MASK.get(side)
    q["type"] = (sm.group(1) or "").strip().lower() if sm else ""
    if not q["type"]:
        q["type"] = (fact(p, "Type") or "").lower()
    q["c"] = CLASS_BIT.get(fact(p, "Class") or "", 0)
    q["repeatable"] = fact(p, "Repeatable") is not None
    # The category the page sits under: a dungeon (link to /dungeons/<slug>),
    # a quest list (/quests/<slug>: zones, raids, classes) or a plain name.
    cm = re.search(r'"qp-crumbs".*?"children":"Quests"\}\],\[\["\$","span",null,\{"aria-hidden":"true","children":" › "\}\],'
                   r'\["\$","(?:span|a)",null,\{(?:"href":"/([a-z]+)/([^"/]+)",)?"children":"([^"]+)"', p)
    q["cat_kind"], q["cat_slug"], q["cat"] = (cm.group(1), cm.group(2), cm.group(3)) if cm else (None, None, "")
    # Chain: an ordered list of steps (li keyed by quest ID), each step
    # holding one or more quests (div.qp-route-quest keyed by ID).
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
    for zone in re.finditer(r'\{"id":(\d+),"name":"([^"]*)","slug":"[^"]*","link":[^,]*,"pins":(\[[^\]]*\])', p):
        map_id, pins = int(zone.group(1)), json.loads(zone.group(3))
        for pin in pins:
            if pin.get("start"):
                givers.append({"n": pin.get("name", "?"), "map": map_id, "x": pin["x"], "y": pin["y"]})
    q["g"] = givers
    q["start"] = npc_fact(p, "Start")
    q["end"] = npc_fact(p, "End")
    obj = re.search(r'"Quest Objectives"\}\],\[\["\$","p","0",\{"lang":"\$undefined","children":"([^"]*)"', p)
    q["objective"] = obj.group(1) if obj else ""
    return q


def parse_dungeon(html):
    """The quest records of one dungeon page: id -> record."""
    p = payload_of(html)
    out = {}
    for rec in json_objects(p, r'\{"id":\d+,"title":"'):
        if "title" in rec and isinstance(rec.get("id"), int):
            out.setdefault(rec["id"], rec)
    return out


# ----------------------------------------------------------------------
# Building
# ----------------------------------------------------------------------

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def instance_key(q):
    """The instance a quest page is about, by title, category or list."""
    if q["where"] in NAME_KEY:
        return NAME_KEY[q["where"]]
    if q["cat_kind"] == "dungeons" and q["cat_slug"] in SLUG_KEY:
        return SLUG_KEY[q["cat_slug"]]
    if q["cat_kind"] == "quests" and q["cat_slug"] in RAID_CAT:
        return RAID_CAT[q["cat_slug"]]
    if q["cat"] in NAME_KEY:
        return NAME_KEY[q["cat"]]
    return None


def breadcrumb_target(q, quests):
    """The quest a breadcrumb leads to: q starts a chain (no p), only says
    "speak with X", and X gives another quest of the set: the one right
    after q in the site's own chain when there is one (Speak with Shoni ->
    Underground Assault), else by preference one for the same instance
    (Seeking Caitlin has no chain on the site). A "speak with" quest
    inside a chain (Look to an Old Friend, p set) is a link, not a
    breadcrumb. None when q is no breadcrumb or X gives nothing we know."""
    if q["p"] or not q["end"] or not BREADCRUMB.match(q["objective"]):
        return None
    after = None
    if q["id"] in q["chain"]:
        i = q["chain"].index(q["id"])
        after = q["chain"][i + 1] if i + 1 < len(q["chain"]) else None
    found = []
    for other in quests.values():
        if other["id"] == q["id"]:
            continue
        names = {g["n"] for g in other["g"]} | ({other["start"]} if other["start"] else set())
        if q["end"] in names:
            found.append(other)
    if not found:
        return None
    found.sort(key=lambda o: (o["id"] != after, o["d"] != q["d"], o["id"]))
    return found[0]["id"]


def cmd_build(cache, out):
    qdir, ddir = os.path.join(cache, "quest"), os.path.join(cache, "dungeons")
    quests = {}
    for name in os.listdir(qdir):
        if re.fullmatch(r"\d+\.html", name):
            q = parse_quest(open(os.path.join(qdir, name), encoding="utf-8").read(), int(name[:-5]))
            if q:
                quests[q["id"]] = q
    listed = {}          # quest id -> (key, record) from the dungeon pages
    for name in sorted(os.listdir(ddir)):
        slug = name[:-5]
        if slug in SLUG_KEY:
            for qid, rec in parse_dungeon(open(os.path.join(ddir, name), encoding="utf-8").read()).items():
                listed.setdefault(qid, (SLUG_KEY[slug], rec))

    # Instance and flags of every quest. A quest is a dungeon quest when
    # the site types it so; the dungeon pages tie the whole chain to the
    # instance (cd) even when only the last step is typed dungeon.
    for q in quests.values():
        q["d"] = instance_key(q)
        if not q["d"] and q["id"] in listed:
            q["d"] = listed[q["id"]][0]
        if q["d"] in RAID_KEYS or q["type"] == "raid":
            q["f"] = 4
        elif q["type"] == "dungeon" and q["d"]:
            q["f"] = 1
        elif q["type"] in ("elite", "group"):
            q["f"] = 2
        else:
            q["f"] = 0
        # The site lists a quest under a dungeon when the dungeon is where
        # it is done, typed or not ("Oh Brother...", "Serpentbloom", the
        # elite-typed "Vorrel's Revenge"): that listing is the site's word
        # that it is a dungeon quest. The UBRS quests it types raid stay raid.
        if q["id"] in listed and q["f"] != 4:
            q["f"] |= 1
        if q["repeatable"]:
            q["f"] = 0
        # A chain link the quest page does not know: the dungeon page's
        # "prev" names the quest before it.
        if not q["p"] and q["id"] in listed:
            prev = listed[q["id"]][1].get("prev")
            if isinstance(prev, dict) and prev.get("title"):
                cands = [o for o in quests.values() if o["t"] == prev["title"] and o["id"] != q["id"]
                         and (o["d"] == q["d"] or o["id"] in listed)]
                if len(cands) == 1:
                    q["p"] = cands[0]["id"]

    # Keys of the chain from each quest on (follow-ups after the instance
    # quest do not need the instance).
    chain_d = {}
    for q in quests.values():
        keys = set()
        start = q["step"] or 0
        for step in q["steps"][start:]:
            for cid in step:
                cq = quests.get(cid)
                if cq and cq["d"] and cq["f"]:
                    keys.add(cq["d"])
        if q["d"] and q["f"]:
            keys.add(q["d"])
        if q["id"] in listed:
            keys.add(listed[q["id"]][0])
        chain_d[q["id"]] = keys

    for q in quests.values():
        q["b"] = breadcrumb_target(q, quests)

    # Which quests to write: every goal and every quest its chain walks
    # back through, plus breadcrumb targets.
    keep = set()
    todo = [qid for qid, q in quests.items() if q["f"]]
    while todo:
        qid = todo.pop()
        if qid in keep or qid not in quests:
            continue
        keep.add(qid)
        q = quests[qid]
        if q["p"]:
            todo.append(q["p"])
        if q["b"]:
            todo.append(q["b"])

    lines = [
        "-- Quest Data: dungeon quests, elite quests, raid quests and every quest",
        "-- leading up to one, as WoW: Forever has them. Generated by",
        "-- tools/fetch_forever.py from ForeverChanges (https://foreverchanges.pro),",
        "-- which reads the Forever client and what the users of its addon see in",
        "-- game. No vanilla data; do not edit by hand.",
        "--",
        "-- [questID] = {",
        "--   t = title, l = quest level, m = minimum level,",
        "--   f = flags (1 dungeon, 2 elite, 4 raid) of this quest,",
        "--   cf = flags of the whole chain, d = instance key of this quest,",
        "--   cd = instance keys of the whole chain (DungeonData keys),",
        "--   r = race mask (0 any; Alliance 77, Horde 178), c = class mask (0 any),",
        "--   p = previous quest in the chain,",
        "--   b = the quest a breadcrumb leads to (\"Speak with X\", and X gives",
        "--       that quest): the client hands out the follow-up directly, so the",
        "--       breadcrumb counts as done once b is in the log or done,",
        "--   g = givers { n = name, k = kind (c creature, i item),",
        "--                mp = { { mapID, x, y }, ... } map percentages on retail",
        "--                map IDs, converted to world positions at login },",
        "--       a giver without mp is named only (the hub shows the name),",
        "--   gi = instance key when the quest starts inside that instance.",
        "-- }",
        "",
        "UlDC.QUESTS = {",
    ]
    n_flag = {}
    for qid in sorted(keep):
        q = quests[qid]
        keys = chain_d[qid]
        cf = 0
        for k in keys:
            cf |= 4 if k in RAID_KEYS else 1
        if q["f"] & 2:
            cf |= 2
        if q["f"]:
            n_flag[q["f"]] = n_flag.get(q["f"], 0) + 1
        parts = [f"t={lua_str(q['t'])}", f"l={q['l']}"]
        if q["m"]:
            parts.append(f"m={q['m']}")
        if q["f"]:
            parts.append(f"f={q['f']}")
        if cf:
            parts.append(f"cf={cf}")
        if q["d"]:
            parts.append(f'd={{"{q["d"]}"}}')
        if keys:
            parts.append("cd={" + ",".join(f'"{k}"' for k in sorted(keys)) + "}")
        if q["r"]:
            parts.append(f"r={q['r']}")
        if q["c"]:
            parts.append(f"c={q['c']}")
        if q["p"]:
            parts.append(f"p={q['p']}")
        if q["b"]:
            parts.append(f"b={q['b']}")
        rec = listed.get(qid, (None, {}))[1]
        giver = rec.get("giver") if isinstance(rec.get("giver"), list) else None
        inside = bool(q["d"] and giver and len(giver) > 1 and NAME_KEY.get(giver[1]) == q["d"])
        if qid in ITEM_STARTS and not q["g"]:
            it = ITEM_STARTS[qid]
            if it.get("mp"):
                parts.append("g={{n=%s,k=\"i\",mp={{%d,%.1f,%.1f}}}}" % (lua_str(it["n"]), *it["mp"]))
            else:
                parts.append("g={{n=%s,k=\"i\"}}" % lua_str(it["n"]))
        elif q["g"]:
            gs = ",".join("{n=%s,k=\"c\",mp={{%d,%.1f,%.1f}}}" % (lua_str(g["n"]), g["map"], g["x"], g["y"]) for g in q["g"])
            parts.append("g={" + gs + "}")
        elif rec.get("starts"):
            parts.append("g={{n=%s,k=\"i\"}}" % lua_str("Item: " + rec["starts"]))
            if q["d"]:
                parts.append(f'gi="{q["d"]}"')
        elif q["start"] or (giver and giver[0]):
            name = q["start"] or giver[0]
            parts.append(f"g={{{{n={lua_str(name)},k=\"c\"}}}}")
            if inside or (q["d"] and not giver):
                parts.append(f'gi="{q["d"]}"')
        elif q["d"]:
            parts.append('g={{n="Item found inside",k="i"}}')
            parts.append(f'gi="{q["d"]}"')
        lines.append(f"  [{qid}]={{{','.join(parts)}}},")
    lines.append("}")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    crumbs = [(q["id"], q["t"], q["b"]) for q in quests.values() if q["id"] in keep and q["b"]]
    nogiver = [qid for qid in sorted(keep) if not quests[qid]["g"] and not quests[qid]["start"]
               and not (listed.get(qid, (None, {}))[1].get("giver")) and qid not in ITEM_STARTS]
    print(f"{len(quests)} quest pages, {len(listed)} on dungeon pages, {len(keep)} written to {out}: "
          f"{n_flag.get(1, 0)} dungeon, {n_flag.get(2, 0)} elite, {n_flag.get(4, 0)} raid")
    print("instances:", sorted({q['d'] for q in quests.values() if q['d']}))
    print("types seen:", sorted({q['type'] for q in quests.values()}))
    print("breadcrumbs:", crumbs)
    print("without any giver:", nogiver)


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("fetch", "build"):
        print(__doc__)
        sys.exit(1)
    out = args[args.index("-o") + 1] if "-o" in args else "QuestData.lua"
    positional = [a for i, a in enumerate(args[1:], 1) if not a.startswith("-") and args[i - 1] != "-o"]
    cache = positional[0] if positional else DEFAULT_CACHE
    if args[0] == "fetch":
        cmd_fetch(cache)
    else:
        cmd_build(cache, out)


if __name__ == "__main__":
    main()
