-- TavernDice: Game
-- The turn-by-turn state machine for one game of 10,000.
--
-- Phases:  ready (turn started, nothing rolled) -> rolling (waiting for dice) ->
--          choosing (pick scoring dice, then Roll on or Bank) -> farkle (short pause) -> next turn
--          over (someone won)
-- When a player reaches the target, everyone else gets one last turn; highest score wins.
--
-- The UI and bots only call the public methods below; everything else fires
--   ns:Fire("TD_UPDATE")              -> redraw
--   ns:Fire("TD_EVENT", kind, ...)    -> narration / sounds / toasts
--   ns:Fire("TD_NET", kind, ...)      -> (friend games) what to tell the other table, see Comms.lua
--
-- Players are local (you), bots, or remote (a friend's own client plays that seat and sends
-- us their actions). In a friend game both clients run this same state machine in lockstep.

local _, ns = ...

local Game = {}
Game.__index = Game
ns.GameClass = Game

local FARKLE_PAUSE = 1.8

local after = function(sec, fn) return ns.C_After(sec, fn) end

-- opts: { players = { {name=, bot=style|nil, remote=bool}, ... }, target=, opening=, ruleset=,
--         server=bool, net = friend's "Name-Realm" (friend games), netId = shared game id }
function ns:NewGame(opts)
  local g = setmetatable({}, Game)
  g.players = {}
  for i, p in ipairs(opts.players) do
    g.players[i] = { name = p.name, bot = p.bot, remote = p.remote, full = p.full,
      score = 0, onBoard = false, farkles = 0, bestTurn = 0 }
  end
  g.target = opts.target or 10000
  g.opening = opts.opening or 500
  g.rules = ns.RULESETS[opts.ruleset or "classic"] or ns.RULESETS.classic
  g.minBank = g.rules.minBank or 0
  g.server = opts.server and true or false
  g.net, g.netId = opts.net, opts.netId
  g.id = (ns.gameCounter or 0) + 1
  ns.gameCounter = g.id
  g.current = 1
  g.turnNo = 0
  g.finalRound = false
  ns.game = g
  ns:Fire("TD_EVENT", "START", g)
  g:StartTurn(1)
  return g
end

function Game:Player() return self.players[self.current] end
function Game:IsMyTurn() local p = self:Player(); return p and not p.bot and not p.remote and self.phase ~= "over" end
function Game:IsLocal(p) p = p or self:Player(); return p and not p.bot and not p.remote end

-- Selection as a digit string ("135") for the wire
function Game:SelectionString()
  local t = {}
  for i = 1, #self.roll do if self.selected[i] then t[#t + 1] = tostring(i) end end
  return table.concat(t)
end

local function netSend(self, kind, ...)
  if self.net and self:IsLocal() then ns:Fire("TD_NET", kind, self, ...) end
end
function Game:IsLive() return ns.game == self and self.phase ~= "over" end

function Game:StartTurn(idx)
  self.current = idx
  self.turnNo = self.turnNo + 1
  self.turnScore = 0
  self.remaining = 6
  self.kept = {}
  self.combo = { [1] = 0, [5] = 0 }   -- 1s and 5s set aside since the last full cup (Mumpits)
  self.roll = {}
  self.selected = {}
  self.phase = "ready"
  ns:Fire("TD_EVENT", "TURN", self:Player(), self)
  ns:Fire("TD_UPDATE")
  self:Kick()
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
function Game:SelectedValues()
  local vals = {}
  for i = 1, #self.roll do if self.selected[i] then vals[#vals + 1] = self.roll[i] end end
  return vals
end

-- Mumpits: with a pair of 5s selected, does one go back in the cup?
-- self.fiveBack: true / false when the player chose, nil = automatic: throw one back,
-- unless keeping both uses every die left (then it's hot dice, which is better).
function Game:FiveBackActive(nVals, can)
  if not can or can == 0 then return false end
  if self.fiveBack ~= nil then return self.fiveBack end
  return nVals < self.remaining
end

local function fbWire(v) if v == nil then return "" end return v and "1" or "0" end
local function fbParse(s) if s == "1" then return true elseif s == "0" then return false end return nil end

-- Points these dice add to the turn. In Mumpits, 1s and 5s already set aside count with them
-- (two 1s earlier + one 1 now = three 1s = 1,000, so this 1 adds 800).
-- Returns score, valid, canThrowBack
function Game:GainFor(vals)
  local s, ok, can = ns.ScoreSelection(vals, self.rules)
  if not ok or not (self.rules and self.rules.comboAcross) then return s, ok, can end
  local combo = self.combo or { [1] = 0, [5] = 0 }
  if combo[1] + combo[5] == 0 then return s, ok, can end
  local rest, c1, c5 = {}, 0, 0
  for _, v in ipairs(vals) do
    if v == 1 then c1 = c1 + 1 elseif v == 5 then c5 = c5 + 1 else rest[#rest + 1] = v end
  end
  local gain = 0
  if #rest > 0 then
    local rs, rok = ns.ScoreSelection(rest, self.rules)
    if not rok then return 0, false, can end
    gain = rs
  end
  gain = gain + ns.OnesFivesScore(1, combo[1] + c1) - ns.OnesFivesScore(1, combo[1])
              + ns.OnesFivesScore(5, combo[5] + c5) - ns.OnesFivesScore(5, combo[5])
  return gain, ok, can
end

-- Returns score, valid, dice used (that leave the cup), dice thrown back, canThrowBack
function Game:SelectionScore()
  local vals = self:SelectedValues()
  if #vals == 0 then return 0, false, 0, 0, 0 end
  local s, ok, can = self:GainFor(vals)
  local back = (ok and self:FiveBackActive(#vals, can)) and 1 or 0
  return s, ok, #vals - back, back, can or 0
end

function Game:Toggle(i)
  if self.phase ~= "choosing" or not self.roll[i] then return end
  self.selected[i] = not self.selected[i] or nil
  self.fiveBack = nil
  netSend(self, "T", self.turnNo, self:SelectionString(), "")
  ns:Fire("TD_UPDATE")
end

-- Keep both 5s (false) or throw one back (true)
function Game:SetFiveBack(v)
  if self.phase ~= "choosing" then return end
  self.fiveBack = v and true or false
  netSend(self, "T", self.turnNo, self:SelectionString(), fbWire(self.fiveBack))
  ns:Fire("TD_UPDATE")
end

function Game:SetSelection(idxList, fiveBack)
  self.selected = {}
  for _, i in ipairs(idxList) do self.selected[i] = true end
  self.fiveBack = fiveBack
  ns:Fire("TD_UPDATE")
end

-- Points this turn if you banked right now (0 if the selection isn't valid)
function Game:PendingTotal()
  local s, ok = self:SelectionScore()
  if not ok then return 0 end
  return self.turnScore + s
end

function Game:CanRoll()
  if self.phase == "ready" then return true end
  if self.phase ~= "choosing" then return false end
  local s, ok = self:SelectionScore()
  return ok and s > 0
end

function Game:CanBank()
  if self.phase ~= "choosing" then return false end
  local s, ok = self:SelectionScore()
  if not ok or s <= 0 then return false end
  local p = self:Player()
  local total = self.turnScore + s
  if total < (self.minBank or 0) then return false end
  return p.onBoard or total >= self.opening
end

-- How many dice the next roll would use (after setting the selection aside)
function Game:NextRollCount()
  if self.phase == "ready" then return self.remaining end
  local _, ok, n = self:SelectionScore()
  if not ok then return self.remaining end
  local left = self.remaining - n
  return left == 0 and 6 or left
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Game:Roll()
  if not self:CanRoll() then return false end
  netSend(self, "A", self.turnNo, self:SelectionString(), "r", fbWire(self.fiveBack))
  if self.phase == "choosing" then
    local s, _, n, refund = self:SelectionScore()
    self.turnScore = self.turnScore + s
    local skip5 = refund > 0
    self.combo = self.combo or { [1] = 0, [5] = 0 }
    for _, v in ipairs(self:SelectedValues()) do
      if v == 1 or v == 5 then self.combo[v] = self.combo[v] + 1 end   -- a thrown-back 5 still counted
      if skip5 and v == 5 then skip5 = false else self.kept[#self.kept + 1] = v end
    end
    if refund > 0 then ns:Fire("TD_EVENT", "FIVEBACK", self:Player()) end
    self.remaining = self.remaining - n
    if self.remaining == 0 then
      self.remaining = 6
      self.kept = {}
      self.combo = { [1] = 0, [5] = 0 }
      ns:Fire("TD_EVENT", "HOTDICE", self:Player(), self.turnScore)
    end
  end
  self.phase = "rolling"
  self.roll, self.selected, self.fiveBack = {}, {}, nil
  ns:Fire("TD_EVENT", "ROLLING", self:Player(), self.remaining)
  ns:Fire("TD_UPDATE")
  -- A friend's seat: their client rolls and sends us the dice (Comms -> RemoteRolled)
  if self:Player().remote then return true end
  local myId, myTurn = self.id, self.turnNo
  ns.Dice.Roll(self.remaining, function(dice, source, raw)
    if ns.game ~= self or self.id ~= myId or self.turnNo ~= myTurn or self.phase ~= "rolling" then return end
    netSend(self, "R", self.turnNo, table.concat(dice), source, raw or "")
    self:OnRolled(dice, source)
  end, self.server)
  return true
end

function Game:OnRolled(dice, source)
  self.roll = dice
  self.rollSource = source
  self.selected = {}
  if ns.IsFarkle(dice) then
    local p = self:Player()
    p.farkles = p.farkles + 1
    local lost = self.turnScore
    self.turnScore = 0
    self.phase = "farkle"
    ns:Fire("TD_EVENT", "FARKLE", p, lost, dice)
    ns:Fire("TD_UPDATE")
    local myId, myTurn = self.id, self.turnNo
    local pause = self.net and FARKLE_PAUSE or FARKLE_PAUSE * (ns.db and ns.db.speed or 1)
    after(pause, function()
      if ns.game == self and self.id == myId and self.turnNo == myTurn and self.phase == "farkle" then
        self:EndTurn()
      end
    end)
    return
  end
  self.phase = "choosing"
  ns:Fire("TD_EVENT", "ROLLED", self:Player(), dice, source)
  ns:Fire("TD_UPDATE")
  self:Kick()
end

function Game:Bank()
  if not self:CanBank() then return false end
  netSend(self, "A", self.turnNo, self:SelectionString(), "b", fbWire(self.fiveBack))
  local p = self:Player()
  local total = self:PendingTotal()
  p.score = p.score + total
  p.onBoard = true
  if total > p.bestTurn then p.bestTurn = total end
  self.turnScore = 0
  ns:Fire("TD_EVENT", "BANK", p, total, self)
  if not self.finalRound and p.score >= self.target then
    self.finalRound = true
    self.finalTrigger = self.current
    ns:Fire("TD_EVENT", "FINAL", p, self)
  end
  self:EndTurn()
  return true
end

function Game:EndTurn()
  if self.phase == "over" then return end
  local nextIdx = self.current % #self.players + 1
  if self.finalRound and nextIdx == self.finalTrigger then
    self:Finish()
    return
  end
  self:StartTurn(nextIdx)
end

function Game:Finish()
  local best
  for _, p in ipairs(self.players) do
    if not best or p.score > best.score then best = p end
  end
  self.winner = best
  self.phase = "over"
  ns:Fire("TD_EVENT", "OVER", best, self)
  ns:Fire("TD_UPDATE")
end

function Game:Abandon()
  self.phase = "over"
  if ns.game == self then ns.game = nil end
  ns:Fire("TD_UPDATE")
end

-- Highest score among everyone except the current player
function Game:LeaderScoreExcept(idx)
  local best = 0
  for i, p in ipairs(self.players) do
    if i ~= idx and p.score > best then best = p.score end
  end
  return best
end

---------------------------------------------------------------------------
-- Applying a friend's moves (called by Comms.lua). Each carries the turn number so a
-- late or duplicate message can't be applied to the wrong turn.
---------------------------------------------------------------------------
local function parseIdx(s)
  local out = {}
  for d in tostring(s or ""):gmatch("%d") do out[#out + 1] = tonumber(d) end
  return out
end

-- Catch up if their next turn's message arrives while our farkle pause is still running
function Game:CatchUp(turn)
  turn = tonumber(turn)
  if turn and turn == self.turnNo + 1 and self.phase == "farkle" then self:EndTurn() end
  return turn == self.turnNo and self:Player().remote and self.phase ~= "over"
end

function Game:RemoteSelect(turn, idx, fb)
  if not self:CatchUp(turn) or self.phase ~= "choosing" then return end
  self:SetSelection(parseIdx(idx), fbParse(fb))
end

function Game:RemoteAction(turn, idx, act, fb)
  if not self:CatchUp(turn) then return false end
  if self.phase == "choosing" then
    self.selected = {}
    for _, i in ipairs(parseIdx(idx)) do self.selected[i] = true end
    self.fiveBack = fbParse(fb)
  end
  local ok
  if act == "b" then ok = self:Bank() else ok = self:Roll() end
  if not ok then ns:Fire("TD_EVENT", "DESYNC", self:Player()) end
  return ok
end

function Game:RemoteRolled(turn, digits, source, raw)
  if not self:CatchUp(turn) or self.phase ~= "rolling" then return false end
  local dice = parseIdx(digits)
  if #dice ~= self.remaining then ns:Fire("TD_EVENT", "DESYNC", self:Player()); return false end
  for _, v in ipairs(dice) do if v < 1 or v > 6 then return false end end
  self.lastRemoteRaw = tonumber(raw)
  self:OnRolled(dice, source)
  return true
end

-- Let a bot act if it's a bot's turn
function Game:Kick()
  local p = self:Player()
  if p and p.bot and ns.Bots then ns.Bots.Schedule(self) end
end
