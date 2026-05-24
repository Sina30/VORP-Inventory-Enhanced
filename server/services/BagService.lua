BagService = BagService or {}

local Core = exports.vorp_core:GetCore()

BackPacks      = BackPacks      or {}
BackPacks.Bags = BackPacks.Bags or { Enabled = false, Items = {}, Categories = {}, Props = { Enabled = false } }
if not next(BackPacks.Bags.Items or {}) then
    print("^3[vorp_inventory]^7 BagService: BackPacks.Bags is empty - config/backpacks.lua or shared/services/backpacksBuilder.lua did not populate it on the server.")
end

local function getChar(source)
    local user = Core.getUser(source)
    return user and user.getUsedCharacter or nil
end

local function hasJob(character, jobs)
    if not jobs or jobs == false then return true end
    local job = character.job
    local grade = tonumber(character.jobGrade or character.grade or 0) or 0
    local min = jobs[job]
    return min ~= nil and grade >= tonumber(min or 0)
end

local function isBagItem(name)
    local cfg = BackPacks.Bags
    return cfg and cfg.Enabled and cfg.Items and cfg.Items[name]
end

function BagService.IsBagItem(name)
    return isBagItem(name) ~= nil and isBagItem(name) ~= false
end

local function getBagMode(bag)
    return bag and bag.mode
        or (BackPacks.BackpackSettings and BackPacks.BackpackSettings.Mode)
        or "capacity"
end

local function ensureBackpackInv(invId, bag)
    if CustomInventoryInfos and CustomInventoryInfos[invId] then return end
    exports.vorp_inventory:registerInventory({
        id                   = invId,
        name                 = bag.label or "Backpack",
        limit                = -1,
        useWeight            = true,
        weight               = tonumber(bag.extraWeight or 10.0) or 10.0,
        acceptWeapons        = bag.acceptWeapons or false,
        shared               = true,
        ignoreItemStackLimit = false,
        whitelistItems       = false,
        UsePermissions       = false,
        UseBlackList         = false,
        whitelistWeapons     = false,
    })
end

local containerWeightCache = {} -- [source] = { weight = N, expires = ms }

local function invalidateContainerCache(source)
    if source then containerWeightCache[source] = nil end
end

local function getInventory(identifier)
    return UsersInventories and UsersInventories.default and UsersInventories.default[identifier] or {}
end

local function collectPlayerBagInvIds(character)
    local inv = getInventory(character.identifier)
    local ids = {}
    for _, item in pairs(inv) do
        if isBagItem(item:getName()) then
            local meta = item:getMetadata() or {}
            local bagId = meta.bagId or tostring(item:getId())
            ids[#ids + 1] = "bp_" .. tostring(bagId)
        end
    end
    return ids
end

function BagService.GetContainerBackpacksWeight(source)
    if not source then return 0 end
    local now = GetGameTimer()
    local cached = containerWeightCache[source]
    if cached and cached.expires > now then return cached.weight end

    local character = getChar(source)
    if not character then return 0 end

    local invIds = collectPlayerBagInvIds(character)
    if #invIds == 0 then
        containerWeightCache[source] = { weight = 0, expires = now + 1500 }
        return 0
    end

    local placeholders = {}
    local params = {}
    for i, id in ipairs(invIds) do
        local key = "inv" .. i
        placeholders[#placeholders + 1] = "@" .. key
        params[key] = id
    end

    local rows = MySQL.query.await(([[
        SELECT COALESCE(SUM(ci.amount * COALESCE(i.weight, 0)), 0) AS total
        FROM character_inventories ci
        LEFT JOIN items_crafted ic ON ic.id = ci.item_crafted_id
        LEFT JOIN items i ON i.id = ic.item_id
        WHERE ci.inventory_type IN (%s)
    ]]):format(table.concat(placeholders, ",")), params)

    local total = (rows and rows[1] and tonumber(rows[1].total)) or 0
    containerWeightCache[source] = { weight = total, expires = now + 1500 }
    return total
end

local function getBagInvWeight(invId)
    local rows = MySQL.query.await([[
        SELECT COALESCE(SUM(ci.amount * COALESCE(i.weight, 0)), 0) AS total
        FROM character_inventories ci
        LEFT JOIN items_crafted ic ON ic.id = ci.item_crafted_id
        LEFT JOIN items i ON i.id = ic.item_id
        WHERE ci.inventory_type = @invType
    ]], { invType = invId })
    return (rows and rows[1] and tonumber(rows[1].total)) or 0
end

local function findBagItemHolder(bagId)
    local bagInvId = "bp_" .. tostring(bagId)
    if not UsersInventories or not UsersInventories.default then return nil, nil end
    for identifier, inv in pairs(UsersInventories.default) do
        for _, it in pairs(inv) do
            if isBagItem(it:getName()) then
                local meta = it:getMetadata() or {}
                if tostring(meta.bagId or it:getId()) == tostring(bagId) then
                    return it, identifier, bagInvId
                end
            end
        end
    end
    return nil, nil, bagInvId
end

local function sourceFromIdentifier(identifier)
    if not identifier then return nil end
    local players = GetPlayers()
    for _, pid in ipairs(players) do
        local user = Core.getUser(tonumber(pid))
        local ch = user and user.getUsedCharacter
        if ch and ch.identifier == identifier then return tonumber(pid) end
    end
    return nil
end

local function updateBagLoadMetadata(invId)
    if type(invId) ~= "string" or invId:sub(1, 3) ~= "bp_" then return end
    local bagId = invId:sub(4)
    local bagItem, identifier = findBagItemHolder(bagId)
    if not bagItem then return end

    local bag = isBagItem(bagItem:getName())
    if not bag then return end

    local capacity = tonumber(bag.extraWeight or 0) or 0
    local current = getBagInvWeight(invId)
    local meta = bagItem:getMetadata() or {}
    meta.bagId = meta.bagId or tostring(bagId)
    meta.Load = string.format("%.1f/%.1f kg", current, capacity)

    local owner = bagItem:getOwner()
    DBService.SetItemMetadata(owner, bagItem:getId(), meta)
    bagItem:setMetadata(meta)

    local src = sourceFromIdentifier(identifier)
    if src then
        TriggerClientEvent("vorpCoreClient:SetItemMetadata", src, bagItem:getId(), meta)
        TriggerClientEvent("vorp_inventory:ReloadInv", src)
    end
end

function BagService.UpdateBagLoadMetadata(invId)
    updateBagLoadMetadata(invId)
end

AddEventHandler("vorp_inventory:Server:OnItemMovedToCustomInventory", function(_, invId, src)
    if type(invId) == "string" and invId:sub(1, 3) == "bp_" then
        invalidateContainerCache(src)
        updateBagLoadMetadata(invId)
    end
end)

AddEventHandler("playerDropped", function() invalidateContainerCache(source) end)

local function itemAllowedInCategories(itemName, categories)
    if not categories or categories == false then return true end
    local cats = BackPacks.Bags and BackPacks.Bags.Categories or {}
    for _, cat in ipairs(categories) do
        if cats[cat] and cats[cat][itemName] then return true end
    end
    return false
end

local function getActiveBags(source, excludeItemId)
    local character = getChar(source)
    if not character then return {}, nil end
    local inv = getInventory(character.identifier)
    local cfg = BackPacks.Bags or {}
    local active = {}
    for _, item in pairs(inv) do
        if not excludeItemId or tonumber(item:getId()) ~= tonumber(excludeItemId) then
            local bag = isBagItem(item:getName())
            if bag and hasJob(character, bag.jobs) then
                local meta = item:getMetadata() or {}
                if not cfg.RequireEquipped or meta.equipped == true then
                    active[#active + 1] = { item = item, config = bag, name = item:getName() }
                end
            end
        end
    end

    if cfg.AllowOnlyOneActiveBag and #active > 1 then
        table.sort(active, function(a, b)
            return (tonumber(a.config.extraWeight or 0) or 0) > (tonumber(b.config.extraWeight or 0) or 0)
        end)
        return { active[1] }, character
    end

    return active, character
end

function BagService.GetEffectiveCapacity(source, addItemName, addWeight, excludeItemId)
    local character = getChar(source)
    if not character then return 0 end
    local base = tonumber(character.invCapacity or 0) or 0
    if base == -1 then return -1 end
    local cfg = BackPacks.Bags
    if not cfg or not cfg.Enabled then return base end

    local active = getActiveBags(source, excludeItemId)
    local unrestricted = 0.0
    local restrictedBonusByCat = {}
    for _, bagData in ipairs(active) do
        local bag = bagData.config
        local bonus = tonumber(bag.extraWeight or 0.0) or 0.0
        if not bag.allowedCategories or bag.allowedCategories == false then
            unrestricted = unrestricted + bonus
        else
            for _, cat in ipairs(bag.allowedCategories) do
                restrictedBonusByCat[cat] = (restrictedBonusByCat[cat] or 0.0) + bonus
            end
        end
    end

    local inv = getInventory(character.identifier)
    local allowedWeightByCat = {}
    local cats = cfg.Categories or {}
    for _, item in pairs(inv) do
        local name = item:getName()
        local weight = (tonumber(item:getWeight() or 0) or 0) * (tonumber(item:getCount() or 1) or 1)
        for cat, items in pairs(cats) do
            if items[name] then allowedWeightByCat[cat] = (allowedWeightByCat[cat] or 0.0) + weight end
        end
    end
    if addItemName and addWeight then
        for cat, items in pairs(cats) do
            if items[addItemName] then allowedWeightByCat[cat] = (allowedWeightByCat[cat] or 0.0) + (tonumber(addWeight) or 0.0) end
        end
    end

    local restrictedCapacity = 0.0
    for cat, bonus in pairs(restrictedBonusByCat) do
        restrictedCapacity = restrictedCapacity + math.min(bonus, allowedWeightByCat[cat] or 0.0)
    end

    return base + unrestricted + restrictedCapacity
end

function BagService.GetCurrentWeight(source)
    local character = getChar(source)
    if not character then return 0 end
    local identifier = character.identifier
    local charId = character.charIdentifier
    local itemsWeight = (InventoryAPI and InventoryAPI.getUserTotalCountItems(identifier, charId)) or 0
    local weaponsWeight = (InventoryAPI and InventoryAPI.getUserTotalCountWeapons(identifier, charId, true)) or 0
    return (tonumber(itemsWeight) or 0) + (tonumber(weaponsWeight) or 0)
end

function BagService.CanRemoveBagItem(source, itemId, amount)
    local cfg = BackPacks.Bags
    if not cfg or not cfg.Enabled or cfg.PreventBagRemovalWhenOverweight == false then
        return true
    end

    local character = getChar(source)
    if not character then return true end
    local inv = getInventory(character.identifier)
    local item = inv and inv[tonumber(itemId)]
    if not item then return true end

    local bag = isBagItem(item:getName())
    if not bag then return true end

    local currentWeight = BagService.GetCurrentWeight(source)
    local removeAmount = tonumber(amount or item:getCount() or 1) or 1
    local itemWeight = (tonumber(item:getWeight() or 0) or 0) * removeAmount
    local capacityAfter = BagService.GetEffectiveCapacity(source, nil, nil, item:getId())
    local weightAfter = math.max(0.0, currentWeight - itemWeight)

    if capacityAfter ~= -1 and weightAfter > capacityAfter then
        return false, T("bag_cannot_remove", weightAfter, capacityAfter)
    end

    return true
end

function BagService.CanUnequipBagItem(source, itemId)
    local cfg = BackPacks.Bags
    if not cfg or not cfg.Enabled or cfg.PreventBagRemovalWhenOverweight == false then
        return true
    end

    local character = getChar(source)
    if not character then return true end
    local inv = getInventory(character.identifier)
    local item = inv and inv[tonumber(itemId)]
    if not item or not isBagItem(item:getName()) then return true end

    local currentWeight = BagService.GetCurrentWeight(source)
    local capacityAfter = BagService.GetEffectiveCapacity(source, nil, nil, item:getId())
    if capacityAfter ~= -1 and currentWeight > capacityAfter then
        return false, T("bag_cannot_unequip", currentWeight, capacityAfter)
    end
    return true
end

function BagService.GetEquippedLabel(source)
    local active = getActiveBags(source)
    local labels = {}
    for _, data in ipairs(active) do labels[#labels + 1] = data.config.label or data.name end
    return table.concat(labels, ", ")
end


local function normalizeNestedPosition(value, fallback)
    if not value then return fallback end
    if value.position then return value.position end
    if value.Position then return value.Position end
    return value
end

local function normalizeNestedRotation(src, fallback)
    if not src then return fallback end

    if src.Rotation then return src.Rotation end

    if src.rotation and type(src.rotation) ~= 'number' then
        if src.rotation.rotation then return src.rotation.rotation end
        return src.rotation
    end
    if src.position and src.position.rotation then return src.position.rotation end
    if src.Position and src.Position.rotation then return src.Position.rotation end
    if src.Position and src.Position.Rotation then return src.Position.Rotation end

    return fallback
end

local function buildPropConfig(bag)
    local props = BackPacks.Bags and BackPacks.Bags.Props or {}
    if not props.Enabled then return nil end
    local src = bag.prop or props.Default
    if not src then return nil end
    return {
        Model = src.Model or src.model or src.prop,
        Bone = src.Bone or src.bone or "CP_Back",
        Position = normalizeNestedPosition(src.Position or src.position, { x = 0.18, y = -0.18, z = -0.02 }),
        Rotation = normalizeNestedRotation(src, { x = -70.0, y = 0.0, z = -90.0 }),
    }
end

local function syncBagProp(source)
    if not BackPacks.Bags or not BackPacks.Bags.Props or not BackPacks.Bags.Props.Enabled then
        TriggerClientEvent("vorp_inventory:client:clearBagProp", source)
        return
    end
    local active = getActiveBags(source)
    if active and active[1] then
        TriggerClientEvent("vorp_inventory:client:setBagProp", source, buildPropConfig(active[1].config), active[1].config.label or active[1].name)
    else
        TriggerClientEvent("vorp_inventory:client:clearBagProp", source)
    end
end

function BagService.SyncBagProp(source)
    syncBagProp(source)
end

function BagService.SyncBagPropDelayed(source, delay)
    local src = tonumber(source)
    if not src then return end
    SetTimeout(tonumber(delay or 250) or 250, function()
        syncBagProp(src)
    end)
end

function BagService.SyncBagPropAfterInventoryChange(source)
    BagService.SyncBagPropDelayed(source, 150)
    BagService.SyncBagPropDelayed(source, 500)
    BagService.SyncBagPropDelayed(source, 1000)
    BagService.SyncBagPropDelayed(source, 1800)
end

local function notify(source, msg)
    Core.NotifyRightTip(source, msg, 3000)
end

local function toggleBag(args)
    local source = args.source
    local character = getChar(source)
    if not character then return end
    local itemData = args.item
    local itemId = tonumber(itemData.id or itemData.mainid)
    local inv = getInventory(character.identifier)
    local item = inv[itemId]
    if not item then return end
    local bag = isBagItem(item:getName())
    if not bag then return end
    if not hasJob(character, bag.jobs) then
        notify(source, T("bag_cannot_use"))
        return
    end

    if getBagMode(bag) == "container" then
        local meta = item:getMetadata() or {}
        if not meta.bagId or meta.bagId == "" then
            meta.bagId = tostring(item:getId())
            DBService.SetItemMetadata(character.charIdentifier, item:getId(), meta)
            item:setMetadata(meta)
            TriggerClientEvent("vorpCoreClient:SetItemMetadata", source, item:getId(), meta)
        end
        local invId = "bp_" .. tostring(meta.bagId)
        ensureBackpackInv(invId, bag)
        invalidateContainerCache(source)
        updateBagLoadMetadata(invId)
        exports.vorp_inventory:openInventory(source, invId)
        return
    end

    local meta = item:getMetadata() or {}
    local willEquip = meta.equipped ~= true

    if willEquip and BackPacks.Bags.AllowOnlyOneActiveBag then
        for _, other in pairs(inv) do
            if tonumber(other:getId()) ~= tonumber(item:getId()) and isBagItem(other:getName()) then
                local om = other:getMetadata() or {}
                if om.equipped then
                    local ok, msg = BagService.CanUnequipBagItem(source, other:getId())
                    if not ok then
                        notify(source, msg or T("bag_reduce_weight_switch"))
                        return
                    end
                    om.equipped = false
                    DBService.SetItemMetadata(character.charIdentifier, other:getId(), om)
                    other:setMetadata(om)
                    TriggerClientEvent("vorpCoreClient:SetItemMetadata", source, other:getId(), om)
                end
            end
        end
    elseif not willEquip then
        local ok, msg = BagService.CanUnequipBagItem(source, item:getId())
        if not ok then
            notify(source, msg or T("bag_reduce_weight_unequip"))
            return
        end
    end

    meta.equipped = willEquip
    meta.description = meta.description or (bag.label or item:getLabel())
    DBService.SetItemMetadata(character.charIdentifier, item:getId(), meta)
    item:setMetadata(meta)
    TriggerClientEvent("vorpCoreClient:SetItemMetadata", source, item:getId(), meta)
    local bagLabel = bag.label or item:getLabel()
    notify(source, T(willEquip and "bag_equipped" or "bag_unequipped", bagLabel))
    TriggerClientEvent("vorp_inventory:ReloadInv", source)
    syncBagProp(source)
end

AddEventHandler("vorp_inventory:Server:OnItemRemoved", function(data, src)
    if not data or not src then return end
    if isBagItem(data.name) then
        BagService.SyncBagPropDelayed(src, 350)
    end
end)


AddEventHandler("vorp_inventory:Server:OnItemCreated", function(data, src)
    if not data or not src then return end
    if isBagItem(data.name) then
        BagService.SyncBagPropDelayed(src, 350)
        BagService.SyncBagPropDelayed(src, 1000)
    end
end)

RegisterServerEvent("vorp_inventory:server:syncBagProp", function()
    syncBagProp(source)
end)

CreateThread(function()
    Wait(1000)
    if not BackPacks.Bags or not BackPacks.Bags.Enabled or not BackPacks.Bags.Items then return end
    for itemName, _ in pairs(BackPacks.Bags.Items) do
        InventoryAPI.registerUsableItem(itemName, toggleBag, GetCurrentResourceName())
    end
end)
