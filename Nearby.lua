-- TavernDice: Nearby
-- "Who around here has Tavern Dice?" so you can invite them in one click.
--
-- How we find people (all invisible add-on messages, nothing shows in chat):
--   * a hidden custom channel ("TavernDiceTable"): we ask WHO with our position; only players
--     within NEAR_YARDS of us answer
--   * your party/raid and guild: everyone with the add-on answers, wherever they are
--   * targeting a player: one quiet whisper asks if they have the add-on
-- Answers (HERE) come back by whisper. Known players also get a line on their tooltip.
-- db.discoverable = false: don't join the channel and don't answer anyone.
--
-- Wire (append-only):
--   WHO~version~continent~x~y              (x, y = world yards; empty when we don't know)
--   HERE~version~continent~x~y~zone~busy~class

local _, ns = ...

local CHANNEL = "TavernDiceTable"
local NEAR_YARDS = 250       -- channel answers only from this close
local KEEP_SECONDS = 180     -- how long someone stays on the list
local SCAN_COOLDOWN = 10

ns.nearby = {}               -- lower(full name) -> entry
local lastScan, lastAnswer, lastTargetAsk = 0, {}, {}

local function now() return GetTime and GetTime() or 0 end
local function myFull() return ns.FullName(UnitName and UnitName("player")) end

---------------------------------------------------------------------------
-- Where am I? (continent + world yards; nil inside instances or when unknown)
---------------------------------------------------------------------------
function ns.MyWorldPos()
  if IsInInstance and IsInInstance() then return nil end
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID or ns.IsSecret(mapID) then return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  local cont, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
  if not (cont and world) then return nil end
  local x, y = world:GetXY()
  if not x or ns.IsSecret(x) then return nil end
  return cont, math.floor(x), math.floor(y)
end

local function distanceTo(cont, x, y)
  cont, x, y = tonumber(cont), tonumber(x), tonumber(y)
  local mc, mx, my = ns.MyWorldPos()
  if not (cont and x and mc) or cont ~= mc then return nil end
  return math.floor(math.sqrt((x - mx) ^ 2 + (y - my) ^ 2))
end
ns.DistanceTo = distanceTo

---------------------------------------------------------------------------
-- The hidden channel
---------------------------------------------------------------------------
local function channelId()
  if not GetChannelName then return nil end
  local id = GetChannelName(CHANNEL)
  if id and id > 0 then return id end
end

local function hideChannelFromChat()
  local remove = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or ChatFrame_RemoveChannel
  if not remove then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf then pcall(remove, cf, CHANNEL) end
  end
end

function ns:JoinTableChannel()
  if not (ns.db and ns.db.discoverable) or channelId() then return end
  if JoinTemporaryChannel then pcall(JoinTemporaryChannel, CHANNEL) end
  ns.C_After(2, hideChannelFromChat)
end

function ns:LeaveTableChannel()
  if channelId() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
end

-- Hide the "Joined channel" / "Left channel" notices for our channel
local function noticeFilter(_, _, _, _, _, _, _, _, _, channelName)
  if type(channelName) == "string" and not ns.IsSecret(channelName) and channelName:lower():find(CHANNEL:lower(), 1, true) then
    return true
  end
  return false
end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  pcall(addFilter, "CHAT_MSG_CHANNEL_NOTICE", noticeFilter)
  pcall(addFilter, "CHAT_MSG_CHANNEL_NOTICE_USER", noticeFilter)
end
ns._noticeFilter = noticeFilter

ns:Listen("LOGIN", function() ns.C_After(12, function() ns:JoinTableChannel() end) end)

---------------------------------------------------------------------------
-- Asking and answering
---------------------------------------------------------------------------
local function send(kind, chatType, target, ...)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local parts = { kind, ... }
  for i = 1, #parts do parts[i] = tostring(parts[i] == nil and "" or parts[i]):gsub("[~|]", "") end
  pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, table.concat(parts, "~"), chatType, target)
end

local function whoArgs()
  local c, x, y = ns.MyWorldPos()
  return ns.VERSION, c or "", x or "", y or ""
end

-- Look around: ask the channel, the group and the guild
function ns:ScanNearby(force)
  if not force and now() - lastScan < SCAN_COOLDOWN then return false end
  lastScan = now()
  ns:JoinTableChannel()
  local id = channelId()
  if id then send("WHO", "CHANNEL", id, whoArgs()) end
  if IsInRaid and IsInRaid() then send("WHO", "RAID", nil, whoArgs())
  elseif IsInGroup and IsInGroup() then send("WHO", "PARTY", nil, whoArgs()) end
  if IsInGuild and IsInGuild() then send("WHO", "GUILD", nil, whoArgs()) end
  return true
end

-- Quietly ask one player (used when you target someone)
function ns:AskPlayer(full)
  if not full then return end
  ns:SendTo(full, "WHO", whoArgs())
end

local function answer(to)
  local c, x, y = ns.MyWorldPos()
  local zone = GetZoneText and GetZoneText() or ""
  if ns.IsSecret(zone) then zone = "" end
  local busy = (ns.game and ns.game.net and ns.game.phase ~= "over") and 1 or 0
  local _, class = UnitClass and UnitClass("player")
  ns:SendTo(to, "HERE", ns.VERSION, c or "", x or "", y or "", zone, busy, class or "")
end

ns.netHandlers.WHO = function(from, version, cont, x, y)
  if not (ns.db and ns.db.discoverable) or ns.SameName(from, myFull()) then return end
  local via = ns.netChannel
  if via == "CHANNEL" then
    -- strangers on the channel: only answer when we're actually near each other
    local d = distanceTo(cont, x, y)
    if not d or d > NEAR_YARDS then return end
  end
  local key = from:lower()
  if lastAnswer[key] and now() - lastAnswer[key] < 5 then return end
  lastAnswer[key] = now()
  answer(from)
end

local VIA_LABEL = { PARTY = "group", RAID = "group", GUILD = "guild" }

ns.netHandlers.HERE = function(from, version, cont, x, y, zone, busy, class)
  if ns.SameName(from, myFull()) then return end
  local key = from:lower()
  local e = ns.nearby[key] or {}
  e.name, e.short = from, ns.ShortName(from)
  e.version, e.zone, e.class = version, zone ~= "" and zone or nil, class ~= "" and class or nil
  e.busy = busy == "1"
  e.dist = distanceTo(cont, x, y)
  e.at = now()
  ns.nearby[key] = e
  ns:Fire("TD_NEARBY")
end

-- Sorted list: nearest first, then the rest by name; old entries dropped
function ns:NearbyList()
  local out = {}
  for key, e in pairs(ns.nearby) do
    if now() - (e.at or 0) > KEEP_SECONDS then ns.nearby[key] = nil else out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    return a.short < b.short
  end)
  return out
end

function ns:HasAddon(full)
  local e = full and ns.nearby[full:lower()]
  return e and now() - (e.at or 0) <= 600
end

---------------------------------------------------------------------------
-- Targeting a player asks them quietly (same faction only; once per 5 minutes each)
---------------------------------------------------------------------------
ns:On("PLAYER_TARGET_CHANGED", function()
  if not (ns.db and ns.db.discoverable) then return end
  if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then return end
  if UnitIsUnit and UnitIsUnit("target", "player") then return end
  if UnitFactionGroup and UnitFactionGroup("target") ~= UnitFactionGroup("player") then return end
  local name, realm = UnitName("target")
  if not name or ns.IsSecret(name) then return end
  local full = ns.FullName(realm and realm ~= "" and (name .. "-" .. realm) or name)
  local key = full:lower()
  if lastTargetAsk[key] and now() - lastTargetAsk[key] < 300 then return end
  lastTargetAsk[key] = now()
  ns:AskPlayer(full)
end)

---------------------------------------------------------------------------
-- Tooltip line for players we know have the add-on
---------------------------------------------------------------------------
local function addTooltipLine(tt)
  if not tt or not tt.GetUnit then return end
  local _, unit = tt:GetUnit()
  if not unit or not UnitIsPlayer(unit) then return end
  local name, realm = UnitName(unit)
  if not name or ns.IsSecret(name) then return end
  local full = ns.FullName(realm and realm ~= "" and (name .. "-" .. realm) or name)
  if ns:HasAddon(full) then
    tt:AddLine(ns.COLOR .. "Tavern Dice|r: up for a game", 1, 1, 1)
  end
end

ns:Listen("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt) ns.SafeCall(addTooltipLine, tt) end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) ns.SafeCall(addTooltipLine, tt) end)
  end
end)
