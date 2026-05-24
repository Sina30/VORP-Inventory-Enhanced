if not Shops or not Shops.Enabled then
    return
end

local Core <const> = exports.vorp_core:GetCore()

CreateThread(function()
    Wait(2500)
    ShopService.LoadAll()
end)

RegisterNetEvent("vorp_inventory:Shop:RequestList", function()
    local _src = source
    TriggerClientEvent("vorp_inventory:Shop:List", _src, ShopService.GetAllForClient())
end)

AddEventHandler("playerDropped", function()
    local _src = source
    if _src then ShopService.Close(_src) end
end)

RegisterNetEvent("vorp_inventory:Shop:Open", function(shopId)
    ShopService.Open(source, shopId)
end)

RegisterNetEvent("vorp_inventory:Shop:Close", function()
    ShopService.Close(source)
end)

RegisterNetEvent("vorp_inventory:Shop:Buy", function(shopId, item, qty)
    ShopService.Buy(source, shopId, item, qty)
end)

RegisterNetEvent("vorp_inventory:Shop:Sell", function(shopId, item, qty)
    ShopService.Sell(source, shopId, item, qty)
end)

RegisterNetEvent("vorp_inventory:Shop:Purchase", function(shopId)
    ShopService.PurchaseShop(source, shopId)
end)

RegisterNetEvent("vorp_inventory:Shop:Restock", function(shopId, item, qty)
    ShopService.Restock(source, shopId, item, qty)
end)
RegisterNetEvent("vorp_inventory:Shop:WithdrawStock", function(shopId, item, qty)
    ShopService.WithdrawStock(source, shopId, item, qty)
end)
RegisterNetEvent("vorp_inventory:Shop:SetPrice", function(shopId, item, buyPrice, sellPrice)
    ShopService.SetPrice(source, shopId, item, buyPrice, sellPrice)
end)
RegisterNetEvent("vorp_inventory:Shop:WithdrawBalance", function(shopId, amount)
    ShopService.WithdrawBalance(source, shopId, amount)
end)
RegisterNetEvent("vorp_inventory:Shop:SetHours", function(shopId, openHour, closeHour, enforce)
    ShopService.SetHours(source, shopId, openHour, closeHour, enforce)
end)
RegisterNetEvent("vorp_inventory:Shop:SetForceClosed", function(shopId, force)
    ShopService.SetForceClosed(source, shopId, force)
end)
RegisterNetEvent("vorp_inventory:Shop:SetEmployee", function(shopId, charid, perms)
    ShopService.SetEmployee(source, shopId, charid, perms)
end)


local function isAdmin(src)
    -- ACE
    if Shops.AdminAceGroups then
        for _, g in ipairs(Shops.AdminAceGroups) do
            if IsPlayerAceAllowed(src, g) then return true end
        end
    end
    -- VORP groups
    if Shops.AdminVorpGroups then
        local user = Core.getUser(src)
        if user then
            local g = user.getGroup
            for _, allowed in ipairs(Shops.AdminVorpGroups) do
                if g == allowed then return true end
            end
        end
    end
    return false
end

local function notify(src, msg)
    Core.NotifyRightTip(src, tostring(msg), 4000)
end

-- /shopowner <shopId> <charid|0>   (0 clears ownership)
RegisterCommand("shopowner", function(src, args)
    if src == 0 then
        -- console
    elseif not isAdmin(src) then
        return notify(src, T("shop_admin_no_perm"))
    end
    local shopId = args[1]
    local charid = tonumber(args[2])
    if not shopId or charid == nil then
        if src == 0 then print("Usage: shopowner <shopId> <charid>  (charid 0 clears)") end
        return src ~= 0 and notify(src, T("shop_usage_owner")) or nil
    end
    ShopService.AdminSetOwner(src, shopId, charid)
end, false)

-- /shopemployee <shopId> <charid> [perms]
RegisterCommand("shopemployee", function(src, args)
    if src == 0 then
    elseif not isAdmin(src) then
        return notify(src, T("shop_admin_no_perm"))
    end
    local shopId = args[1]
    local charid = tonumber(args[2])
    local perms  = args[3] and tonumber(args[3]) or Shops.DefaultEmployeePerms
    if not shopId or not charid then
        return src ~= 0 and notify(src, T("shop_usage_employee")) or print("Usage: shopemployee <shopId> <charid> [perms]")
    end
    if charid == 0 then
        MySQL.update.await("DELETE FROM vorp_shop_employees WHERE shop_id=@s;", { s = shopId })
        return notify(src, T("shop_employee_cleared", shopId))
    end
    if perms == 0 then
        MySQL.update.await("DELETE FROM vorp_shop_employees WHERE shop_id=@s AND charid=@c;", { s = shopId, c = charid })
    else
        MySQL.update.await("INSERT INTO vorp_shop_employees (shop_id, charid, perms) VALUES (@s,@c,@p) ON DUPLICATE KEY UPDATE perms=@p;", { s = shopId, c = charid, p = perms })
    end
    -- Refresh the in-memory cache
    local shop = ShopService.Get(shopId)
    if shop then
        if perms == 0 then shop.employees[charid] = nil else shop.employees[charid] = perms end
    end
    notify(src, T("shop_employee_updated_cmd", charid, shopId, perms))
end, false)

-- /shopreset <shopId>
RegisterCommand("shopreset", function(src, args)
    if src ~= 0 and not isAdmin(src) then return notify(src, T("shop_admin_no_perm")) end
    local shopId = args[1]
    if not shopId then return notify(src, T("shop_usage_reset")) end
    ShopService.Reset(src, shopId)
end, false)

-- Shop logs are sent to Discord via Logs.ShopWebHook (config/logs.lua).
-- The /shoplogs command was removed when DB logging was replaced with webhooks.
