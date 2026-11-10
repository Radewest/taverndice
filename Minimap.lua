-- TavernDice: Minimap button
-- Left-click opens the table, drag to move around the minimap.

local ADDON, ns = ...

local btn

local function position()
  local a = math.rad(ns.db.minimap.angle or 210)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function build()
  btn = CreateFrame("Button", "TavernDiceMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\media\\icon")
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnClick", function() ns:ToggleWindow() end)
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      if mx and cx then
        ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        position()
      end
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(ns.COLOR .. "Tavern Dice|r")
    GameTooltip:AddLine("Click to open the dice table. Drag to move.", 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  position()
  btn:SetShown(not ns.db.minimap.hide)
end

ns:Listen("LOGIN", function() if Minimap then build() end end)
