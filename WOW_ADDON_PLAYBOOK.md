# WoW Forever add-on playbook

Everything we learned building **Tjommie** (Harry's first WoW Forever add-on, Nov 2026), written so a new chat can start the next add-on without repeating the groundwork. Read this first, then copy `wow-addon-template/`.

---

## 1. Where things live

| What | Where |
|---|---|
| All WoW add-on work | `OneDrive\Claude Projects\App Dev\wow-forever-addons\` |
| Starter template | `wow-forever-addons\wow-addon-template\` (this playbook is inside it) |
| Tjommie (reference add-on) | GitHub [Radewest/tjommie](https://github.com/Radewest/tjommie), with a local copy in `wow-forever-addons\Tjommie\` |
| Tjommie developer notes | `CLAUDE.md` in the Tjommie repo (architecture, protocol, decisions) |
| CurseForge | Harry's author account. Tjommie is project **1786857** |
| GitHub | Account **Radewest**. Cloud Claude sessions can attach repos with push access |
| Game install (Harry's PC) | `World of Warcraft\_classic_beta_\Interface\AddOns\` (the folder name may change after Forever launches) |

---

## 2. The platform: WoW Forever

- **What it is:** Classic content (Camelot) running on the **modern Midnight-era client and add-on API**. Use modern APIs (`C_Map`, `C_Item`, `C_BattleNet`, `C_QuestLog`, `C_UnitAuras`, `C_ChatInfo`, the `Menu` API, `BackdropTemplate`, `Settings`), but guard every call with `if C_X and C_X.Fn then`.
- **TOC:** `## Interface: 16001`. Ship **two identical TOCs**: `MyAddon_Camelot.toc` (Forever's internal game type, which the client prefers) and `MyAddon.toc` (fallback). CurseForge maps 16001 to game version **1.60.1 (Forever)**.
- **Midnight add-on restrictions apply.**
  - Add-ons may *show* information but not *decide* things in combat (no WeakAuras-style "do X when HP < Y", no auto-marking, no telling players where to move, no tracking other players' debuffs).
  - Some values are **secret** in combat or instances. Check them with `issecretvalue(v)` (wrapped as `ns.IsSecret`).
  - Player map position is `nil` inside instances.
  - Add-on messages can be blocked in instanced content, so always `pcall` sends.
  - **Ideas that work well:** UI, maps, bags, quests, professions, social features, out-of-combat helpers.
- **Campsites:** standing near a campfire gives the buff **"Campfire Nearby"** (also "Welcoming Campfire"). Campfire spell IDs: 818 (Basic), 1283400 (Journeyman), 1291341 (Expert). Harry calls the campfire **"Gees Vuur"** in-game.
- **Waylaid Crates (Merchant's Favor):**
  - **Getting them:** world drops and chests, or buy them on the AH. They aren't Bind on Pickup.
  - **Filling them:** each crate lists several material options (e.g. 20 Peacebloom *or* 10 Briarthorn) and you fill just one.
  - **Tiers by level:** Apprentice and Journeyman (10), Expert (20), Artisan (35).
  - **Hand-in:** Alliance at Marcy Baker (Azeroth Commerce Authority, Redridge); Horde at Dokimi (near the Crossroads, Barrens).
  - **Rewards:** Merchant's Favor, spent on a title, toy, pet, tabard, Pack Kodo mount and recipes.
  - **Tjommie plans to use them** in v0.5.
- **Before building anything** that depends on a Forever-specific system, search the web first. Forever launched after the model's knowledge cutoff.

---

## 3. How Harry likes to work

- Brief, direct answers. Little formatting, no long reports.
- He plays with a friend, and add-ons are often social or duo-focused. Tone: friendly with light **South African flavour** ("tjommie", "Lekker", "Gesondheid!", "boet", "Howzit").
- **Every change:** bump the version, add a **CHANGELOG.md** entry, and name zips with the version (`MyAddon-vX.Y.Z.zip`). Keep old zips for rollback.
- **Ask before major architectural changes.** Brainstorm options, agree a phased roadmap, and record it in the add-on's CLAUDE.md.
- **He shares the OneDrive folder with his friend.** After a release, copy the add-on folder and zip there (only the add-on, not tests or CLAUDE.md).
- **He doesn't want manual release steps.** Pushing a version bump must be the whole release.
- **Security:** tokens and API keys go straight into GitHub secrets, never into chat. If he pastes one, tell him to regenerate it.

---

## 4. Add-on architecture (proven in Tjommie, included in the template)

- **One namespace:** `local ADDON, ns = ...`, plus a global alias for `/dump`.
- **`Core.lua`:**
  - `ns:On(event, fn)` is the event bus. `ns:Listen` / `ns:Fire` are internal callbacks.
  - Everything runs through `ns.SafeCall` (xpcall plus stack trace), so **every error lands in the bug log** and still reaches BugSack.
  - Saved variables with **merged defaults**, so new settings appear for existing users.
  - `ns:Print` for direct replies to slash commands. `ns:Chat(msg, "important"|"all")` follows a chat setting (Off / Important / Everything). **Never echo pop-ups to chat by default:** that was Tjommie's "chat spam" bug.
- **`Bugs.lua`:**
  - A self bug log in `DB.errors`, deduplicated and capped at 30, with version, count and stack.
  - `/myaddon bugs` opens a pre-selected, copyable window.
  - It also chains `seterrorhandler` for errors that happen outside the safe wrappers.
  - **Bug reports = paste the `/bugs` output.**
- **The usual next files:** `Comms.lua` (if players talk to each other), `Settings.lua`, `UI.lua`, `Toast.lua`, `Welcome.lua`, `Demo.lua`. Copy them from Tjommie and adapt.
- **Settings:** build the panel once and use it in two places: your own tab and Blizzard's Options → AddOns (`Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory`, with an `InterfaceOptions_AddCategory` fallback). Use plain frames for checkboxes, sliders and cycle buttons rather than fragile templates.
- **Welcome guide** on first install, a **demo mode** (fake data so you can test alone), and a **version-mismatch warning** if players talk to each other.
- **Media:** generate TGA textures with Python (32-bit, uncompressed, top-left origin, power-of-two sizes). Build the icon at 1024 px, then export 64 px TGA for the game (`## IconTexture`) and a 400 px PNG for the CurseForge logo.

### Player-to-player messaging (from Tjommie)
- **Prefix** ≤16 characters, registered with `C_ChatInfo.RegisterAddonMessagePrefix`. Separator `~`. **Never send `|`**, because chat treats it as an escape character. Keep messages ≤250 bytes and test the worst-case size.
- **Transport:**
  - If the other player is an online Battle.net friend, use `BNSendGameData(gameAccountID, prefix, msg)`, received via `BN_CHAT_MSG_ADDON`. It works across realms and factions.
  - Otherwise use an addon `WHISPER`, which needs the same realm and faction.
- **Hide the "No player named X" spam** with a `CHAT_MSG_SYSTEM` message filter.
- **Trust:** ignore messages from anyone except the linked partner. Pairing needs consent (request, then an Accept/Decline StaticPopup). The right-click "Add as …" option uses `Menu.ModifyMenu("MENU_UNIT_*", …)`.
- **Wire formats:** only ever **append** fields, so older versions keep working.
- **Privacy toggles:** pause sharing your position, hide your gold.

### Useful API notes
- **Position:** `C_Map.GetBestMapForUnit` → `GetPlayerMapPosition` → `GetWorldPosFromMapPos`. World coordinates are in yards, so distance is straight-line. For direction, project onto the current map with `GetMapPosFromWorldPos` and `GetMapWorldSize`, then use `GetPlayerFacing` (0 = north, counter-clockwise). Texture `SetRotation` is counter-clockwise.
- **ETA:** distance ÷ smoothed closing speed over about 5 s. Show `--:--` when you're not getting closer.
- **World map overlay:** add a frame on `WorldMapFrame:GetCanvas()`; refresh on `OnMapChanged` and `OnShow`; scale pins by `1 / GetCanvasScale()`.
- **Loot:** parse `CHAT_MSG_LOOT` using patterns built from `LOOT_ITEM_SELF*` globals. Item data loads asynchronously, so use `Item:CreateFromItemID(id):ContinueOnItemLoad`.
- **Class upgrade rules (Classic):** best armour is Plate at 40 for Warriors and Paladins (Mail before), Mail at 40 for Hunters and Shamans (Leather before), Leather for Rogues and Druids, Cloth for casters. Add weapon-skill sets and main-stat filters (`C_Item.GetItemStats`), then compare item level with equipped gear.
- **Quests:** log rewards via `C_QuestLog.SetSelectedQuest` + `GetQuestLogItemLink`. Quest-giver and hand-in screens: `QUEST_DETAIL` / `QUEST_COMPLETE` + `GetQuestItemLink`. Vendors: `MERCHANT_SHOW`.
- **Lifetime data:**
  - `/played` via `RequestTimePlayed` + `TIME_PLAYED_MSG`. Suppress the chat print by temporarily wrapping `ChatFrame_DisplayTimePlayed`.
  - Completed quests: `C_QuestLog.GetAllCompletedQuestIDs`.
  - Kills (1197), deaths (60) and drinks (346): `GetStatistic`, but only if Forever kept Statistics (not yet confirmed).
- **Drunk levels:** `DRUNK_MESSAGE_SELF2-4` and `DRUNK_MESSAGE_ITEM_SELF2-4` system messages. Dancing: hook `DoEmote` / `C_ChatInfo.PerformEmote`, and stop on movement (`GetUnitSpeed`).

---

## 5. Testing (no game needed)

- `pip install lupa luaparser`, then `python3 tests/run_tests.py`. This runs a syntax check of every `.lua` file plus `tests/smoke.lua`, which loads the add-on **in TOC order** against WoW API stubs (`tests/stubs.lua`), fires events and asserts behaviour.
- **Add a check for every feature.** A file missing from the TOC shows up as a failing test.
- GitHub Actions runs the tests on every push and before every release.
- **It still doesn't replace a real play-test:** demo mode, BugSack + BugGrabber, the bug-log command and `/reload`.

---

## 6. Release pipeline: GitHub → CurseForge, fully automatic

**One-time setup per add-on:**
1. **GitHub:** Harry creates an **empty** repo under Radewest (public suits an MIT add-on). Claude attaches it with push access and pushes `main`.
2. **CurseForge:**
   - Create the project: game World of Warcraft, Class Addons.
   - Summary: one line. Description: HTML pasted via the `</>` button.
   - Main category Quests & Leveling (or whatever fits), plus additional categories.
   - **Licence MIT**, distribution "allow third-party apps", logo 400 px PNG.
   - The first upload is manual (zip, tick the Forever 1.60.x version, Beta while testing). New projects are reviewed within about a day.
   - On the project's **Source** tab: leave **"No automatic packaging"** (we package ourselves; otherwise every version uploads twice) and set Source Code to the GitHub URL.
3. **Wire it up:**
   - Put `## X-Curse-Project-ID: <id>` in both TOCs (the ID is in the "About Project" box).
   - Harry creates a CurseForge API token (profile → My API Tokens) and saves it as the repo secret **`CF_API_KEY`**: GitHub → Settings → Secrets and variables → Actions.
   - Wago is optional: `## X-Wago-ID` + `WAGO_API_TOKEN`.

**Every release:** bump `## Version` in both TOCs and `ns.VERSION`, add a CHANGELOG entry, run the tests, commit and push `main`. That's the whole release.
- **`release.yml`** (runs on every push to main) reads the TOC version.
  - If the tag is new: it runs the tests, creates tag `vX.Y.Z` and starts **`package.yml`** with `gh workflow run --ref vX.Y.Z`.
  - If a tag exists with no GitHub Release: it moves the tag to HEAD and retries the packaging.
- **`package.yml`** runs `BigWigsMods/packager@v2`. It builds `MyAddon-vX.Y.Z-forever.zip`, creates the GitHub Release, and uploads to CurseForge as game version 1.60.1 with **CHANGELOG.md** as the changelog (`manual-changelog` in `.pkgmeta`).
- **`.pkgmeta`** leaves `tests`, `CLAUDE.md`, `.github` and other dev files out of the zip.

**Pitfalls we hit (already fixed in the template):**
- **Cloud Claude sessions can push `main` but not tags** (the proxy returns 403). That's why the workflow creates the tags.
- **Tags pushed by the built-in `GITHUB_TOKEN` don't start other workflows.** `workflow_dispatch` is the exception, which is why `package.yml` is started that way.
- **The packager skips "future tags"** when it runs on a branch push ("Found future tag … not packaging"). It has to run on the tag ref, which `package.yml` does.
- The `gh` CLI token in the cloud session may be invalid. Public GitHub API reads, and job logs via `api.github.com/repos/…/actions/jobs/<id>/logs`, still work for public repos.
- CurseForge's site and API block automated fetches, so ask Harry to check the CurseForge page itself.

---

## 7. Starting a new add-on (checklist)

1. **Agree the idea and scope with Harry**, check it against the Midnight restrictions, and search the web for any Forever-specific systems it relies on.
2. **Copy `wow-addon-template/`** into a new folder named after the add-on. **Move `github-workflows/*.yml` into `.github/workflows/`** in the new repo. (The copy on Harry's PC can't hold a `.github` folder, because the remote tools treat it as protected. The cloud session can create it normally, and Tjommie's repo has the same files as a reference.) Rename `MyAddon` / `MYADDON` / `myaddon` everywhere: file names, TOCs, Core, Bugs, the tests, `.pkgmeta`, `release.yml`, and the saved-variable names `MyAddonDB` / `MyAddonCharDB`. Pick a slash command.
3. **Write the add-on's own `CLAUDE.md`:** what it is, architecture table, decisions, roadmap. Use Tjommie's as the model.
4. **Build in phases.** Add tests for each feature and keep the CHANGELOG current.
5. **Make an icon**, a 400 px logo and a layout mockup when there's UI. Get Harry's OK on the look before building it.
6. **Publish:** GitHub repo, then the CurseForge project and first manual upload, then project ID + `CF_API_KEY`. After that, a version bump plus push is the release.
7. **After each release,** copy the add-on folder and versioned zip into the OneDrive `wow-forever-addons` folder.

---

## 8. Tjommie at a glance (reference)

- **What it is:** a duo-levelling companion. Two friends link up (right-click → Add as Tjommie, then Accept) and each sees the other's:
  - location: tracker bar with arrow, distance, compass heading, arrival time, plus a map pin and trail;
  - live feed and loot-style pop-ups;
  - class-aware loot and upgrade alerts, wishlists and an upgrade finder (quests, quest-givers, vendors);
  - head-to-head stats: Lifetime and Since Tjommie, including drinks, dancing and time at the Gees Vuur.
- **It also has:** settings (tab plus Blizzard options), privacy toggles, a welcome guide, demo mode, a bug log, and a version warning.
- **Status:** v0.4.0 released automatically to CurseForge on 2026-11-09.
- **Next up:** v0.5 "helping each other" (professions, needs list, Waylaid Crates, mailbox helper). After that, multiple tjommies (up to 4, with one main).
- Full details are in Tjommie's `CLAUDE.md`.
