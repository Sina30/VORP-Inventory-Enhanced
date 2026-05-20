PlayerAmmoInfo = { ammo = {} }
local playerammoinfo   = PlayerAmmoInfo
local updatedAmmoCache = {}
local durabilityChanged = {}
local Core <const>     = exports.vorp_core:GetCore()
local ammoupdate       = true

local function addAmmoToPed(ammoData)
    for ammoType, ammo in pairs(ammoData) do
        SetPedAmmoByType(PlayerPedId(), joaat(ammoType), ammo)
    end
end

RegisterNetEvent("vorpinventory:recammo", function(ammoData)
    playerammoinfo.ammo = ammoData.ammo
end)

RegisterNetEvent("vorpinventory:loaded", function()
    SendNUIMessage({ action = "reclabels", labels = SharedData.AmmoLabels })

    local result <const> = Core.Callback.TriggerAwait("vorpinventory:getammoinfo")
    if not result then return end

    playerammoinfo.ammo = result.ammo or {}
    playerammoinfo.charidentifier = result.charidentifier

    addAmmoToPed(playerammoinfo.ammo)
    SendNUIMessage({ action = "updateammo", ammo = playerammoinfo.ammo })
end)

RegisterNetEvent("vorpinventory:updateuiammocount", function(ammo)
    SendNUIMessage({ action = "updateammo", ammo = ammo })
    NUIService.LoadInv()
end)

RegisterNetEvent("vorpinventory:setammotoped", function(ammoData)
    local PlayerPedId <const> = PlayerPedId()
    RemoveAllPedWeapons(PlayerPedId, true, true)
    RemoveAllPedAmmo(PlayerPedId)
    addAmmoToPed(ammoData)
end)

RegisterNetEvent("vorpinventory:updateinventory", function()
    NUIService.LoadInv()
end)

RegisterNetEvent("vorpinventory:ammoUpdateToggle", function(state)
    if not ammoupdate and state then
        local result <const> = Core.Callback.TriggerAwait("vorpinventory:getammoinfo")
        if not result then return end

        playerammoinfo.ammo = result.ammo or {}
        playerammoinfo.charidentifier = result.charidentifier
        addAmmoToPed(playerammoinfo.ammo)
        SendNUIMessage({
            action = "updateammo",
            ammo   = playerammoinfo.ammo
        })
    end
    ammoupdate = state
end)

--* AMMO SAVING THREAD
CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession

    while true do
        local sleep = 500

        if not InInventory and playerammoinfo.ammo then
            local playerPedId <const> = PlayerPedId()
            local isArmed <const> = IsPedArmed(playerPedId, 4) == 1
            local wephash <const> = GetPedCurrentHeldWeapon(playerPedId)
            local ismelee <const> = IsWeaponMeleeWeapon(wephash) == 1
            local wepgroup <const> = GetWeapontypeGroup(wephash)
            local ammotypes <const> = SharedData.AmmoTypes[wepgroup]
            local isThrownGroup <const> = wepgroup == `GROUP_THROWN`
            local isBowGroup <const> = wepgroup == `GROUP_BOW`
            local isPetrol <const> = wepgroup == `GROUP_PETROLCAN`

            if ammotypes and (isArmed or isThrownGroup or isBowGroup or isPetrol) and not ismelee then
                for ammo_name, ammo_data in pairs(ammotypes) do
                    if playerammoinfo.ammo[ammo_name] then -- is ammo valid
                        local ammoQty = GetPedAmmoByType(playerPedId, joaat(ammo_name))
                        if (isThrownGroup or isBowGroup or isPetrol) and ammoQty == 1 then
                            ammoQty = 0
                        end

                        if playerammoinfo.ammo[ammo_name] ~= ammoQty then
                            -- Durability: detect shots fired
                            if Config.WeaponDurability and Config.WeaponDurability.Enabled and ammoQty < playerammoinfo.ammo[ammo_name] then
                                local shotsFired = playerammoinfo.ammo[ammo_name] - ammoQty
                                local loss = shotsFired * (Config.WeaponDurability.DurabilityLossPerShot or 0.5)
                                for _, wp in pairs(UserWeapons) do
                                    if wp:getUsed() and GetWeapontypeGroup(joaat(wp:getName())) == wepgroup then
                                        wp:setDurability(math.max(0, wp:getDurability() - loss))
                                        durabilityChanged[wp:getId()] = wp:getDurability()
                                        if wp:getDurability() <= 0 then
                                            wp:UnequipWeapon()
                                            Core.NotifyRightTip(T("weaponBroken") or "This weapon is broken", 3000)
                                        end
                                    end
                                end
                            end
                            updatedAmmoCache[ammo_name] = ammoQty
                            playerammoinfo.ammo[ammo_name] = ammoQty
                        end
                    end
                end

                if next(updatedAmmoCache) then
                    SendNUIMessage({ action = "updateammo", ammo = playerammoinfo.ammo })
                end
            end
        end
        Wait(sleep)
    end
end)

--* AMMO UPDATE THREAD
CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession

    while true do
        if ammoupdate then
            if next(updatedAmmoCache) then
                TriggerServerEvent("vorpinventory:updateammo", playerammoinfo)
                updatedAmmoCache = {}
            end
            -- Sync durability to server
            if next(durabilityChanged) then
                for weaponId, dur in pairs(durabilityChanged) do
                    TriggerServerEvent("vorpinventory:updateWeaponDurability", weaponId, dur)
                end
                durabilityChanged = {}
            end
        end
        Wait(10000) -- update every 10 seconds
    end
end)
