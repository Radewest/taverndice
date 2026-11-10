-- TavernDice: Core
-- Namespace, saved variables, safe event bus, internal callbacks, chat helpers, slash commands.
-- Same proven structure as Tjommie. Rename "TavernDice" everywhere when starting a new add-on.

local ADDON, ns = ...
_G.TavernDice = ns -- handy for /dump TavernDice while developing

ns.VERSION = "0.2.2"   -- keep in sync with ## Version in both TOCs

---------------------------------------------------------------------------
-- API shims (Forever runs the modern Midnight-era client; keep fallbacks anyway)
---------------------------------------------------------------------------
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Timers that run through SafeCall, so errors land in the bug log
function ns.C_After(sec, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(sec, function() ns.SafeCall(fn) end)
  else
    ns.SafeCall(fn)
  end
end

ns.COLOR = "|cffffb347"   -- warm tavern amber

-- Midnight "secret values": some data is hidden from add-ons in combat/instances.
function ns.IsSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Safe calls: every handler runs through this, so errors land in the bug log (Bugs.lua)
---------------------------------------------------------------------------
local function addStack(e)
  return tostring(e) .. "\n" .. (debugstack and debugstack(2, 10, 0) or "")
end

function ns.SafeCall(fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, addStack)
  if not ok then ns:ReportError(err) end
  return ok
end

function ns:ReportError(err, skipHandler)
  if self.LogError then pcall(self.LogError, self, err) end
  if not skipHandler then
    self.reporting = true
    pcall(geterrorhandler(), (tostring(err):match("^[^\n]*")))
    self.reporting = false
  end
end

---------------------------------------------------------------------------
-- Event bus: ns:On("EVENT", fn)  /  internal callbacks: ns:Listen / ns:Fire
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns:On(event, fn)
  if not eventHandlers[event] then
    eventHandlers[event] = {}
    eventFrame:RegisterEvent(event)
  end
  table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = eventHandlers[event]
  if not list then return end
  for _, fn in ipairs(list) do ns.SafeCall(fn, ...) end
end)

local callbacks = {}
function ns:Listen(name, fn)
  callbacks[name] = callbacks[name] or {}
  table.insert(callbacks[name], fn)
end
function ns:Fire(name, ...)
  local list = callbacks[name]
  if not list then return end
  for _, fn in ipairs(list) do ns.SafeCall(fn, ...) end
end

---------------------------------------------------------------------------
-- Saved variables (defaults are merged in, so new settings appear for existing users)
---------------------------------------------------------------------------
local DEFAULTS = {
  errors = {},          -- bug log (Bugs.lua)
  chat = "important",   -- "off" | "important" | "all"
  target = 10000,       -- points to win
  opening = 500,        -- points needed in one turn to get "on the board" (first bank only)
  ruleset = "classic",  -- "classic" | "mumpits" (Scoring.lua RULESETS)
  opponents = { "balanced" },  -- bot styles (Bots.lua), 1-3 of them
  server = false,       -- use real /roll dice (needed for fair multiplayer; optional solo)
  hideRollLines = true, -- hide our own /roll lines from chat
  speed = 1,            -- bot / pause speed multiplier (lower = faster)
  sound = true,
  discoverable = true,  -- join the hidden channel and answer "who has Tavern Dice?" (Nearby.lua)
  tableTalk = "auto",   -- "auto" (friend beside you) | "always" | "off"  (Talk.lua)
  ui = {},              -- window position and scale
  minimap = { angle = 210, hide = false },
  welcomed = false,
}
local CHAR_DEFAULTS = {
  stats = { games = 0, wins = 0, farkles = 0, hotDice = 0, bestTurn = 0, banked = 0, highScore = 0 },
}

local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; applyDefaults(dst[k], v) else dst[k] = v end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      applyDefaults(dst[k], v)
    end
  end
end

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  TavernDiceDB = TavernDiceDB or {}
  TavernDiceCharDB = TavernDiceCharDB or {}
  applyDefaults(TavernDiceDB, DEFAULTS)
  applyDefaults(TavernDiceCharDB, CHAR_DEFAULTS)
  ns.db, ns.cdb = TavernDiceDB, TavernDiceCharDB
  ns:Fire("DB_READY")
end)

ns:On("PLAYER_LOGIN", function() ns:Fire("LOGIN") end)

---------------------------------------------------------------------------
-- Chat: ns:Print for direct replies to slash commands; ns:Chat respects the chat setting
---------------------------------------------------------------------------
function ns:Print(msg)
  print(ns.COLOR .. "Tavern Dice|r: " .. tostring(msg))
end

function ns:Chat(msg, level)
  local setting = self.db and self.db.chat or "important"
  if setting == "off" then return end
  if level == "all" and setting ~= "all" then return end
  self:Print(msg)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/dice  - open or close the dice table",
  "/dice new  - start a new game with your current settings",
  "/dice invite [name]  - invite a friend (or your target) to play",
  "/dice tjommie  - invite your tjommie (needs Tjommie)",
  "/dice leave  - leave a game with a friend",
  "/dice findme  - let nearby players find you (on/off)",
  "/dice server | local  - real /roll dice from the server, or quiet local dice",
  "/dice stats  - your record at the table",
  "/dice minimap  - show or hide the minimap button",
  "/dice reset  - put the window back in the middle",
  "/dice bugs  - copy the bug log for the developer",
}

SLASH_TAVERNDICE1 = "/dice"
SLASH_TAVERNDICE2 = "/taverndice"
SlashCmdList.TAVERNDICE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns:ToggleWindow() end
  elseif cmd == "new" then
    if ns.StartFromSettings then ns:StartFromSettings(); ns:ShowWindow() end
  elseif cmd == "invite" then
    if rest ~= "" then ns:Invite(rest) else ns:InviteTarget() end
  elseif cmd == "tjommie" then
    ns:InviteTjommie()
  elseif cmd == "findme" then
    ns.db.discoverable = not ns.db.discoverable
    if ns.db.discoverable then ns:JoinTableChannel() else ns:LeaveTableChannel() end
    ns:Print(ns.db.discoverable and "Nearby players with Tavern Dice can find you, and you them." or "You're hidden: nobody can find you, and you won't find them.")
  elseif cmd == "leave" then
    ns:LeaveTable()
  elseif cmd == "server" or cmd == "local" then
    ns.db.server = (cmd == "server")
    ns:Print(ns.db.server and "Dice now come from the server's /roll (applies to your next game)." or "Dice are rolled locally (applies to your next game).")
    ns:Fire("TD_UPDATE")
  elseif cmd == "stats" then
    local s = ns.cdb.stats
    ns:Print(string.format("Games %d, wins %d, best turn %d, high score %d, farkles %d, hot dice %d.",
      s.games, s.wins, s.bestTurn, s.highScore, s.farkles, s.hotDice))
  elseif cmd == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    if TavernDiceMinimapButton then TavernDiceMinimapButton:SetShown(not ns.db.minimap.hide) end
    ns:Print(ns.db.minimap.hide and "Minimap button hidden." or "Minimap button shown.")
  elseif cmd == "reset" then
    if ns.ResetWindow then ns:ResetWindow() end
  elseif cmd == "bugs" then
    if rest == "clear" then ns:ClearErrors() else ns:ShowBugs() end
  else
    ns:Print("v" .. ns.VERSION)
    for _, l in ipairs(HELP) do ns:Print(l) end
  end
end
