-- TavernDice: UI
-- The dice table window: header, the ledger (scores), the felt with six dice, Roll / Bank,
-- the tavern log, and the "Pull up a chair" panel for starting games.
-- Redraws on TD_UPDATE; narration arrives on TD_LOG.

local ADDON, ns = ...

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"   -- WoW's storybook font; falls back to the template font
local W, H = 580, 520
local DIE, GAP = 48, 8                     -- 6 x 48 + 5 x 8 = 328 px, inside the 358 px felt
local BRASS = { 0.72, 0.55, 0.25 }
local frame
local refresh   -- defined below; build() attaches it

local function fmt(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function now() return GetTime and GetTime() or 0 end

---------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------
local function titleFont(fs, size)
  if fs.SetFont then pcall(fs.SetFont, fs, TITLE_FONT, size, "") end
  fs:SetShadowOffset(1, -1)
end

local function panel(parent, texture, tile, alpha)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({
    bgFile = MEDIA .. texture, tile = tile and true or false, tileSize = 256,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  p:SetBackdropColor(1, 1, 1, alpha or 1)
  p:SetBackdropBorderColor(BRASS[1], BRASS[2], BRASS[3])
  return p
end

local function button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, h or 24)
  b:SetText(text)
  return b
end

-- Your clicks on Roll / Bank: mark them so table talk may /say (needs a real click outdoors)
local function clicked(fn)
  return function(...)
    ns.inClick = true
    ns.SafeCall(fn, ...)
    ns.inClick = false
  end
end

-- A button that cycles through values: values = { {value, label}, ... }
local function cycle(parent, label, values, get, set, w, onChange)
  local b = button(parent, "", w or 220, 22)
  local function idx()
    local cur = get()
    for i, v in ipairs(values) do if v[1] == cur then return i end end
    return 1
  end
  function b:Refresh() self:SetText(label .. ": " .. values[idx()][2]) end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, mouse)
    local i = idx() + ((mouse == "RightButton") and -1 or 1)
    if i > #values then i = 1 elseif i < 1 then i = #values end
    set(values[i][1])
    self:Refresh()
    if onChange then onChange() end
  end)
  b:Refresh()
  return b
end

local function makeDie(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetPoint("TOPLEFT", -5, 5)
  b.glow:SetPoint("BOTTOMRIGHT", 5, -5)
  b.glow:SetTexture(MEDIA .. "glow")
  b.glow:Hide()
  function b:SetFace(v)
    if v then self.tex:SetTexture(MEDIA .. "die" .. v); self:Show() else self:Hide() end
  end
  return b
end

-- Centre however many dice are on the felt
local function layoutDice(f, n)
  if f.diceCount == n then return end
  f.diceCount = n
  local rowW = n * DIE + (n - 1) * GAP
  for i = 1, 6 do
    local d = f.dice[i]
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", f.felt, "TOP", -rowW / 2 + (i - 1) * (DIE + GAP), -62)
  end
end

local function isYou(p) return p and not p.bot and not p.remote end

local function nameColored(p)
  if p.remote then return "|cff6fb7ff" .. p.name .. "|r" end
  if p.bot then return "|cffffffff" .. p.name .. "|r" end
  return "|cff66dd66" .. p.name .. "|r"
end

---------------------------------------------------------------------------
-- Toast: a big word over the felt that fades ("FARKLE!", "HOT DICE!")
---------------------------------------------------------------------------
local function showToast(text, r, g, b)
  if not frame then return end
  local t = frame.toast
  t.text:SetText(text)
  t.text:SetTextColor(r, g, b)
  t.start = now()
  t:SetAlpha(1)
  t:Show()
end

---------------------------------------------------------------------------
-- Build the window
---------------------------------------------------------------------------
local function savePosition(f)
  local point, _, rel, x, y = f:GetPoint()
  ns.db.ui.point, ns.db.ui.rel, ns.db.ui.x, ns.db.ui.y = point, rel, x, y
end

local function build()
  local f = CreateFrame("Frame", "TavernDiceFrame", UIParent, "BackdropTemplate")
  f:SetSize(W, H)
  local u = ns.db.ui
  if u.point then f:SetPoint(u.point, UIParent, u.rel or u.point, u.x or 0, u.y or 0) else f:SetPoint("CENTER") end
  f:SetScale(u.scale or 1)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetBackdrop({
    bgFile = MEDIA .. "wood", tile = true, tileSize = 256,
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 32,
    insets = { left = 10, right = 10, top = 10, bottom = 10 },
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
  table.insert(UISpecialFrames, "TavernDiceFrame")

  -- Header band -----------------------------------------------------------
  local band = f:CreateTexture(nil, "BORDER")
  band:SetPoint("TOPLEFT", 10, -10)
  band:SetPoint("TOPRIGHT", -10, -10)
  band:SetHeight(36)
  band:SetColorTexture(0, 0, 0, 0.35)
  local rule = f:CreateTexture(nil, "BORDER")
  rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  rule:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.8)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFont(f.title, 22)
  f.title:SetPoint("LEFT", band, "LEFT", 12, 0)
  f.title:SetText(ns.COLOR .. "Tavern Dice|r")
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("LEFT", f.title, "RIGHT", 12, -2)
  f.sub:SetTextColor(0.85, 0.78, 0.62)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(26, 26)
  close:SetPoint("RIGHT", band, "RIGHT", -4, 0)
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.status:SetPoint("RIGHT", close, "LEFT", -8, 0)

  -- The ledger -------------------------------------------------------------
  local board = panel(f, "leather", true)
  board:SetPoint("TOPLEFT", 18, -54)
  board:SetSize(178, 252)
  local bt = board:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleFont(bt, 16)
  bt:SetPoint("TOP", 0, -8)
  bt:SetText("|cffffd100The Ledger|r")
  f.rows = {}
  for i = 1, 4 do
    local r = CreateFrame("Frame", nil, board)
    r:SetSize(164, 40)
    r:SetPoint("TOPLEFT", 7, -30 - (i - 1) * 44)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.8, 0.3, 0.16)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
    r.bar:SetColorTexture(1, 0.82, 0.2, 0.9)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", 8, -4)
    r.name:SetWidth(150); r.name:SetJustifyH("LEFT")
    r.score = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.score:SetPoint("BOTTOMLEFT", 8, 3)
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.note:SetPoint("BOTTOMRIGHT", -6, 5)
    f.rows[i] = r
  end
  f.targetText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.targetText:SetPoint("BOTTOM", 0, 38)
  f.targetText:SetTextColor(0.9, 0.82, 0.62)
  f.newBtn = button(board, "New game", 150, 22)
  f.newBtn:SetPoint("BOTTOM", 0, 10)
  f.newBtn:SetScript("OnClick", function() ns:ShowLobby() end)

  -- The felt ---------------------------------------------------------------
  local felt = panel(f, "felt", false)
  felt:SetPoint("TOPLEFT", board, "TOPRIGHT", 8, 0)
  felt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -54)
  felt:SetHeight(252)
  f.felt = felt

  local keptLabel = felt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  keptLabel:SetPoint("TOPLEFT", 12, -10)
  keptLabel:SetText("Set aside this turn")
  keptLabel:SetTextColor(0.7, 0.85, 0.7)
  f.kept = {}
  for i = 1, 6 do
    local d = makeDie(felt, 22)
    d:SetPoint("TOPLEFT", 12 + (i - 1) * 26, -24)
    d:EnableMouse(false)
    d:Hide()
    f.kept[i] = d
  end

  f.dice = {}
  local rowW = 6 * DIE + 5 * GAP
  for i = 1, 6 do
    local d = makeDie(felt, DIE)
    d:SetPoint("TOPLEFT", felt, "TOP", -rowW / 2 + (i - 1) * (DIE + GAP), -62)
    d:SetScript("OnClick", function()
      if ns.game and ns.game:IsMyTurn() and not f.animating then ns.game:Toggle(i) end
    end)
    d:SetScript("OnEnter", function(self)
      if ns.game and ns.game:IsMyTurn() and ns.game.phase == "choosing" then self.tex:SetVertexColor(1, 1, 0.85) end
    end)
    d:SetScript("OnLeave", function(self) self.tex:SetVertexColor(1, 1, 1) end)
    d:Hide()
    f.dice[i] = d
  end

  f.turnText = felt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.turnText:SetPoint("TOP", 0, -126)
  f.hint = felt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.hint:SetPoint("TOP", f.turnText, "BOTTOM", 0, -6)
  f.hint:SetWidth(330)

  -- Mumpets: a pair of 5s can stay, or one goes back in the cup
  f.fiveBtn = button(felt, "", 190, 20)
  f.fiveBtn:SetPoint("TOP", f.hint, "BOTTOM", 0, -6)
  f.fiveBtn:SetScript("OnClick", function()
    local g = ns.game
    if g and g:IsMyTurn() then
      local _, _, _, back = g:SelectionScore()
      g:SetFiveBack(back == 0)
    end
  end)
  f.fiveBtn:Hide()

  -- Mumpets straight chase: risk the spare die for the missing number
  f.chaseBtn = button(felt, "Chase the straight!", 150, 20)
  f.chaseBtn:SetPoint("TOPRIGHT", -10, -8)
  f.chaseBtn:SetScript("OnClick", clicked(function() if ns.game and ns.game:IsMyTurn() then ns.game:Chase() end end))
  f.chaseBtn:SetScript("OnEnter", function(self)
    local g = ns.game
    local missing = g and g:ChaseInfo()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Chase the straight", 1, 0.82, 0)
    if missing then
      GameTooltip:AddLine("Reroll the spare die and hope for a " .. missing .. ".", 1, 1, 1)
      GameTooltip:AddLine("Hit (1 in 6): a straight, " .. fmt((g.rules.straight or 3000)) .. ".", 0.4, 0.87, 0.4)
      GameTooltip:AddLine("Miss: turn over, this turn's points lost, and " .. fmt(g.rules.chasePenalty or 500) .. " off your score.", 1, 0.33, 0.33)
    end
    GameTooltip:Show()
  end)
  f.chaseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.chaseBtn:Hide()

  f.rollBtn = button(felt, "Roll", 140, 28)
  f.rollBtn:SetPoint("BOTTOMRIGHT", felt, "BOTTOM", -6, 14)
  f.rollBtn:SetScript("OnClick", clicked(function() if ns.game and ns.game:IsMyTurn() then ns.game:Roll() end end))
  f.bankBtn = button(felt, "Bank", 140, 28)
  f.bankBtn:SetPoint("BOTTOMLEFT", felt, "BOTTOM", 6, 14)
  f.bankBtn:SetScript("OnClick", clicked(function() if ns.game and ns.game:IsMyTurn() then ns.game:Bank() end end))

  local toast = CreateFrame("Frame", nil, felt)
  toast:SetAllPoints()
  toast:SetFrameLevel(felt:GetFrameLevel() + 20)
  toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  titleFont(toast.text, 34)
  toast.text:SetPoint("CENTER", 0, 14)
  toast:Hide()
  f.toast = toast

  -- Tavern log -------------------------------------------------------------
  local logBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  logBg:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 0, -8)
  logBg:SetPoint("BOTTOMRIGHT", -18, 18)
  logBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  logBg:SetBackdropColor(0.04, 0.025, 0.015, 0.88)
  logBg:SetBackdropBorderColor(BRASS[1], BRASS[2], BRASS[3])
  local log = CreateFrame("ScrollingMessageFrame", nil, logBg)
  log:SetPoint("TOPLEFT", 10, -8)
  log:SetPoint("BOTTOMRIGHT", -10, 8)
  log:SetFontObject(GameFontHighlightSmall)
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(80)
  log:SetInsertMode("BOTTOM")
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  f.log = log
  for _, line in ipairs(ns.log) do log:AddMessage(line) end

  -- Animation: dice tumble briefly on every throw; toast fades
  f:SetScript("OnUpdate", function(self)
    local t = now()
    if self.animating then
      local waiting = ns.game and ns.game.phase == "rolling"
      if t >= self.animUntil and not waiting then
        self.animating = false
        self:Refresh()
        if self.pendingToast then
          showToast(unpack(self.pendingToast))
          self.pendingToast = nil
        end
      elseif t >= (self.nextFace or 0) then
        self.nextFace = t + 0.06
        if self.animOnly then
          -- straight chase: only the spare die tumbles
          local d = self.dice[self.animOnly]
          d:SetFace(math.random(1, 6)); d.glow:Hide()
        else
          layoutDice(self, self.animCount or 6)
          for i = 1, (self.animCount or 6) do self.dice[i]:SetFace(math.random(1, 6)); self.dice[i].glow:Hide() end
          for i = (self.animCount or 6) + 1, 6 do self.dice[i]:Hide() end
        end
      end
    end
    local toastF = self.toast
    if toastF:IsShown() then
      local age = t - (toastF.start or 0)
      if age > 1.6 then toastF:Hide() elseif age > 0.9 then toastF:SetAlpha(1 - (age - 0.9) / 0.7) end
    end
  end)

  f.lobby = ns:BuildLobby(f)
  f.Refresh = refresh
  return f
end

---------------------------------------------------------------------------
-- "Pull up a chair": start a game against the regulars, or invite a friend
---------------------------------------------------------------------------
local RULES_NOTE = {
  classic = "Classic: 1 = 100, 5 = 50, three of a kind = face x 100 (three 1s = 1,000), straight 1,500, three pairs 1,000.",
  mumpets = "Mumpets: bank 400+ every turn. Two 5s can be made a 1. Straight 3,000, and one short? Chase it, or lose 500.",
}
local TALK_NOTE = {
  auto = "Table talk: you /say \"Hot dice!\" and cheer or sigh when your friend is beside you. Quiet when far apart.",
  always = "Table talk: you always /say and emote, even against the regulars.",
  off = "Table talk: your character stays quiet.",
}

function ns:BuildLobby(f)
  local p = panel(f, "wood", true)
  p:SetPoint("TOPLEFT", 18, -54)
  p:SetPoint("BOTTOMRIGHT", -18, 18)
  p:SetBackdropColor(0.75, 0.75, 0.75, 1)
  p:SetFrameLevel(f:GetFrameLevel() + 30)
  p:EnableMouse(true)

  local shade = p:CreateTexture(nil, "BACKGROUND", nil, 1)
  shade:SetPoint("TOPLEFT", 3, -3); shade:SetPoint("BOTTOMRIGHT", -3, 3)
  shade:SetColorTexture(0, 0, 0, 0.35)

  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFont(t, 22)
  t:SetPoint("TOP", 0, -12)
  t:SetText("|cffffd100Pull up a chair|r")
  local s = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s:SetPoint("TOP", t, "BOTTOM", 0, -4)
  s:SetTextColor(0.85, 0.78, 0.62)
  s:SetText("Right-click any button to step back through its choices.")

  local LX, RX = 136, 408   -- column centres
  local function at(ctrl, x, y) ctrl:SetPoint("TOP", p, "TOPLEFT", x, y); return ctrl end
  local function header(text, x, y)
    local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFont(h, 15)
    at(h, x, y)
    h:SetText("|cffffd100" .. text .. "|r")
    return h
  end

  local db = ns.db
  p.controls = {}
  local function add(ctrl) p.controls[#p.controls + 1] = ctrl; return ctrl end

  -- Left: the regulars -------------------------------------------------------
  header("Tavern regulars", LX, -62)
  local styles = {}
  for _, k in ipairs(ns.Bots.ORDER) do
    local st = ns.Bots.STYLES[k]
    styles[#styles + 1] = { k, st.name .. " (" .. st.label .. ")" }
  end
  local seatVals = { { 0, "empty" } }
  for _, v in ipairs(styles) do seatVals[#seatVals + 1] = v end
  for seat = 1, 3 do
    add(at(cycle(p, "Seat " .. (seat + 1), seat == 1 and styles or seatVals,
      function() return db.opponents[seat] or 0 end,
      function(v)
        if v == 0 then db.opponents[seat] = nil else db.opponents[seat] = v end
        local packed = {}
        for i = 1, 3 do if db.opponents[i] then packed[#packed + 1] = db.opponents[i] end end
        wipe(db.opponents); for i, v2 in ipairs(packed) do db.opponents[i] = v2 end
        for _, c in ipairs(p.controls) do c:Refresh() end
      end, 250), LX, -84 - (seat - 1) * 26))
  end
  local deal = at(button(p, "Deal me in", 170, 26), LX, -166)
  -- StartFromSettings closes the panel itself, after the new game exists (see HideLobby)
  deal:SetScript("OnClick", function() ns:StartFromSettings() end)
  local tip = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  at(tip, LX, -202)
  tip:SetWidth(250)
  tip:SetTextColor(0.85, 0.78, 0.62)
  tip:SetText("Tip: right-click any player and choose |cffffb347Invite to Tavern Dice|r.")

  -- Right: a friend -----------------------------------------------------------
  header("A friend, near or far", RX, -62)
  p.tjBtn = at(button(p, "Invite my tjommie", 120, 22), RX - 65, -84)
  p.tjBtn:SetScript("OnClick", function() ns:InviteTjommie() end)
  p.tjBtn:SetScript("OnEnter", function(self)
    local tj = ns.TjommieBuddy and ns:TjommieBuddy()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(tj and ("Your tjommie: " .. ns.ShortName(tj)) or "Link a tjommie in Tjommie first.", 1, 1, 1)
    GameTooltip:Show()
  end)
  p.tjBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local tgt = at(button(p, "Invite target", 120, 22), RX + 65, -84)
  tgt:SetScript("OnClick", function() ns:InviteTarget() end)

  -- Nearby players with the add-on
  local nh = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nh:SetPoint("TOPLEFT", p, "TOPLEFT", RX - 125, -116)
  nh:SetText("|cffffd100Nearby with Tavern Dice|r")
  local look = CreateFrame("Button", nil, p)
  look:SetSize(70, 14)
  look:SetPoint("TOPRIGHT", p, "TOPLEFT", RX + 125, -115)
  look.text = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  look.text:SetAllPoints()
  look.text:SetJustifyH("RIGHT")
  look.text:SetText("|cffffb347Look around|r")
  look:SetScript("OnClick", function() ns:ScanNearby(true); p:RefreshNearby() end)
  p.nearRows = {}
  for i = 1, 4 do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(250, 20)
    row:SetPoint("TOPLEFT", p, "TOPLEFT", RX - 125, -132 - (i - 1) * 21)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0.25)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.where:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.btn = button(row, "Invite", 56, 18)
    row.btn:SetPoint("RIGHT", -1, 0)
    row:Hide()
    p.nearRows[i] = row
  end
  p.nearEmpty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.nearEmpty:SetPoint("TOPLEFT", p, "TOPLEFT", RX - 119, -137)
  p.nearEmpty:SetWidth(240)
  p.nearEmpty:SetJustifyH("LEFT")

  function p:RefreshNearby()
    local list = ns.NearbyList and ns:NearbyList() or {}
    for i, row in ipairs(self.nearRows) do
      local e = list[i]
      if e then
        local color = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
        row.name:SetText((color and color.colorStr) and ("|c" .. color.colorStr .. e.short .. "|r") or e.short)
        local where = e.dist and (e.dist .. " yd") or (e.zone or "")
        if e.busy then where = where .. "  at a table" end
        row.where:SetText(where)
        row.btn:SetScript("OnClick", function() ns:Invite(e.name) end)
        row.btn:SetEnabled(not e.busy)
        row:Show()
      else
        row:Hide()
      end
    end
    if #list == 0 then
      self.nearEmpty:SetText(ns.db.discoverable and "Nobody found yet. Players close by, in your group or guild show up here."
        or "Finding players is off. Type /dice findme to turn it on.")
    else
      self.nearEmpty:SetText("")
    end
  end

  -- Divider + house rules ---------------------------------------------------
  local div = p:CreateTexture(nil, "ARTWORK")
  div:SetPoint("TOPLEFT", 20, -240); div:SetPoint("TOPRIGHT", -20, -240)
  div:SetHeight(1)
  div:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.7)
  header("House rules", W / 2 - 18, -248)

  local notes = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  notes:SetPoint("TOP", 0, -356)
  notes:SetWidth(500)
  notes:SetSpacing(3)
  notes:SetTextColor(0.85, 0.78, 0.62)
  local function updateNotes()
    notes:SetText((RULES_NOTE[db.ruleset] or "") .. "\n" .. (TALK_NOTE[db.tableTalk] or ""))
  end
  p.UpdateNotes = updateNotes

  add(at(cycle(p, "Rules", { { "classic", "Classic" }, { "mumpets", "Mumpets" } },
    function() return db.ruleset end, function(v) db.ruleset = v end, 250, updateNotes), LX, -272))
  add(at(cycle(p, "Play to", { { 2000, "2,000" }, { 5000, "5,000" }, { 10000, "10,000" } },
    function() return db.target end, function(v) db.target = v end, 250), LX, -298))
  add(at(cycle(p, "First bank", { { 0, "any" }, { 350, "350+" }, { 500, "500+" }, { 1000, "1,000+" } },
    function() return db.opening end, function(v) db.opening = v end, 250), LX, -324))
  add(at(cycle(p, "Dice", { { false, "local" }, { true, "server /roll" } },
    function() return db.server end, function(v) db.server = v end, 250), RX, -272))
  add(at(cycle(p, "Pace", { { 0.5, "brisk" }, { 1, "relaxed" }, { 1.6, "slow" } },
    function() return db.speed end, function(v) db.speed = v end, 250), RX, -298))
  add(at(cycle(p, "Table talk", { { "auto", "auto" }, { "always", "always" }, { "off", "off" } },
    function() return db.tableTalk end, function(v) db.tableTalk = v end, 250, updateNotes), RX, -324))

  -- Footer -------------------------------------------------------------------
  p.stats = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.stats:SetPoint("BOTTOM", 0, 40)

  p.back = button(p, "Back to the game", 160, 24)
  p.back:SetPoint("BOTTOM", 0, 10)
  p.back:SetScript("OnClick", function() ns:HideLobby() end)
  p.leave = button(p, "Leave the table", 140, 24)
  p.leave:SetPoint("LEFT", p.back, "RIGHT", 8, 0)
  -- leaving ends the game, and with no game the panel stays open for the next one
  p.leave:SetScript("OnClick", function() ns:LeaveTable() end)

  p:SetScript("OnShow", function(self)
    for _, c in ipairs(self.controls) do c:Refresh() end
    updateNotes()
    local g = ns.game
    local live = g and g.phase ~= "over"
    self.back:SetShown(live and true or false)
    self.leave:SetShown(live and g.net and true or false)
    self.tjBtn:SetText("Invite my tjommie")
    self.tjBtn:SetEnabled(ns.TjommieBuddy and ns:TjommieBuddy() and true or false)
    if ns.ScanNearby then ns:ScanNearby() end
    self:RefreshNearby()
    local st = ns.cdb.stats
    self.stats:SetText(string.format("Your record: %d games, %d wins, best turn %s, high score %s",
      st.games, st.wins, fmt(st.bestTurn), fmt(st.highScore)))
  end)
  p:Hide()
  return p
end

-- ns.lobbyOpen mirrors the panel, so tests (and anything else) can check it
function ns:ShowLobby()
  ns.lobbyOpen = true
  if frame and frame.lobby then frame.lobby:Show() end
end

function ns:HideLobby()
  ns.lobbyOpen = false
  if frame and frame.lobby then frame.lobby:Hide() end
end

function ns:StartFromSettings()
  if ns.game and ns.game.phase ~= "over" then
    if ns.game.net then ns:LeaveTable() else ns.game:Abandon() end
  end
  local players = { { name = (UnitName and UnitName("player")) or "You" } }
  local used = {}
  for _, style in ipairs(ns.db.opponents) do
    local st = ns.Bots.STYLES[style]
    if st then
      local name = st.name
      used[name] = (used[name] or 0) + 1
      if used[name] > 1 then name = name .. " " .. string.rep("I", used[name]) end
      players[#players + 1] = { name = name, bot = style }
    end
  end
  if #players == 1 then players[2] = { name = ns.Bots.STYLES.balanced.name, bot = "balanced" } end
  -- Ending the old game above briefly leaves no game, which reopens the panel; so close the
  -- panel only now, once the new game exists (v0.2.6 fix: "Deal me in" seemed to do nothing).
  local g = ns:NewGame({ players = players, target = ns.db.target, opening = ns.db.opening, ruleset = ns.db.ruleset, server = ns.db.server })
  ns:HideLobby()
  return g
end

---------------------------------------------------------------------------
-- Redraw
---------------------------------------------------------------------------
refresh = function(f)
  local g = ns.game
  if not g then
    f.sub:SetText("")
    f.status:SetText("")
    for _, r in ipairs(f.rows) do r:Hide() end
    for i = 1, 6 do f.dice[i]:Hide(); f.kept[i]:Hide() end
    f.turnText:SetText(""); f.hint:SetText("")
    f.rollBtn:Disable(); f.bankBtn:Disable()
    f.targetText:SetText("")
    ns:ShowLobby()
    return
  end

  -- Header
  f.sub:SetText(g.rules.name .. "  -  first to " .. fmt(g.target))
  if g.net then
    local near = ns.FriendNearby and ns:FriendNearby()
    f.status:SetText("|cff6fb7ff" .. ns.ShortName(g.net) .. "|r  " .. (near and "|cff66dd66at your table|r" or "|cff999999from afar|r"))
  else
    f.status:SetText("")
  end

  -- Ledger
  for i, r in ipairs(f.rows) do
    local p = g.players[i]
    if p then
      r:Show()
      r.name:SetText(nameColored(p))
      r.score:SetText(fmt(p.score))
      r.note:SetText(p.onBoard and "" or "not on the board")
      local cur = i == g.current and g.phase ~= "over"
      r.hl:SetShown(cur); r.bar:SetShown(cur)
    else
      r:Hide()
    end
  end
  local rulesLine
  if g.minBank > 0 then
    rulesLine = "Bank " .. fmt(g.minBank) .. "+ every turn"
  else
    rulesLine = "First bank: " .. (g.opening > 0 and (fmt(g.opening) .. "+") or "any")
  end
  f.targetText:SetText(g.finalRound and "|cffffd100Final round!|r" or rulesLine)

  -- Kept dice
  for i = 1, 6 do f.kept[i]:SetFace(g.kept[i]) end

  -- Dice on the felt
  if not f.animating then
    if #g.roll > 0 then layoutDice(f, #g.roll) end
    local _, selOk = g:SelectionScore()
    for i = 1, 6 do
      local d = f.dice[i]
      local v = g.roll[i]
      d:SetFace(v)
      if v and g.selected[i] then
        d.glow:Show()
        if selOk then d.glow:SetVertexColor(1, 0.82, 0.2) else d.glow:SetVertexColor(1, 0.25, 0.2) end
        d.tex:SetAlpha(1)
      else
        d.glow:Hide()
        d.tex:SetAlpha(g.phase == "farkle" and 0.6 or 1)
      end
    end
  end

  -- Turn text, hint, buttons
  local p = g:Player()
  local mine = g:IsMyTurn()
  local selScore, selOk, selN, refund, canBack = g:SelectionScore()
  local chaseFor, chaseIdx = g:ChaseInfo()
  local showChase = mine and chaseFor and not f.animating
  f.chaseBtn:SetShown(showChase and true or false)
  if not f.animating then
    for i = 1, 6 do
      local d = f.dice[i]
      if chaseFor and i == chaseIdx and not g.selected[i] then d.tex:SetVertexColor(1, 0.9, 0.55) else d.tex:SetVertexColor(1, 1, 1) end
    end
  end
  local showFive = mine and g.phase == "choosing" and selOk and (canBack or 0) > 0 and not f.animating
  f.fiveBtn:SetShown(showFive and true or false)
  if showFive then
    f.fiveBtn:SetText((refund or 0) > 0 and "Keep both 5s instead" or "Make it a 1 instead")
  end
  if g.phase == "over" then
    local w = g.winner
    f.turnText:SetText(w and (isYou(w) and "|cff66dd66You win!|r" or (nameColored(w) .. " wins!")) or "The table is empty.")
    f.hint:SetText("Click New game for another round.")
  elseif g.phase == "farkle" then
    f.turnText:SetText("|cffff5555Farkle!|r")
    f.hint:SetText("No scoring dice. The turn's points are lost.")
  elseif mine then
    local line = "Turn: " .. fmt(g.turnScore)
    if selN > 0 then
      line = line .. (selOk and ("  +" .. fmt(selScore) .. " = |cffffd100" .. fmt(g.turnScore + selScore) .. "|r") or "  |cffff5555(not a scoring set)|r")
    end
    f.turnText:SetText(line)
    if g.phase == "ready" then
      f.hint:SetText("Roll the dice.")
    elseif g.chase then
      f.hint:SetText("Come on, " .. g.chase.missing .. "...")
    elseif chaseFor and selN == 0 then
      f.hint:SetText("One " .. chaseFor .. " short of a straight! Chase it, or play it safe.")
    elseif g.phase == "rolling" then
      f.hint:SetText("Waiting for the server's roll...")
    elseif selOk and (canBack or 0) > 0 then
      f.hint:SetText((refund or 0) > 0 and "Two 5s made a 1 (100). One 5 goes back in the cup."
        or "Keeping both 5s (100).")
    elseif g.minBank > 0 and g:PendingTotal() < g.minBank then
      f.hint:SetText(string.format("You need %s this turn before you can bank.", fmt(g.minBank)))
    elseif not p.onBoard and g.opening > 0 and g:PendingTotal() < g.opening then
      f.hint:SetText(string.format("You need %s in one turn to get on the board.", fmt(g.opening)))
    else
      f.hint:SetText("Pick scoring dice, then roll on or bank.")
    end
  else
    f.turnText:SetText(nameColored(p) .. ": " .. fmt(g.turnScore + ((selOk and selScore) or 0)))
    f.hint:SetText(p.remote and ("Waiting for " .. p.name .. "...") or ("Watching " .. p.name .. " play..."))
  end

  local canAct = mine and not f.animating
  local n = g:NextRollCount()
  local hot = g.phase == "choosing" and selOk and (g.remaining - selN == 0)
  f.rollBtn:SetText(hot and "Hot dice! Roll 6" or ("Roll " .. n .. (n == 1 and " die" or " dice")))
  f.rollBtn:SetEnabled(canAct and g:CanRoll())
  local bankTotal = g:PendingTotal()
  f.bankBtn:SetText(bankTotal > 0 and ("Bank " .. fmt(bankTotal)) or "Bank")
  f.bankBtn:SetEnabled(canAct and g:CanBank())
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function ns:ShowWindow()
  frame = frame or build()
  frame:Show()
  frame:Refresh()
end

function ns:ToggleWindow()
  if frame and frame:IsShown() then frame:Hide() else self:ShowWindow() end
end

function ns:ResetWindow()
  ns.db.ui.point = nil
  if frame then frame:ClearAllPoints(); frame:SetPoint("CENTER") end
  self:Print("Window moved back to the middle.")
end

function ns:GetWindow() return frame end

ns:Listen("TD_UPDATE", function()
  if frame and frame:IsShown() then frame:Refresh() end
end)

ns:Listen("TD_LOG", function(line)
  if frame then frame.log:AddMessage(line) end
end)

ns:Listen("TD_NEARBY", function()
  if frame and frame.lobby:IsShown() then frame.lobby:RefreshNearby() end
end)

ns:Listen("TD_LOG_RESET", function()
  if frame then frame.log:Clear() end
end)

ns:Listen("TD_EVENT", function(kind, a, b, c)
  if not frame then return end
  if kind == "ROLLING" then
    frame.animating = frame:IsShown()
    frame.animUntil = now() + (c and 0.9 or 0.45)   -- the chase gets a longer, tenser tumble
    frame.animCount = b or 6
    frame.animOnly = c
    frame.pendingToast = nil
  elseif kind == "STRAIGHT" then
    if frame.animating then frame.pendingToast = { "STRAIGHT!", 0.4, 0.95, 0.4 } else showToast("STRAIGHT!", 0.4, 0.95, 0.4) end
  elseif kind == "CHASEMISS" then
    if frame.animating then frame.pendingToast = { "MISSED!", 1, 0.3, 0.25 } else showToast("MISSED!", 1, 0.3, 0.25) end
  elseif kind == "FARKLE" then
    if frame.animating then frame.pendingToast = { "FARKLE!", 1, 0.3, 0.25 } else showToast("FARKLE!", 1, 0.3, 0.25) end
  elseif kind == "HOTDICE" then
    showToast("HOT DICE!", 1, 0.82, 0.2)
  elseif kind == "OVER" then
    showToast(isYou(a) and "You win!" or "Game over", 1, 0.82, 0.2)
  end
end)

ns:Listen("LOGIN", function()
  if not ns.db.welcomed then
    ns.db.welcomed = true
    ns:Print("Welcome, traveller. Type |cffffff00/dice|r to sit down at the table and play ten thousand.")
  end
end)
