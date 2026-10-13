# CLAUDE.md, UlDungeonCompanion

WoW: Forever-addon som finner dungeons, dungeonquests og elitequests som passer spillerens nivå, på verdenskartet og i et eget vindu. For spillere som vil leve på egen hånd, men ikke gå glipp av gruppeinnholdet. Jonatans main er resto-druid, men addonen skal virke for alle klasser og begge fraksjoner.

## Modus

**Lever ferdig** (bestemt 13.10.2026): jeg skriver koden, Jonatan tester i spillet. Samme arbeidsflyt som UlRemedyForever (`~/prosjekter/claude/UlRemedyForever/`), som er referansen for struktur, stil og rutiner. Ingen kode deles mellom de to; mønstre gjenbrukes, filer kopieres ikke.

## Definisjoner (Jonatans, 13.10.2026)

- **Dungeonquest:** et enkelt quest eller en questkjede som på et eller annet punkt krever at man går inn i en instans (giver står der inne, et mål skal drepes eller plukkes der, eller et område utforskes der). Hele kjeden teller, og addonen peker på det første ugjorte steget.
- **Elitequest:** gruppequest i åpen verden (vanilla quest_template Type 1; Type 81 er dungeon).
- **Nivåpassende:** avgjøres mot spillerens nivå med spillets egne vanskelighetsfarger. Klasse, rase og fraksjon leses fra klienten, dataene bærer maskene for alle.

## Struktur

- Mappa er selve repoet. Flate Lua-filer, én modul per funksjon, listet i TOC-rekkefølge.
- `Core.lua` eier `UlDC` (global tabell), `UlDungeonCompanionDB`, `FEATURES` (én linje per av/på-funksjon) og `COMMANDS` (resten av `/udc`). `Options.lua` tegner vinduet fra de to tabellene. Moduler henger funksjoner på `UlDC` og Core kaller dem bare hvis de finnes.
- `DungeonData.lua` er statisk data (instansinnganger i verdenskoordinater, kontinent 0/1). Kilde: vmangos 1.12, `areatrigger_teleport` joinet med `areatrigger_template`. Nivåspenn er de klassiske, ikke verifisert mot Forever.
- `DungeonPins.lua` tegner pins via egen `MapCanvasDataProvider`, projiserer med `C_Map.GetMapPosFromWorldPos`, og hopper over innganger spillet selv tegner (`C_EncounterJournal.GetDungeonEntrancesForMap`) og legger nivålinja i spillets tooltip i stedet.
- `Probe.lua` er `/udc probe`: tester quest-, kart- og journal-API-er og lagrer alt i `UlDungeonCompanionDB.probe`.
- Statisk spilldata skal genereres av Python i `tools/` (ikke med i zip). vmangos-databasen (SQLite) ligger i scratchpad fra reagentjobben i UlRemedyForever; hentes ellers fra GitHub-release `vmangos/core` tag `db_latest`, fila `db-sqlite-*.zip`.

## Klienten

Forever-klienten (build 1.60.1.70338, Interface 16001) kjører retail 12.x sitt grensesnitt med secret values. Anta retail-API, ikke Classic, og verifiser på betaen. Rør aldri Blizzards paneler annet enn via post-hooks. Egne pins via egen dataprovider er trygt (bevist i UlRemedyForever). Spillets questlogg (QuestMapFrame) skal ikke hookes før probe sier det er trygt; eget vindu er standard.

## Testløkke

- Jonatan spiller på Windows-maskinen `win` (Tailscale, PowerShell). Forever ligger i `C:\Program Files (x86)\World of Warcraft\_classic_beta_\`. Addons: `...\Interface\AddOns\`, SavedVariables: `...\WTF\Account\105561400#1\SavedVariables\UlDungeonCompanion.lua`.
- **Probe-resultat hentes med scp**, ikke skjermbilde: etter `/udc probe` og `/reload` eller utlogging, `scp "win:C:/Program Files (x86)/World of Warcraft/_classic_beta_/WTF/Account/105561400#1/SavedVariables/UlDungeonCompanion.lua" /tmp/udc/`. Lesing fra Windows er fritt, skriving og sletting krever spørsmål først.
- **Direkte til spillmaskinen** (på klart ja fra Jonatan, det er skriving på Windows): pakk zip med `--dry-run`, pakk ut i scratchpad, `scp -r UlDungeonCompanion win:C:/Users/knitr/claude/addon-staging/`, så over ssh `Copy-Item -Recurse -Force` fra staging til AddOns-mappa. scp klarer ikke mellomrommene i `Program Files (x86)`, derfor omveien. Ny TOC krever full omstart av spillet.
- Utgivelse: `/package-addon`, beta uten å spørre, release krever klart ja. CurseForge-prosjekt 1743328 (`project_id` i `.curseforge.json`). Vakt på godkjenningskøen etter hver opplasting.
- Versjon bumpes i TOC per endring, commit-meldinger med scope (`feat(pins):`, `fix(probe):`), TOC-versjonen nevnt i meldingen.
- Syntaks sjekkes lokalt med `luac -p *.lua` (Homebrew Lua 5.4, WoW er 5.1: ingen `//`, ingen `%x` med flyttall).
- Aldri kode fra andre addons, heller ikke de som ligger installert på Windows-maskinen. Blizzards FrameXML er eneste referanse.

## Status

- 13.10.2026: 0.1.0 stillas skrevet. Ingenting verifisert i spill ennå. Neste: Jonatan kjører `/udc probe` og `/udc pins` på et sonekart, jeg henter probe-fila, så designes questdataen.
