-- TavernDice smoke tests: load the add-on against stubbed WoW APIs and check the basics.
-- Run: python3 tests/run_tests.py   (add a check for every new feature)

local root = arg[1]
dofile(root .. "/tests/stubs.lua")

local failures, checks = 0, 0
local function check(cond, label)
  checks = checks + 1
  if cond then print("  ok   " .. label) else failures = failures + 1; print("  FAIL " .. label) end
end

local handlerErrors = 0
geterrorhandler = function() return function(e) handlerErrors = handlerErrors + 1; print("  (error) " .. tostring(e)) end end

-- Load files in TOC order (a file missing from the TOC = a failing test)
local ns = {}
for line in io.lines(root .. "/TavernDice.toc") do
  local file = line:match("^([%w_]+%.lua)%s*$")
  if file then assert(loadfile(root .. "/" .. file))("TavernDice", ns) end
end

local function fire(e, ...) assert(events[e], "event not registered: " .. e)._OnEvent(events[e], e, ...) end

print("Loading")
fire("ADDON_LOADED", "TavernDice")
fire("PLAYER_LOGIN")
check(ns.db and ns.cdb, "saved variables initialised")

print("Bug log")
ns:On("TAVERNDICE_TEST_ERROR", function() local x; return x.y end)
fire("TAVERNDICE_TEST_ERROR"); fire("TAVERNDICE_TEST_ERROR")
local last = ns.db.errors[#ns.db.errors]
check(last and last.count == 2, "errors are logged and de-duplicated")
handlerErrors = handlerErrors - 2
ns:ShowBugs()

-- Add feature checks here --------------------------------------------------
local function flush(max)
  local n = 0
  while #timers > 0 and n < (max or 100000) do
    local fn = table.remove(timers, 1); fn(); n = n + 1
  end
  return n
end
flush()

print("Scoring")
local S = ns.ScoreSelection
local function sc(t) local s, ok = S(t); return ok and s or -1 end
check(sc({1}) == 100 and sc({5}) == 50 and sc({1, 5}) == 150, "singles")
check(sc({2, 2, 2}) == 200 and sc({1, 1, 1}) == 1000 and sc({6, 6, 6}) == 600, "three of a kind")
check(sc({2, 2, 2, 2}) == 400 and sc({4, 4, 4, 4, 4}) == 1600 and sc({6, 6, 6, 6, 6, 6}) == 4800, "four+ of a kind doubles")
check(sc({1, 2, 3, 4, 5, 6}) == 1500, "straight")
check(sc({2, 2, 3, 3, 4, 4}) == 1000 and sc({1, 1, 5, 5, 3, 3}) == 1000, "three pairs")
check(sc({1, 1, 1, 1, 5, 5}) == 2100, "four 1s and two 5s beats three pairs")
check(sc({2}) == -1 and sc({1, 2}) == -1 and sc({}) == -1, "non-scoring dice make a selection invalid")
check(ns.IsFarkle({2, 3, 4, 6, 2, 3}) and not ns.IsFarkle({2, 3, 4, 6, 2, 5}), "farkle detection")
check(ns.BestScore({1, 1, 1, 5, 2, 3}) == 1050, "best score")

print("Dice")
local D = ns.Dice
check(D.MaxFor(6) == 46655 and D.MaxFor(1) == 5, "roll ranges")
local all1, all6 = D.Decode(0, 6), D.Decode(46655, 6)
check(table.concat(all1) == "111111" and table.concat(all6) == "666666", "decode extremes")
local seen = {}
for v = 0, 215 do local d = D.Decode(v, 3); seen[table.concat(d)] = true end
local distinct = 0; for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct == 216, "decode is one-to-one (fair)")
local got
D.Roll(6, function(d, src) got = { d, src } end, true)
check(rolled[#rolled][1] == 0 and rolled[#rolled][2] == 46655, "server roll asks /roll 0-46655")
fire("CHAT_MSG_SYSTEM", "Bob rolls 12 (0-46655)")
check(got == nil, "other players' rolls are ignored")
fire("CHAT_MSG_SYSTEM", "Harry rolls 31337 (0-46655)")
check(got and got[2] == "server" and table.concat(got[1]) == table.concat(D.Decode(31337, 6)), "server roll decoded")
local filter = ns.Dice._filter
check(filter and filter(nil, nil, "Harry rolls 31337 (0-46655)") == true, "our roll line is hidden")
check(filter(nil, nil, "Bob rolls 5 (1-100)") == false and filter(nil, nil, "Harry rolls 50 (1-100)") == false, "normal /roll lines stay")
local got2
D.Roll(3, function(d, src) got2 = src end, true)
flush()
check(got2 == "fallback", "falls back to local dice when the server roll never arrives")

print("Game")
local script = {}
local realRoll = D.Roll
D.Roll = function(n, cb) local d = table.remove(script, 1) or {2, 3, 4, 6, 2, 3}; local t = {}; for i = 1, n do t[i] = d[i] end; cb(t, "local") end
local g = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 500 })
check(g:IsMyTurn() and g.phase == "ready" and g:CanRoll() and not g:CanBank(), "human starts, can roll, can't bank")
script = { {1, 1, 2, 3, 4, 6} }
g:Roll()
check(g.phase == "choosing", "rolled into choosing")
g:SetSelection({1, 2})
check(g:SelectionScore() == 200 and not g:CanBank(), "200 is below the opening 500")
script = { {5, 5, 5, 2} }
check(g:NextRollCount() == 4, "4 dice left after setting 2 aside")
g:Roll()
check(#g.roll == 4 and g.turnScore == 200 and #g.kept == 2, "set-aside dice carried into the turn")
g:SetSelection({1, 2, 3})
check(g:PendingTotal() == 700 and g:CanBank(), "700 total, can bank to get on the board")
g:Bank()
check(g.players[1].score == 700 and g.players[1].onBoard and g.current == 2, "banked and turn passed to the bot")
g:Abandon(); timers = {}

g = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 0 })
script = { {1, 2, 3, 4, 5, 6} }
g:Roll()
g:SetSelection({1, 2, 3, 4, 5, 6})
check(g:NextRollCount() == 6, "hot dice offers all six again")
script = { {2, 3, 4, 6, 2, 3} }
g:Roll()
check(g.phase == "farkle" and g.turnScore == 0, "farkle wipes the turn")
check(#timers == 1, "one pause timer after a farkle")
D.Roll = realRoll
-- run just the farkle pause, then the bot plays the rest
local fn = table.remove(timers, 1); fn()
check(g.current == 2, "after a farkle the turn passes on")
g:Abandon(); timers = {}

print("Final round")
g = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 2000, opening = 0 })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = 1 end; cb(t, "local") end
g.players[1].score = 1500
g:Roll(); g:SetSelection({1, 2, 3, 4, 5, 6})
g:Bank()
check(g.finalRound and g.finalTrigger == 1 and g.current == 2, "reaching the target starts the final round")
flush()
check(g.phase == "over" and g.winner ~= nil, "the bot gets its last turn, then the game ends")
D.Roll = realRoll
timers = {}

print("Bots")
local o = ns.Bots.Choose({1, 2, 3, 4, 6, 6}, "balanced")
check(o and o.score == 100 and o.kept == 1, "bot keeps the 1")
o = ns.Bots.Choose({1, 2, 3, 4, 5, 6}, "cautious")
check(o and o.score == 1500, "bot takes the straight")
local games, wins, okAll, turns = 0, {}, true, 0
local before = ns.cdb.stats.games
for i = 1, 150 do
  local style = ns.Bots.ORDER[(i % 3) + 1]
  local gg = ns:NewGame({ players = { { name = "A", bot = "cautious" }, { name = "B", bot = "balanced" }, { name = "C", bot = "reckless" } }, target = 10000, opening = 500 })
  flush(200000)
  if gg.phase ~= "over" or not gg.winner or gg.winner.score < 10000 then okAll = false end
  wins[gg.winner and gg.winner.name or "?"] = (wins[gg.winner and gg.winner.name or "?"] or 0) + 1
  turns = turns + gg.turnNo
  games = games + 1
end
check(okAll, "150 bot-only games all finish with a winner over 10,000")
print(string.format("     wins: cautious %d, balanced %d, reckless %d; avg %.0f turns", wins.A or 0, wins.B or 0, wins.C or 0, turns / games))
check(ns.cdb.stats.games == before + 150, "games are counted in your stats")

print("Mumpits")
local M = ns.RULESETS.mumpits
local s5, ok5, ref5 = ns.ScoreSelection({5, 5}, M)
check(s5 == 100 and ok5 and ref5 == 1, "two 5s = 100 and one may go back")
check(select(3, ns.ScoreSelection({5, 5})) == 0, "classic has no 5 refund")
check(select(3, ns.ScoreSelection({5, 5, 5}, M)) == 0, "three 5s are a triple, no refund")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({5, 5, 2, 3, 4, 6})[i] end; cb(t, "local") end
local gm = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 0, ruleset = "mumpits" })
gm:Roll(); gm:SetSelection({1, 2})
check(gm:NextRollCount() == 5 and not gm:CanBank(), "5-5 leaves 5 dice to roll; 100 is under 400 so no bank")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 1, 1, 2, 3})[i] end; cb(t, "local") end
gm:Roll()
check(#gm.roll == 5 and #gm.kept == 1 and gm.turnScore == 100, "only one 5 set aside, the other rolled again")
gm:SetSelection({1, 2, 3})
check(gm:CanBank() and gm:PendingTotal() == 1100, "1,100 can bank in Mumpits")
gm:Bank()
gm.players[1].onBoard = true
check(gm.players[1].score == 1100, "Mumpits bank recorded")
gm:Abandon(); timers = {}
-- last two dice are 5, 5: automatically keep both = hot dice; the player can choose otherwise
gm = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 0, ruleset = "mumpits" })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 1, 1, 2, 5, 5})[i] end; cb(t, "local") end
gm:Roll(); gm:SetSelection({1, 2, 3})
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = 5 end; cb(t, "local") end
gm:Roll()
check(gm.remaining == 3 and #gm.roll == 3, "three dice left")
gm.roll = {5, 5}; gm.remaining = 2; gm.phase = "choosing"
gm:SetSelection({1, 2})
check(gm:NextRollCount() == 6, "last two dice are 5-5: hot dice by default")
gm:SetFiveBack(true)
check(gm:NextRollCount() == 1, "or throw one 5 back and roll it")
gm:SetFiveBack(false)
check(gm:NextRollCount() == 6, "and back to keeping both")
gm.roll = {5, 5, 3}; gm.remaining = 3
gm:SetSelection({1, 2})
check(gm:NextRollCount() == 2, "with dice to spare, one 5 goes back by default")
gm:SetFiveBack(false)
check(gm:NextRollCount() == 1, "keeping both 5s leaves one die")
gm:Abandon(); timers = {}
-- 1s and 5s add up across rolls in Mumpits
gm = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 0, ruleset = "mumpits" })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 1, 2, 3, 4, 6})[i] end; cb(t, "local") end
gm:Roll(); gm:SetSelection({1, 2})
check(gm:SelectionScore() == 200, "two 1s = 200")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 2, 3, 4})[i] end; cb(t, "local") end
gm:Roll(); gm:SetSelection({1})
check(gm:SelectionScore() == 800 and gm:PendingTotal() == 1000, "then another 1 makes three 1s = 1,000")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 5, 2})[i] end; cb(t, "local") end
gm:Roll(); gm:SetSelection({1, 2})
check(gm:PendingTotal() == 2050, "a fourth 1 doubles it (2,000) plus a 5")
gm:Abandon(); timers = {}
local cg = ns:NewGame({ players = { { name = "Harry" }, { name = "Mira", bot = "balanced" } }, target = 10000, opening = 0, ruleset = "classic" })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 1, 2, 3, 4, 6})[i] end; cb(t, "local") end
cg:Roll(); cg:SetSelection({1, 2})
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 2, 3, 4})[i] end; cb(t, "local") end
cg:Roll(); cg:SetSelection({1})
check(cg:PendingTotal() == 300, "classic: each roll scores on its own")
cg:Abandon(); timers = {}
local opts = ns.ScoringOptions({5, 5}, M)
check(#opts == 4, "bots see both choices for a pair of 5s")
D.Roll = realRoll
D.Roll = realRoll
local okM = true
for i = 1, 60 do
  local gg = ns:NewGame({ players = { { name = "A", bot = "cautious" }, { name = "B", bot = "reckless" } }, target = 5000, opening = 0, ruleset = "mumpits" })
  flush(200000)
  if gg.phase ~= "over" or not gg.winner then okM = false end
end
check(okM, "60 Mumpits bot games all finish")

print("Friend game (host)")
timers = {}; sent = {}
local function lastSent() return sent[#sent] end
local function from(msg) fire("CHAT_MSG_ADDON", "TavernDice", msg, "WHISPER", "Bob-Realm") end
ns.db.ruleset = "classic"; ns.db.target = 2000; ns.db.opening = 0; ns.db.server = false
ns:Invite("Bob")
local inv = lastSent()
check(inv and inv:match("^INV~"), "invite sent")
local invId = select(3, strsplit("~", inv))
from("ACC~wrongid~0.2.0")
check(not (ns.game and ns.game.net), "an accept for another invite is ignored")
from("ACC~" .. invId .. "~0.2.0")
local ng = ns.game
check(ng and ng.net == "Bob-Realm" and ng.players[1].name == "Harry" and ng.players[2].remote, "accept starts a friend game, host first")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 1, 1, 2, 3, 4})[i] end; cb(t, "local") end
sent = {}
ng:Roll()
check(sent[1] == "A~" .. invId .. "~1~~r~" and sent[2] == "R~" .. invId .. "~1~111234~local~", "our roll is sent to the friend")
ng:Toggle(1); ng:Toggle(2); ng:Toggle(3)
check(sent[#sent] == "T~" .. invId .. "~1~123~", "our selection is shared live")
ng:Bank()
check(sent[#sent] == "A~" .. invId .. "~1~123~b~" and ng.current == 2, "our bank is sent, then it's their turn")
check(not ng:IsMyTurn(), "we can't act on the friend's turn")
sent = {}
from("A~" .. invId .. "~2~~r")
check(ng.phase == "rolling" and #sent == 0, "their roll waits for their dice")
fire("CHAT_MSG_ADDON", "TavernDice", "R~" .. invId .. "~2~555555~local~", "WHISPER", "Mallory-Realm")
check(ng.phase == "rolling", "strangers can't play the friend's seat")
from("R~" .. invId .. "~2~515234~local~")
check(ng.phase == "choosing" and table.concat(ng.roll) == "515234", "their dice arrive")
from("T~" .. invId .. "~2~12")
check(ng.selected[1] and ng.selected[2] and ng:SelectionScore() == 150, "their live selection shows")
from("A~" .. invId .. "~2~12~r")
check(ng.turnScore == 150 and ng.phase == "rolling" and ng.remaining == 4, "their roll-on is applied")
from("R~" .. invId .. "~2~2346~local~")
check(ng.phase == "farkle" and ng.turnScore == 0, "their farkle is detected on our side too")
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = 1 end; cb(t, "local") end
sent = {}
-- our next-turn message arrives while their farkle pause is still running on our side
from("A~" .. invId .. "~3~~r")
check(ng.current == 1, "a message for the next turn ends the farkle pause first")
from("Q~" .. invId)
check(ns.game == nil, "the friend leaving ends the game")
timers = {}

print("Friend game (guest)")
popups = {}
from("INV~0.2.0~g42~mumpits~5000~0~0")
check(popups[1] and popups[1].data.set.ruleset == "mumpits" and popups[1].data.set.target == 5000, "invitation pops up with their rules")
from("INV~0.2.0~g43~mumpits~5000~0~0")
check(#popups == 1, "repeat invitations are throttled")
sent = {}
StaticPopupDialogs.TAVERNDICE_INVITE.OnAccept(nil, popups[1].data)
local gg2 = ns.game
check(sent[1] == "ACC~g42~" .. ns.VERSION, "accepting tells the host")
check(gg2 and gg2.players[1].remote and gg2.players[2].name == "Harry" and gg2.rules.key == "mumpits", "guest sits second with the host's rules")
check(not gg2:IsMyTurn(), "host goes first")
from("A~g42~1~~r")
from("R~g42~1~123456~server~99999")
check(gg2.phase == "rolling", "a server roll that doesn't match its /roll value is refused")
gg2:Abandon(); timers = {}
D.Roll = realRoll

print("Table talk")
chatSent = {}; emotes = {}
ns.db.tableTalk = "auto"
local tg = ns:NewGame({ players = { { name = "Harry" }, { name = "Bob", remote = true, full = "Bob-Realm" } }, target = 2000, opening = 0, net = "Bob-Realm", netId = "t1" })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({2, 3, 4, 6, 2, 3})[i] end; cb(t, "local") end
tg:Roll()
check(#chatSent == 0 and #emotes == 0, "far apart: no chat on farkle")
tg:Abandon(); timers = {}
unitsNear.party1 = { name = "Bob", visible = true }
tg = ns:NewGame({ players = { { name = "Harry" }, { name = "Bob", remote = true, full = "Bob-Realm" } }, target = 2000, opening = 0, net = "Bob-Realm", netId = "t2" })
check(ns:FriendNearby(), "friend in the group and in sight counts as nearby")
tg:Roll()
check(#chatSent + #emotes == 1, "beside you: a sigh or grunt on farkle")
tg:Abandon(); timers = {}
tg = ns:NewGame({ players = { { name = "Harry" }, { name = "Bob", remote = true, full = "Bob-Realm" } }, target = 2000, opening = 0, net = "Bob-Realm", netId = "t3" })
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 2, 3, 4, 5, 6})[i] end; cb(t, "local") end
chatSent = {}
tg:Roll(); tg:SetSelection({1, 2, 3, 4, 5, 6})
ns.inClick = true; tg:Roll(); ns.inClick = false
check(chatSent[1] and chatSent[1][2] == "SAY" and chatSent[1][1]:find("Hot dice"), "hot dice during your click: /say")
tg:Abandon(); timers = {}
chatSent = {}
ns.db.tableTalk = "off"
tg = ns:NewGame({ players = { { name = "Harry" }, { name = "Bob", remote = true, full = "Bob-Realm" } }, target = 2000, opening = 0, net = "Bob-Realm", netId = "t4" })
tg:Roll(); tg:SetSelection({1, 2, 3, 4, 5, 6}); tg:Roll()
check(#chatSent == 0, "table talk off: silent")
tg:Abandon(); timers = {}
ns.db.tableTalk = "auto"; unitsNear = {}
D.Roll = realRoll

print("Nearby")
local addonSent = {}
local realSend = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(p, m, ch, t) addonSent[#addonSent + 1] = { m = m, ch = ch, t = t } end
local function fromVia(who, msg, ch) fire("CHAT_MSG_ADDON", "TavernDice", msg, ch, who) end
ns:ScanNearby(true)
local chans = {}
for _, x in ipairs(addonSent) do if x.m:match("^WHO~") then chans[x.ch] = true end end
check(chans.CHANNEL and chans.GUILD, "looking around asks the hidden channel and the guild")
check(not ns:ScanNearby(), "looking around is throttled")
-- someone close by on the channel asks: we answer
addonSent = {}
fromVia("Ann-Realm", "WHO~0.2.1~0~2000~1500", "CHANNEL")
check(addonSent[1] and addonSent[1].m:match("^HERE~") and addonSent[1].ch == "WHISPER" and addonSent[1].t == "Ann-Realm", "a nearby asker gets an answer")
-- someone far away on the channel: no answer
addonSent = {}
fromVia("Far-Realm", "WHO~0.2.1~0~3900~2900", "CHANNEL")
check(#addonSent == 0, "far-away askers on the channel are ignored")
fromVia("Guildie-Realm", "WHO~0.2.1~~~", "GUILD")
check(#addonSent == 1, "guild members always get an answer")
ns.db.discoverable = false
addonSent = {}
fromVia("Bob2-Realm", "WHO~0.2.1~0~2000~1500", "PARTY")
check(#addonSent == 0, "hidden: nobody gets an answer")
ns.db.discoverable = true
-- answers build the list, nearest first
fromVia("Zed-Realm", "HERE~0.2.1~0~2100~1500~Elwynn Forest~0~MAGE", "WHISPER")
fromVia("Amy-Realm", "HERE~0.2.1~0~2010~1500~Elwynn Forest~1~", "WHISPER")
fromVia("Guildie-Realm", "HERE~0.2.1~~~~Stormwind City~0~", "WHISPER")
local list = ns:NearbyList()
check(#list == 3 and list[1].short == "Amy" and list[1].dist == 10 and list[1].busy and list[2].short == "Zed" and list[3].dist == nil, "nearby list: nearest first, busy flagged, far ones last")
check(ns:HasAddon("Zed-Realm") and not ns:HasAddon("Nobody-Realm"), "known players are remembered for tooltips")
-- targeting asks once
addonSent = {}
unitsNear.target = { name = "Tara", visible = true }
fire("PLAYER_TARGET_CHANGED"); fire("PLAYER_TARGET_CHANGED")
check(#addonSent == 1 and addonSent[1].t == "Tara-Realm" and addonSent[1].m:match("^WHO~"), "targeting a player asks them once")
unitsNear = {}
check(ns._noticeFilter(nil, nil, "x", "", "", "", "", "", "", "5. TavernDiceTable") == true, "channel join notices are hidden")
C_ChatInfo.SendAddonMessage = realSend

print("UI")
ns.db.opponents = { "cautious", "reckless", "reckless" }
ns:ShowWindow()
local g2 = ns:StartFromSettings()
check(#g2.players == 4 and g2.players[4].name ~= g2.players[3].name, "lobby seats become players with unique names")
ns:GetWindow():Refresh()
D.Roll = function(n, cb) local t = {}; for i = 1, n do t[i] = ({1, 5, 2, 3, 4, 6})[i] end; cb(t, "local") end
g2:Roll(); g2:Toggle(1); ns:GetWindow():Refresh()
check(g2.selected[1] and g2:SelectionScore() == 100, "clicking a die selects it")
g2:Toggle(1)
check(not g2.selected[1], "clicking again unselects")
D.Roll = realRoll
ns:GetWindow().lobby:Show(); ns:GetWindow().lobby:RefreshNearby()
ns:ToggleWindow(); ns:ToggleWindow()
SlashCmdList.TAVERNDICE("stats"); SlashCmdList.TAVERNDICE("help"); SlashCmdList.TAVERNDICE("minimap")
SlashCmdList.TAVERNDICE("server")
check(ns.db.server == true, "/dice server switches dice source")
SlashCmdList.TAVERNDICE("local")
check(#ns.log > 0, "tavern log has lines")

check(handlerErrors == 0, "no unexpected errors (" .. handlerErrors .. ")")
print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then error("tests failed") end
