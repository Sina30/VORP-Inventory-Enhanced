ShopClient = {
    list  = {},          -- snapshot from server
    peds  = {},          -- [shopId] = pedHandle
    blips = {},          -- [shopId] = blipHandle
    current = nil,       -- shopId currently open in UI
}

if not Shops or not Shops.Enabled then
    return
end

local Core <const> = exports.vorp_core:GetCore()

local function cleanupShop(id)
    local ped = ShopClient.peds[id]
    if type(ped) == "number" and DoesEntityExist(ped) then
        DeleteEntity(ped)
        SetEntityAsNoLongerNeeded(ped)
    end
    ShopClient.peds[id] = nil

    local blip = ShopClient.blips[id]
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    ShopClient.blips[id] = nil
end

local function cleanupAll()
    for id, _ in pairs(ShopClient.peds) do cleanupShop(id) end
end

local function spawnPedIfNeeded(shop)
    if not Shops.Features.NpcPed then return end
    if not shop.ped or not shop.ped.model then return end

    local status = ShopClient.peds[shop.id]
    if status == "loading" or status == "failed" then return end
    if type(status) == "number" and DoesEntityExist(status) then return end

    ShopClient.peds[shop.id] = "loading"

    CreateThread(function()
        local hash = type(shop.ped.model) == "string" and joaat(shop.ped.model) or shop.ped.model
        if not IsModelValid(hash) then
            print(("^3[vorp_inventory]^7 shop ped model is not valid: %s (%s)"):format(tostring(shop.ped.model), shop.id))
            ShopClient.peds[shop.id] = "failed"
            return
        end

        RequestModel(hash)
        local tries = 0
        while not HasModelLoaded(hash) and tries < 50 do
            Wait(50); tries = tries + 1
        end
        if not HasModelLoaded(hash) then
            print(("^3[vorp_inventory]^7 shop ped model failed to load: %s (%s)"):format(tostring(shop.ped.model), shop.id))
            ShopClient.peds[shop.id] = "failed"
            return
        end

        local ped = CreatePed(hash, shop.coord.x, shop.coord.y, shop.coord.z - 1.0, shop.ped.heading or 0.0, false, false, false, false)
        SetEntityCanBeDamaged(ped, false)
        SetPedCanBeTargetted(ped, false)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetModelAsNoLongerNeeded(hash)
        ShopClient.peds[shop.id] = ped
    end)
end

local function spawnBlipIfNeeded(shop)
    if not shop.blip or not shop.blip.enabled then return end
    if ShopClient.blips[shop.id] and DoesBlipExist(ShopClient.blips[shop.id]) then return end
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, shop.coord.x, shop.coord.y, shop.coord.z, shop.blip.name or "Shop")
    SetBlipSprite(blip, shop.blip.sprite or -776993475, true)
    SetBlipScale(blip, shop.blip.scale or 0.2)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, shop.blip.name or "Shop")
    ShopClient.blips[shop.id] = blip
end

local promptGroup, browsePrompt, purchasePrompt, managePrompt
local function ensurePrompts()
    if promptGroup then return end
    promptGroup = GetRandomIntInRange(0, 0xffffff)

    browsePrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(browsePrompt, 0xCEFD9220)
    UiPromptSetText(browsePrompt, CreateVarString(10, "LITERAL_STRING", T("ui").shop_prompt_browse or "Browse Shop"))
    UiPromptSetEnabled(browsePrompt, true)
    UiPromptSetVisible(browsePrompt, true)
    UiPromptSetStandardMode(browsePrompt, true)
    UiPromptSetGroup(browsePrompt, promptGroup, 0)
    UiPromptRegisterEnd(browsePrompt)

    purchasePrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(purchasePrompt, 0x760A9C6F) -- G
    UiPromptSetText(purchasePrompt, CreateVarString(10, "LITERAL_STRING", T("ui").shop_prompt_purchase or "Purchase Shop"))
    UiPromptSetEnabled(purchasePrompt, true)
    UiPromptSetVisible(purchasePrompt, true)
    UiPromptSetHoldMode(purchasePrompt, 1000)
    UiPromptSetGroup(purchasePrompt, promptGroup, 0)
    UiPromptRegisterEnd(purchasePrompt)

    managePrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(managePrompt, 0x771AF4D5) -- H
    UiPromptSetText(managePrompt, CreateVarString(10, "LITERAL_STRING", T("ui").shop_prompt_manage or "Manage Shop"))
    UiPromptSetEnabled(managePrompt, true)
    UiPromptSetVisible(managePrompt, true)
    UiPromptSetStandardMode(managePrompt, true)
    UiPromptSetGroup(managePrompt, promptGroup, 0)
    UiPromptRegisterEnd(managePrompt)
end

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    Wait(1500)
    ensurePrompts()
    TriggerServerEvent("vorp_inventory:Shop:RequestList")

    local lastTriggered = 0
    while true do
        local sleep = 1000
        local list = ShopClient.list
        if list and #list > 0 then
            local ped = PlayerPedId()
            local pc  = GetEntityCoords(ped, true, true)
            for _, shop in ipairs(list) do
                if shop.coord then
                    local dist = #(pc - vector3(shop.coord.x, shop.coord.y, shop.coord.z))
                    if dist <= (shop.drawDistance or 25.0) then
                        spawnPedIfNeeded(shop)
                        spawnBlipIfNeeded(shop)
                    end
                    if dist <= (shop.interactDistance or 2.0) then
                        sleep = 0
                        local label = CreateVarString(10, "LITERAL_STRING", shop.name or "Shop")
                        UiPromptSetActiveGroupThisFrame(promptGroup, label, 0, 0, 0, 0)

                        if InInventory then break end
                        if (GetGameTimer() - lastTriggered) < 1500 then break end

                        if IsControlJustPressed(0, 0xCEFD9220) then -- E -> browse
                            lastTriggered = GetGameTimer()
                            TriggerServerEvent("vorp_inventory:Shop:Open", shop.id)
                        elseif shop.purchasable and not shop.owned and UiPromptHasHoldModeCompleted(purchasePrompt) then
                            lastTriggered = GetGameTimer()
                            TriggerServerEvent("vorp_inventory:Shop:Purchase", shop.id)
                        elseif shop.owned and IsControlJustPressed(0, 0x771AF4D5) then -- H -> manage
                            lastTriggered = GetGameTimer()
                            TriggerServerEvent("vorp_inventory:Shop:Open", shop.id)
                        end
                        break
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then cleanupAll() end
end)

function ShopClient.OpenUI(payload)
    ShopClient.current = payload.id
    InInventory = true
    DisplayRadar(false)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "display",
        type   = "shop",
        title  = payload.name,
        id     = payload.id,
        capacity = payload.capacity,
    })
    SendNUIMessage({
        action = "setShopState",
        shop   = payload,
    })
end

function ShopClient.Refresh(payload)
    if ShopClient.current ~= payload.id then return end
    SendNUIMessage({
        action = "setShopState",
        shop   = payload,
    })
    if NUIService and NUIService.LoadInv then
        NUIService.LoadInv()
    end
end

function ShopClient.CloseUI()
    ShopClient.current = nil
    if InInventory then
        SetNuiFocus(false, false)
        DisplayRadar(true)
        SendNUIMessage({ action = "hide" })
        InInventory = false
    end
end

function ShopClient.UpdateListEntry(shopId, ownerCharId)
    for _, s in ipairs(ShopClient.list) do
        if s.id == shopId then
            s.owned = ownerCharId ~= nil
            break
        end
    end
end
