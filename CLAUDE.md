# Tavern Dice: Developer Notes

> Started from `wow-addon-template`. Read `WOW_ADDON_PLAYBOOK.md` before changing anything. Tjommie's `CLAUDE.md` (GitHub Radewest/tjommie) is the worked example for messaging, pairing and settings.

## What it is
A WoW Forever add-on for playing 10,000 (Farkle / Dix Mille / Zilch / Greed) at the tavern table. v0.1 is solo against bots; v0.2 adds games with friends. Tone: tavern / fantasy roleplay (Harry plays a roleplaying gnome mage). **No** South African flavour in this one.
- **Owner:** Harry. **Licence:** MIT. **CurseForge project ID:** 1795741. **GitHub:** Radewest/taverndice (source of truth).
- **Current version:** v0.2.3
- **Slash:** `/dice` (also `/taverndice`). Saved variables `TavernDiceDB`, `TavernDiceCharDB`.

## Architecture
| File | Role |
|---|---|
| Core.lua | Namespace, saved variables (merged defaults), `ns:On`, `ns:Listen` / `ns:Fire`, `ns.C_After` (safe timers), `ns:Print` / `ns:Chat`, slash commands |
| Bugs.lua | Self bug log (`/dice bugs`) |
| Scoring.lua | Pure rules: `ns.RULES`, `ns.ScoreSelection(dice)` -> score, valid; `ns.ScoringOptions(roll)`; `ns.IsFarkle`. No WoW API |
| Dice.lua | Dice source. Local (`math.random`) or server: one `RandomRoll(0, 6^n-1)` decoded as n base-6 digits; parses `RANDOM_ROLL_RESULT` from `CHAT_MSG_SYSTEM`; hides our own roll lines with a chat filter; 4 s timeout falls back to local |
| Game.lua | Turn state machine (ready -> rolling -> choosing -> farkle/next turn -> over), opening minimum, hot dice, final round. Fires `TD_UPDATE` and `TD_EVENT(kind, ...)` |
| Bots.lua | Bot styles (cautious / balanced / reckless): `Choose` = best of score + keepBonus x dice left; `ShouldBank` = bank-at threshold by dice left, always bank to win, in the final round keep rolling until ahead |
| Comms.lua | Friend games: invite / accept (StaticPopup), lockstep move sync, server-roll check, leave, right-click "Invite to Tavern Dice", Tjommie buddy (`TjommieDB.buddy`). Transport like Tjommie/Birdsong: BNSendGameData, else addon WHISPER. Wire: INV, ACC, DEC, T, A, R, Q (see file header; append-only) |
| Nearby.lua | Finding players with the add-on: hidden custom channel `TavernDiceTable` (joined after login, removed from chat frames, join notices filtered), WHO~version~continent~x~y to CHANNEL / PARTY / RAID / GUILD and as a quiet whisper on target; HERE replies by whisper. Channel askers only get a reply within 250 world yards. `ns:NearbyList()` (nearest first), tooltip line via TooltipDataProcessor. `db.discoverable` (`/dice findme`) |
| Talk.lua | Table talk: /say on hot dice and win (only inside your Roll/Bank click, `ns.inClick`; otherwise EMOTE), CHEER on win, SIGH or a grunt emote on Farkle. `db.tableTalk` auto (friend in group and `UnitIsVisible`) / always / off |
| Lines.lua | Tavern narration into `ns.log` (`TD_LOG`), sounds, per-character stats |
| UI.lua | Dice table window: ledger, felt with six clickable dice + set-aside tray, Roll / Bank, tavern log, toasts, new-game panel (`BuildLobby`), `StartFromSettings` |
| Minimap.lua | Minimap button (drag to move) |
| media/ | die1-6.tga, glow.tga (selection outline, tinted gold / red), icon.tga, wood.tga (tiled window), felt.tga, leather.tga. Generated with Python/PIL, 32-bit uncompressed TGA, top-left origin |

## Key decisions (and why)
- **Server dice via one /roll per throw.** Add-on RNG can be edited, so multiplayer needs dice nobody controls. `/roll 0-46655` (6^6 - 1) gives six fair dice in one chat line; fewer dice use 6^n - 1. Every player's add-on reads the same system message, so v0.2 multiplayer can verify each other's rolls. Solo defaults to local dice so we don't spam people nearby.
- **Not yet verified in Forever:** that `RandomRoll` is callable by add-ons and that roll lines reach `CHAT_MSG_SYSTEM` in the `RANDOM_ROLL_RESULT` format. The timeout fallback covers a failure, but test `/dice server` in game early.
- **Four+ of a kind doubles** (classic Dix Mille) rather than fixed 1000/2000/3000. Three pairs 1000, straight 1500. All numbers live in `ns.RULES` for future house-rule toggles.
- **Rulesets** (`ns.RULESETS` in Scoring.lua, chosen in the lobby, stored on the game as `g.rules`): **Classic**, and Harry's house rules **Mumpits**: never bank under 400 in a turn (`minBank`), and two 5s score 100; the player chooses to keep both or throw one back to reroll (`fivesPair`; `ScoreSelection` returns a third value `canThrowBack`; `Game.fiveBack` true/false/nil, nil = automatic: throw one back unless keeping both would be hot dice). Sent as the last field of T and A. The opening minimum is separate and only applies to your first bank.
- **Friend games are lockstep, not host-authoritative.** Both clients run the same Game; each plays its own seat and sends A (roll on / bank, with the selection), R (the dice) and T (live selection). Every message carries the turn number. A next-turn message during our Farkle pause ends the pause first (`Game:CatchUp`). Seat 1 = the inviter. Settings come from the inviter's INV.
- **Dice trust in friend games:** each client rolls its own dice. With server dice on, R includes the raw /roll value; the receiver refuses dice that don't decode from it, and if grouped it checks the /roll line it saw (`Dice.WasSeen`). Far apart and not grouped, the system message isn't visible, so it's trust between friends.
- **Table talk and protected chat:** /say outdoors needs a hardware event, so Talk only uses SAY inside your own click; async moments (server roll results, a friend's last turn ending the game) use EMOTE / DoEmote.
- **Finding players needs no server:** a hidden custom channel is the only realm-wide way to reach strangers; SAY/YELL add-on messages only work inside instances. **Not yet verified in Forever:** that add-ons may still join custom channels and send CHANNEL add-on messages under the Midnight rules. Group/guild and target checks work either way.
- **Final round:** whoever passes the target triggers one last turn for everyone else; highest score wins.
- **Bot tuning:** in 150 simulated 3-bot games, balanced won ~42%, cautious and reckless ~29% each, ~17 turns per player to 10,000.
- **Gold bets are scoreboard only.** Add-ons can't move gold.

## Conventions
- **Every change:** bump `## Version` in both TOCs and `ns.VERSION`; add a CHANGELOG entry; run `python3 tests/run_tests.py`; commit and push `main`. Pushing a new version *is* the release (playbook, section 6). Then copy the add-on folder and zip into OneDrive `wow-forever-addons`.
- Add new files to both TOCs, and give every feature a check in `tests/smoke.lua`.
- Guard modern APIs, pcall risky calls, check `ns.IsSecret`. Pop-ups never echo to chat by default.

## Roadmap (agreed with Harry, 2026-11-09)
1. **v0.1 (done): solo vs bots.** Rules engine, bots, dice table UI, optional server dice, stats.
2. **v0.2 (done for 2 players): play with friends.** Still to do: 3-6 players and spectators. 2-6 players over party/raid add-on messages, or whisper / Battle.net for a duo (reuse Tjommie's Comms). Invite + accept, host keeps the turn order, every throw is a server /roll that all clients decode and check. Spectators. Version-mismatch warning.
3. **v0.3: house rules and roleplay.** Rule toggles (fixed 4/5/6-of-a-kind values, partial straights, three-farkle penalty, opening score), optional in-character /e emotes ("shakes the dice cup"), lifetime head-to-head stats, settings in Blizzard Options -> AddOns.
