-- =================================================================================
-- VORP INVENTORY -- WEAPON HOLSTERING (visual prop attachment)
-- Spawns and attaches a weapon prop to the player's body when the weapon is equipped
-- (selected in inventory) but not currently held in hand. Cosmetic only — does not
-- affect gameplay or ammo. Categories come from Config.WeaponCategories.
-- =================================================================================

if not Config.WeaponHolstering or not Config.WeaponHolstering.Enabled then
    return
end

local cfg = Config.WeaponHolstering

-- [weaponId] = entityHandle for currently-attached props
local attached = {}

-- Map weapon-name to category using the same prefix rules the server uses.
local function categorize(weaponName)
    if not weaponName or not Config.WeaponCategories then return "Other" end
    for category, prefixes in pairs(Config.WeaponCategories) do
        if type(prefixes) == "table" then
            for _, prefix in ipairs(prefixes) do
                if type(prefix) == "string" and prefix ~= "" and weaponName:sub(1, #prefix) == prefix then
                    return category
                end
            end
        end
    end
    return "Other"
end

-- Resolve the prop model hash for a weapon. Prefers ModelOverrides, falls back to
-- joaat("w_" .. lower(weaponName)) which works for most RDR3 weapons.
local function propModelFor(weaponName)
    if cfg.ModelOverrides and cfg.ModelOverrides[weaponName] then
        return joaat(cfg.ModelOverrides[weaponName])
    end
    return joaat("w_" .. string.lower(weaponName))
end

local function detach(weaponId)
    local ent = attached[weaponId]
    if ent and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    attached[weaponId] = nil
end

local function detachAll()
    for id, _ in pairs(attached) do detach(id) end
end

local function attach(weaponId, weaponName)
    if attached[weaponId] then return end
    local category = categorize(weaponName)
    local boneCfg = cfg.Bones and cfg.Bones[category]
    if not boneCfg then return end -- this category has no holster slot configured

    local model = propModelFor(weaponName)
    if not IsModelValid(model) then return end
    RequestModel(model)
    local tries = 0
    while not HasModelLoaded(model) and tries < 50 do
        Wait(50); tries = tries + 1
    end
    if not HasModelLoaded(model) then return end

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped, true, true)
    local prop = CreateObject(model, pedCoords.x, pedCoords.y, pedCoords.z, true, true, true)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, boneCfg.bone),
        boneCfg.offsetX or 0.0, boneCfg.offsetY or 0.0, boneCfg.offsetZ or 0.0,
        boneCfg.rotX or 0.0,   boneCfg.rotY or 0.0,   boneCfg.rotZ or 0.0,
        false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(model)
    attached[weaponId] = prop
end

-- A weapon is "holstered visible" when it's selected in inventory but the ped's
-- current held weapon is something else (i.e. ped has multiple weapons and this
-- one isn't the active one).
local function shouldShowAsHolstered(weaponId, weaponData, currentHash)
    if not weaponData or not weaponData.getUsed then return false end
    if not weaponData:getUsed() then return false end
    local nameHash = joaat(weaponData:getName())
    if nameHash == currentHash then return false end -- this IS the active one — real weapon shown
    return true
end

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession

    while true do
        local interval = cfg.PollInterval or 500
        local ped = PlayerPedId()
        local _, currentHash = GetCurrentPedWeapon(ped, false, 0, false)

        if UserWeapons then
            -- 1. Detach props for weapons that are no longer "holstered visible".
            for weaponId, _ in pairs(attached) do
                local wp = UserWeapons[weaponId]
                if not wp or not shouldShowAsHolstered(weaponId, wp, currentHash) then
                    detach(weaponId)
                end
            end
            -- 2. Attach props for newly-holstered weapons.
            for weaponId, wp in pairs(UserWeapons) do
                if shouldShowAsHolstered(weaponId, wp, currentHash) and not attached[weaponId] then
                    attach(weaponId, wp:getName())
                end
            end
        end

        Wait(interval)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then detachAll() end
end)
