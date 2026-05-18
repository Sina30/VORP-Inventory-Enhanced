PickupsService = {}

local WorldPickups   = {}

function PickupsService.loadModel(model)
	if not IsModelValid(model) then return print(model, "not a valid model") end

	if not HasModelLoaded(model) then
		RequestModel(model, false)
		repeat Wait(0) until HasModelLoaded(model)
	end
end

function PickupsService.getUniqueId()
	local index = GetRandomIntInRange(0, 0xffffff)
	while WorldPickups[index] do
		index = GetRandomIntInRange(0, 0xffffff)
	end
	return index
end

local function getRandomPositionAround(position, radius)
	local angle <const> = math.random() * 2 * math.pi -- Random angle in radians
	local dx = radius * math.cos(angle)
	local dy = radius * math.sin(angle)

	return vector3(position.x + dx, position.y + dy, position.z)
end


function PickupsService.CreateObject(objectHash, position, itemType)
	if itemType == "item_standard" then
		local model <const> = Config.spawnableProps[objectHash] or Config.spawnableProps.default_box
		PickupsService.loadModel(model)
		local entityHandle <const> = CreateObject(joaat(model), position.x, position.y, position.z - 1, false, false, false, false)
		repeat Wait(0) until DoesEntityExist(entityHandle)

		PlaceObjectOnGroundProperly(entityHandle, false)
		FreezeEntityPosition(entityHandle, true)
		SetPickupLight(entityHandle, true)
		SetEntityCollision(entityHandle, false, true)
		SetModelAsNoLongerNeeded(model)

		return entityHandle
	else
		if not SharedData.Weapons[objectHash] then
			return PickupsService.CreateObject("default_box", position, "item_standard")
		end

		if not Config.UseWeaponModels then
			return PickupsService.CreateObject("default_box", position, "item_standard")
		end

		Citizen.InvokeNative(0x72D4CB5DB927009C, joaat(objectHash), 1, true) -- request weapon asset
		repeat Wait(0) until Citizen.InvokeNative(0xFF07CF465F48B830, joaat(objectHash))
		local object <const> = CreateWeaponObject(joaat(objectHash), 0, position.x, position.y, position.z, true, 1.0)
		repeat Wait(0) until DoesEntityExist(object)
		PlaceObjectOnGroundProperly(object, true)
		SetPickupLight(object, true)
		SetEntityVisible(object, true)
		if Config.weaponAdjustments[objectHash] then
			SetEntityRotation(object, Config.weaponAdjustments[objectHash], 0.0, 0.0, 0, true)
		end

		SetEntityCollision(object, false, false)
		SetEntityInvincible(object, true)
		SetEntityProofs(object, 1, true)
		FreezeEntityPosition(object, true)

		return object
	end
end

local function getNearbyDropPosition(coords, radius)
	for _, pickup in pairs(WorldPickups) do
		local dist = #(coords - pickup.coords)
		if dist <= radius then
			return pickup.coords
		end
	end
	return nil
end

function PickupsService.createPickup(name, amount, metadata, weaponId, id, degradation)
	local playerPed <const> = PlayerPedId()
	local coords <const>    = GetEntityCoords(playerPed, true, true)
	-- Check if there's an existing drop within 5 units of player
	local interactDist = Config.DropInventory and Config.DropInventory.Marker and Config.DropInventory.Marker.InteractDistance or 5.0
	local position          = getNearbyDropPosition(coords, interactDist)
	if not position then
		position = vector3(coords.x, coords.y, coords.z)
	end
	local index <const>     = PickupsService.getUniqueId()
	local targetSlot = pendingDropSlot
	pendingDropSlot = nil
	local data <const>      = { name = name, obj = index, amount = amount, metadata = metadata, weaponId = weaponId, position = position, id = id, degradation = degradation, targetSlot = targetSlot }
	if weaponId == 1 then
		TriggerServerEvent("vorpinventory:sharePickupServerItem", data)
	else
		TriggerServerEvent("vorpinventory:sharePickupServerWeapon", data)
	end
	Wait(1000)
	if Config.SFX.ItemDrop then
		PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
	end
end

RegisterNetEvent("vorpInventory:createPickup", PickupsService.createPickup)

function PickupsService.createMoneyPickup(amount)
	local playerPed <const> = PlayerPedId()
	local coords <const>    = GetEntityCoords(playerPed, true, true)
	local interactDist = Config.DropInventory and Config.DropInventory.Marker and Config.DropInventory.Marker.InteractDistance or 5.0
	local position          = getNearbyDropPosition(coords, interactDist)
	if not position then
		position = vector3(coords.x, coords.y, coords.z)
	end
	local handle <const>    = PickupsService.getUniqueId()
	local targetSlot = pendingDropSlot
	pendingDropSlot = nil
	local data <const>      = { handle = handle, amount = amount, position = position, targetSlot = targetSlot }
	TriggerServerEvent("vorpinventory:shareMoneyPickupServer", data)
	Wait(1000)
	if Config.SFX.MoneyDrop then
		PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
	end
end

RegisterNetEvent("vorpInventory:createMoneyPickup", PickupsService.createMoneyPickup)

function PickupsService.createGoldPickup(amount)

	local playerPed <const> = PlayerPedId()
	local coords <const>    = GetEntityCoords(playerPed, true, true)
	local interactDist = Config.DropInventory and Config.DropInventory.Marker and Config.DropInventory.Marker.InteractDistance or 5.0
	local position          = getNearbyDropPosition(coords, interactDist)
	if not position then
		position = vector3(coords.x, coords.y, coords.z)
	end
	local handle <const>    = PickupsService.getUniqueId()
	local targetSlot = pendingDropSlot
	pendingDropSlot = nil
	local data <const>      = { handle = handle, amount = amount, position = position, targetSlot = targetSlot }
	TriggerServerEvent("vorpinventory:shareGoldPickupServer", data)
	Wait(1000)
	if Config.SFX.GoldDrop then
		PlaySoundFrontend("show_info", "Study_Sounds", true, 0)
	end
end

RegisterNetEvent("vorpInventory:createGoldPickup", PickupsService.createGoldPickup)

function PickupsService.sharePickupClient(data, value)
	if value == 1 then
		if WorldPickups[data.obj] then return end
		local id = 1

		if data.type == "item_standard" then
			local item <const> = UserInventory[data.id]
			if item then
				item:quitCount(data.amount)
				if item:getCount() == 0 then
					UserInventory[data.id] = nil
				end
			end
			id = 2
		end

		local label <const> = Utils.GetLabel(data.name, id, data.metadata)
		if not label then
			print(("label not found for %s %s"):format(data.name, id))
		end
		local pickup <const> = {
			label    = (label or data.name) .. " x " .. tostring(data.amount),
			entityId = 0,
			coords   = data.position,
			uid      = data.uid,
			type     = data.type,
			name     = data.name,
		}
		WorldPickups[data.obj] = pickup

		-- Drop notification (only for the player who dropped)
		if data.droppedBy == GetPlayerServerId(PlayerId()) then
			local itemLabel = label or data.name
			SendNUIMessage({ action = "itemNotification", ["type"] = "remove", name = data.name, label = itemLabel, count = data.amount })
		end

		NUIService.LoadInv()
		if InInventory then PickupsService.sendNearbyDropsToNUI() end
	else
		local pickup <const> = WorldPickups[data.obj]
		if pickup then
			if pickup.entityId and DoesEntityExist(pickup.entityId) then
				DeleteEntity(pickup.entityId)
			end
			WorldPickups[data.obj] = nil
		end
		if InInventory then PickupsService.sendNearbyDropsToNUI() end
	end
end

RegisterNetEvent("vorpInventory:sharePickupClient", PickupsService.sharePickupClient)

function PickupsService.shareMoneyPickupClient(handle, amount, position, uuid, value)
	if value == 1 then
		if WorldPickups[handle] == nil then
			local pickup <const> = {
				label = T("money") .. tostring(amount) .. ")",
				entityId = 0,
				amount = amount,
				isMoney = true,
				isGold = false,
				coords = position,
				uuid = uuid,
				type = "item_standard",
				name = "money_bag"
			}
			WorldPickups[handle] = pickup
			if InInventory then PickupsService.sendNearbyDropsToNUI() end
		end
	else
		local pickup <const> = WorldPickups[handle]
		if pickup then
			if pickup.entityId and DoesEntityExist(pickup.entityId) then
				DeleteEntity(pickup.entityId)
			end

			WorldPickups[handle] = nil
			if InInventory then PickupsService.sendNearbyDropsToNUI() end
		end
	end
end

RegisterNetEvent("vorpInventory:shareMoneyPickupClient", PickupsService.shareMoneyPickupClient)

function PickupsService.shareGoldPickupClient(handle, amount, position, uuid, value)
	if value == 1 then
		if not WorldPickups[handle] then
			local pickup <const> = {
				label = T("gold") .. " (" .. tostring(amount) .. ")",
				entityId = 0,
				amount = amount,
				isMoney = false,
				isGold = true,
				coords = position,
				uuid = uuid,
				type = "item_standard",
				name = "gold_bag"
			}

			WorldPickups[handle] = pickup
			if InInventory then PickupsService.sendNearbyDropsToNUI() end
		end
	else
		local pickup <const> = WorldPickups[handle]
		if pickup then
			if pickup.entityId and DoesEntityExist(pickup.entityId) then
				DeleteEntity(pickup.entityId)
			end

			WorldPickups[handle] = nil
			if InInventory then PickupsService.sendNearbyDropsToNUI() end
		end
	end
end

RegisterNetEvent("vorpInventory:shareGoldPickupClient", PickupsService.shareGoldPickupClient)

-- DropLocations sync from server
local ClientDropLocations = {}

function PickupsService.syncDropLocations(data)
	ClientDropLocations = {}
	for _, loc in ipairs(data) do
		ClientDropLocations[loc.dropId] = { coords = loc.coords, slots = loc.slots }
	end
	-- If inventory is open, update NUI
	if InInventory then
		PickupsService.sendNearbyDropsToNUI()
	end
end

RegisterNetEvent("vorpInventory:syncDropLocations", PickupsService.syncDropLocations)

function PickupsService.playerAnim()
	local playerPed <const> = PlayerPedId()
	local animDict <const> = "amb_work@world_human_box_pickup@1@male_a@stand_exit_withprop"
	if not HasAnimDictLoaded(animDict) then
		RequestAnimDict(animDict)
		repeat Wait(0) until HasAnimDictLoaded(animDict)
	end

	TaskPlayAnim(playerPed, animDict, "exit_front", 1.0, 8.0, -1, 1, 0, false, false, false)
	Wait(1200)
	if Config.SFX.PickUp then
		PlaySoundFrontend("CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true, 1)
	end
	Wait(1000)
	ClearPedTasks(playerPed, true, true)
end

RegisterNetEvent("vorpInventory:playerAnim", PickupsService.playerAnim)


CurrentDropId = nil

function PickupsService.sendNearbyDropsToNUI()
	local playerPed = PlayerPedId()
	local playerCoords = GetEntityCoords(playerPed, true, true)
	local nearbyItems = {}
	local foundDropId = nil

	for dropId, loc in pairs(ClientDropLocations) do
		local dist = #(playerCoords - loc.coords)
		local interactDist = Config.DropInventory and Config.DropInventory.Marker and Config.DropInventory.Marker.InteractDistance or 5.0
		if dist <= interactDist then
			foundDropId = dropId
			for _, item in ipairs(loc.slots) do
				nearbyItems[#nearbyItems + 1] = item
			end
		end
	end

	-- Lock check for drop
	if foundDropId and not CurrentDropId then
		local Core = exports.vorp_core:GetCore()
		local isLocked = Core.Callback.TriggerAwait("vorpinventory:isDropLocked", foundDropId)
		if isLocked then
			Core.NotifyRightTip(T and T("inventoryInUse") or "This inventory is currently in use", 3000)
			nearbyItems = {}
			foundDropId = nil
		else
			TriggerServerEvent("vorpinventory:lockDrop", foundDropId)
			CurrentDropId = foundDropId
		end
	end

	SendNUIMessage({
		action = "setDropZoneItems",
		items = nearbyItems,
		hasNearbyDrops = #nearbyItems > 0,
		dropId = foundDropId,
	})
end

CreateThread(function()
	local function isAnyPlayerNear()
		local playerPed <const>    = PlayerPedId()
		local playerCoords <const> = GetEntityCoords(playerPed, true, true)
		local players <const>      = GetActivePlayers()
		local count                = 0
		for _, player in ipairs(players) do
			local targetPed = GetPlayerPed(player)
			if player ~= PlayerId() then
				local targetCoords <const> = GetEntityCoords(targetPed, true, true)
				local distance <const> = #(playerCoords - targetCoords)
				if distance < 2.0 then
					count = count + 1
				end
			end
		end

		return count
	end

	repeat Wait(2000) until LocalPlayer.state.IsInSession
	while true do
		local sleep = 1000

		local playerPed = PlayerPedId()
		local playerCoords = GetEntityCoords(playerPed, true, true)

		-- Draw markers from dropId locations
		for dropId, loc in pairs(ClientDropLocations) do
			local dist = #(playerCoords - loc.coords)
			local m = Config.DropInventory and Config.DropInventory.Marker or {}
			if dist <= (m.DrawDistance or 5.0) then
				sleep = 0
				local s = m.Scale or {}
				local c = m.Color or {}
				DrawMarker(m.Sprite or 0x94FDAE17, loc.coords.x, loc.coords.y, loc.coords.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s.x or 0.8, s.y or 0.8, s.z or 0.3, c.r or 202, c.g or 165, c.b or 128, c.a or 120, false, false, 0, true, false, false, false)
			end
		end

		Wait(sleep)
	end
end)


-- for debug
AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() ~= resourceName then return end
	if not Config.DevMode then return end
	--delete all entities
	for key, value in pairs(WorldPickups) do
		if DoesEntityExist(value.entityId) then
			DeleteEntity(value.entityId)
		end
	end
end)
