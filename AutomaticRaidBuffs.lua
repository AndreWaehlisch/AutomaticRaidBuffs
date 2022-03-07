-- only startup if player is druid
if ( (select(2, UnitClass("player"))) ~= "DRUID" ) then
	print("ARB: Addon only supported for druids.")
	return
end

local checkSpell1 = GetSpellInfo(1126) -- mark of the wild
local checkSpell2 = GetSpellInfo(21849) -- gift of the wild
local isInCombat = InCombatLockdown()

-- setup Buff Button, this is where the magic happens :)
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
buffButton:Show()

bb = buffButton

buffButton:SetAttribute("type", "spell")
buffButton:SetAttribute("spell1", checkSpell1)
buffButton:SetAttribute("spell2", checkSpell2)
buffButton:RegisterForClicks("RightButtonUp", "LeftButtonUp")

buffButton.labelString = buffButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffButton.labelString:SetWidth(150)
buffButton.labelString:SetHeight(25)
buffButton.labelString:SetPoint("TOP", buffButton, "BOTTOM", 0, -1)

buffButton.icon = buffButton:CreateTexture()
buffButton.icon:SetTexture(136078)
buffButton.icon:SetAllPoints(buffButton)

buffButton.cooldownFrame = CreateFrame("Cooldown", nil, buffButton, "CooldownFrameTemplate")
buffButton.cooldownFrame:SetAllPoints(buffButton)

local function BuffMissing(unitid)
	if (not UnitExists(unitid)) or UnitIsDeadOrGhost(unitid) or (not UnitIsConnected(unitid)) then
		return false
	end

	local curtime = GetTime()

	local spell1, _, _, _, _, expiration1 = AuraUtil.FindAuraByName(checkSpell1, unitid)
	local spell2, _, _, _, _, expiration2 = AuraUtil.FindAuraByName(checkSpell2, unitid)

	local missing1 = true
	local missing2 = true

	if spell1 and ((expiration1 - curtime) > 300) then
		missing1 = false
	end

	if spell2 and ((expiration2 - curtime) > 300) then
		missing2 = false
	end

	return (missing1 and missing2), IsSpellInRange(checkSpell1, unitid)
end

local function SearchBuff()
	local buff_unitid = ""
	local buff_num = 0 -- number of members missing buffs (and are in range for buffing!)
	local buff_num_rangecheck = 0 -- total number of members missing buffs, even if they are out of range
	local isinraid = IsInRaid()
	local unit_base = "party"
	local group_end_mod = 4

	if isinraid then
		unit_base = "raid"
		group_end_mod = 5
	end

	for i_member = 1, GetNumGroupMembers() do
		if (buff_num > 0) and (((i_member - 1) % group_end_mod) == 0) then
			-- we found a group/groupmember with missing buffs, bail out
			break
		end

		local unitid = unit_base .. i_member
		local buffMissing, inRange = BuffMissing(unitid)

		if buffMissing then
			if inRange then
				buff_unitid = unitid
				buff_num = buff_num + 1
			end

			buff_num_rangecheck = buff_num_rangecheck + 1
		end
	end

	-- check for player if not in raid (since player is not part of "partyN"
	if (not isinraid) and (buff_num == 0) then
		if BuffMissing("player") then
			buff_unitid = "player"
			buff_num = 1
			buff_num_rangecheck = 1
		end
	end

	-- check pets
	if buff_num == 0 then
		for i_member = 1, GetNumGroupMembers() do
			local unitid = unit_base .. "pet" .. i_member
			local buffMissing, inRange = BuffMissing(unitid)

			if (buffMissing and inRange) then
				buff_unitid = unitid
				buff_num = 1
				buff_num_rangecheck = 1
				break
			end
		end
	end

	return buff_unitid, buff_num, buff_num_rangecheck
end

local buffeventFrame = CreateFrame("Frame")
buffeventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
buffeventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

local elapsed = 0
local function eventFunc(self, event_elapsed, ...)
	if event_elapsed == "PLAYER_REGEN_DISABLED" then
		-- do stuff when we enter combat
		buffButton:Hide()
		buffeventFrame:Hide() -- disable OnUpdate by hiding the frame
		isInCombat = true
		return
	elseif event_elapsed == "PLAYER_REGEN_ENABLED" then
		-- do stuff when we leave combat
		buffeventFrame:Show() -- renable OnUpdate
		isInCombat = false
	else
		--OnUpdate
		elapsed = elapsed + event_elapsed
	end

	if (not isInCombat) and (elapsed > 0.5) then
		elapsed = 0

		local buff_unitid, buff_num, buff_num_rangecheck = SearchBuff()
		if buff_num > 0 then
			buffButton:Show()
			local unitname = UnitNameUnmodified(buff_unitid)
			local unitclass = UnitClassBase(buff_unitid)
			local hexcolor = RAID_CLASS_COLORS[unitclass]:GenerateHexColor()
			buffButton.labelString:SetText("|c" .. hexcolor .. unitname .. "|r (" .. buff_num .. ((buff_num_rangecheck > 1) and "/" .. buff_num_rangecheck or "") .. ")")
			buffButton:SetAttribute("unit", buff_unitid)
			--TODO add "out of range" status?
		else
			buffButton:Hide()
		end
	end
end

buffeventFrame:SetScript("OnEvent", eventFunc)
buffeventFrame:SetScript("OnUpdate", eventFunc)

local GCDeventFrame = CreateFrame("Frame")
GCDeventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
--GCDeventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
GCDeventFrame:SetScript("OnEvent", function(self, event, ...)
	local start, dur, enabled = GetSpellCooldown(1126)
	if (enabled == 1) and (dur > 0) and (start > 0) then
		buffButton.cooldownFrame:SetCooldown(start, dur)
	end
end)
