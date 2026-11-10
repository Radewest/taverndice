-- TavernDice: Bots
-- Tavern regulars you can play against solo. Each has a style:
--   cautious : banks early, keeps the dice it can
--   balanced : the sensible middle
--   reckless : pushes its luck, loves a full cup of dice
-- Bots act on short timers so you can watch them play.

local _, ns = ...

local Bots = {}
ns.Bots = Bots

Bots.STYLES = {
  cautious = {
    label = "Cautious",
    name = "Old Barnaby",
    keepBonus = 40,
    bankAt = { 200, 250, 350, 600, 1500, 3000 },  -- index = dice left to roll
  },
  balanced = {
    label = "Balanced",
    name = "Mira Ashvale",
    keepBonus = 60,
    bankAt = { 300, 350, 500, 1000, 2000, 3000 },
  },
  reckless = {
    label = "Reckless",
    name = "Grizzle Sparkfuse",
    keepBonus = 90,
    bankAt = { 500, 700, 1000, 2000, 3000, 5000 },
  },
}
Bots.ORDER = { "cautious", "balanced", "reckless" }

-- Pick which dice to set aside. Returns option { idx, score, kept }.
function Bots.Choose(roll, style, rules, g)
  local S = Bots.STYLES[style] or Bots.STYLES.balanced
  local best, bestValue
  for _, o in ipairs(ns.ScoringOptions(roll, rules)) do
    if g then  -- Mumpits: what these dice really add, counting 1s / 5s already set aside
      local vals = {}
      for _, i in ipairs(o.idx) do vals[#vals + 1] = roll[i] end
      o.score = g:GainFor(vals)
    end
    local left = #roll - o.kept
    if left == 0 then left = 6 end  -- hot dice
    local value = o.score + S.keepBonus * left
    if not bestValue or value > bestValue or (value == bestValue and o.score > best.score) then
      best, bestValue = o, value
    end
  end
  return best
end

-- After choosing: bank now? (total = points this turn including the chosen dice)
function Bots.ShouldBank(g, total, diceLeft, style)
  local S = Bots.STYLES[style] or Bots.STYLES.balanced
  local p = g:Player()
  if total < (g.minBank or 0) then return false end
  if not p.onBoard and total < g.opening then return false end
  local after = p.score + total
  if g.finalRound then
    -- last chance: keep rolling until we're ahead
    return after > g:LeaderScoreExcept(g.current)
  end
  if after >= g.target then return true end
  -- hot dice with a small turn: always roll the fresh six
  if diceLeft == 0 then return total >= S.bankAt[6] end
  return total >= (S.bankAt[diceLeft] or 300)
end

local function delay()
  return 1.1 * (ns.db and ns.db.speed or 1)
end

-- One bot step: roll, or choose dice then bank / roll on.
function Bots.Step(g)
  if not g:IsLive() then return end
  local p = g:Player()
  if not p.bot then return end
  if g.phase == "ready" then
    g:Roll()
  elseif g.phase == "choosing" then
    local o = Bots.Choose(g.roll, p.bot, g.rules, g)
    if not o then return end
    g:SetSelection(o.idx, o.fiveBack)
    local total = g.turnScore + o.score
    local left = g.remaining - o.kept
    if Bots.ShouldBank(g, total, left, p.bot) and g:CanBank() then
      ns.C_After(delay() * 0.8, function() if g:IsLive() and g.phase == "choosing" then g:Bank() end end)
    else
      ns.C_After(delay() * 0.8, function() if g:IsLive() and g.phase == "choosing" then g:Roll() end end)
    end
  end
end

function Bots.Schedule(g)
  g.botToken = (g.botToken or 0) + 1
  local myToken = g.botToken
  ns.C_After(delay(), function()
    if g.botToken == myToken then Bots.Step(g) end
  end)
end
