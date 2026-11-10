-- TavernDice: Lines
-- Tavern narration for the table log, sounds, and your stats at the table.
-- Listens to TD_EVENT from Game.lua; writes to ns.log and fires TD_LOG(line).

local _, ns = ...

ns.log = {}
local MAX_LOG = 60

local function pick(t) return t[math.random(1, #t)] end
local function fmt(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local GOLD, RED, GREEN, GREY = "|cffffd100", "|cffff5555", "|cff66dd66", "|cff999999"

local L = {
  start = {
    "The innkeeper slides a battered dice cup across the table.",
    "Chairs scrape, tankards thud down. A game of ten thousand begins.",
    "Six bone dice rattle onto the table. Let's play.",
  },
  turnBot = {
    "%s cracks their knuckles and reaches for the cup.",
    "%s blows on the dice for luck.",
    "%s gives the cup a long, thoughtful shake.",
  },
  turnYou = {
    "Your turn. The cup is warm from the last throw.",
    "The dice come to you.",
    "All eyes on you, friend.",
  },
  farkle = {
    "%s throws %s... nothing! FARKLE. %s lost.",
    "%s stares at %s. Not a scoring die among them. FARKLE! %s gone.",
    "A groan around the table: %s, %s. FARKLE, %s lost.",
  },
  bank = {
    "%s banks %s and leans back, satisfied.",
    "%s sweeps %s into the ledger.",
    "%s says \"I'll take it\" and banks %s.",
  },
  bankYou = {
    "You bank %s and lean back, satisfied.",
    "You sweep %s into the ledger.",
    "\"I'll take it.\" You bank %s.",
  },
  farkleYou = {
    "You throw %s... nothing! FARKLE. %s lost.",
    "You stare at %s. Not a scoring die among them. FARKLE! %s gone.",
    "A groan around the table: %s. FARKLE, %s lost.",
  },
  hot = {
    "HOT DICE! %s scored with every die and scoops all six back up.",
    "Every die counts. HOT DICE for %s, and the cup is full again!",
  },
  hotYou = {
    "HOT DICE! Every one of your dice scored. Scoop all six back up!",
    "Every die counts. HOT DICE, and the cup is full again!",
  },
  final = {
    "%s passes %s! Everyone else gets one last throw.",
  },
  finalYou = {
    "You pass %s! Everyone else gets one last throw.",
  },
  win = {
    "%s wins with %s! Drinks are on the loser.",
    "%s takes the table with %s. The innkeeper rings the bell.",
  },
  winYou = {
    "You win with %s! Drinks are on the loser.",
    "You take the table with %s. The innkeeper rings the bell.",
  },
}

local function add(line)
  table.insert(ns.log, line)
  while #ns.log > MAX_LOG do table.remove(ns.log, 1) end
  ns:Fire("TD_LOG", line)
end
ns.AddLog = add

local function other(p) return p and (p.bot or p.remote) end
ns.IsOther = other

local function nameOf(p)
  if not p then return "?" end
  if p.remote then return "|cff6fb7ff" .. p.name .. "|r" end
  return p.bot and (GOLD .. p.name .. "|r") or (GREEN .. "You" .. "|r")
end

local function diceText(d)
  local t = {}
  for i, v in ipairs(d or {}) do t[i] = tostring(v) end
  return GREY .. "[" .. table.concat(t, " ") .. "]|r"
end

local function sound(kind)
  if not (ns.db and ns.db.sound) or not PlaySound or not SOUNDKIT then return end
  local id = ({
    ROLLED = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
    BANK = SOUNDKIT.LOOT_WINDOW_COIN_SOUND,
    FARKLE = SOUNDKIT.IG_QUEST_FAILED,
    HOTDICE = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.IG_QUEST_LIST_COMPLETE,
    OVER = SOUNDKIT.IG_QUEST_LIST_COMPLETE,
  })[kind]
  if id then pcall(PlaySound, id, "SFX") end
end

local function stats() return ns.cdb and ns.cdb.stats end

ns:Listen("TD_EVENT", function(kind, a, b, c)
  local s = stats()
  if kind == "START" then
    wipe(ns.log)
    ns:Fire("TD_LOG_RESET")
    add(pick(L.start))
  elseif kind == "TURN" then
    local p = a
    if other(p) then add(string.format(pick(L.turnBot), nameOf(p))) else add(pick(L.turnYou)) end
  elseif kind == "ROLLED" then
    local p, dice, source = a, b, c
    local tag = (source == "server") and (GREY .. " (server roll)|r") or ""
    add(string.format("%s %s %s%s", nameOf(p), other(p) and "rolls" or "roll", diceText(dice), tag))
  elseif kind == "FARKLE" then
    local p, lost, dice = a, b, c
    if other(p) then
      add(RED .. string.format(pick(L.farkle), nameOf(p) .. RED, diceText(dice) .. RED, fmt(lost)) .. "|r")
    else
      add(RED .. string.format(pick(L.farkleYou), diceText(dice) .. RED, fmt(lost)) .. "|r")
    end
    if s and not other(p) then s.farkles = s.farkles + 1 end
  elseif kind == "HOTDICE" then
    local p = a
    add(GOLD .. (other(p) and string.format(pick(L.hot), nameOf(p) .. GOLD) or pick(L.hotYou)) .. "|r")
    if s and not other(p) then s.hotDice = s.hotDice + 1 end
  elseif kind == "BANK" then
    local p, total, g = a, b, c
    local line = other(p) and string.format(pick(L.bank), nameOf(p), GOLD .. fmt(total) .. "|r")
      or string.format(pick(L.bankYou), GOLD .. fmt(total) .. "|r")
    add(line .. GREY .. "  (" .. fmt(p.score) .. ")|r")
    if s and not other(p) then
      s.banked = s.banked + total
      if total > s.bestTurn then s.bestTurn = total end
    end
  elseif kind == "DESYNC" then
    add(RED .. "The table got out of step with " .. nameOf(a) .. RED .. ". Start a new game if the dice look wrong.|r")
  elseif kind == "FIVEBACK" then
    add(GREY .. (other(a) and (a.name .. " keeps one 5 and tosses the other back in the cup.") or "You keep one 5 and toss the other back in the cup.") .. "|r")
  elseif kind == "FINAL" then
    local p, g = a, b
    add(GOLD .. (other(p) and string.format(pick(L.final), nameOf(p) .. GOLD, fmt(g.target))
      or string.format(pick(L.finalYou), fmt(g.target))) .. "|r")
  elseif kind == "OVER" then
    local p, g = a, b
    add(GOLD .. (other(p) and string.format(pick(L.win), nameOf(p) .. GOLD, fmt(p.score))
      or string.format(pick(L.winYou), fmt(p.score))) .. "|r")
    if s then
      s.games = s.games + 1
      for _, pl in ipairs(g.players) do
        if not other(pl) and pl.score > s.highScore then s.highScore = pl.score end
      end
      if not other(p) then s.wins = s.wins + 1 end
    end
  end
  sound(kind)
end)
