-- only startup if player is druid
if ( (select(2,UnitClass("player"))) ~= "DRUID" ) then
	print("Addon only supported for druids.")
	return
end

local pauseDueToMovement = GetTime() -- if any raid movevement (i.e., players are moved to another raid group) is detected, this variable will contain the current GetTime() to allow for a pause
local groupsize = "solo" -- will contain either "solo", "party" or "raid"
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

buffButton:SetAttribute("type1", "spell")
buffButton:SetAttribute("unit", "player")
buffButton:SetAttribute("spell", 1126)

buffButton.labelString = buffButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffButton.labelString:SetWidth(150)
buffButton.labelString:SetHeight(25)
buffButton.labelString:SetText("Welcome to ARB")
buffButton.labelString:SetPoint("BOTTOM", buffButton, "BOTTOM")

buffButton.icon = buffButton:CreateTexture()
buffButton.icon:SetTexture(136078)
buffButton.icon:SetAllPoints(buffButton)

buffButton.cooldownFrame = CreateFrame("Cooldown", nil, buffButton, "CooldownFrameTemplate")
buffButton.cooldownFrame:SetAllPoints(buffButton)

local function BuffMissing(unitid)
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

	return (missing1 and missing2)
end

local function SearchBuff()
	local buff_unitid = ""
	local buff_num = 0
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

		if BuffMissing(unitid) then
			buff_unitid = unitid
			buff_num = buff_num + 1
		end
	end

	-- check for player if not in raid (since player is not part of "partyN"
	if (not isinraid) and (buff_num == 0) then
		if BuffMissing("player") then
			buff_unitid = "player"
			buff_num = 1
		end
	end

	-- check pets
	if buff_num == 0 then
		for i_member = 1, GetNumGroupMembers() do
			local unitid = unit_base .. "pet" .. i_member

			if BuffMissing(unitid) then
				buff_unitid = unitid
				buff_num = 1
				break
			end
		end
	end

	return buff_unitid, buff_num
end

local buffeventFrame = CreateFrame("Frame")
buffeventFrame:RegisterEvent("UNIT_AURA")
buffeventFrame:SetScript("OnEvent", function(self, event, unit)
	if not isInCombat then
		local buff_unitid, buff_num = SearchBuff()
		if buff_num > 0 then
			buffButton:Show()
			buffButton.labelString:SetText(buff_unitid)
			buffButton:SetAttribute("unit", buff_unitid)
			buffButton:SetAttribute("spell", 26990)
			--TODO add check for GOTW instead of MOTW
		else
			buffButton:Hide()
		end
	end
end)

local function GetGCD()
	return GetSpellCooldown(1126)
end

local GCDeventFrame = CreateFrame("Frame")
GCDeventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
--GCDeventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
GCDeventFrame:SetScript("OnEvent", function(self, event, ...)
	local start, dur, enabled = GetGCD()
	if (enabled == 1) and (dur > 0) and (start > 0) then
		buffButton.cooldownFrame:SetCooldown(start, dur)
	end
end)

local combateventFrame = CreateFrame("Frame")
combateventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combateventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combateventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_REGEN_ENABLED" then
		-- do stuff when we leave combat
		buffButton:Show()
		isInCombat = false
	else
		-- do stuff when we enter combat
		buffButton:Hide()
		isInCombat = true
	end
end)

local raidmovementFrame = CreateFrame("Frame")
raidmovementFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
raidmovementFrame:SetScript("OnEvent", function(self, event, ...)
	pauseDueToMovement = GetTime() -- TODO
end)
