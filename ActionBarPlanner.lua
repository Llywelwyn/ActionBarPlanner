local ADDON_NAME, ns = ...

local BAR_DEFS = {
	{binding = "ACTIONBUTTON%d", offset = 0, button = "ActionButton%d", always = true},
	{binding = "MULTIACTIONBAR1BUTTON%d", offset = 60, button = "MultiBarBottomLeftButton%d", container = "MultiBarBottomLeft", always = true},
	{binding = "MULTIACTIONBAR2BUTTON%d", offset = 48, button = "MultiBarBottomRightButton%d", container = "MultiBarBottomRight", always = true},
	{binding = "MULTIACTIONBAR3BUTTON%d", offset = 24, button = "MultiBarRightButton%d", container = "MultiBarRight", always = true},
	{binding = "MULTIACTIONBAR4BUTTON%d", offset = 36, button = "MultiBarLeftButton%d", container = "MultiBarLeft", always = true},
	{binding = "MULTIACTIONBAR5BUTTON%d", offset = 144, button = "MultiBar5Button%d", container = "MultiBar5"},
	{binding = "MULTIACTIONBAR6BUTTON%d", offset = 156, button = "MultiBar6Button%d", container = "MultiBar6"},
	{binding = "MULTIACTIONBAR7BUTTON%d", offset = 168, button = "MultiBar7Button%d", container = "MultiBar7"},
}
local BARS = {}

local function IsBarEnabled(bar)
	if bar.index == 1 then
		return true
	end
	local toggles = {GetActionBarToggles()}
	if toggles[bar.index - 1] then
		return true
	end
	local container = bar.container and _G[bar.container]
	return (container and container:IsShown()) and true or false
end

local UNIVERSAL_SPELLS = {
	{id = 5019, level = 1},
	{id = 6603, level = 1},
}

local SLOT_SIZE, SLOT_GAP, ROW_GAP = 36, 4, 8
local PALETTE_WIDTH = 240
local QUESTION_MARK = 134400

local ALL_KEYS = {}
do
	local function add(...)
		for _, k in ipairs({...}) do
			tinsert(ALL_KEYS, k)
		end
	end
	add("`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=")
	add("TAB", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\")
	add("CAPSLOCK", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'")
	add("Z", "X", "C", "V", "B", "N", "M", ",", ".", "/")
	add("SPACE")
	add("F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12")
	add("UP", "DOWN", "LEFT", "RIGHT", "INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN")
	add("NUMPAD0", "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9")
	add("NUMPADPLUS", "NUMPADMINUS", "NUMPADMULTIPLY", "NUMPADDIVIDE", "NUMPADDECIMAL")
	add("BUTTON3", "BUTTON4", "BUTTON5", "BUTTON6", "BUTTON7", "BUTTON8", "MOUSEWHEELUP", "MOUSEWHEELDOWN")
end
local MOD_GROUPS = {
	{"", "Unmodified"},
	{"SHIFT-", "Shift"},
	{"CTRL-", "Ctrl"},
	{"ALT-", "Alt"},
}

local GetName = C_Spell.GetSpellName or function(id)
	local si = C_Spell.GetSpellInfo(id)
	return si and si.name
end
local GetTexture = C_Spell.GetSpellTexture
local GetSubtext = C_Spell.GetSpellSubtext
local PickupSpell = C_Spell.PickupSpell or PickupSpell
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local PickupItemByID = (C_Item and C_Item.PickupItem) or PickupItem

local function IsKnown(id)
	return C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player)
		or C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false)
end

local db
local classSpells = {}
local heldEntry, heldKey
local frame, cursorFrame, paletteRows, slotButtons, rankMenu, hiddenBtn, searchText
local keysFrame, keysRows
local shareFrame, pendingImport
local unplannedOnly = false
local barRows = {}
local overlays = {}
local refreshPending = false
local applyQueued = false

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ActionBarPlanner|r: " .. msg)
end

local function PlayUISound(kitName)
	local kit = SOUNDKIT and SOUNDKIT[kitName]
	if kit then
		pcall(PlaySound, kit)
	end
end

local function BuildBars()
	wipe(BARS)
	for i, def in ipairs(BAR_DEFS) do
		if def.always or _G[def.button:format(1)] or (def.container and _G[def.container]) then
			def.index = i
			def.label = "Action Bar " .. i
			tinsert(BARS, def)
		end
	end
end

local function BuildClassSpells()
	local _, class = UnitClass("player")
	local faction = UnitFactionGroup("player")
	local raceId = select(3, UnitRace("player"))
	wipe(classSpells)
	local function accept(s)
		local factionOk = not s.faction or s.faction == faction
		local raceOk = not s.races or tContains(s.races, raceId)
		local exists = not C_Spell.DoesSpellExist or C_Spell.DoesSpellExist(s.id)
		return factionOk and raceOk and exists
	end
	for _, s in ipairs(ns.SPELLS[class] or {}) do
		if accept(s) then
			tinsert(classSpells, s)
		end
	end
	for _, s in ipairs(UNIVERSAL_SPELLS) do
		if accept(s) then
			tinsert(classSpells, s)
		end
	end
end

local function RequestSpellData()
	for _, s in ipairs(classSpells) do
		if not C_Spell.IsSpellDataCached(s.id) then
			C_Spell.RequestLoadSpellData(s.id)
		end
	end
end

local function SpellEntry(id)
	for _, s in ipairs(classSpells) do
		if s.id == id then
			return s
		end
	end
end

local function SpellLevel(id)
	local s = SpellEntry(id)
	return s and s.level
end

local function IsTalentEntry(e)
	if e.t ~= "spell" then
		return false
	end
	if e.exact then
		local s = SpellEntry(e.id)
		return s and s.talent or false
	end
	local name = GetName(e.id)
	if not name then
		return false
	end
	local any = false
	for _, s in ipairs(classSpells) do
		if GetName(s.id) == name then
			if not s.talent then
				return false
			end
			any = true
		end
	end
	return any
end

local function FirstRankLevel(e)
	if e.exact then
		return SpellLevel(e.id)
	end
	local name = GetName(e.id)
	if not name then
		return SpellLevel(e.id)
	end
	local min
	for _, s in ipairs(classSpells) do
		if GetName(s.id) == name and (not min or s.level < min) then
			min = s.level
		end
	end
	return min or SpellLevel(e.id)
end

local function RanksOf(name)
	local ranks = {}
	for _, s in ipairs(classSpells) do
		if GetName(s.id) == name then
			tinsert(ranks, s)
		end
	end
	sort(ranks, function(a, b)
		return a.level < b.level
	end)
	return ranks
end

local function ResolveSpell(e)
	if e.exact then
		return IsKnown(e.id) and e.id or nil
	end
	if IsKnown(e.id) then
		return e.id
	end
	local name = GetName(e.id)
	if not name then
		return nil
	end
	local best, bestLevel
	for _, s in ipairs(classSpells) do
		if GetName(s.id) == name and IsKnown(s.id) and (not bestLevel or s.level > bestLevel) then
			best, bestLevel = s.id, s.level
		end
	end
	return best
end

local function FindMacroIndex(e)
	local numGlobal, numChar = GetNumMacros()
	local maxGlobal = MAX_ACCOUNT_MACROS or 120
	local byBody, byName
	local function scan(from, to)
		for i = from, to do
			local name, _, body = GetMacroInfo(i)
			if name then
				if name == e.name and (not e.body or body == e.body) then
					return i
				end
				if not byBody and e.body and body == e.body then
					byBody = i
				end
				if not byName and e.name ~= "" and name == e.name then
					byName = i
				end
			end
		end
	end
	return scan(1, numGlobal) or scan(maxGlobal + 1, maxGlobal + numChar) or byBody or byName
end

local function EntryIcon(e)
	if e.t == "spell" then
		return GetTexture(e.id)
	elseif e.t == "item" then
		local icon = GetItemIcon and GetItemIcon(e.id)
		if not icon and C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(e.id)
		end
		return icon
	elseif e.t == "macro" then
		local idx = FindMacroIndex(e)
		local icon = idx and select(2, GetMacroInfo(idx))
		return icon or e.icon
	end
end

local function EntryMatchesSlot(e, slot)
	local actionType, id = GetActionInfo(slot)
	if e.t == "spell" then
		local target = ResolveSpell(e)
		return target and actionType == "spell" and id == target
	elseif e.t == "item" then
		return actionType == "item" and id == e.id
	elseif e.t == "macro" then
		if actionType ~= "macro" then
			return false
		end
		if id and id > 0 then
			local name, _, body = GetMacroInfo(id)
			if e.body then
				return body == e.body and (e.name == "" or name == e.name)
			end
			return name == e.name
		end
		return e.name ~= "" and GetActionText(slot) == e.name
	end
end

local function MatchesSearch(e)
	if not searchText or searchText == "" then
		return false
	end
	local name
	if e.t == "spell" then
		name = GetName(e.id)
	elseif e.t == "item" then
		name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id))
			or (GetItemInfo and GetItemInfo(e.id))
	elseif e.t == "macro" then
		name = e.name
	end
	return name and strfind(strlower(name), strlower(searchText), 1, true) ~= nil or false
end

local function PaletteEntries()
	local byName, loading = {}, 0
	local hidden = db.hidden or {}
	for _, s in ipairs(classSpells) do
		local name = GetName(s.id)
		if not name then
			loading = loading + 1
		elseif not hidden[name] then
			local line = byName[name]
			if not line then
				byName[name] = {maxId = s.id, maxLevel = s.level, minLevel = s.level, talent = s.talent or false}
			else
				if s.level > line.maxLevel then
					line.maxId, line.maxLevel = s.id, s.level
				end
				if s.level < line.minLevel then
					line.minLevel = s.level
				end
				line.talent = line.talent and (s.talent or false)
			end
		end
	end
	local planned = {}
	for _, pe in pairs(db.plan) do
		if pe.t == "spell" then
			local n = GetName(pe.id)
			if n then
				planned[n] = true
			end
		end
	end
	local entries = {}
	local filter = searchText and strlower(searchText) or ""
	for name, line in pairs(byName) do
		if (filter == "" or strfind(strlower(name), filter, 1, true)) and not (unplannedOnly and planned[name]) then
			tinsert(entries, {
				id = line.maxId,
				level = line.minLevel,
				name = name,
				talent = line.talent,
				planned = planned[name],
			})
		end
	end
	sort(entries, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.name < b.name
	end)
	if loading > 0 and filter == "" then
		tinsert(entries, {loading = loading})
	end
	return entries
end

local function AbbrevKey(key)
	key = key:gsub("SHIFT%-", "s-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
	key = key:gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
	key = key:gsub("BUTTON", "m"):gsub("NUMPAD", "n")
	return key
end

local function BindText(cmd)
	local key = GetBindingKey(cmd)
	return key and AbbrevKey(key) or ""
end

local function SetHeldEntry(e)
	heldEntry = e
	heldKey = nil
	if rankMenu then
		rankMenu:Hide()
	end
	cursorFrame.text:SetText("")
	if e then
		cursorFrame.icon:Show()
		cursorFrame.icon:SetTexture(EntryIcon(e) or QUESTION_MARK)
		cursorFrame:Show()
	else
		cursorFrame:Hide()
	end
end

local function SetHeldKey(key)
	heldEntry = nil
	heldKey = key
	if rankMenu then
		rankMenu:Hide()
	end
	if key then
		cursorFrame.icon:Hide()
		cursorFrame.text:SetText(AbbrevKey(key))
		cursorFrame:Show()
	else
		cursorFrame.text:SetText("")
		cursorFrame:Hide()
	end
end

local function UpdatePreview()
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local slot = bar.offset + i
			local e = db.plan[slot]
			local differs = db.preview and e and not EntryMatchesSlot(e, slot)
			local match = db.preview and e and MatchesSearch(e)
			local ov = overlays[slot]
			if differs or match then
				if not ov then
					local button = _G[bar.button:format(i)]
					if button then
						ov = CreateFrame("Frame", nil, button)
						ov:SetAllPoints()
						ov:SetFrameLevel(button:GetFrameLevel() + 10)
						ov.glow = ov:CreateTexture(nil, "OVERLAY", nil, -1)
						ov.glow:SetAllPoints()
						ov.glow:SetColorTexture(1, 0.85, 0.2, 0.3)
						ov.icon = ov:CreateTexture(nil, "OVERLAY")
						ov.icon:SetPoint("TOPLEFT", 2, -2)
						ov.icon:SetPoint("BOTTOMRIGHT", -2, 2)
						ov.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
						ov.icon:SetAlpha(0.22)
						ov.level = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
						ov.level:SetPoint("BOTTOM", 0, 2)
						ov.level:SetAlpha(0.75)
						overlays[slot] = ov
					end
				end
				if ov then
					ov.glow:SetShown(match and true or false)
					if differs then
						ov.icon:Show()
						ov.icon:SetTexture(EntryIcon(e) or QUESTION_MARK)
						if e.t == "spell" and not ResolveSpell(e) then
							ov.icon:SetDesaturated(true)
							if IsTalentEntry(e) then
								ov.level:SetTextColor(1, 0.82, 0)
								ov.level:SetText("T")
							else
								ov.level:SetTextColor(1, 0.35, 0.35)
								local level = FirstRankLevel(e)
								ov.level:SetText(level and ("L" .. level) or "")
							end
						else
							ov.icon:SetDesaturated(false)
							ov.level:SetText("")
						end
					else
						ov.icon:Hide()
						ov.level:SetText("")
					end
					ov:Show()
				end
			elseif ov then
				ov:Hide()
			end
		end
	end
end

local function IsActionBarCommand(action)
	return action:match("^ACTIONBUTTON%d+$") or action:match("^MULTIACTIONBAR%dBUTTON%d+$")
end

local function FreeKeyRows()
	local rows = {}
	for _, grp in ipairs(MOD_GROUPS) do
		local mod, label = grp[1], grp[2]
		local free, taken = {}, {}
		for _, base in ipairs(ALL_KEYS) do
			local key = mod .. base
			local action = GetBindingAction(key)
			if not action or action == "" then
				tinsert(free, {key = key})
			elseif not IsActionBarCommand(action) then
				tinsert(taken, {key = key, action = action})
			end
		end
		if #free + #taken > 0 then
			tinsert(rows, {header = label})
			for _, r in ipairs(free) do
				tinsert(rows, r)
			end
			for _, r in ipairs(taken) do
				tinsert(rows, r)
			end
		end
	end
	return rows
end

local function BindingDisplayName(action)
	return _G["BINDING_NAME_" .. action] or action
end

local function CreateKeysRow(i)
	local row = CreateFrame("Button", nil, keysFrame.scrollContent)
	row:SetSize(180, 18)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 2, 0)
	row.text:SetPoint("RIGHT", -2, 0)
	row.text:SetJustifyH("LEFT")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnClick", function(self)
		if self.entry and self.entry.key then
			SetHeldKey(self.entry.key)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not (self.entry and self.entry.key) then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(AbbrevKey(self.entry.key))
		if self.entry.action then
			GameTooltip:AddLine("Currently: " .. BindingDisplayName(self.entry.action), 1, 0.8, 0.4)
			GameTooltip:AddLine("Binding it to a bar button will replace that.", 0.6, 0.6, 0.6)
		else
			GameTooltip:AddLine("Not bound to anything.", 0.5, 1, 0.5)
		end
		GameTooltip:AddLine("Click, then click a planner slot to bind.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	keysRows[i] = row
	return row
end

local function RefreshKeysUI()
	if not keysFrame or not keysFrame:IsShown() then
		return
	end
	local rows = FreeKeyRows()
	for i = 1, math.max(#rows, #keysRows) do
		local r = rows[i]
		local row = keysRows[i] or (r and CreateKeysRow(i))
		if not row then
			break
		end
		row.entry = r
		if not r then
			row:Hide()
		elseif r.header then
			row.text:SetText("|cffffd100" .. r.header .. "|r")
			row:Show()
		elseif r.action then
			row.text:SetText(("|cffffcc66%-5s|r |cff909090%s|r"):format(AbbrevKey(r.key), BindingDisplayName(r.action)))
			row:Show()
		else
			row.text:SetText(("|cff88ff88%-5s|r unbound"):format(AbbrevKey(r.key)))
			row:Show()
		end
	end
	keysFrame.scrollContent:SetHeight(#rows * 18 + 4)
end

local function RefreshLayout()
	if not frame then
		return
	end
	local shown = 0
	for idx, bar in ipairs(BARS) do
		local row = barRows[idx]
		if IsBarEnabled(bar) then
			shown = shown + 1
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 12, -40 - (shown - 1) * (SLOT_SIZE + ROW_GAP))
			row:Show()
		else
			row:Hide()
		end
	end
	frame:SetHeight(50 + math.max(shown, 1) * (SLOT_SIZE + ROW_GAP) + 50)
end

local function RefreshUI()
	UpdatePreview()
	if not frame or not frame:IsShown() then
		return
	end

	frame.autoCheck:SetChecked(db.autoPlace and true or false)
	frame.previewCheck:SetChecked(db.preview and true or false)

	for _, btn in ipairs(slotButtons) do
		local bind = BindText(btn.bindingCmd)
		btn.hotkey:SetText(bind)
		local e = db.plan[btn.slot]
		btn.level:SetText("")
		btn.rank:SetText("")
		btn.glow:SetShown(e and MatchesSearch(e) or false)
		if e then
			btn.icon:SetTexture(EntryIcon(e) or QUESTION_MARK)
			btn.icon:SetAlpha(1)
			btn.icon:SetDesaturated(false)
			btn.icon:Show()
			if e.t == "spell" then
				if not ResolveSpell(e) then
					btn.icon:SetDesaturated(true)
					if IsTalentEntry(e) then
						btn.level:SetTextColor(1, 0.82, 0)
						btn.level:SetText("T")
					else
						btn.level:SetTextColor(1, 0.35, 0.35)
						local level = FirstRankLevel(e)
						btn.level:SetText(level and ("L" .. level) or "")
					end
				end
				if e.exact then
					local sub = GetSubtext and GetSubtext(e.id)
					local n = sub and sub:match("%d+")
					btn.rank:SetText(n and ("R" .. n) or "R")
				end
			end
		else
			local ghost = GetActionTexture(btn.slot)
			if ghost then
				btn.icon:SetTexture(ghost)
				btn.icon:SetAlpha(0.2)
				btn.icon:SetDesaturated(true)
				btn.icon:Show()
			else
				btn.icon:Hide()
			end
		end
	end

	local entries = PaletteEntries()
	for i, row in ipairs(paletteRows) do
		local e = entries[i]
		row.entry = e
		if not e then
			row:Hide()
		elseif e.loading then
			row.icon:Hide()
			row.check:Hide()
			row.text:SetText("|cff808080Loading " .. e.loading .. " spells...|r")
			row:Show()
		else
			row.icon:SetTexture(GetTexture(e.id))
			row.icon:Show()
			row.check:SetShown(e.planned and true or false)
			local color = IsKnown(e.id) and "|cff88ff88" or "|cffffffff"
			local levelText = e.talent and "|cffffd100 T|r" or ("|cffaaaaaa%2d|r"):format(e.level)
			row.text:SetText(("%s %s%s|r"):format(levelText, color, e.name))
			row:Show()
		end
	end
	frame.scrollContent:SetHeight(#entries * 22 + 4)

	local hiddenCount = 0
	for _ in pairs(db.hidden or {}) do
		hiddenCount = hiddenCount + 1
	end
	hiddenBtn:SetShown(hiddenCount > 0)
	hiddenBtn:SetText(hiddenCount .. " hidden")
	RefreshKeysUI()
end

local function QueueRefresh()
	if refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.2, function()
		refreshPending = false
		RefreshUI()
	end)
end

local function ApplySlot(slot)
	local e = db.plan[slot]
	if not e or EntryMatchesSlot(e, slot) then
		return false
	end
	if e.t == "spell" then
		local target = ResolveSpell(e)
		if not target then
			return false
		end
		PickupSpell(target)
	elseif e.t == "item" then
		if PickupItemByID then
			PickupItemByID(e.id)
		end
	elseif e.t == "macro" then
		local idx = FindMacroIndex(e)
		if not idx then
			return false
		end
		PickupMacro(idx)
	end
	if GetCursorInfo() then
		PlaceAction(slot)
		ClearCursor()
		return true
	end
	ClearCursor()
	return false
end

local function ApplyAll(silent)
	if InCombatLockdown() then
		applyQueued = true
		if not silent then
			Print("In combat — will place when combat ends.")
		end
		return
	end
	local placed = 0
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			if ApplySlot(bar.offset + i) then
				placed = placed + 1
			end
		end
	end
	if placed > 0 then
		Print("Placed " .. placed .. " planned action(s) onto your bars.")
	elseif not silent then
		Print("Nothing to place — bars already match your plan (items must be in your bags).")
	end
	QueueRefresh()
end

local function AutoPlaceLearned(spellId)
	local name = GetName(spellId)
	if not name then
		return
	end
	for slot, e in pairs(db.plan) do
		if e.t == "spell" and GetName(e.id) == name then
			if InCombatLockdown() then
				applyQueued = true
			elseif ApplySlot(slot) then
				Print(name .. " placed onto its planned slot.")
			end
		end
	end
	QueueRefresh()
end

local function ImportCurrentBars()
	local imported = 0
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local slot = bar.offset + i
			local actionType, id = GetActionInfo(slot)
			local e
			if actionType == "spell" and id and id > 0 then
				e = {t = "spell", id = id}
			elseif actionType == "item" and id and id > 0 then
				e = {t = "item", id = id}
			elseif actionType == "macro" then
				local name, icon, body
				if id and id > 0 then
					name, icon, body = GetMacroInfo(id)
				end
				if not name then
					name = GetActionText(slot)
					icon = GetActionTexture(slot)
				end
				if name then
					e = {t = "macro", name = name, icon = icon, body = body}
				end
			end
			if e then
				db.plan[slot] = e
				imported = imported + 1
			end
		end
	end
	Print("Imported " .. imported .. " action(s) from your current bars.")
	RefreshUI()
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do
	B64INV[B64:sub(i, i)] = i - 1
end

local function B64Encode(s)
	if s == "" then
		return "-"
	end
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		tinsert(out, B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=")
			.. (c and B64:sub(c4 + 1, c4 + 1) or "="))
	end
	return table.concat(out)
end

local function B64Decode(s)
	if s == "-" then
		return ""
	end
	local out = {}
	for i = 1, #s, 4 do
		local n1 = B64INV[s:sub(i, i)]
		local n2 = B64INV[s:sub(i + 1, i + 1)]
		if not n1 or not n2 then
			return nil
		end
		local n3 = B64INV[s:sub(i + 2, i + 2)]
		local n4 = B64INV[s:sub(i + 3, i + 3)]
		local n = n1 * 262144 + n2 * 4096 + (n3 or 0) * 64 + (n4 or 0)
		tinsert(out, string.char(math.floor(n / 65536) % 256))
		if n3 then
			tinsert(out, string.char(math.floor(n / 256) % 256))
		end
		if n4 then
			tinsert(out, string.char(n % 256))
		end
	end
	return table.concat(out)
end

local EXPORT_HEADER = "ActionBarPlanner:v1"

local function ExportPlan()
	local lines = {EXPORT_HEADER}
	local slots = {}
	for slot in pairs(db.plan) do
		tinsert(slots, slot)
	end
	sort(slots)
	for _, slot in ipairs(slots) do
		local e = db.plan[slot]
		if e.t == "spell" then
			tinsert(lines, slot .. " spell " .. e.id .. (e.exact and " x" or ""))
		elseif e.t == "item" then
			tinsert(lines, slot .. " item " .. e.id)
		elseif e.t == "macro" then
			tinsert(lines, slot .. " macro " .. B64Encode(e.name or "") .. " "
				.. B64Encode(e.body or "") .. " " .. (e.icon or 0))
		end
	end
	return table.concat(lines, "\n")
end

local function ParsePlan(text)
	local entries, count, sawHeader = {}, 0, false
	for rawLine in text:gmatch("[^\r\n]+") do
		local line = rawLine:match("^%s*(.-)%s*$")
		if line ~= "" then
			if not sawHeader then
				if line ~= EXPORT_HEADER then
					return nil, "First line must be " .. EXPORT_HEADER
				end
				sawHeader = true
			else
				local slot, kind, rest = line:match("^(%d+)%s+(%a+)%s+(.+)$")
				slot = tonumber(slot)
				local e
				if slot and slot >= 1 and slot <= 180 then
					if kind == "spell" then
						local id, x = rest:match("^(%d+)%s*(x?)$")
						if id then
							e = {t = "spell", id = tonumber(id), exact = (x == "x") or nil}
						end
					elseif kind == "item" then
						local id = rest:match("^(%d+)$")
						if id then
							e = {t = "item", id = tonumber(id)}
						end
					elseif kind == "macro" then
						local n, b, icon = rest:match("^(%S+)%s+(%S+)%s+(%d+)$")
						if n then
							local name, body = B64Decode(n), B64Decode(b)
							if name and body then
								icon = tonumber(icon)
								e = {
									t = "macro",
									name = name,
									body = body ~= "" and body or nil,
									icon = icon > 0 and icon or nil,
								}
							end
						end
					end
				end
				if not e then
					return nil, "Could not read line: " .. line
				end
				entries[slot] = e
				count = count + 1
			end
		end
	end
	if count == 0 then
		return nil, "Nothing to import."
	end
	return entries, count
end

StaticPopupDialogs["ACTIONBARPLANNER_IMPORTPLAN"] = {
	text = "Replace the current plan with %s imported action(s)?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		if pendingImport then
			wipe(db.plan)
			for slot, e in pairs(pendingImport) do
				db.plan[slot] = e
			end
			pendingImport = nil
			Print("Plan imported.")
			RefreshUI()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ACTIONBARPLANNER_CLEAR"] = {
	text = "Clear the entire action bar plan for this character?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		wipe(db.plan)
		RefreshUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function PlaceGameCursor(slot)
	local cursorType, a, b, c = GetCursorInfo()
	local e
	if cursorType == "spell" then
		local id = (type(c) == "number" and c > 0) and c or (type(b) == "number" and b or nil)
		if id then
			e = {t = "spell", id = id}
		end
	elseif cursorType == "item" then
		e = {t = "item", id = a}
	elseif cursorType == "macro" then
		local name, icon, body
		if type(a) == "number" and a > 0 then
			name, icon, body = GetMacroInfo(a)
		elseif type(a) == "string" then
			name = a
			icon, body = select(2, GetMacroInfo(a))
		end
		if name then
			e = {t = "macro", name = name, icon = icon, body = body}
		end
	end
	if e then
		db.plan[slot] = e
		PlayUISound("IG_ABILITY_ICON_DROP")
	end
	ClearCursor()
	RefreshUI()
end

local function BindHeldKey(btn)
	local key = heldKey
	SetHeldKey(nil)
	if InCombatLockdown() then
		Print("Cannot change keybinds in combat.")
		return
	end
	local prevAction = GetBindingAction(key)
	if SetBinding(key, btn.bindingCmd) then
		pcall(SaveBindings, GetCurrentBindingSet and GetCurrentBindingSet() or 2)
		local suffix = ""
		if prevAction and prevAction ~= "" then
			suffix = " (was " .. BindingDisplayName(prevAction) .. ")"
		end
		Print(AbbrevKey(key) .. " bound to " .. btn.desc .. suffix .. ".")
	else
		Print("Could not bind " .. AbbrevKey(key) .. ".")
	end
	RefreshUI()
end

local function SlotOnClick(btn, mouseButton)
	if heldKey then
		if mouseButton == "LeftButton" then
			BindHeldKey(btn)
		else
			SetHeldKey(nil)
		end
		return
	end
	if GetCursorInfo() then
		PlaceGameCursor(btn.slot)
		return
	end
	if mouseButton == "RightButton" then
		if heldEntry then
			SetHeldEntry(nil)
		else
			db.plan[btn.slot] = nil
		end
	else
		if heldEntry then
			local previous = db.plan[btn.slot]
			db.plan[btn.slot] = heldEntry
			PlayUISound("IG_ABILITY_ICON_DROP")
			SetHeldEntry(previous)
		elseif db.plan[btn.slot] then
			SetHeldEntry(db.plan[btn.slot])
			db.plan[btn.slot] = nil
			PlayUISound("IG_ABILITY_ICON_PICKUP")
		end
	end
	RefreshUI()
	if GameTooltip:GetOwner() == btn then
		btn:GetScript("OnEnter")(btn)
	end
end

local function SlotOnEnter(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	local e = db.plan[btn.slot]
	if e then
		if e.t == "spell" then
			GameTooltip:SetSpellByID(e.id)
			if not ResolveSpell(e) then
				if IsTalentEntry(e) then
					GameTooltip:AddLine("Granted by a talent — not yet learned.", 1, 0.82, 0)
				else
					local level = FirstRankLevel(e)
					if level then
						GameTooltip:AddLine("Trainable at level " .. level, 1, 0.4, 0.4)
					end
				end
			end
			if e.exact then
				GameTooltip:AddLine("Pinned to this rank — will not auto-upgrade.", 1, 0.8, 0.2)
			end
		elseif e.t == "item" then
			GameTooltip:SetItemByID(e.id)
		elseif e.t == "macro" then
			GameTooltip:SetText("Macro: " .. (e.name ~= "" and e.name or "(unnamed)"))
			if e.body and e.body ~= "" then
				GameTooltip:AddLine(e.body, 0.8, 0.8, 0.8, true)
			end
			if not FindMacroIndex(e) then
				GameTooltip:AddLine("This macro no longer exists.", 1, 0.4, 0.4)
			end
		end
		GameTooltip:AddLine("Left-click to move, right-click to remove.", 0.6, 0.6, 0.6)
	else
		GameTooltip:SetText("Empty planned slot")
		GameTooltip:AddLine("Drop a palette spell here, or drag an item,", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("macro, or spell from the game onto it.", 0.6, 0.6, 0.6)
		if GetActionInfo(btn.slot) then
			GameTooltip:AddLine("Faded icon shows what is on this slot right now.", 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:Show()
end

local function CreateSlotButton(parent, slot, bindingCmd)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(SLOT_SIZE, SLOT_SIZE)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn.slot = slot
	btn.bindingCmd = bindingCmd

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	btn.bg:SetColorTexture(0, 0, 0, 0.5)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 1, -1)
	btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	btn.hotkey = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	btn.hotkey:SetPoint("TOPRIGHT", -2, -2)

	btn.level = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.level:SetPoint("BOTTOMLEFT", 2, 2)
	btn.level:SetTextColor(1, 0.35, 0.35)

	btn.rank = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.rank:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.rank:SetTextColor(1, 0.8, 0.2)

	btn.glow = btn:CreateTexture(nil, "OVERLAY")
	btn.glow:SetAllPoints()
	btn.glow:SetColorTexture(1, 0.85, 0.2, 0.35)
	btn.glow:Hide()

	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetScript("OnClick", SlotOnClick)
	btn:SetScript("OnReceiveDrag", function(self)
		if GetCursorInfo() then
			PlaceGameCursor(self.slot)
		end
	end)
	btn:SetScript("OnEnter", SlotOnEnter)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

local function ShowRankMenu(row)
	local ranks = RanksOf(row.entry.name)
	if #ranks <= 1 then
		if ranks[1] then
			SetHeldEntry({t = "spell", id = ranks[1].id, exact = true})
			PlayUISound("IG_ABILITY_ICON_PICKUP")
		end
		return
	end
	rankMenu:Hide()
	local width = 150
	for i, s in ipairs(ranks) do
		local item = rankMenu.items[i]
		if not item then
			item = CreateFrame("Button", nil, rankMenu)
			item:SetSize(width - 8, 18)
			item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
			item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			item.text:SetPoint("LEFT", 4, 0)
			item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			item:SetScript("OnClick", function(self)
				SetHeldEntry({t = "spell", id = self.spellId, exact = true})
				PlayUISound("IG_ABILITY_ICON_PICKUP")
			end)
			rankMenu.items[i] = item
		end
		item.spellId = s.id
		local sub = GetSubtext and GetSubtext(s.id)
		local label = (sub and sub ~= "" and sub or "Base") .. "  |cffaaaaaaL" .. s.level .. "|r"
		local color = IsKnown(s.id) and "|cff88ff88" or "|cffffffff"
		item.text:SetText(color .. label .. "|r")
		item:Show()
	end
	for i = #ranks + 1, #rankMenu.items do
		rankMenu.items[i]:Hide()
	end
	rankMenu:SetSize(width, #ranks * 18 + 8)
	rankMenu:ClearAllPoints()
	rankMenu:SetPoint("TOPRIGHT", row, "TOPLEFT", -2, 0)
	rankMenu:Show()
end

local function PaletteRowOnClick(row, mouseButton)
	if not (row.entry and row.entry.id) then
		return
	end
	if mouseButton == "RightButton" then
		if IsShiftKeyDown() then
			db.hidden = db.hidden or {}
			db.hidden[row.entry.name] = true
			RefreshUI()
		else
			ShowRankMenu(row)
		end
	else
		SetHeldEntry({t = "spell", id = row.entry.id})
		PlayUISound("IG_ABILITY_ICON_PICKUP")
	end
end

local function PaletteRowOnEnter(row)
	if not (row.entry and row.entry.id) then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:SetSpellByID(row.entry.id)
	GameTooltip:AddLine("Click to pick up (auto-upgrades ranks).", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Right-click to pick a specific rank.", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Shift-right-click to hide from this list.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function BuildUI()
	frame = CreateFrame("Frame", "ActionBarPlannerFrame", UIParent, "BasicFrameTemplateWithInset")
	local gridWidth = 12 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
	frame:SetSize(100 + gridWidth + PALETTE_WIDTH + 60, 60 + #BARS * (SLOT_SIZE + ROW_GAP) + 60)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			SetHeldEntry(nil)
		end
		rankMenu:Hide()
	end)
	frame:SetScript("OnShow", function()
		RefreshLayout()
		RefreshUI()
	end)
	frame:SetScript("OnHide", function()
		SetHeldEntry(nil)
	end)
	tinsert(UISpecialFrames, "ActionBarPlannerFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Action Bar Planner — " .. UnitName("player"))

	slotButtons = {}
	for barIndex, bar in ipairs(BARS) do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(88 + 12 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP, SLOT_SIZE)
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", 0, 0)
		label:SetWidth(84)
		label:SetJustifyH("LEFT")
		label:SetText(bar.label)
		for i = 1, 12 do
			local btn = CreateSlotButton(row, bar.offset + i, bar.binding:format(i))
			btn.desc = bar.label .. " button " .. i
			btn:SetPoint("LEFT", 88 + (i - 1) * (SLOT_SIZE + SLOT_GAP), 0)
			tinsert(slotButtons, btn)
		end
		barRows[barIndex] = row
	end
	RefreshLayout()

	local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	importBtn:SetSize(95, 22)
	importBtn:SetPoint("BOTTOMLEFT", 12, 14)
	importBtn:SetText("Import Bars")
	importBtn:SetScript("OnClick", ImportCurrentBars)

	local placeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	placeBtn:SetSize(105, 22)
	placeBtn:SetPoint("LEFT", importBtn, "RIGHT", 5, 0)
	placeBtn:SetText("Place Learned")
	placeBtn:SetScript("OnClick", function()
		ApplyAll(false)
	end)

	local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearBtn:SetSize(75, 22)
	clearBtn:SetPoint("LEFT", placeBtn, "RIGHT", 5, 0)
	clearBtn:SetText("Clear Plan")
	clearBtn:SetScript("OnClick", function()
		StaticPopup_Show("ACTIONBARPLANNER_CLEAR")
	end)

	frame.autoCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	local autoCheck = frame.autoCheck
	autoCheck:SetSize(24, 24)
	autoCheck:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
	autoCheck:SetChecked(db.autoPlace)
	autoCheck:SetScript("OnClick", function(self)
		db.autoPlace = self:GetChecked() and true or false
	end)
	local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 0, 0)
	autoLabel:SetText("Auto-place")

	frame.previewCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	local previewCheck = frame.previewCheck
	previewCheck:SetSize(24, 24)
	previewCheck:SetPoint("LEFT", autoLabel, "RIGHT", 8, 0)
	previewCheck:SetChecked(db.preview)
	previewCheck:SetScript("OnClick", function(self)
		db.preview = self:GetChecked() and true or false
		UpdatePreview()
	end)
	local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	previewLabel:SetPoint("LEFT", previewCheck, "RIGHT", 0, 0)
	previewLabel:SetText("Preview")

	local keysBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	keysBtn:SetSize(75, 22)
	keysBtn:SetPoint("LEFT", previewLabel, "RIGHT", 8, 0)
	keysBtn:SetText("Keybinds")
	keysBtn:SetScript("OnClick", function()
		keysFrame:SetShown(not keysFrame:IsShown())
	end)

	local shareBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	shareBtn:SetSize(55, 22)
	shareBtn:SetPoint("LEFT", keysBtn, "RIGHT", 5, 0)
	shareBtn:SetText("Share")
	shareBtn:SetScript("OnClick", function()
		shareFrame:SetShown(not shareFrame:IsShown())
	end)

	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetSize(PALETTE_WIDTH - 110, 20)
	search:SetPoint("TOPRIGHT", -120, -34)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self)
		searchText = self:GetText()
		RefreshUI()
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)

	local unplannedCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	unplannedCheck:SetSize(24, 24)
	unplannedCheck:SetPoint("LEFT", search, "RIGHT", 2, 0)
	unplannedCheck:SetChecked(unplannedOnly)
	unplannedCheck:SetScript("OnClick", function(self)
		unplannedOnly = self:GetChecked() and true or false
		RefreshUI()
	end)
	unplannedCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Show only spells not yet in the plan")
		GameTooltip:Show()
	end)
	unplannedCheck:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	hiddenBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	hiddenBtn:SetSize(62, 20)
	hiddenBtn:SetPoint("LEFT", unplannedCheck, "RIGHT", 2, 0)
	hiddenBtn:SetScript("OnClick", function()
		wipe(db.hidden or {})
		RefreshUI()
	end)
	hiddenBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Unhide all palette entries")
		GameTooltip:Show()
	end)
	hiddenBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local scroll = CreateFrame("ScrollFrame", "ActionBarPlannerScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPRIGHT", -32, -60)
	scroll:SetPoint("BOTTOMRIGHT", -32, 14)
	scroll:SetWidth(PALETTE_WIDTH - 20)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(PALETTE_WIDTH - 20, 100)
	scroll:SetScrollChild(content)
	frame.scrollContent = content

	paletteRows = {}
	for i = 1, 300 do
		local row = CreateFrame("Button", nil, content)
		row:SetSize(PALETTE_WIDTH - 24, 22)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 2, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		row.text:SetPoint("RIGHT", -18, 0)
		row.text:SetJustifyH("LEFT")

		row.check = row:CreateTexture(nil, "OVERLAY")
		row.check:SetSize(14, 14)
		row.check:SetPoint("RIGHT", -2, 0)
		row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnClick", PaletteRowOnClick)
		row:SetScript("OnEnter", PaletteRowOnEnter)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:Hide()
		tinsert(paletteRows, row)
	end

	rankMenu = CreateFrame("Frame", nil, frame)
	rankMenu:SetFrameStrata("DIALOG")
	rankMenu.bg = rankMenu:CreateTexture(nil, "BACKGROUND")
	rankMenu.bg:SetAllPoints()
	rankMenu.bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	rankMenu.items = {}
	rankMenu:Hide()

	keysFrame = CreateFrame("Frame", "ActionBarPlannerKeysFrame", frame, "BasicFrameTemplateWithInset")
	keysFrame:SetSize(230, 420)
	keysFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
	local keysTitle = keysFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	keysTitle:SetPoint("TOP", 0, -5)
	keysTitle:SetText("Keybinding")
	keysFrame:SetScript("OnShow", RefreshKeysUI)
	keysFrame:Hide()

	local keysScroll = CreateFrame("ScrollFrame", "ActionBarPlannerKeysScroll", keysFrame, "UIPanelScrollFrameTemplate")
	keysScroll:SetPoint("TOPLEFT", 8, -28)
	keysScroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local keysContent = CreateFrame("Frame", nil, keysScroll)
	keysContent:SetSize(180, 100)
	keysScroll:SetScrollChild(keysContent)
	keysFrame.scrollContent = keysContent

	keysRows = {}

	shareFrame = CreateFrame("Frame", "ActionBarPlannerShareFrame", frame, "BasicFrameTemplateWithInset")
	shareFrame:SetSize(460, 300)
	shareFrame:SetPoint("CENTER", frame, "CENTER")
	shareFrame:SetFrameStrata("DIALOG")
	local shareTitle = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	shareTitle:SetPoint("TOP", 0, -5)
	shareTitle:SetText("Share Plan")
	shareFrame:Hide()

	local shareScroll = CreateFrame("ScrollFrame", "ActionBarPlannerShareScroll", shareFrame, "UIPanelScrollFrameTemplate")
	shareScroll:SetPoint("TOPLEFT", 12, -32)
	shareScroll:SetPoint("BOTTOMRIGHT", -32, 44)
	local shareEdit = CreateFrame("EditBox", nil, shareScroll)
	shareEdit:SetMultiLine(true)
	shareEdit:SetAutoFocus(false)
	shareEdit:SetFontObject(ChatFontNormal)
	shareEdit:SetWidth(400)
	shareEdit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	shareScroll:SetScrollChild(shareEdit)

	local exportBtn = CreateFrame("Button", nil, shareFrame, "UIPanelButtonTemplate")
	exportBtn:SetSize(120, 22)
	exportBtn:SetPoint("BOTTOMLEFT", 12, 12)
	exportBtn:SetText("Export to text")
	exportBtn:SetScript("OnClick", function()
		shareEdit:SetText(ExportPlan())
		shareEdit:SetFocus()
		shareEdit:HighlightText()
	end)

	local importStrBtn = CreateFrame("Button", nil, shareFrame, "UIPanelButtonTemplate")
	importStrBtn:SetSize(120, 22)
	importStrBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
	importStrBtn:SetText("Import from text")
	importStrBtn:SetScript("OnClick", function()
		local entries, countOrErr = ParsePlan(shareEdit:GetText())
		if not entries then
			Print(countOrErr)
			return
		end
		pendingImport = entries
		StaticPopup_Show("ACTIONBARPLANNER_IMPORTPLAN", countOrErr)
	end)

	local shareHint = shareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	shareHint:SetPoint("LEFT", importStrBtn, "RIGHT", 8, 0)
	shareHint:SetText("|cff909090Ctrl-C to copy, Ctrl-V to paste|r")

	cursorFrame = CreateFrame("Frame", nil, UIParent)
	cursorFrame:SetSize(30, 30)
	cursorFrame:SetFrameStrata("TOOLTIP")
	cursorFrame.icon = cursorFrame:CreateTexture(nil, "OVERLAY")
	cursorFrame.icon:SetAllPoints()
	cursorFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	cursorFrame.text = cursorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	cursorFrame.text:SetPoint("CENTER")
	cursorFrame:Hide()
	cursorFrame:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 14)
	end)
end

local function Toggle()
	if not frame then
		BuildUI()
	end
	frame:SetShown(not frame:IsShown())
end

function ActionBarPlanner_CompartmentClick()
	Toggle()
end

local minimapBtn, settingsCategory
local Atan2 = math.atan2 or math.atan

local function UpdateMinimapButton()
	if not minimapBtn then
		return
	end
	minimapBtn:SetShown(not db.minimap.hide)
	local angle = math.rad(db.minimap.angle or 220)
	minimapBtn:ClearAllPoints()
	minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function OpenOptions()
	local opened = false
	if settingsCategory and Settings and Settings.OpenToCategory then
		opened = pcall(Settings.OpenToCategory, settingsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		opened = pcall(InterfaceOptionsFrame_OpenToCategory, "Action Bar Planner")
	end
	if not opened then
		Toggle()
	end
end

local function CreateMinimapButton()
	if minimapBtn or not Minimap then
		return
	end
	minimapBtn = CreateFrame("Button", "ActionBarPlannerMinimapButton", Minimap)
	minimapBtn:SetSize(32, 32)
	minimapBtn:SetFrameStrata("MEDIUM")
	minimapBtn:SetFrameLevel(8)
	minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapBtn:RegisterForDrag("LeftButton")
	minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(21, 21)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("CENTER", -1, 1)
	minimapBtn:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			OpenOptions()
		else
			Toggle()
		end
	end)
	minimapBtn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimap.angle = math.deg(Atan2(cy / scale - my, cx / scale - mx))
			UpdateMinimapButton()
		end)
	end)
	minimapBtn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	minimapBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Action Bar Planner")
		GameTooltip:AddLine("Left-click: open the planner.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: options.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag to move around the minimap.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	minimapBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	UpdateMinimapButton()
end

local function MakeOptionCheck(panel, y, label, get, set)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", 16, y)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	text:SetText(label)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb.Refresh = function(self)
		self:SetChecked(get() and true or false)
	end
	return cb
end

local function CreateOptionsPanel()
	local panel = CreateFrame("Frame")
	panel.name = "Action Bar Planner"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Action Bar Planner")
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetJustifyH("LEFT")
	sub:SetText("Plan your max-level action bars before you get there.\nSlash commands: /abp (open), /abp preview, /abp minimap")
	local checks = {
		MakeOptionCheck(panel, -78, "Show minimap button", function()
			return not db.minimap.hide
		end, function(v)
			db.minimap.hide = not v
			UpdateMinimapButton()
		end),
		MakeOptionCheck(panel, -108, "Auto-place spells as you learn them", function()
			return db.autoPlace
		end, function(v)
			db.autoPlace = v
			RefreshUI()
		end),
		MakeOptionCheck(panel, -138, "Preview planned actions on the real bars", function()
			return db.preview
		end, function(v)
			db.preview = v
			UpdatePreview()
			RefreshUI()
		end),
	}
	local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	openBtn:SetSize(120, 22)
	openBtn:SetPoint("TOPLEFT", 16, -178)
	openBtn:SetText("Open Planner")
	openBtn:SetScript("OnClick", Toggle)
	panel:SetScript("OnShow", function()
		for _, cb in ipairs(checks) do
			cb:Refresh()
		end
	end)
	if Settings and Settings.RegisterCanvasLayoutCategory then
		settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(settingsCategory)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

local function MigrateDB()
	for slot, e in pairs(db.plan) do
		if type(e) == "number" then
			db.plan[slot] = {t = "spell", id = e}
		end
	end
end

SLASH_ACTIONBARPLANNER1 = "/abp"
SLASH_ACTIONBARPLANNER2 = "/actionbarplanner"
SLASH_ACTIONBARPLANNER3 = "/hbp"
SlashCmdList.ACTIONBARPLANNER = function(msg)
	msg = msg and msg:lower() or ""
	if msg:match("^preview") then
		db.preview = not db.preview
		Print("Bar preview " .. (db.preview and "on" or "off") .. ".")
		UpdatePreview()
		return
	end
	if msg:match("^minimap") then
		db.minimap.hide = not db.minimap.hide
		Print("Minimap button " .. (db.minimap.hide and "hidden" or "shown") .. ".")
		UpdateMinimapButton()
		return
	end
	Toggle()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("UPDATE_MACROS")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "ITEM_DATA_LOAD_RESULT")
pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			ActionBarPlannerDB = ActionBarPlannerDB or {}
			db = ActionBarPlannerDB
			db.plan = db.plan or {}
			db.hidden = db.hidden or {}
			db.minimap = db.minimap or {hide = false, angle = 220}
			MigrateDB()
		end
	elseif event == "PLAYER_LOGIN" then
		BuildBars()
		BuildClassSpells()
		RequestSpellData()
		CreateMinimapButton()
		CreateOptionsPanel()
		UpdatePreview()
		Print("Loaded — type /abp to plan your bars, /abp preview to toggle the on-bar preview.")
	elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
		if db and db.autoPlace and arg1 then
			AutoPlaceLearned(arg1)
		else
			QueueRefresh()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if applyQueued then
			applyQueued = false
			ApplyAll(true)
		end
	elseif db then
		QueueRefresh()
	end
end)
