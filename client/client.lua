
-- On resource start: remove weapons from ped + disable weapon wheel
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        RemoveAllPedWeapons(ped, true, true)
    end
end)

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    EnableHudContext(GetHashKey("HUD_CTX_MP_IN_ROLE_CUTSCENE"))
end)

if Config.DevMode then
    AddEventHandler('onClientResourceStart', function(resourceName)
        if (GetCurrentResourceName() ~= resourceName) then
            return
        end

        SendNUIMessage({ action = "hide" })
        RemoveAllPedWeapons(PlayerPedId(), true, true)
        TriggerServerEvent("DEV:loadweapons")
        TriggerServerEvent("vorpinventory:getItemsTable")
        Wait(1000)
        TriggerServerEvent("vorpinventory:getInventory")
        Wait(1000)
        TriggerServerEvent("vorpCore:LoadAllAmmo")
        Wait(100)
        TriggerEvent("vorpinventory:loaded")
        print("^1WARNING: Dev mode is enabled^7 do not use this in production live servers")
    end)
end

-- Hotbar toggle with Tab
CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    while true do
        Wait(0)
        if IsControlJustPressed(0, 0xB238FE0B) then
           
            NUIService.SendHotbarItems()
            SendNUIMessage({ action = "toggleHotbar" })
        end
        if IsControlJustPressed(0, 0xE6F612E4) then NUIService.UseHotbarSlot(1)
        elseif IsControlJustPressed(0, 0x1CE6D9EB) then NUIService.UseHotbarSlot(2)
        elseif IsControlJustPressed(0, 0xAE69478F) then NUIService.UseHotbarSlot(3)
        elseif IsControlJustPressed(0, 0x8F9F9E58) then NUIService.UseHotbarSlot(4)
        elseif IsControlJustPressed(0, 0xAB62E997) then NUIService.UseHotbarSlot(5)
        end
    end
end)

-- Craft locations prompt system
CreateThread(function()
    if not Config.CraftLocations or #Config.CraftLocations == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local craftGroup = GetRandomIntInRange(0, 0xffffff)
    local craftPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(craftPrompt, 0xCEFD9220)
    UiPromptSetText(craftPrompt, CreateVarString(10, "LITERAL_STRING", "Craft"))
    UiPromptSetEnabled(craftPrompt, true)
    UiPromptSetVisible(craftPrompt, true)
    UiPromptSetHoldMode(craftPrompt, 1000)
    UiPromptSetGroup(craftPrompt, craftGroup, 0)
    UiPromptRegisterEnd(craftPrompt)

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)
        local nearCraft = false

        for _, loc in ipairs(Config.CraftLocations) do
            local dist = #(playerCoords - loc.coord)
            if dist <= 2.0 then
                nearCraft = true
                sleep = 0

                local label = CreateVarString(10, "LITERAL_STRING", "Craft Station")
                UiPromptSetActiveGroupThisFrame(craftGroup, label, 0, 0, 0, 0)

                if UiPromptHasHoldModeCompleted(craftPrompt) then
                    NUIService.OpenInv()
                    SendNUIMessage({ action = "openCraft" })
                    TriggerServerEvent("vorpinventory:getCraftItems")
                end
                break
            end
        end

        Wait(sleep)
    end
end)




-- Weapon repair prompt system
local RepairCore = exports.vorp_core:GetCore()
CreateThread(function()
    local durConfig = Config.WeaponDurability
    if not durConfig or not durConfig.Enabled or not durConfig.RepairLocations or #durConfig.RepairLocations == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local repairGroup = GetRandomIntInRange(0, 0xffffff)
    local repairPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(repairPrompt, 0xCEFD9220)
    UiPromptSetText(repairPrompt, CreateVarString(10, "LITERAL_STRING", "Repair Weapon"))
    UiPromptSetEnabled(repairPrompt, true)
    UiPromptSetVisible(repairPrompt, true)
    UiPromptSetStandardMode(repairPrompt, true)
    UiPromptSetGroup(repairPrompt, repairGroup, 0)
    UiPromptRegisterEnd(repairPrompt)

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)

        for _, loc in ipairs(durConfig.RepairLocations) do
            local dist = #(playerCoords - loc.coord)
            if dist <= 2.0 then
                sleep = 0
                local label = CreateVarString(10, "LITERAL_STRING", "Gunsmith")
                UiPromptSetActiveGroupThisFrame(repairGroup, label, 0, 0, 0, 0)

                if UiPromptHasStandardModeCompleted(repairPrompt, 0) then
                    CreateThread(function()
                        local ped = PlayerPedId()
                        local _, weaponHash = GetCurrentPedWeapon(ped, false, 0, false)
                        if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then
                            RepairCore.NotifyRightTip("No weapon in hand", 3000)
                            return
                        end
                        -- Find matching weapon in UserWeapons
                        local foundId = nil
                        for id, wp in pairs(UserWeapons) do
                            if wp:getUsed() and joaat(wp:getName()) == weaponHash then
                                foundId = id
                                break
                            end
                        end
                        if not foundId then
                            RepairCore.NotifyRightTip("No weapon found", 3000)
                            return
                        end
                        local weapon = UserWeapons[foundId]
                        if weapon:getDurability() >= 100 then
                            RepairCore.NotifyRightTip(T("weaponFullDurability") or "This weapon doesn't need repair", 3000)
                            return
                        end
                        -- Calculate repair time
                        local repairTime = math.floor((durConfig.MaxRepairTime or 60000) * (1 - weapon:getDurability() / 100))
                        -- Unequip weapon
                        weapon:UnequipWeapon()
                        UserWeapons[foundId] = nil
                        NUIService.LoadInv()
                        -- Progress bar via vorp_progressbar
                        local progressbar = exports.vorp_progressbar:initiate()
                        progressbar.start("Repairing...", repairTime, function() end, "linear", "rgb(74, 158, 107)")
                        -- Server
                        TriggerServerEvent("vorpinventory:repairWeapon", foundId, repairTime)
                    end)
                end
                break
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    if not Config.UseLanternPutOnBelt then
        return
    end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local lastLantern = 0
    while true do
        local pedid = PlayerPedId()
        local weaponHeld <const> = GetPedCurrentHeldWeapon(pedid)
        local isLantern <const> = IsWeaponLantern(weaponHeld) == 1 -- assuming it will return all lanterns to true
        if isLantern then
            lastLantern = weaponHeld
        end

        if lastLantern ~= 0 and not isLantern then
            SetCurrentPedWeapon(pedid, lastLantern, true, 12, false, false)
            lastLantern = 0
        end
        Wait(500)
    end
end)


-- Steal command: search nearest player's inventory
local StealCore = exports.vorp_core:GetCore()
RegisterCommand("steal", function()
    if InInventory then return end
    -- Weapon requirement check
    if Config.StealRequiresWeapon then
        local ped = PlayerPedId()
        local _, weaponHash = GetCurrentPedWeapon(ped, false, 0, false)
        if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then
            StealCore.NotifyRightTip(T("stealNeedWeapon") or "You need a weapon to steal", 3000)
            return
        end
    end
    local nearestPlayers = Utils.getNearestPlayers()
    if #nearestPlayers == 0 then
        StealCore.NotifyRightTip(T("noplayersnearby") or "No players nearby", 3000)
        return
    end
    local closestPlayer = nil
    local closestDist = 999.0
    local myCoords = GetEntityCoords(PlayerPedId(), true, true)
    for _, player in ipairs(nearestPlayers) do
        local targetPed = GetPlayerPed(player)
        local targetCoords = GetEntityCoords(targetPed, true, true)
        local dist = #(targetCoords - myCoords)
        if dist < closestDist then
            closestDist = dist
            closestPlayer = player
        end
    end
    if closestPlayer then
        local targetServerId = GetPlayerServerId(closestPlayer)
        TriggerServerEvent("vorpinventory:stealPlayer", targetServerId)
    end
end, false)

-- Stash prompts
CreateThread(function()
    if not Config.Stashes or #Config.Stashes == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local stashGroup = GetRandomIntInRange(0, 0xffffff)
    local stashPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(stashPrompt, Config.StashPrompt.Key or 0xCEFD9220)
    UiPromptSetText(stashPrompt, CreateVarString(10, "LITERAL_STRING", "Open Stash"))
    UiPromptSetEnabled(stashPrompt, true)
    UiPromptSetVisible(stashPrompt, true)
    UiPromptSetHoldMode(stashPrompt, Config.StashPrompt.HoldDuration or 500)
    UiPromptSetGroup(stashPrompt, stashGroup, 0)
    UiPromptRegisterEnd(stashPrompt)

    local lastTriggered = 0
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)
        local drawDist = Config.StashPrompt.DrawDistance or 2.0

        for _, stash in ipairs(Config.Stashes) do
            local dist = #(playerCoords - stash.coord)
            if dist <= drawDist then
                sleep = 0
                local label = CreateVarString(10, "LITERAL_STRING", stash.name or "Stash")
                UiPromptSetActiveGroupThisFrame(stashGroup, label, 0, 0, 0, 0)

                if UiPromptHasHoldModeCompleted(stashPrompt) and not InInventory and (GetGameTimer() - lastTriggered) > 2000 then
                    lastTriggered = GetGameTimer()
                    TriggerServerEvent("vorpinventory:openStash", stash.id)
                end
                break
            end
        end

        Wait(sleep)
    end
end)

-- DEV: test steal on yourself
if Config.DevMode then
    RegisterCommand("stealself", function()
        if InInventory then return end
        TriggerServerEvent("vorpinventory:stealPlayer", GetPlayerServerId(PlayerId()))
    end, false)
end

-- ENABLE PUSH TO TALK
CreateThread(function()
    repeat Wait(5000) until LocalPlayer.state.IsInSession
    if not Config.EnablePushToTalk then
        return
    end
    local isNuiFocused = false

    while true do
        local sleep = 0
        if InInventory then
            if not isNuiFocused then
                SetNuiFocusKeepInput(true)
                isNuiFocused = true
            end

            DisableAllControlActions(0)
            EnableControlAction(0, `INPUT_PUSH_TO_TALK`, true)
        else
            sleep = 1000
            if isNuiFocused then
                SetNuiFocusKeepInput(false)
                isNuiFocused = false
            end
        end
        Wait(sleep)
    end
end)

