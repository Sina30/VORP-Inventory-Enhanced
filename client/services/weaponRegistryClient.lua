local Core <const> = exports.vorp_core:GetCore()

local registryOpen = false

local function openRegistry()
	if registryOpen then return end
	local data = Core.Callback.TriggerAwait("vorpinventory:openWeaponRegistry")
	if not data then return end -- not a lawman / registry disabled
	registryOpen = true
	SetNuiFocus(true, true)
	SendNUIMessage({ action = "openWeaponRegistry", players = data })
end

local function closeRegistry()
	if not registryOpen then return end
	registryOpen = false
	SetNuiFocus(false, false)
	SendNUIMessage({ action = "closeWeaponRegistry" })
end

RegisterNetEvent("vorpinventory:registryData", function(data)
	if not registryOpen then return end
	SendNUIMessage({ action = "weaponRegistryData", players = data or {} })
end)

RegisterNUICallback("RegistryRegister", function(data, cb)
	if data and data.weaponId and data.targetServerId then
		TriggerServerEvent("vorpinventory:registryRegisterWeapon", data.weaponId, data.targetServerId)
	end
	cb('ok')
end)

RegisterNUICallback("RegistryRefresh", function(_, cb)
	local data = Core.Callback.TriggerAwait("vorpinventory:refreshWeaponRegistry")
	if data then
		SendNUIMessage({ action = "weaponRegistryData", players = data })
	end
	cb('ok')
end)

RegisterNUICallback("RegistrySearch", function(data, cb)
	local serial = data and data.serial
	if serial and serial ~= "" then
		local result = Core.Callback.TriggerAwait("vorpinventory:registrySearchSerial", serial)
		SendNUIMessage({ action = "weaponRegistrySearchResult", serial = serial, result = result or false })
	end
	cb('ok')
end)

RegisterNUICallback("RegistryClose", function(_, cb)
	closeRegistry()
	cb('ok')
end)

CreateThread(function()
	local cfg = Config.WeaponRegistry
	if not cfg or not cfg.Enabled or not cfg.Stations or #cfg.Stations == 0 then return end

	repeat Wait(2000) until LocalPlayer.state.IsInSession

	local group = GetRandomIntInRange(0, 0xffffff)
	local prompt = UiPromptRegisterBegin()
	UiPromptSetControlAction(prompt, cfg.PromptKey or 0xCEFD9220)
	UiPromptSetText(prompt, CreateVarString(10, "LITERAL_STRING", "Weapon Registry"))
	UiPromptSetEnabled(prompt, true)
	UiPromptSetVisible(prompt, true)
	UiPromptSetHoldMode(prompt, 400)
	UiPromptSetGroup(prompt, group, 0)
	UiPromptRegisterEnd(prompt)

	local lastTriggered = 0
	while true do
		local sleep = 1000
		local playerCoords = GetEntityCoords(PlayerPedId(), true, true)
		local drawDist = cfg.PromptDistance or 2.0

		for _, coord in ipairs(cfg.Stations) do
			if #(playerCoords - coord) <= drawDist then
				sleep = 0
				local label = CreateVarString(10, "LITERAL_STRING", "Weapon Registry")
				UiPromptSetActiveGroupThisFrame(group, label, 0, 0, 0, 0)
				if UiPromptHasHoldModeCompleted(prompt) and not registryOpen and (GetGameTimer() - lastTriggered) > 1500 then
					lastTriggered = GetGameTimer()
					openRegistry()
				end
				break
			end
		end

		Wait(sleep)
	end
end)
