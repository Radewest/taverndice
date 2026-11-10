-- TavernDice: Comms
-- Playing a friend, near or far. Same transport as Tjommie and Birdsong: Battle.net game data
-- when they're an online Battle.net friend (works across realms and factions), otherwise a
-- hidden add-on whisper (same realm and faction).
--
-- Both clients run the same Game in lockstep. Each client plays its own seat and tells the
-- other what it did; the other applies it. Nobody else's messages are accepted, except an
-- invitation, which always needs an Accept click.
--
-- Wire format (append fields only; "~" separator, never "|"):
--   INV~version~gameId~ruleset~target~opening~server     invitation
--   ACC~gameId~version                                   accepted
--   DEC~gameId                                           declined
--   T~gameId~turn~selection                              live selection ("135" = dice 1, 3, 5)
--   A~gameId~turn~selection~act                          act: r = roll on, b = bank
--   R~gameId~turn~dice~source~raw                        my roll ("251346"); raw = the /roll value
--   Q~gameId                                             I left the table

local _, ns = ...

local PREFIX = "TavernDice"
ns.PREFIX = PREFIX
local SEP = "~"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end

local INVITE_TIMEOUT = 45
local GREY, GOLD = "|cff999999", "|cffffd100"

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function normRealm(r) return r and (r:gsub("[%s%-']", "")) or nil end

function ns.FullName(name)
  if type(name) ~= "string" or name == "" or ns.IsSecret(name) then return nil end
  if not name:find("-", 1, true) then
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm then name = name .. "-" .. realm end
  end
  return name
end

function ns.ShortName(full) return full and (strsplit("-", full)) or "?" end

local function myFull() return ns.FullName(UnitName and UnitName("player")) end

local function same(a, b)
  a, b = ns.FullName(a), ns.FullName(b)
  return a and b and a:lower() == b:lower()
end
ns.SameName = same

---------------------------------------------------------------------------
-- Sending (Battle.net if possible)
---------------------------------------------------------------------------
local function findBNet(fullName)
  if not fullName or not BNGetNumFriends or not C_BattleNet or not C_BattleNet.GetFriendNumGameAccounts then return nil end
  local name, realm = strsplit("-", fullName, 2)
  for i = 1, (BNGetNumFriends() or 0) do
    for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
      local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
      if g and g.isOnline and g.characterName and g.characterName:lower() == name:lower() then
        local r = normRealm(g.realmName)
        if not realm or not r or r:lower() == realm:lower() then return g.gameAccountID end
      end
    end
  end
end

function ns:SendTo(target, ...)
  if not target then return end
  local parts = { ... }
  for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]):gsub("[~|]", "") end
  local msg = table.concat(parts, SEP)
  if #msg > 250 then msg = msg:sub(1, 250) end
  local gid = findBNet(target)
  if gid and BNSendGameData then
    pcall(BNSendGameData, gid, PREFIX, msg)
  elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", target) -- blocked in some instances: pcall
  end
end

-- Moves made at our table go to the friend (Game.lua fires TD_NET for our own seat only)
ns:Listen("TD_NET", function(kind, g, ...)
  if g and g.net and ns.game == g then ns:SendTo(g.net, kind, g.netId, ...) end
end)

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------
function ns.CompareVersions(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return nil end
  local pa, pb = {}, {}
  for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  if #pa == 0 or #pb == 0 then return nil end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

local function versionNote(who, theirs)
  local cmp = ns.CompareVersions(ns.VERSION, theirs)
  if not cmp or cmp == 0 then return end
  local short = ns.ShortName(who)
  if cmp > 0 then
    ns.AddLog(GOLD .. short .. " has Tavern Dice v" .. theirs .. " (you have v" .. ns.VERSION .. "). Ask them to update.|r")
  else
    ns.AddLog(GOLD .. short .. " has a newer Tavern Dice (v" .. theirs .. "). Grab the update from CurseForge.|r")
  end
end

---------------------------------------------------------------------------
-- Starting a friend game
---------------------------------------------------------------------------
local outgoing   -- { to, id, at }
local lastInvite = {}

local function startNetGame(friend, id, set, iAmHost)
  if ns.game and ns.game.phase ~= "over" then
    if ns.game.net then ns:SendTo(ns.game.net, "Q", ns.game.netId) end
    ns.game:Abandon()
  end
  local me = { name = UnitName("player") or "You" }
  local them = { name = ns.ShortName(friend), remote = true, full = friend }
  local players = iAmHost and { me, them } or { them, me }
  local g = ns:NewGame({
    players = players, target = set.target, opening = set.opening, ruleset = set.ruleset,
    server = set.server, net = friend, netId = id,
  })
  ns.AddLog(GREY .. (iAmHost and "You go first." or (ns.ShortName(friend) .. " goes first.")) .. "|r")
  if ns.ShowWindow then ns:ShowWindow() end
  if ns.HideLobby then ns:HideLobby() end
  return g
end
ns._StartNetGame = startNetGame

local function currentSettings()
  local db = ns.db
  return { ruleset = db.ruleset, target = db.target, opening = db.opening, server = db.server and true or false }
end

function ns:Invite(name)
  local full = ns.FullName(name)
  if not full then self:Print("Who should I invite? Target your friend, or type /dice invite Name."); return end
  if same(full, myFull()) then self:Print("You can't play yourself, though the dice won't mind."); return end
  local id = tostring(time and time() or 0) .. tostring(math.random(100, 999))
  outgoing = { to = full, id = id, at = GetTime and GetTime() or 0 }
  local s = currentSettings()
  self:SendTo(full, "INV", ns.VERSION, id, s.ruleset, s.target, s.opening, s.server and 1 or 0)
  self:Print("Invitation sent to |cffffff00" .. ns.ShortName(full) .. "|r. Waiting for them to pull up a chair...")
  ns.C_After(INVITE_TIMEOUT, function()
    if outgoing and outgoing.id == id then
      outgoing = nil
      ns:Print("No answer from " .. ns.ShortName(full) .. ". Are they online, with Tavern Dice v0.2 or newer?")
    end
  end)
end

function ns:InviteTarget()
  if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
    local name, realm = UnitName("target")
    if name and not ns.IsSecret(name) then
      return self:Invite(realm and realm ~= "" and (name .. "-" .. realm) or name)
    end
  end
  self:Print("Target your friend first, then invite them.")
end

-- Tjommie integration: invite whoever is linked in Tjommie, in one click
function ns:TjommieBuddy()
  return TjommieDB and type(TjommieDB.buddy) == "string" and TjommieDB.buddy or nil
end

function ns:InviteTjommie()
  local b = self:TjommieBuddy()
  if b then self:Invite(b) else self:Print("No tjommie found. Is Tjommie installed and linked?") end
end

function ns:LeaveTable()
  local g = ns.game
  if g and g.net and g.phase ~= "over" then
    ns:SendTo(g.net, "Q", g.netId)
    ns.AddLog(GREY .. "You leave the table.|r")
    g:Abandon()
  end
end

StaticPopupDialogs["TAVERNDICE_INVITE"] = {
  text = "%s",
  button1 = "Pull up a chair",
  button2 = DECLINE or "Decline",
  OnAccept = function(_, data)
    if not data then return end
    ns:SendTo(data.from, "ACC", data.id, ns.VERSION)
    startNetGame(data.from, data.id, data.set, false)
    versionNote(data.from, data.version)
  end,
  OnCancel = function(_, data, reason)
    if data and reason == "clicked" then ns:SendTo(data.from, "DEC", data.id) end
  end,
  timeout = INVITE_TIMEOUT,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function fmt(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

local handlers = {}
ns.netHandlers = handlers   -- Nearby.lua adds WHO / HERE

handlers.INV = function(from, version, id, ruleset, target, opening, server)
  if not id or id == "" then return end
  local key = from:lower()
  local now = GetTime and GetTime() or 0
  if lastInvite[key] and now - lastInvite[key] < 10 then return end
  lastInvite[key] = now
  local set = {
    ruleset = ns.RULESETS[ruleset] and ruleset or "classic",
    target = math.max(500, math.min(50000, tonumber(target) or 10000)),
    opening = math.max(0, math.min(5000, tonumber(opening) or 0)),
    server = server == "1",
  }
  local rules = ns.RULESETS[set.ruleset]
  local text = ns.COLOR .. "Tavern Dice|r\n\n|cffffff00" .. ns.ShortName(from) .. "|r invites you to a game of ten thousand.\n"
    .. GREY .. rules.name .. ", first to " .. fmt(set.target)
    .. (set.server and ", server dice" or "") .. "|r\n"
  if ns.game and ns.game.phase ~= "over" then text = text .. "\n" .. GREY .. "This ends the game you're playing now.|r\n" end
  if StaticPopup_Show then
    StaticPopup_Show("TAVERNDICE_INVITE", text, nil, { from = from, id = id, set = set, version = version })
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
end

handlers.ACC = function(from, id, version)
  if not outgoing or outgoing.id ~= id or not same(outgoing.to, from) then return end
  outgoing = nil
  startNetGame(from, id, currentSettings(), true)
  versionNote(from, version)
end

handlers.DEC = function(from, id)
  if not outgoing or outgoing.id ~= id or not same(outgoing.to, from) then return end
  outgoing = nil
  ns:Print(ns.ShortName(from) .. " says not tonight. Maybe another round later.")
end

-- In-game messages: only from the friend we're playing, for this game
local function liveGame(from, id)
  local g = ns.game
  if g and g.net and g.netId == id and same(g.net, from) and g.phase ~= "over" then return g end
end

handlers.T = function(from, id, turn, sel)
  local g = liveGame(from, id)
  if g then g:RemoteSelect(turn, sel) end
end

handlers.A = function(from, id, turn, sel, act)
  local g = liveGame(from, id)
  if g then g:RemoteAction(turn, sel, act) end
end

local warnedUnseen = {}
handlers.R = function(from, id, turn, digits, source, raw)
  local g = liveGame(from, id)
  if not g then return end
  local n = #(digits or "")
  local value = tonumber(raw)
  -- A server roll must decode to exactly these dice
  if source == "server" and value and table.concat(ns.Dice.Decode(value, n)) ~= digits then
    ns.AddLog("|cffff5555Those dice don't match " .. ns.ShortName(from) .. "'s /roll, so they weren't used. Start a new game if this keeps happening.|r")
    return
  end
  if not g:RemoteRolled(turn, digits, source, raw) then return end
  -- If we can see their /roll (you're grouped), confirm it came from the server
  if source == "server" and value then
    local short = ns.ShortName(from)
    ns.C_After(2, function()
      if ns.Dice.WasSeen(short, value, 20) then
        g.verified = (g.verified or 0) + 1
      elseif not warnedUnseen[g.netId] then
        warnedUnseen[g.netId] = true
        ns.AddLog(GREY .. "You can't see " .. short .. "'s /roll from here. Join a group to check their dice.|r")
      end
    end)
  end
end

handlers.Q = function(from, id)
  local g = liveGame(from, id)
  if not g then return end
  ns.AddLog(GOLD .. ns.ShortName(from) .. " has left the table.|r")
  g:Abandon()
end

-- channel: how it arrived (WHISPER, PARTY, RAID, GUILD, CHANNEL, BN); kept in ns.netChannel for handlers
function ns:HandleNetMessage(from, msg, channel)
  if type(msg) ~= "string" or ns.IsSecret(msg) or not from or ns.IsSecret(from) then return end
  ns.netChannel = channel or "WHISPER"
  local fields = { strsplit(SEP, msg) }
  local kind = table.remove(fields, 1)
  local h = handlers[kind]
  if h then h(from, unpack(fields)) end
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
  if prefix ~= PREFIX then return end
  ns:HandleNetMessage(ns.FullName(sender), text, channel)
end)

ns:On("BN_CHAT_MSG_ADDON", function(prefix, text, _, senderID)
  if prefix ~= PREFIX or not C_BattleNet or not C_BattleNet.GetGameAccountInfoByID then return end
  local g = C_BattleNet.GetGameAccountInfoByID(senderID)
  if not (g and g.characterName) then return end
  ns:HandleNetMessage(g.characterName .. "-" .. (normRealm(g.realmName) or ""), text, "BN")
end)

---------------------------------------------------------------------------
-- "No player named X is currently playing." -> a quiet note instead of chat spam
---------------------------------------------------------------------------
local function systemFilter(_, _, msg)
  local g = ns.game
  if not (g and g.net) or type(msg) ~= "string" or ns.IsSecret(msg) or not ERR_CHAT_PLAYER_NOT_FOUND_S then return false end
  local short = ns.ShortName(g.net)
  if msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(short) or msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(g.net) then
    if not g.lostNoted and g.phase ~= "over" then
      g.lostNoted = true
      ns.AddLog(GOLD .. short .. " can't be reached. They may have logged off.|r")
    end
    return true
  end
  return false
end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then pcall(addFilter, "CHAT_MSG_SYSTEM", systemFilter) end

---------------------------------------------------------------------------
-- Right-click a player: "Invite to Tavern Dice"
---------------------------------------------------------------------------
local MENU_TAGS = {
  "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET",
  "MENU_UNIT_FRIEND", "MENU_UNIT_BN_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
  "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_CHAT_ROSTER",
}

local function nameFromContext(ctx)
  if not ctx then return nil end
  if ctx.unit and UnitIsPlayer(ctx.unit) and not UnitIsUnit(ctx.unit, "player") then
    return GetUnitName(ctx.unit, true)
  end
  if ctx.bnetIDAccount and C_BattleNet and C_BattleNet.GetAccountInfoByID then
    local acc = C_BattleNet.GetAccountInfoByID(ctx.bnetIDAccount)
    local g = acc and acc.gameAccountInfo
    if g and g.characterName and g.clientProgram == BNET_CLIENT_WOW then
      return g.characterName .. (g.realmName and ("-" .. normRealm(g.realmName)) or "")
    end
    return nil
  end
  if ctx.name then
    return ctx.server and ctx.server ~= "" and (ctx.name .. "-" .. normRealm(ctx.server)) or ctx.name
  end
end

ns:Listen("LOGIN", function()
  if not (Menu and Menu.ModifyMenu) then return end
  for _, tag in ipairs(MENU_TAGS) do
    pcall(Menu.ModifyMenu, tag, function(_, root, ctx)
      local name = nameFromContext(ctx)
      if not name or ns.IsSecret(name) or same(name, myFull()) then return end
      root:CreateDivider()
      root:CreateButton(ns.COLOR .. "Invite to Tavern Dice|r", function() ns:Invite(name) end)
    end)
  end
end)
