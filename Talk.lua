-- TavernDice: Table talk
-- When you play in person, your character reacts out loud:
--   hot dice  -> /say a line              you win -> /cheer + /say a line
--   Farkle    -> /sigh, or an emote grunt
-- Only for your own seat. Setting db.tableTalk:
--   "auto"   : talk in friend games when your friend is close by (grouped and in sight); quiet
--              when you're far apart, and quiet against bots
--   "always" : always talk, bot games included
--   "off"    : never
-- /say outdoors needs a key or mouse press, so we only /say during your own Roll or Bank click
-- (ns.inClick, set by the UI). Otherwise the line goes out as an emote, which is always allowed.

local _, ns = ...

local function pick(t) return t[math.random(1, #t)] end

local SAY = {
  hot = { "Hot dice!", "Hot dice! Every last one of them!", "Hot dice! Pass me that cup again." },
  win = { "And that's the game!", "Ha! The table is mine!", "Drinks are on the loser!" },
}
local EMOTE = {
  hot = { "slams the cup down. \"Hot dice!\"", "grins as every die scores. \"Hot dice!\"" },
  win = { "throws both hands in the air. \"That's the game!\"", "sweeps the winnings into a pouch, grinning." },
  farkle = { "grunts and shoves the dice away.", "grunts.", "glares at the dice and grunts." },
}

-- Is the friend we're playing within sight? (party/raid units and target; nil if we can't tell)
function ns:FriendNearby()
  local g = ns.game
  if not (g and g.net) then return false end
  local short = ns.ShortName(g.net)
  local units = { "target", "mouseover", "focus" }
  for i = 1, 4 do units[#units + 1] = "party" .. i end
  for i = 1, 40 do units[#units + 1] = "raid" .. i end
  for _, u in ipairs(units) do
    if UnitExists and UnitExists(u) then
      local name = UnitName(u)
      if name and not ns.IsSecret(name) and name == short then
        return UnitIsVisible and UnitIsVisible(u) and true or false
      end
    end
  end
  return false
end

function ns:TalkAllowed()
  local mode = ns.db and ns.db.tableTalk or "auto"
  if mode == "off" then return false end
  if mode == "always" then return true end
  return self:FriendNearby()
end

local function sendChat(text, channel)
  if SendChatMessage then return pcall(SendChatMessage, text, channel) end
  if C_ChatInfo and C_ChatInfo.SendChatMessage then return pcall(C_ChatInfo.SendChatMessage, text, channel) end
end

local function doEmote(token)
  if C_ChatInfo and C_ChatInfo.PerformEmote then return pcall(C_ChatInfo.PerformEmote, token) end
  if DoEmote then return pcall(DoEmote, token) end
end

local function say(kind)
  if ns.inClick then
    sendChat(pick(SAY[kind]), "SAY")
  else
    sendChat(pick(EMOTE[kind]), "EMOTE")
  end
end

ns:Listen("TD_EVENT", function(kind, p)
  if not p or p.bot or p.remote then return end      -- only our own seat
  if kind ~= "HOTDICE" and kind ~= "OVER" and kind ~= "FARKLE" then return end
  if not ns:TalkAllowed() then return end
  if kind == "HOTDICE" then
    say("hot")
  elseif kind == "OVER" then
    doEmote("CHEER")
    say("win")
  elseif kind == "FARKLE" then
    if math.random(1, 2) == 1 then doEmote("SIGH") else sendChat(pick(EMOTE.farkle), "EMOTE") end
  end
end)
