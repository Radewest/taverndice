local function any()
  local o = {}
  return setmetatable(o, { __index = function(t, k)
    local f = function(self, ...)
      if k == "GetWidth" or k == "GetHeight" then return 1000 end
      if k == "IsShown" or k == "HasFocus" then return true end
      if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
      if k == "GetStringHeight" then return 14 end
      if k == "GetFrameLevel" then return 1 end
      if k == "GetMapID" then return 1429 end
      if k == "GetCanvasScale" then return 1 end
      if k == "GetText" then return "" end
      if k:match("^Create") then return any() end
      return nil
    end
    rawset(t, k, f); return f end })
end
_G.unpack = unpack or table.unpack
math.atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
strsplit = function(sep, s, n)
  local out, i = {}, 1
  while true do
    if n and #out == n-1 then out[#out+1] = s:sub(i); break end
    local a,b = s:find(sep, i, true)
    if not a then out[#out+1] = s:sub(i); break end
    out[#out+1] = s:sub(i, a-1); i = b+1
  end
  return table.unpack(out)
end
events = {}
frames = {}
CreateFrame = function(t, name)
  local f = any()
  f.RegisterEvent = function(self, e) events[e] = self end
  f.SetScript = function(self, k, fn) self["_"..k] = fn end
  f.HookScript = f.SetScript
  if name then _G[name] = f end
  return f
end
UIParent = any(); GameTooltip = any(); WorldMapFrame = any()
WorldMapFrame.ScrollContainer = {Child = any()}
UISpecialFrames = {}
timers = {}
C_Timer = { After = function(s, fn) table.insert(timers, fn) end,
  NewTicker = function(s, fn) table.insert(timers, fn); return {Cancel=function() end} end,
  NewTimer = function(s, fn) table.insert(timers, fn); return {Cancel=function() end} end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(p, m, c, t) sent[#sent+1] = m end }
sent = {}
C_BattleNet = {}
BNGetNumFriends = function() return 0 end
function vec(x,y) return {GetXY=function() return x,y end} end
CreateVector2D = vec
C_Map = {
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return vec(0.5, 0.5) end,
  GetWorldPosFromMapPos = function(m, p) local x,y = p:GetXY(); return 0, vec(x*4000, y*3000) end,
  GetMapPosFromWorldPos = function(c, p, m) local x,y = p:GetXY(); return m, vec(x/4000, y/3000) end,
  GetMapWorldSize = function() return 4000, 3000 end,
}
GetPlayerFacing = function() return 0 end
GetTime = function() return os.clock() + 100 end
GetZoneText = function() return "Elwynn Forest" end
GetSubZoneText = function() return "Goldshire" end
GetNormalizedRealmName = function() return "Realm" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 20 end
UnitName = function() return "Harry" end
GetMoney = function() return 5000 end
GetInventoryItemLink = function(u, s) if s == 16 then return "item:100" end end
GetInventoryItemID = function() return nil end
ITEMS = {
  [100] = {"Old Sword", "|Hitem:100|h[Old Sword]|h", 2, 10, 5, "", "", 1, "INVTYPE_2HWEAPON", 0, 0, 2, 8, 2},
  [200] = {"Mail Helm", "|Hitem:200|h[Mail Helm]|h", 3, 25, 18, "", "", 1, "INVTYPE_HEAD", 0, 0, 4, 3, 2},
  [300] = {"Cloth Robe of Int", "|Hitem:300|h[Robe]|h", 3, 25, 18, "", "", 1, "INVTYPE_ROBE", 0, 0, 4, 1, 2},
  [400] = {"Big Axe", "|Hitem:400|h[Big Axe]|h", 3, 25, 18, "", "", 1, "INVTYPE_2HWEAPON", 0, 0, 2, 1, 1},
}
C_Item = { GetItemInfo = function(id) id = tonumber(tostring(id):match("%d+")); local t = ITEMS[id]; if t then return table.unpack(t) end end,
  GetItemStats = function(link) if link:find("300") then return {ITEM_MOD_INTELLECT_SHORT=5} end return {ITEM_MOD_STRENGTH_SHORT=3} end,
  GetDetailedItemLevelInfo = function(link) return 10 end, GetItemIconByID = function() return 1 end }
Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(self, fn) fn() end, GetItemLink = function() return "link"..id end } end }
C_ClassColor = { GetClassColor = function() return {r=1,g=0.5,b=0} end }
date = os.date; time = os.time
hooksecurefunc = function() end
geterrorhandler = function() return function(e) print("ERROR: "..tostring(e)) end end
print = print
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
LOOT_ITEM_SELF = "You receive loot: %s."
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ChatFrame_AddMessageEventFilter = function() end
PlaySound = function() end
SOUNDKIT = {}
C_QuestLog = { GetTitleForQuestID = function() return "Test Quest" end }
GameFontHighlightSmall = {}
SlashCmdList = {}; C_Container = {GetContainerItemID=function(b,s) if b==0 and s==1 then return 200 end end, GetContainerNumSlots=function() return 4 end}

UnitXP=function() return 100 end; UnitXPMax=function() return 1000 end
Minimap = CreateFrame("Frame"); GetCursorPosition=function() return 0,0 end
CLASS_ICON_TCOORDS={WARRIOR={0,0.25,0,0.25},MAGE={0.25,0.5,0,0.25}}
BreakUpLargeNumbers=function(n) return tostring(n) end
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end

debugstack=function() return "stack line 1\nstack line 2" end
seterrorhandler=function() end
GetBuildInfo=function() return "1.60.1","12345","",16001 end
ChatFontNormal={}

StaticPopupDialogs={}
ACCEPT="Accept"; DECLINE="Decline"
DRUNK_MESSAGE_SELF2 = "You feel tipsy."
DRUNK_MESSAGE_SELF3 = "You feel drunk."
DRUNK_MESSAGE_SELF4 = "You feel completely smashed."
DRUNK_MESSAGE_ITEM_SELF3 = "You drink the %s and feel drunk."
IsInInstance = function() return false, "none" end
RequestTimePlayed = function() fire_time_played = true end
C_QuestLog = C_QuestLog or {}
GetStatistic = function(id) if id == 60 then return "12" end return "--" end

-- TavernDice additions
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
rolled = {}
RandomRoll = function(lo, hi) rolled[#rolled + 1] = { lo, hi } end
Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
chatFilters = {}
ChatFrame_AddMessageEventFilter = function(ev, fn) chatFilters[ev] = fn end
SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 1, IG_QUEST_FAILED = 2 }
ChatFrame_AddMessageEventFilter = function(ev, fn) chatFilters[ev] = chatFilters[ev] or fn end
popups = {}
StaticPopup_Show = function(which, text, _, data) popups[#popups + 1] = { which = which, text = text, data = data } end
chatSent = {}
SendChatMessage = function(msg, ch) chatSent[#chatSent + 1] = { msg, ch } end
emotes = {}
DoEmote = function(t) emotes[#emotes + 1] = t end
unitsNear = {}
UnitExists = function(u) return unitsNear[u] ~= nil end
UnitIsVisible = function(u) return unitsNear[u] and unitsNear[u].visible end
UnitName = function(u) if u == "player" or u == nil then return "Harry" end return unitsNear[u] and unitsNear[u].name end
UnitIsPlayer = function() return true end

channels = {}
GetChannelName = function(n) return channels[n] or 0 end
JoinTemporaryChannel = function(n) channels[n] = 5 end
LeaveChannelByName = function(n) channels[n] = nil end
IsInGuild = function() return true end
IsInGroup = function() return false end
IsInRaid = function() return false end
UnitFactionGroup = function() return "Alliance" end
UnitIsUnit = function(a, b) return a == b end
RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
