-- TavernDice: Dice
-- Where the numbers come from.
--
--  "local"  : the client's random numbers. Quiet, instant; right for solo games against bots.
--  "server" : one real /roll per throw, so the numbers come from Blizzard's server and nobody
--             can tamper with them. We roll 0 .. 6^n - 1 and read the result as n base-6 digits,
--             which gives n fair dice from a single /roll. Our own roll lines are hidden from
--             chat. If no result arrives within a few seconds we fall back to local dice.

local _, ns = ...

ns.Dice = {}
local Dice = ns.Dice

local pending      -- { n, max, cb, token }
local token = 0
local ROLL_TIMEOUT = 4

-- Turn a number 0 .. 6^n - 1 into n dice (each 1..6). Exposed for tests.
function Dice.Decode(value, n)
  local out = {}
  for i = 1, n do
    out[i] = (value % 6) + 1
    value = math.floor(value / 6)
  end
  return out
end

function Dice.MaxFor(n)
  local m = 1
  for _ = 1, n do m = m * 6 end
  return m - 1
end

local function localRoll(n)
  local out = {}
  for i = 1, n do out[i] = math.random(1, 6) end
  return out
end

local function rollFunction()
  if C_RandomRoll and C_RandomRoll.RandomRoll then return C_RandomRoll.RandomRoll end
  return RandomRoll
end

function Dice.ServerAvailable()
  return rollFunction() ~= nil
end

-- Roll n dice and call cb(dice, source). source = "server" | "local" | "fallback".
function Dice.Roll(n, cb, wantServer)
  local fn = rollFunction()
  if not wantServer or not fn then
    cb(localRoll(n), "local")
    return
  end
  token = token + 1
  local myToken = token
  local max = Dice.MaxFor(n)
  pending = { n = n, max = max, cb = cb, token = myToken }
  local ok = pcall(fn, 0, max)
  if not ok then
    pending = nil
    cb(localRoll(n), "fallback")
    return
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(ROLL_TIMEOUT, function()
      if pending and pending.token == myToken then
        pending = nil
        ns:Chat("The server roll didn't come back, so these dice were rolled locally.", "important")
        cb(localRoll(n), "fallback")
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Reading "Harry rolls 31337 (0-46655)" from system chat
---------------------------------------------------------------------------
local rollPattern
local function getPattern()
  if rollPattern then return rollPattern end
  local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  -- escape magic characters, then turn %s / %d into captures
  local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  rollPattern = "^" .. p .. "$"
  return rollPattern
end
Dice.GetPattern = getPattern

local function myName()
  local n = UnitName and UnitName("player")
  return n
end

local function parseRoll(msg)
  if type(msg) ~= "string" or ns.IsSecret(msg) then return end
  local who, value, low, high = msg:match(getPattern())
  if not who then return end
  if Ambiguate then who = Ambiguate(who, "short") end
  return who, tonumber(value), tonumber(low), tonumber(high)
end

local function isDiceRange(low, high)
  if low ~= 0 then return false end
  for n = 2, 6 do if high == Dice.MaxFor(n) then return true end end
  return false
end

-- The friend we're playing (short name), if any
local function opponentShort()
  local g = ns.game
  if not (g and g.net) then return nil end
  return (strsplit("-", g.net))
end

-- Is this one of the table's dice rolls (ours, or our friend's)? Used to hide it from chat.
local function isTableRoll(msg)
  local who, _, low, high = parseRoll(msg)
  if not who then return false end
  if who == myName() then
    return isDiceRange(low, high) or (pending ~= nil and low == 0 and high == pending.max)
  end
  return who == opponentShort() and isDiceRange(low, high)
end

-- Other players' dice-shaped rolls, kept briefly so a friend's server roll can be checked
Dice.seen = {}
function Dice.WasSeen(who, value, withinSec)
  local now = GetTime and GetTime() or 0
  for i = #Dice.seen, 1, -1 do
    local r = Dice.seen[i]
    if r.who == who and r.value == value and now - r.t <= (withinSec or 15) then return true end
  end
  return false
end

ns:On("CHAT_MSG_SYSTEM", function(msg)
  local who, value, low, high = parseRoll(msg)
  if not who or not value then return end
  if who ~= myName() then
    if isDiceRange(low, high) or (low == 0 and high == 5) then
      table.insert(Dice.seen, { who = who, value = value, high = high, t = GetTime and GetTime() or 0 })
      while #Dice.seen > 20 do table.remove(Dice.seen, 1) end
    end
    return
  end
  if not pending then return end
  if low ~= 0 or high ~= pending.max then return end
  local p = pending
  pending = nil
  p.cb(Dice.Decode(value, p.n), "server", value)
end)

-- Hide the table's 0-46655 style lines (they mean nothing to a human reader).
local function chatFilter(_, _, msg)
  if ns.db and ns.db.hideRollLines and isTableRoll(msg) then return true end
  return false
end

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then pcall(addFilter, "CHAT_MSG_SYSTEM", chatFilter) end
Dice._filter = chatFilter
