-- TavernDice: Bug log
-- TavernDice records its own Lua errors (with a short stack trace) in TavernDiceDB.errors.
-- /dice bugs opens a window with everything selected, ready to Ctrl+C and send to the developer.
-- Errors still go to BugSack / the default error frame as normal.

local _, ns = ...

local MAX_ERRORS = 30
local notified = false
local window

function ns:LogError(err)
  if not self.db then return end
  err = tostring(err or "?")
  local first = err:match("^[^\n]*") or err
  local stack = err:sub(#first + 2)
  local log = self.db.errors

  for _, e in ipairs(log) do
    if e.msg == first then
      e.count = (e.count or 1) + 1
      e.last = time()
      return
    end
  end
  table.insert(log, { msg = first, stack = stack, count = 1, first = time(), last = time(), v = ns.VERSION })
  while #log > MAX_ERRORS do table.remove(log, 1) end

  if not notified then
    notified = true
    self:Chat("|cffff5555TavernDice hit a bug.|r Type |cffffff00/dice bugs|r to copy the details and send them to the developer.")
  end
end

function ns:ClearErrors()
  wipe(self.db.errors)
  self:Print("Bug log cleared.")
  if window and window:IsShown() then window:Refresh() end
end

local function buildReport()
  local version, build, _, toc = GetBuildInfo()
  local lines = {
    string.format("TavernDice %s | client %s (%s) toc %s | %s", ns.VERSION, tostring(version), tostring(build), tostring(toc), date("%Y-%m-%d %H:%M")),
    "",
  }
  if #ns.db.errors == 0 then
    table.insert(lines, "No errors logged. Nice.")
  end
  for i, e in ipairs(ns.db.errors) do
    table.insert(lines, string.format("#%d  x%d  (v%s, last %s)", i, e.count or 1, e.v or "?", date("%m-%d %H:%M", e.last or 0)))
    table.insert(lines, e.msg)
    if e.stack and e.stack ~= "" then table.insert(lines, e.stack) end
    table.insert(lines, "")
  end
  return table.concat(lines, "\n")
end

local function createWindow()
  local f = CreateFrame("Frame", "TavernDiceBugFrame", UIParent, "BackdropTemplate")
  f:SetSize(560, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  f:SetBackdropColor(0.03, 0.03, 0.04, 0.97)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(UISpecialFrames, "TavernDiceBugFrame")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("|cff33ff99TavernDice|r bug log")
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetText("Everything is selected: press Ctrl+C, then paste it to the developer.")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -56)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(500)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  clear:SetSize(100, 22)
  clear:SetPoint("BOTTOMLEFT", 16, 14)
  clear:SetText("Clear log")
  clear:SetScript("OnClick", function() ns:ClearErrors() end)

  local selBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selBtn:SetSize(100, 22)
  selBtn:SetPoint("LEFT", clear, "RIGHT", 8, 0)
  selBtn:SetText("Select all")
  selBtn:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)

  function f:Refresh()
    edit:SetText(buildReport())
    edit:SetFocus()
    edit:HighlightText()
  end
  return f
end

function ns:ShowBugs()
  window = window or createWindow()
  window:Show()
  window:Refresh()
end

-- Catch TavernDice errors that happen outside our event wrappers (timers, OnUpdate scripts).
-- If another addon (e.g. BugGrabber) blocks this, BugSack still has them.
ns:Listen("LOGIN", function()
  local prev = geterrorhandler()
  pcall(seterrorhandler, function(msg, ...)
    if not ns.reporting and type(msg) == "string" and msg:find("AddOns[\\/]TavernDice[\\/]") then
      pcall(ns.LogError, ns, msg .. "\n" .. (debugstack and debugstack(3, 10, 0) or ""))
    end
    return prev(msg, ...)
  end)
end)
