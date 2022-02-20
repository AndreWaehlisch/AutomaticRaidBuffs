-- only startup if player is druid
if ( (select(2,UnitClass("player"))) ~= "DRUID" ) then
	print("Addon only supported for druids.")
	return
else
	print("AutomaticRaidBuffs: NOT YET")
	return
end

local pauseDueToMovement = GetTime() -- if any raid movevement (i.e., players are moved to another raid group) is detected, this variable will contain the current GetTime() to allow for a pause
local groupsize = "solo" -- will contain either "solo", "party" or "raid"
local checkspell1 = "Mark of the Wild"
local checkspell2 = "Gift of the Wild"

local function CheckRaidOrParty()
	if IsInRaid() then
		groupsize = "raid"
	elseif IsInGroup() then
		groupsize = "party"
	else
		groupsize = "solo"
	end
end

-- setup Buff Button, this is where the magic happens :)
local buffButton = CreateFrame("Button", "AutomaticRaidBuffs_BuffButton", UIParent, "SecureActionButtonTemplate")
buffButton:SetWidth(200)
buffButton:SetHeight(25)
buffButton:EnableMouse(true)
buffButton:SetMovable(true)
buffButton:RegisterForDrag("LeftButton")
buffButton:SetScript("OnDragStop", function()
	buffButton:StopMovingOrSizing()
end)
buffButton:Show()

buffButton:SetAttribute("type1", "macro") -- TODO ???
buffButton:SetAttribute("unit", "player") -- TODO
buffButton:SetAttribute("spell", "Mark of the Wild") -- TODO

buffButton.labelString = ARB.BuffButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffButton.labelString:SetWidth(150)
buffButton.labelString:SetHeight(25)
buffButton.labelString:SetText("Hallo Test")

buffButton.icon = ARB.buffButton:CreateTexture()
buffButton.icon:SetTexture("") -- TODO
buffButton.icon:SetAllPoints(ARB.buffButton)

buffButton.cooldownFrame = CreateFrame("Cooldown", nil, buffButton)
buffButton.cooldownFrame:SetAllPoints(buffButton)

local buffeventFrame = CreateFrame("Frame")
buffeventFrame:RegisterEvent("UNIT_AURA")
buffeventFrame:SetScript("OnEvent", function(self, event, unit)
	--TODO
	
end)

local function GetGCD()
	-- TODO
	return 0, 0, 0
end

local function SearchBuff()
	local buff_unitid, buff_num = "", 0

	for i_member = 1, membercount do
		local foundCheck = false
		local unitid = "player" -- TODO

		for j = 1, buffcount do
			if ((name == checkspell1) or (name == checkspell2)) and (duration > 300) then
				foundCheck = true
				break
			end
		end

		if not foundCheck then
			buff_unitid = unitid
			buff_num = 1

			--TODO: check other players in same group
		end
	end

	return buff_unitid, buff_num
end

local GCDeventFrame = CreateFrame("Frame")
GCDeventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN") -- TODO: OnUpdate?
GCDeventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
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
	else
		-- do stuff when we enter combat
		buffButton:Hide()
	end
end)

local raidmovementFrame = CreateFrame("Frame")
raidmovementFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
raidmovementFrame:SetScript("OnEvent", function(self, event, ...)
	pauseDueToMovement = GetTime()
	CheckRaidOrParty()
end)
