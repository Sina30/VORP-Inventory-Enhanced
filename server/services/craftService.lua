local Core = exports.vorp_core:GetCore()
local CraftData = {} -- charId -> { [slot] = { name, label, count, weight } }
local jsonPath = GetResourcePath(GetCurrentResourceName()) .. "/craft_inventories.json"

-- Load JSON
local function loadCraftData()
    local file = io.open(jsonPath, "r")
    if file then
        local content = file:read("*a")
        file:close()
        if content and content ~= "" then
            CraftData = json.decode(content) or {}
        end
    end
end

-- Save JSON
local function saveCraftData()
    local file = io.open(jsonPath, "w")
    if file then
        file:write(json.encode(CraftData))
        file:close()
    end
end

-- Load on start
loadCraftData()

local function getCharId(source)
    local user = Core.getUser(source)
    if not user then return nil end
    return tostring(user.getUsedCharacter.charIdentifier)
end

local function getPlayerCraftSlots(charId)
    if not CraftData[charId] then CraftData[charId] = {} end
    return CraftData[charId]
end

local function sendCraftToNUI(source, charId)
    local slots = getPlayerCraftSlots(charId)
    local items = {}
    for slotNum, slotData in pairs(slots) do
        items[#items + 1] = {
            slot = tonumber(slotNum),
            name = slotData.name,
            label = slotData.label,
            count = slotData.count,
            weight = slotData.weight,
        }
    end

    -- Check recipe match
    local matchedRecipe = nil
    local matchedRewardName = nil
    for rewardName, recipe in pairs(Config.CraftItems) do
        local allMet = true
        for _, req in ipairs(recipe.requiredItems) do
            local found = 0
            for _, item in pairs(slots) do
                if item.name == req.name then
                    found = found + item.count
                end
            end
            if found < req.requiredAmount then
                allMet = false
                break
            end
        end
        if allMet then
            matchedRecipe = recipe
            matchedRewardName = rewardName
            break
        end
    end

    local recipeData = nil
    if matchedRecipe and matchedRewardName then
        local svItem = ServerItems[matchedRewardName]
        recipeData = {
            rewardName = matchedRewardName,
            rewardLabel = svItem and svItem:getLabel() or matchedRewardName,
            rewardAmount = matchedRecipe.rewardAmount,
            rewardWeight = svItem and svItem:getWeight() or 0,
            timerForPerAmount = matchedRecipe.timerForPerAmount,
            requiredItems = {},
        }
        for _, req in ipairs(matchedRecipe.requiredItems) do
            local reqSvItem = ServerItems[req.name]
            recipeData.requiredItems[#recipeData.requiredItems + 1] = {
                name = req.name,
                label = reqSvItem and reqSvItem:getLabel() or req.name,
                weight = reqSvItem and reqSvItem:getWeight() or 0,
                requiredAmount = req.requiredAmount,
            }
        end
    end

    TriggerClientEvent("vorpInventory:setCraftItems", source, items, recipeData)
end

-- Get craft items
RegisterServerEvent("vorpinventory:getCraftItems")
AddEventHandler("vorpinventory:getCraftItems", function()
    local src = source
    local charId = getCharId(src)
    if not charId then return end
    sendCraftToNUI(src, charId)
end)

-- Add item from player to craft
RegisterServerEvent("vorpinventory:craftAddItem")
AddEventHandler("vorpinventory:craftAddItem", function(itemId, amount, targetSlot)
    local src = source
    local charId = getCharId(src)
    if not charId then return end

    local user = Core.getUser(src)
    local identifier = user.getUsedCharacter.identifier
    local charIdentifier = user.getUsedCharacter.charIdentifier
    local inv = UsersInventories.default[identifier]
    if not inv then return end

    local item = inv[tonumber(itemId)]
    if not item then return end
    if amount > item:getCount() then amount = item:getCount() end

    local slots = getPlayerCraftSlots(charId)

    -- Check if target slot has same item
    local targetKey = tostring(targetSlot)
    if slots[targetKey] and slots[targetKey].name == item:getName() then
        slots[targetKey].count = slots[targetKey].count + amount
    elseif not slots[targetKey] then
        slots[targetKey] = {
            name = item:getName(),
            label = item:getLabel(),
            count = amount,
            weight = item:getWeight() or 0,
        }
    else
        return -- different item at target slot
    end

    -- Remove from player inventory
    item:quitCount(amount)
    if item:getCount() <= 0 then
        DBService.DeleteItem(charIdentifier, item:getId())
        inv[tonumber(itemId)] = nil
    else
        DBService.SetItemAmount(charIdentifier, item:getId(), item:getCount())
    end

    saveCraftData()
    sendCraftToNUI(src, charId)
    TriggerClientEvent("vorp_inventory:ReloadInv", src)
end)

-- Remove item from craft to player
RegisterServerEvent("vorpinventory:craftRemoveItem")
AddEventHandler("vorpinventory:craftRemoveItem", function(fromSlot, amount, targetSlot)
    local src = source
    local charId = getCharId(src)
    if not charId then return end

    local slots = getPlayerCraftSlots(charId)
    local slotKey = tostring(fromSlot)
    if not slots[slotKey] then return end

    local slotData = slots[slotKey]
    if amount > slotData.count then amount = slotData.count end

    -- Check if player can carry
    local canCarry = InventoryAPI.canCarryItem(src, slotData.name, amount)
    if not canCarry then
        Core.NotifyRightTip(src, "Cannot carry this item", 2000)
        return
    end

    -- Add to player
    local user = Core.getUser(src)
    local charIdentifier = user.getUsedCharacter.charIdentifier
    local identifier = user.getUsedCharacter.identifier
    local svItem = ServerItems[slotData.name]
    if not svItem then return end

    -- Check target slot for stacking
    local inv = UsersInventories.default[identifier]
    local targetItem = nil
    if targetSlot and inv then
        for _, existingItem in pairs(inv) do
            if existingItem:getSlot() == targetSlot and existingItem:getName() == slotData.name then
                targetItem = existingItem
                break
            end
        end
    end

    if targetItem then
        targetItem:addCount(amount, true)
        DBService.SetItemAmount(charIdentifier, targetItem:getId(), targetItem:getCount())
    else
        DBService.CreateItem(charIdentifier, svItem:getId(), amount, {}, slotData.name, 0, function(result)
            if result and result.id then
                local newItem = Item:New({
                    count = amount, id = result.id, limit = svItem.limit, label = svItem.label,
                    metadata = {}, name = slotData.name, type = svItem.type,
                    canUse = svItem.canUse, canRemove = svItem.canRemove,
                    owner = charIdentifier, desc = svItem.desc, group = svItem.group,
                    weight = svItem.weight, slot = targetSlot,
                })
                if inv then inv[result.id] = newItem end
                if targetSlot then DBService.UpdateItemSlot(charIdentifier, result.id, targetSlot) end
            end
        end, "default")
    end

    -- Remove from craft
    slotData.count = slotData.count - amount
    if slotData.count <= 0 then
        slots[slotKey] = nil
    end

    saveCraftData()
    sendCraftToNUI(src, charId)
    TriggerClientEvent("vorp_inventory:ReloadInv", src)
end)

-- Craft swap slot
RegisterServerEvent("vorpinventory:craftSwapSlot")
AddEventHandler("vorpinventory:craftSwapSlot", function(fromSlot, toSlot)
    local src = source
    local charId = getCharId(src)
    if not charId then return end
    local slots = getPlayerCraftSlots(charId)
    local fromKey, toKey = tostring(fromSlot), tostring(toSlot)
    local temp = slots[fromKey]
    slots[fromKey] = slots[toKey]
    slots[toKey] = temp
    saveCraftData()
    sendCraftToNUI(src, charId)
end)

-- Craft merge slot
RegisterServerEvent("vorpinventory:craftMergeSlot")
AddEventHandler("vorpinventory:craftMergeSlot", function(fromSlot, toSlot, amount)
    local src = source
    local charId = getCharId(src)
    if not charId then return end
    local slots = getPlayerCraftSlots(charId)
    local fromKey, toKey = tostring(fromSlot), tostring(toSlot)
    if not slots[fromKey] or not slots[toKey] then return end
    if slots[fromKey].name ~= slots[toKey].name then return end

    local moveAmount = math.min(amount, slots[fromKey].count)
    slots[toKey].count = slots[toKey].count + moveAmount
    slots[fromKey].count = slots[fromKey].count - moveAmount
    if slots[fromKey].count <= 0 then slots[fromKey] = nil end

    saveCraftData()
    sendCraftToNUI(src, charId)
end)

-- Craft split slot
RegisterServerEvent("vorpinventory:craftSplitSlot")
AddEventHandler("vorpinventory:craftSplitSlot", function(fromSlot, toSlot, amount)
    local src = source
    local charId = getCharId(src)
    if not charId then return end
    local slots = getPlayerCraftSlots(charId)
    local fromKey, toKey = tostring(fromSlot), tostring(toSlot)
    if not slots[fromKey] or slots[toKey] then return end

    local moveAmount = math.min(amount, slots[fromKey].count)
    if moveAmount <= 0 or moveAmount >= slots[fromKey].count then return end

    slots[toKey] = {
        name = slots[fromKey].name,
        label = slots[fromKey].label,
        count = moveAmount,
        weight = slots[fromKey].weight,
    }
    slots[fromKey].count = slots[fromKey].count - moveAmount

    saveCraftData()
    sendCraftToNUI(src, charId)
end)

-- Start crafting
RegisterServerEvent("vorpinventory:startCraft")
AddEventHandler("vorpinventory:startCraft", function(rewardName, craftAmount)
    local src = source
    local charId = getCharId(src)
    if not charId then return end

    local recipe = Config.CraftItems[rewardName]
    if not recipe then return end
    craftAmount = craftAmount or 1

    local slots = getPlayerCraftSlots(charId)

    for _, req in ipairs(recipe.requiredItems) do
        local found = 0
        for _, item in pairs(slots) do
            if item.name == req.name then found = found + item.count end
        end
        if found < req.requiredAmount * craftAmount then return end
    end

    local totalTimer = recipe.timerForPerAmount * craftAmount

    TriggerClientEvent("vorpInventory:craftStarted", src, totalTimer)

    SetTimeout(totalTimer, function()
        for _, req in ipairs(recipe.requiredItems) do
            local remaining = req.requiredAmount * craftAmount
            local reqSvItem = ServerItems[req.name]
            for slotKey, item in pairs(slots) do
                if item.name == req.name and remaining > 0 then
                    local remove = math.min(remaining, item.count)
                    item.count = item.count - remove
                    remaining = remaining - remove
                    if item.count <= 0 then slots[slotKey] = nil end
                end
            end
            TriggerClientEvent("vorpInventory:itemNotify", src, "remove", req.name, reqSvItem and reqSvItem:getLabel() or req.name, req.requiredAmount * craftAmount)
        end

        local svItem = ServerItems[rewardName]
        local totalReward = recipe.rewardAmount * craftAmount
        if svItem then
            InventoryAPI.addItem(src, rewardName, totalReward)
        end

        saveCraftData()
        sendCraftToNUI(src, charId)
        TriggerClientEvent("vorpInventory:craftCompleted", src, rewardName)
        TriggerClientEvent("vorp_inventory:ReloadInv", src)
    end)
end)
