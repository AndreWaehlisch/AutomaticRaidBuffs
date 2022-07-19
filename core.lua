-- only startup if player is druid
if ( (select(2, UnitClass("player"))) ~= "DRUID" ) then
	print("ARB: Addon only supported for druids.")
	return
end

local function format_percent(percent)
	return format("%d", ceil(percent))
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

local checkSpell1 = GetSpellInfo(1126) -- mark of the wild
local checkSpell2 = GetSpellInfo(21849) -- gift of the wild

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
buffButton:SetAttribute("spell1", checkSpell1)
buffButton:SetAttribute("spell2", checkSpell2)
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

	local expiration = curtime
	local spell1, _, _, _, _, expiration1 = AuraUtil.FindAuraByName(checkSpell1, unitid)
	local spell2, _, _, _, _, expiration2 = AuraUtil.FindAuraByName(checkSpell2, unitid)

	local missing1 = true
	local missing2 = true

	if spell1 then
		if (((expiration1 - curtime) > 420) or (expiration1 == 0)) then
			missing1 = false
		end

		if expiration1 > 0 then
			expiration = expiration1
		end
	end

	if spell2 then
		if (((expiration2 - curtime) > 420) or (expiration2 == 0)) then
			missing2 = false
		end

		if expiration2 > 0 then
			expiration = expiration2
		end
	end

	local alive_inrange = (not UnitIsDeadOrGhost(unitid)) and (IsSpellInRange(checkSpell1, unitid) == 1)

	return (missing1 and missing2), alive_inrange, expiration
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
	local result_arr = {{}, {}, {}, {}, {}}
	local result_pet = nil

	for i_member = 1, n_members do
		local unitid = unit_base .. i_member
		local buffMissing, alive_inrange, expiration = BuffMissing(unitid, curtime)
		local arr = {}

		local subgroup
		if isinraid then
			subgroup = select(3, GetRaidRosterInfo(i_member))
		else
			subgroup = 1
		end

		if ( (subgroup ~= nil) and (subgroup <=5) ) then
			tinsert(result_arr[subgroup], arr)

			arr["unitid"] = unitid
			arr["buffMissing"] = buffMissing
			arr["alive_inrange"] = alive_inrange
			arr["buffDuration"] = expiration - curtime

			-- check pet
			unitid = unit_base .. "pet" .. i_member
			buffMissing, alive_inrange = BuffMissing(unitid, curtime)
			if buffMissing and alive_inrange then
				result_pet = unitid
			end
		end
	end

	-- check for player if not in raid (since player is not part of "partyN")
	if (not isinraid) then
		local buffMissing, alive_inrange, expiration = BuffMissing("player", curtime)
		local arr = {}

		tinsert(result_arr[1], arr)

		arr["unitid"] = "player"
		arr["buffMissing"] = buffMissing
		arr["alive_inrange"] = alive_inrange
		arr["buffDuration"] = expiration - curtime
	end

	return result_arr, result_pet
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

		local result_arr, result_pet = SearchBuff()

		local buff_num
		local buff_num_rangecheck
		local buffDuration -- duration (in seconds) of remaining buffs
		local subgroup
		local num_subgroup_members
		local buffDuration_min
		local buff_unitid
		local iter_break = false

		for iter = 1, 2 do
			for i_subgroup, arr_subgroup in pairs(result_arr) do
				buff_num = 0
				buff_num_rangecheck = 0
				buffDuration = 0
				subgroup = i_subgroup
				num_subgroup_members = 0
				buffDuration_min = 1E300
				buff_unitid = nil

				for i, arr in pairs(arr_subgroup) do
					if arr["buffMissing"] then
						buff_num_rangecheck = buff_num_rangecheck + 1

						if arr["alive_inrange"] then
							buff_num = buff_num + 1
						end
					end

					if ( (arr["buffDuration"] < buffDuration_min) and ((buff_unitid == nil) or arr["alive_inrange"]) ) then
						buffDuration_min = arr["buffDuration"]
						buff_unitid = arr["unitid"]
					end

					buffDuration = buffDuration + arr["buffDuration"]
					num_subgroup_members = num_subgroup_members + 1
				end

				-- found a subgroup with missing buffs and everyone in range, stop here
				if (iter == 1) and (buff_num_rangecheck == buff_num) and (buff_num > 0) then
					iter_break = true
					break
				end

				-- on the second iter, found a subgroup with missing buffs (not everyone in range), stop there
				if (iter == 2) and (buff_num_rangecheck > 0) then
					iter_break = true
					break
				end
			end

			if iter_break then
				break
			end
		end

		-- if no player needs buffs: check for pets
		if (buff_num_rangecheck == 0) and (result_pet ~= nil) then
			buff_num = 1
			buff_num_rangecheck = 1
			buff_unitid = result_pet
		end

		if buff_num_rangecheck > 0 then
			buffButton:Show()
			local unitname = UnitNameUnmodified(buff_unitid)
			local unitclass = UnitClassBase(buff_unitid)
			local hexcolor = RAID_CLASS_COLORS[unitclass]:GenerateHexColor()
			local percent_color_string_all = percent_color(100 * buffDuration / (max(num_subgroup_members, 1)*3600))
			local percent_color_string_min = percent_color(100 * buffDuration_min / 3600)

			buffButton.labelString:SetText("|c" .. hexcolor .. unitname .. "|r (" .. buff_num .. "/" .. buff_num_rangecheck .. ")")
			buffButton.durationString:SetText("Grp: " .. subgroup .. "\nDuration: " .. percent_color_string_min .. "% / " ..  percent_color_string_all .. "%")

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
