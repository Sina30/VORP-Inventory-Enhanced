local currentBagProp = nil

local function notify(msg)
    TriggerEvent("vorp:TipRight", msg, 2500)
end

local function normalizeVec(tbl, default)
    tbl = tbl or default or {}
    return tonumber(tbl.x or tbl[1] or 0.0) or 0.0,
        tonumber(tbl.y or tbl[2] or 0.0) or 0.0,
        tonumber(tbl.z or tbl[3] or 0.0) or 0.0
end

local function boneIndexFromName(ped, boneName)
    if type(boneName) == "number" then return GetPedBoneIndex(ped, boneName) end
    boneName = tostring(boneName or "CP_Back")

    -- CP_Back is used by many RedM backpack scripts. Prefer named bone lookup when available.
    if GetEntityBoneIndexByName then
        local idx = GetEntityBoneIndexByName(ped, boneName)
        if idx and idx ~= -1 then return idx end
    end

    local map = {
        CP_Back = 0x60F0,
        SKEL_SPINE3 = 0x60F0,
        SKEL_SPINE2 = 0x60F1,
        SKEL_SPINE1 = 0x60F2,
        SKEL_L_HAND = 0x49D9,
        SKEL_R_HAND = 0xDEAD,
        SKEL_L_FOREARM = 0xEEEB,
        SKEL_R_FOREARM = 0x6E5C,
    }
    return GetPedBoneIndex(ped, map[boneName] or map.CP_Back)
end

local function deleteBagProp()
    if currentBagProp and DoesEntityExist(currentBagProp) then
        DetachEntity(currentBagProp, true, true)
        DeleteEntity(currentBagProp)
        DeleteObject(currentBagProp)
    end
    currentBagProp = nil
end

RegisterNetEvent("vorp_inventory:client:clearBagProp", function()
    deleteBagProp()
end)

RegisterNetEvent("vorp_inventory:client:setBagProp", function(prop, label)
    deleteBagProp()
    if not prop or not prop.Model then return end

    local ped = PlayerPedId()
    local model = joaat(prop.Model)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(model) then
        notify(T("bag_prop_not_loaded", tostring(prop.Model)))
        return
    end

    local coords = GetEntityCoords(ped)
    currentBagProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    SetEntityAsMissionEntity(currentBagProp, true, true)

    local px, py, pz = normalizeVec(prop.Position, { x = 0.18, y = -0.18, z = -0.02 })
    local rx, ry, rz = normalizeVec(prop.Rotation, { x = 0.0, y = 90.0, z = 180.0 })
    local rotationOrder = tonumber(prop.RotationOrder or prop.rotationOrder or 1) or 1
    AttachEntityToEntity(currentBagProp, ped, boneIndexFromName(ped, prop.Bone), px, py, pz, rx, ry, rz, true, true, false, true, rotationOrder, true)
    SetModelAsNoLongerNeeded(model)
end)


RegisterCommand("bagproprefresh", function()
    TriggerServerEvent("vorp_inventory:server:syncBagProp")
end, false)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then deleteBagProp() end
end)

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    TriggerServerEvent("vorp_inventory:server:syncBagProp")
end)
