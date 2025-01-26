-- only startup if player is druid
if ( (select(2, UnitClass("player"))) ~= "DRUID" ) then
	print("ARB: Addon only supported for druids.")
	return
end

local function format_percent(percent)
	if (percent > 100) or (percent < 0) then
		return -1
	end
	return format("%d", floor(percent + 0.5))
end

local function percent_color(percent)
	if percent > 80 then
		return "|cff00cc00" .. format_percent(percent) .. "|r"
	elseif percent > 25 then
		return format_percent(percent)
	else
		return "|cffcc0000" .. format_percent(percent) .. "|r"
	end
end

local checkSpell = GetSpellInfo(1126) -- mark of the wild

local buffButton = CreateFrame("Button", "AutomaticRaidBuffs_BuffButton", UIParent, "SecureActionButtonTemplate")
buffButton:SetPoint("CENTER", UIParent, "CENTER")
buffButton:SetWidth(100)
buffButton:SetHeight(100)
buffButton:EnableMouse(true)
buffButton:SetMovable(true)
buffButton:RegisterForDrag("LeftButton")
buffButton:SetScript("OnDragStart", function()
	buffButton:StartMoving()
end)
buffButton:SetScript("OnDragStop", function()
	buffButton:StopMovingOrSizing()
end)
if not InCombatLockdown() then
	buffButton:Show()
end

buffButton:SetAttribute("type", "spell")
buffButton:SetAttribute("spell1", checkSpell)
buffButton:SetAttribute("spell2", checkSpell)
buffButton:RegisterForClicks("RightButtonUp", "LeftButtonUp")

buffButton.labelString = buffButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffButton.labelString:SetWidth(150)
buffButton.labelString:SetHeight(25)
buffButton.labelString:SetPoint("TOP", buffButton, "BOTTOM", 0, -1)

buffButton.durationString = buffButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffButton.durationString:SetWidth(200)
buffButton.durationString:SetHeight(25)
buffButton.durationString:SetPoint("TOP", buffButton.labelString, "BOTTOM")

buffButton.icon = buffButton:CreateTexture()
buffButton.icon:SetTexture(136078)
buffButton.icon:SetAllPoints(buffButton)

buffButton.cooldownFrame = CreateFrame("Cooldown", nil, buffButton, "CooldownFrameTemplate")
buffButton.cooldownFrame:SetAllPoints(buffButton)

local function BuffMissing(unitid, curtime)
	if (not UnitExists(unitid)) or (not UnitIsConnected(unitid)) then
		return false, true, curtime + 3600
	end

	local spell, _, _, _, _, expiration = AuraUtil.FindAuraByName(checkSpell, unitid)

	local missing = true

	if spell then
		if (((expiration - curtime) > 420) or (expiration == 0)) then
			missing = false
		end

		if expiration > 0 then
			expiration = expiration
		end
	else
		expiration = curtime
	end

	local alive_inrange = (not UnitIsDeadOrGhost(unitid)) and (IsSpellInRange(checkSpell, unitid) == 1)

	if (not alive_inrange) and (not missing) then
		expiration = curtime + 3600 -- out of range w/ buff counts as full duration
	end

	return missing, alive_inrange, expiration
end

local function SearchBuff()
	local isinraid = IsInRaid()

	local unit_base
	if isinraid then
		unit_base = "raid"
		n_members = GetNumGroupMembers()
	else
		unit_base = "party"
		n_members = GetNumGroupMembers() - 1 -- player is not part of party
	end

	local curtime = GetTime()
	local result_arr = {}

	for i_member = 1, n_members do
		local _, _, subgroup = GetRaidRosterInfo(i_member)
		local unitid = unit_base .. i_member
		local buffMissing, alive_inrange, expiration = BuffMissing(unitid, curtime)
		local arr = {}

		if (subgroup > 5) and (n_members > 25) then
			buffMissing = false -- only look at the first 5 sub-groups
		end

		tinsert(result_arr, arr)

		arr["unitid"] = unitid
		arr["buffMissing"] = buffMissing
		arr["alive_inrange"] = alive_inrange
		arr["buffDuration"] = expiration - curtime
	end

	-- check for player if not in raid (since player is not part of "partyN")
	if (not isinraid) then
		local buffMissing, alive_inrange, expiration = BuffMissing("player", curtime)
		local arr = {}

		tinsert(result_arr, arr)

		arr["unitid"] = "player"
		arr["buffMissing"] = buffMissing
		arr["alive_inrange"] = alive_inrange
		arr["buffDuration"] = expiration - curtime
	end

	return result_arr
end

local buffeventFrame = CreateFrame("Frame")
buffeventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
buffeventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
buffeventFrame:RegisterEvent("PLAYER_UNGHOST")
buffeventFrame:RegisterEvent("PLAYER_ALIVE")
buffeventFrame:RegisterEvent("PLAYER_DEAD")

local elapsed = 0
local function eventFunc(self, event_elapsed, ...)
	if (event_elapsed == "PLAYER_REGEN_DISABLED") or (event_elapsed == "PLAYER_DEAD") then
		-- do stuff when we enter combat or die
		if not InCombatLockdown() then
			buffButton:Hide()
			buffeventFrame:Hide() -- disable OnUpdate by hiding the frame
		end
		return
	elseif (type(event_elapsed) == "string") then
		if InCombatLockdown() then
			return
		end

		-- do stuff when we leave combat or are alive again (i.e., on any other events than those above which are not OnUpdate)
		buffeventFrame:Show() -- renable OnUpdate
	else
		--OnUpdate
		elapsed = elapsed + event_elapsed
	end

	if (elapsed > 0.5) then
		elapsed = 0

		local result_arr = SearchBuff()

		local buff_num = 0
		local buff_num_rangecheck = 0
		local num_members = 0
		local buffDuration = 0-- duration (in seconds) of remaining buffs
		local buffDuration_min = 1E300
		local buff_unitid = nil

		for i, arr in pairs(result_arr) do
			if arr["buffMissing"] then
				buff_num_rangecheck = buff_num_rangecheck + 1

				if arr["alive_inrange"] then
					buff_num = buff_num + 1
				end
			end

			if (arr["buffDuration"] < buffDuration_min) then
				buffDuration_min = arr["buffDuration"]
				buff_unitid = arr["unitid"]
			end

			buffDuration = buffDuration + arr["buffDuration"]
			num_members = num_members + 1
		end

		if buff_num_rangecheck > 0 then
			local unitname = UnitNameUnmodified(buff_unitid)
			local unitclass = UnitClassBase(buff_unitid)
			local hexcolor_obj = RAID_CLASS_COLORS[unitclass]

			if hexcolor_obj == nil then
				return -- this may happen during initialization, just bail out
			end

			local hexcolor = hexcolor_obj:GenerateHexColor()
			local percent_color_string_all = percent_color(100 * buffDuration / (max(num_members, 1)*3600))
			local percent_color_string_min = percent_color(100 * buffDuration_min / 3600)

			buffButton:Show()
			buffButton.labelString:SetText("|c" .. hexcolor .. unitname .. "|r (" .. buff_num .. "/" .. buff_num_rangecheck .. ")")
			buffButton.durationString:SetText("Duration: " .. percent_color_string_min .. "% / " ..  percent_color_string_all .. "%")

			buffButton:SetAttribute("unit", buff_unitid)
			buffButton.icon:SetDesaturated(buff_num < buff_num_rangecheck)
		else
			buffButton:Hide()
		end
	end
end

buffeventFrame:SetScript("OnEvent", eventFunc)
buffeventFrame:SetScript("OnUpdate", eventFunc)

local GCDeventFrame = CreateFrame("Frame")
GCDeventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
GCDeventFrame:SetScript("OnEvent", function(self, event, ...)
	local start, dur, enabled = GetSpellCooldown(1126)
	if (enabled == 1) and (dur > 0) and (start > 0) then
		buffButton.cooldownFrame:SetCooldown(start, dur)
	end
end)
