-- TavernDice: Scoring
-- Pure rules for 10,000 (Farkle / Dix Mille). No WoW API calls here, so it's easy to test.
--
-- Default rules (house-rule toggles come later; keep every number in ns.RULES):
--   single 1 = 100, single 5 = 50
--   three of a kind = face x 100 (three 1s = 1000)
--   each extra die of that kind doubles it (4 = x2, 5 = x4, 6 = x8)
--   straight 1-2-3-4-5-6 = 1500, three pairs = 1000 (six dice only)

local _, ns = ...

ns.RULES = {
  single1 = 100,
  single5 = 50,
  tripleOnes = 1000,
  tripleFaceMult = 100,
  straight = 1500,
  threePairs = 1000,
}

-- Rulesets (picked in the new-game panel). Scoring above is shared; these change how a turn plays.
--   minBank   : you can never bank less than this in one turn
--   fivesPair : two 5s can be "made a 1": they count 100 and one 5 goes back in the cup to roll
--               again. Or keep both as two 5s (also 100). Every roll scores on its own.
ns.RULESETS = {
  classic = { key = "classic", name = "Classic", minBank = 0, fivesPair = false },
  mumpets = { key = "mumpets", name = "Mumpets", minBank = 400, fivesPair = true,
              straight = 3000, straightChase = true, chasePenalty = 500 },
--   straight      : what 1-2-3-4-5-6 scores (default ns.RULES.straight, 1,500)
--   straightChase : with six dice showing five different numbers, you may reroll the spare die
--                   for the missing one. Hit = the straight. Miss = turn over, lose the turn's
--                   points and chasePenalty off your score (it can go below 0).
}
ns.RULESETS.mumpits = ns.RULESETS.mumpets   -- old name (v0.1.1 - v0.2.4): saved settings and invites

ns.RULESET_ORDER = { "classic", "mumpets" }

local function counts(dice)
  local c = { 0, 0, 0, 0, 0, 0 }
  for _, v in ipairs(dice) do c[v] = c[v] + 1 end
  return c
end
ns.CountDice = counts

-- Score a set of dice the player wants to set aside.
-- Returns score, valid, canThrowBack. valid = every die in the set contributes to the score.
-- canThrowBack = 1 when the player may put one of a pair of 5s back in the cup (Mumpets);
-- the score is 100 either way, so it's the player's choice (Game.fiveBack).
function ns.ScoreSelection(dice, rules)
  local R = ns.RULES
  local n = #dice
  if n == 0 then return 0, false end
  local c = counts(dice)

  -- Six-dice specials
  local special = 0
  if n == 6 then
    local ones, pairs2 = 0, 0
    for f = 1, 6 do
      if c[f] == 1 then ones = ones + 1 end
      if c[f] == 2 then pairs2 = pairs2 + 1 end
    end
    if ones == 6 then special = (rules and rules.straight) or R.straight end
    if pairs2 == 3 then special = math.max(special, R.threePairs) end
  end

  -- Kinds and singles
  local score, valid = 0, true
  for f = 1, 6 do
    local k = c[f]
    if k >= 3 then
      local base = (f == 1) and R.tripleOnes or f * R.tripleFaceMult
      for _ = 4, k do base = base * 2 end
      score = score + base
    elseif k > 0 then
      if f == 1 then score = score + R.single1 * k
      elseif f == 5 then score = score + R.single5 * k
      else valid = false end
    end
  end

  if special > 0 and (special >= score or not valid) then return special, true, 0 end
  if not valid then return 0, false, 0 end
  local refund = (rules and rules.fivesPair and c[5] == 2) and 1 or 0
  return score, true, refund
end

-- Every valid way to set dice aside from a roll: list of { idx = {...}, score, kept }
function ns.ScoringOptions(roll, rules)
  local opts = {}
  local n = #roll
  local total = 1
  for _ = 1, n do total = total * 2 end
  for mask = 1, total - 1 do
    local idx, vals = {}, {}
    local m = mask
    for i = 1, n do
      local bitOn = m % 2 == 1
      m = math.floor(m / 2)
      if bitOn then
        idx[#idx + 1] = i
        vals[#vals + 1] = roll[i]
      end
    end
    local s, ok, can = ns.ScoreSelection(vals, rules)
    if ok and s > 0 then
      opts[#opts + 1] = { idx = idx, score = s, kept = #idx, fiveBack = (can > 0) and false or nil }
      if can > 0 then opts[#opts + 1] = { idx = idx, score = s, kept = #idx - 1, fiveBack = true } end
    end
  end
  return opts
end

-- Best possible score in a roll (0 = Farkle)
function ns.BestScore(roll)
  local best = 0
  for _, o in ipairs(ns.ScoringOptions(roll)) do
    if o.score > best then best = o.score end
  end
  return best
end

function ns.IsFarkle(roll)
  return ns.BestScore(roll) == 0
end
