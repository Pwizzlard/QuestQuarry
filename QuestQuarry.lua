-- QuestQuarry: RestedXP-style target + quest item buttons for pinned quests + the selected quest.
-- Auto data comes from QuestieDB (LibQuestieDB) when loaded; manual entries via /qt.

local f = CreateFrame("Frame", "QuestQuarryFrame", UIParent, "BackdropTemplate")
local DB, Pins, QDB
local tBtns, iBtns, headers, pending, queued = {}, {}, {}, false, false
local ROW, PAD, W, MAX_PINS = 20, 6, 182, 5

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
local GetItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local GetItemCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown

local Build -- forward

-- "Selected" = whichever changed most recently: quest log selection or super-track
-- (clicking a quest in Questie's tracker super-tracks it without touching the log selection).
local current, rawSel, rawSuper
local function PollSelection()
  local s = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
  local t = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() or 0
  local changed = false
  -- a new pick becomes current; deselecting the source of current clears it (box = pins only)
  if s ~= rawSel then
    if s ~= 0 then current = s elseif current == rawSel then current = nil end
    rawSel = s; changed = true
  end
  if t ~= rawSuper then
    if t ~= 0 then current = t elseif current == rawSuper then current = nil end
    rawSuper = t; changed = true
  end
  return changed
end

local function SelectedQuest()
  if current and C_QuestLog.GetLogIndexForQuestID(current) then return current end
end

-- The unpinned "selected quest" preview only shows while you're looking at your quests,
-- so nothing appears on its own (Questie also moves the selection behind the scenes).
local function Browsing()
  for _, fr in pairs({ QuestLogExFrame, ClassicQuestLog, QuestLogFrame, WorldMapFrame }) do
    if fr:IsShown() then return true end
  end
  return false
end

local function IsPinned(id)
  for _, p in ipairs(Pins) do if p == id then return true end end
end

local function Unpin(id)
  for i = #Pins, 1, -1 do if Pins[i] == id then tremove(Pins, i) end end
end

local function Pin(id)
  if not id or IsPinned(id) then return end
  if #Pins >= MAX_PINS then print("QuestQuarry: all " .. MAX_PINS .. " slots full, unpin one first"); return end
  tinsert(Pins, id)
end

-- One section = {title, qid, targets, items}. `seen` is shared so a mob/item shows once overall.
local function NewSection(seen, title, qid)
  local s = { title = title, qid = qid, targets = {}, items = {}, turnin = {} }
  function s.T(name, turnin)
    if name and name ~= "" and not seen[name] then
      seen[name] = true; s.targets[#s.targets + 1] = name; s.turnin[name] = turnin
    end
  end
  function s.I(id, auto)
    id = tonumber(id)
    if not id or seen[id] or GetItemCount(id) == 0 then return end
    if auto and not GetItemSpell(id) then return end -- auto items: only ones with a "Use:"
    seen[id] = true; s.items[#s.items + 1] = id
  end
  return s
end

local function GatherQuest(s, qid)
  local T, I = s.T, s.I
  local objs = C_QuestLog.GetQuestObjectives(qid) or {}
  local allDone = #objs > 0
  for _, o in ipairs(objs) do if not o.finished then allDone = false end end
  local function done(name) -- a finished objective line mentions this name
    for _, o in ipairs(objs) do
      if o.finished and o.text and o.text:find(name, 1, true) then return true end
    end
  end

  local q = QDB and QDB.Quest.objectives(qid)
  local complete = allDone or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid))
  if complete then -- swap mob rows for the turn-in NPC
    local fin = QDB and QDB.Quest.finishedBy(qid)
    for _, npc in ipairs(fin and fin[1] or {}) do T(QDB.Npc.name(npc), true) end
  else
    if q then
      for _, c in ipairs(q[1] or {}) do -- kill objectives
        local n = QDB.Npc.name(c[1])
        if n and not done(n) then T(n) end
      end
      for _, it in ipairs(q[3] or {}) do -- loot objectives -> mobs that drop it
        local iname = QDB.Item.name(it[1])
        if not (iname and done(iname)) then
          for k, npc in ipairs(QDB.Item.npcDrops(it[1]) or {}) do
            if k > 4 then break end -- ponytail: first 4 droppers; filter by zone if wrong mobs show
            T(QDB.Npc.name(npc))
          end
        end
      end
      for _, kc in ipairs(q[5] or {}) do -- kill-credit objectives
        local n = QDB.Npc.name(kc[2])
        if n and not done(kc[3] or n) then T(n) end
      end
    else -- no Questie: parse "0/10 Kobold Vermin slain" style lines (English client)
      for _, o in ipairs(objs) do
        if o.type == "monster" and not o.finished and o.text then
          T((o.text:gsub("%d+/%d+", ""):gsub(":", ""):gsub(" slain", ""):match("^%s*(.-)%s*$")))
        end
      end
    end
  end

  if q then for _, sp in ipairs(q[6] or {}) do I(sp[3], true) end end -- "use item on X" objectives
  if QDB then
    I(QDB.Quest.sourceItemId(qid), true)
    for _, id in ipairs(QDB.Quest.requiredSourceItems(qid) or {}) do I(id, true) end
  end
  local idx = C_QuestLog.GetLogIndexForQuestID(qid)
  if GetQuestLogSpecialItemInfo and idx then
    local link = GetQuestLogSpecialItemInfo(idx)
    if link then I(link:match("item:(%d+)")) end
  end
end

local function Gather()
  local seen, sections = {}, {}
  local manual = NewSection(seen, "Manual")
  for _, n in ipairs(DB.targets) do manual.T(n) end
  for _, id in ipairs(DB.items) do manual.I(id) end
  if #manual.targets + #manual.items > 0 then sections[1] = manual end
  if not DB.auto then return sections end

  local quests, sel = {}, SelectedQuest()
  for _, id in ipairs(Pins) do if C_QuestLog.GetLogIndexForQuestID(id) then quests[#quests + 1] = id end end
  if sel and not IsPinned(sel) and (DB.follow or Browsing()) then quests[#quests + 1] = sel end
  for _, qid in ipairs(quests) do
    local s = NewSection(seen, C_QuestLog.GetTitleForQuestID(qid) or ("Quest " .. qid), qid)
    GatherQuest(s, qid)
    sections[#sections + 1] = s
  end
  return sections
end

local function Header(i)
  local h = CreateFrame("Frame", nil, f)
  h:SetSize(W - PAD * 2, 14)
  h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h.text:SetPoint("LEFT", 2, 0); h.text:SetPoint("RIGHT", -16, 0); h.text:SetJustifyH("LEFT")
  h.pin = CreateFrame("Button", nil, h)
  h.pin:SetSize(14, 14); h.pin:SetPoint("RIGHT")
  h.pin:SetNormalFontObject("GameFontHighlightSmall")
  h.pin:SetHighlightFontObject("GameFontNormalSmall")
  h.pin:SetScript("OnClick", function()
    if h.qid == "manual" then wipe(DB.targets); wipe(DB.items)
    elseif IsPinned(h.qid) then Unpin(h.qid)
    else Pin(h.qid) end
    GameTooltip:Hide()
    Build()
  end)
  h.pin:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:SetText(h.qid == "manual" and "Clear manual targets"
      or IsPinned(h.qid) and "Unpin this quest" or "Pin this quest")
    GameTooltip:Show()
  end)
  h.pin:SetScript("OnLeave", GameTooltip_Hide)
  headers[i] = h
  return h
end

local function TargetButton(i)
  local b = CreateFrame("Button", "QuestQuarryT" .. i, f, "SecureActionButtonTemplate")
  b:SetSize(W - PAD * 2, 18)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0); b.text:SetPoint("RIGHT"); b.text:SetJustifyH("LEFT")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  tBtns[i] = b
  return b
end

local function ItemButton(i)
  local b = CreateFrame("Button", "QuestQuarryI" .. i, f, "SecureActionButtonTemplate")
  b:SetSize(30, 30)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); b.cd:SetAllPoints()
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(s.id); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  iBtns[i] = b
  return b
end

-- "Next quest enemy" buttons. The secure snippet advances the list so it keeps cycling in
-- combat; the list itself is refreshed out of combat by Build.
local CYCLE_SNIPPET = [[
  local n = self:GetAttribute("count") or 0
  if n == 0 then self:SetAttribute("macrotext", "/targetenemy") return end -- no quest mobs: normal Tab
  if down then -- advance once per press (down + up both arrive)
    local i = (self:GetAttribute("idx") or 0) % n + 1
    self:SetAttribute("idx", i)
    -- start at the next name; if nothing (alive) was found, fall through to the following ones,
    -- as many as fit in WoW's 255-character macro limit
    local tail = "\n/cleartarget [dead]" .. self:GetAttribute("suffix")
    local m = "/cleartarget\n/targetexact " .. self:GetAttribute("name" .. i)
    for k = 1, n - 1 do
      local line = "\n/targetexact [noexists][dead] " .. self:GetAttribute("name" .. ((i - 1 + k) % n + 1))
      if #m + #line + #tail > 255 then break end
      m = m .. line
    end
    self:SetAttribute("macrotext", m .. tail)
  end
]]

local function CycleButton(name, parent)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  SecureHandlerWrapScript(b, "OnClick", b, CYCLE_SNIPPET)
  return b
end

-- Invisible one for Tab / the keybind (on UIParent so it works even when the box is hidden).
local cyc = CycleButton("QuestQuarryCycle", UIParent)
cyc:SetSize(1, 1)
cyc:SetPoint("CENTER")
cyc:EnableMouse(false)

-- Clickable one on the box.
local nextBtn = CycleButton("QuestQuarryNext", f)
nextBtn:SetSize(80, 16)
nextBtn:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -4, 2)
nextBtn:SetNormalFontObject("GameFontHighlightSmall")
nextBtn:SetHighlightFontObject("GameFontNormalSmall")
nextBtn:SetText("Next target >")

-- After a press (out of combat only: attributes are locked in combat), make the next press start
-- right after the name just found, so it alternates between nearby quest mobs instead of
-- re-finding the same one while the rotation walks through names that aren't around.
for _, b in ipairs({ cyc, nextBtn }) do
  b:HookScript("OnClick", function(s)
    if InCombatLockdown() or not UnitExists("target") then return end
    local name = UnitName("target")
    for i = 1, s:GetAttribute("count") or 0 do
      if s:GetAttribute("name" .. i) == name then
        cyc:SetAttribute("idx", i); nextBtn:SetAttribute("idx", i)
        return
      end
    end
  end)
end

BINDING_HEADER_QUESTQUARRY = "QuestQuarry"
_G["BINDING_NAME_CLICK QuestQuarryCycle:LeftButton"] = "Target next quest enemy"

-- Checkbox: temporarily point Tab at the cycle button (override binding; saved keybinds untouched).
local function ApplyTab()
  ClearOverrideBindings(cyc)
  if DB.tab then SetOverrideBindingClick(cyc, true, "TAB", "QuestQuarryCycle", "LeftButton") end
end

local tabBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
tabBox:SetSize(20, 20)
tabBox:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -2, -4)
tabBox.label = tabBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tabBox.label:SetPoint("RIGHT", tabBox, "LEFT", -1, 0)
tabBox.label:SetText("Quest Only Tab")
tabBox:SetScript("OnClick", function(s)
  if InCombatLockdown() then
    s:SetChecked(DB.tab); print("QuestQuarry: can't change Tab in combat"); return
  end
  DB.tab = s:GetChecked() and true or false
  ApplyTab()
end)

local function RefreshItems()
  for _, b in ipairs(iBtns) do
    if b:IsShown() then
      b.count:SetText(GetItemCount(b.id))
      local start, dur = GetItemCooldown(b.id)
      b.cd:SetCooldown(start or 0, dur or 0)
    end
  end
end

-- Secure buttons can't change in combat, so rebuilds wait for PLAYER_REGEN_ENABLED.
function Build()
  if InCombatLockdown() then pending = true; return end
  pending = false
  local y, hi, ti, ii, ci, maxItems = -6, 0, 0, 0, 0, 0

  for _, s in ipairs(Gather()) do
    hi = hi + 1
    local h = headers[hi] or Header(hi)
    h.qid = s.qid or "manual"
    h.text:SetText(s.title)
    h.pin:SetText((s.qid and not IsPinned(s.qid)) and "|cff33ff33+|r" or "|cffff3333x|r")
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", PAD, y); h:Show()
    y = y - 16

    for _, name in ipairs(s.targets) do
      ti = ti + 1
      local b = tBtns[ti] or TargetButton(ti)
      local turnin = s.turnin[name] -- friendly turn-in NPC: no skull, not in the cycle
      if not turnin then
        ci = ci + 1
        cyc:SetAttribute("name" .. ci, name); nextBtn:SetAttribute("name" .. ci, name)
      end
      b:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name .. ((DB.mark and not turnin) and "\n/tm !8" or ""))
      b.icon:SetTexture(turnin and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
      b.text:SetText(turnin and ("|cffffd100Turn in:|r " .. name) or name)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD, y); b:Show()
      y = y - ROW
    end

    for i, id in ipairs(s.items) do
      ii = ii + 1
      local b = iBtns[ii] or ItemButton(ii)
      b.id = id
      b:SetAttribute("item", "item:" .. id)
      b.icon:SetTexture(GetItemIcon(id))
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD + (i - 1) * 34, y - 2); b:Show()
    end
    if #s.items > 0 then y = y - 36 end
    maxItems = math.max(maxItems, #s.items)
    y = y - 4
  end

  for _, b in ipairs({ cyc, nextBtn }) do
    b:SetAttribute("count", ci)
    b:SetAttribute("suffix", DB.mark and "\n/tm !8" or "")
  end
  nextBtn:SetShown(ci > 0)
  tabBox:SetChecked(DB.tab)

  for i = hi + 1, #headers do headers[i]:Hide() end
  for i = ti + 1, #tBtns do tBtns[i]:Hide() end
  for i = ii + 1, #iBtns do iBtns[i]:Hide() end
  f:SetSize(math.max(W, PAD * 2 + maxItems * 34), -y + 2)
  f:SetShown(hi > 0)
  RefreshItems()
end

local function Queue() -- QUEST_LOG_UPDATE is spammy; coalesce
  if queued then return end
  queued = true
  C_Timer.After(0.3, function() queued = false; Build() end)
end

f:SetSize(W, 40)
f:SetPoint("CENTER", 300, 0)
f:Hide()
f:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.7)
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(s) if not InCombatLockdown() then s:StartMoving() end end)
f:SetScript("OnDragStop", function(s)
  s:StopMovingOrSizing()
  local p, _, rp, x, y = s:GetPoint()
  DB.pos = { p, rp, x, y }
end)

f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, e, arg)
  if e == "ADDON_LOADED" then
    if arg ~= "QuestQuarry" then return end
    f:UnregisterEvent("ADDON_LOADED")
    QuestQuarryDB = QuestQuarryDB or {}
    QuestQuarryPins = QuestQuarryPins or {}
    DB, Pins = QuestQuarryDB, QuestQuarryPins
    DB.targets, DB.items = DB.targets or {}, DB.items or {}
    if DB.auto == nil then DB.auto = true end
    if DB.mark == nil then DB.mark = true end
    if DB.follow == nil then DB.follow = true end
    ApplyTab()
    if DB.pos then f:ClearAllPoints(); f:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4]) end
    if LibQuestieDB and LibQuestieDB.RequireContract and LibQuestieDB.RequireContract(4) then QDB = LibQuestieDB end
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED", "QUEST_REMOVED",
      "QUEST_WATCH_LIST_CHANGED", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED" }) do
      pcall(f.RegisterEvent, f, ev)
    end
    -- Quest log selection has no reliable event/hook on this client, so watch it (cheap compare).
    local lastBrowse
    C_Timer.NewTicker(0.25, function()
      local br = Browsing()
      if PollSelection() or br ~= lastBrowse then lastBrowse = br; Queue() end
    end)
  elseif e == "QUEST_REMOVED" then -- turned in / abandoned: free the slot
    Unpin(arg); Queue()
  elseif e == "PLAYER_REGEN_ENABLED" then
    if pending then Build() end
  elseif e == "BAG_UPDATE_COOLDOWN" then
    RefreshItems()
  else
    Queue()
  end
end)

SLASH_QUESTQUARRY1, SLASH_QUESTQUARRY2 = "/qt", "/questquarry"
SlashCmdList.QUESTQUARRY = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local id = tonumber(arg:match("item:(%d+)") or arg)
  if cmd == "add" then
    if arg == "" then arg = UnitName("target") or "" end
    for name in arg:gmatch("[^,]+") do
      name = name:match("^%s*(.-)%s*$")
      if name ~= "" then tinsert(DB.targets, name) end
    end
  elseif cmd == "item" and id then
    tinsert(DB.items, id)
  elseif cmd == "del" then
    for i = #DB.targets, 1, -1 do if DB.targets[i]:lower() == arg:lower() then tremove(DB.targets, i) end end
    for i = #DB.items, 1, -1 do if DB.items[i] == id then tremove(DB.items, i) end end
  elseif cmd == "clear" then
    wipe(DB.targets); wipe(DB.items)
  elseif cmd == "pin" then
    Pin(SelectedQuest())
  elseif cmd == "unpin" then
    wipe(Pins)
  elseif cmd == "auto" then
    DB.auto = not DB.auto; print("QuestQuarry auto from quest:", DB.auto)
  elseif cmd == "follow" then
    DB.follow = not DB.follow; print("QuestQuarry always show selected quest (off = only while quest log/map is open):", DB.follow)
  elseif cmd == "mark" then
    DB.mark = not DB.mark; print("QuestQuarry skull marking:", DB.mark)
  else
    print("|cff33ff99QuestQuarry|r /qt add [Name, Name...] (no name = current target) | item <link or id> | del <name/item> | clear")
    print("  /qt pin (pin selected quest, up to " .. MAX_PINS .. ") | unpin (clear all pins) | follow | auto | mark")
    print("Manual targets: " .. table.concat(DB.targets, ", ") .. "  items: " .. table.concat(DB.items, ", "))
    print("QuestieDB: " .. (QDB and "found" or "not found (kill objectives only)"))
  end
  Build()
end
