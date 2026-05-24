local Core <const> = exports.vorp_core:GetCore()

ShopService = {}

local ShopCache  = {}
local ViewerShop = {} -- [source] = shopId (set while a player has a shop UI open)

local function notify(src, msg, ms)
    if not src or not msg then return end
    Core.NotifyRightTip(src, tostring(msg), ms or 3500)
end

local function defOrDefault(def, key)
    if def[key] ~= nil then return def[key] end
    return Shops.Defaults[key]
end

local function isFeatureOn(name)
    return Shops.Features and Shops.Features[name] == true
end

local function findDef(shopId)
    if not Shops.List then return nil end
    for _, d in ipairs(Shops.List) do
        if d.id == shopId then return d end
    end
    return nil
end

local function getChar(src)
    local user = Core.getUser(src)
    if not user then return nil end
    return user.getUsedCharacter
end

local function isOwner(shop, charid)
    if not shop or not shop.row then return false end
    return shop.row.owner_charid ~= nil and tonumber(shop.row.owner_charid) == tonumber(charid)
end

local function hasPerm(shop, charid, mask)
    if isOwner(shop, charid) then return true end
    local perms = shop.employees[tonumber(charid)]
    if not perms then return false end
    return (perms & mask) == mask
end

local function getInGameHour()
    if GetResourceState("weathersync") == "started" then
        local ok, t = pcall(function() return exports.weathersync:getTime() end)
        if ok and t and t.hour then return tonumber(t.hour) or 12 end
    end
    return tonumber(os.date("%H")) or 12
end

local function isShopOpen(shop)
    if not isFeatureOn("OpeningHours") then return true end
    local def = shop.def
    if shop.row and shop.row.force_closed and tonumber(shop.row.force_closed) == 1 then
        return false
    end
    local enforce = (shop.row and shop.row.enforce_hours ~= nil) and tonumber(shop.row.enforce_hours) == 1 or defOrDefault(def, "enforceHours")
    if not enforce then return true end
    local openH  = (shop.row and shop.row.open_hour) or defOrDefault(def, "openHour")
    local closeH = (shop.row and shop.row.close_hour) or defOrDefault(def, "closeHour")
    local hour = getInGameHour()
    if openH == closeH then return true end
    if openH < closeH then
        return hour >= openH and hour < closeH
    else -- overnight wrap (e.g. 22 -> 4)
        return hour >= openH or hour < closeH
    end
end

local function colorForKind(kind)
    local hook = Logs and Logs.ShopWebHook
    if not hook then return 0 end
    local map = {
        buy       = hook.colorBuy,
        sell      = hook.colorSell,
        restock   = hook.colorRestock,
        wd_stock  = hook.colorWithdraw,
        withdraw  = hook.colorWithdraw,
        purchase  = hook.colorPurchase,
        assign    = hook.colorAdmin,
        employee  = hook.colorAdmin,
        reset     = hook.colorAdmin,
        price     = hook.colorPrices,
        hours     = hook.colorHours,
        forced    = hook.colorHours,
    }
    return map[kind] or 0
end

local function describeActor(src, charid)
    if src and tonumber(src) > 0 then
        local user = Core.getUser(src)
        if user then
            local c = user.getUsedCharacter
            return string.format("%s %s", c.firstname or "", c.lastname or ""), GetPlayerName(src) or "n/a"
        end
    end
    if charid then
        local row = MySQL.single.await("SELECT firstname, lastname FROM characters WHERE charidentifier=@c;", { c = tonumber(charid) })
        if row then return string.format("%s %s", row.firstname or "", row.lastname or ""), "offline" end
    end
    return "Unknown", "n/a"
end

local function logEvent(shopId, kind, src, charid, payload)
    if not isFeatureOn("TransactionLog") then return end
    local hook = Logs and Logs.ShopWebHook
    if not hook or not hook.Active or not hook.webhook or hook.webhook == "" then return end

    local shop = ShopCache[shopId]
    local shopName = shop and shop.def and shop.def.name or shopId
    local actor, steam = describeActor(src, charid)
    payload = payload or {}

    local lang = (T("WebHookLang") and type(T("WebHookLang")) == "table") and T("WebHookLang") or {}
    local title = (lang["shop_" .. kind]) or (hook.TitleFallback and hook.TitleFallback[kind]) or ("Shop Event: " .. kind)

    local lines = {
        string.format("**%s:** `%s` (`%s`)", lang.shop_shop or "Shop", shopName, shopId),
        string.format("**%s:** `%s` — `%s`", lang.charname or "Player", actor, steam ~= "n/a" and steam or ""),
    }
    if payload.item then
        lines[#lines+1] = string.format("**%s:** `%s` x `%s`", lang.item or "Item", tostring(payload.item), tostring(payload.qty or 1))
    end
    if payload.price ~= nil then
        lines[#lines+1] = string.format("**%s:** `$%s`", lang.amount or "Amount", tostring(payload.price))
    end
    if payload.balance ~= nil then
        lines[#lines+1] = string.format("**%s:** `$%s`", lang.shop_balance or "Balance", tostring(payload.balance))
    end
    if payload.target then
        lines[#lines+1] = string.format("**%s:** `%s`", lang.shop_target or "Target", tostring(payload.target))
    end
    if payload.perms ~= nil then
        lines[#lines+1] = string.format("**%s:** `%s`", lang.shop_perms or "Permissions", tostring(payload.perms))
    end
    if payload.extra then
        lines[#lines+1] = tostring(payload.extra)
    end

    local info = {
        source      = src or 0,
        title       = title,
        name        = hook.webhookname or "SHOP LOGS",
        description = table.concat(lines, "\n"),
        webhook     = hook.webhook,
        color       = colorForKind(kind),
        logo        = hook.logo,
        footerlogo  = hook.footerlogo,
        avatar      = hook.avatar,
    }
    SvUtils.SendDiscordWebhook(info)
end

local function loadShop(def)
    local row = MySQL.single.await("SELECT * FROM vorp_shops WHERE id=@id;", { id = def.id })
    if not row then
        MySQL.insert.await("INSERT INTO vorp_shops (id, balance) VALUES (@id, 0);", { id = def.id })
        row = MySQL.single.await("SELECT * FROM vorp_shops WHERE id=@id;", { id = def.id })
    end

    local stockRows = MySQL.query.await("SELECT item, qty, buy_price, sell_price FROM vorp_shop_stock WHERE shop_id=@id;", { id = def.id }) or {}
    local stock = {}
    for _, r in ipairs(stockRows) do
        stock[r.item] = { qty = tonumber(r.qty) or 0, buy_price = tonumber(r.buy_price) or 0, sell_price = tonumber(r.sell_price) or 0 }
    end

    local configItems = {}
    if def.stock then
        for _, s in ipairs(def.stock) do configItems[s.item] = true end
    end
    for itemName in pairs(stock) do
        if not configItems[itemName] then
            MySQL.update.await("DELETE FROM vorp_shop_stock WHERE shop_id=@s AND item=@i;", { s = def.id, i = itemName })
            stock[itemName] = nil
        end
    end

    if def.stock then
        for _, s in ipairs(def.stock) do
            if not stock[s.item] then
                local qty = (def.type == "npc") and 0 or (tonumber(s.stock) or 0)
                MySQL.insert.await("INSERT INTO vorp_shop_stock (shop_id, item, qty, buy_price, sell_price) VALUES (@s,@i,@q,@b,@l);", {
                    s = def.id, i = s.item, q = qty, b = tonumber(s.price) or 0, l = tonumber(s.sellPrice) or 0
                })
                stock[s.item] = { qty = qty, buy_price = tonumber(s.price) or 0, sell_price = tonumber(s.sellPrice) or 0 }
            end
        end
    end

    if def.type == "npc" and def.stock then
        for _, s in ipairs(def.stock) do
            local entry = stock[s.item]
            local cfgBuy  = tonumber(s.price) or 0
            local cfgSell = tonumber(s.sellPrice) or 0
            if entry and (entry.buy_price ~= cfgBuy or entry.sell_price ~= cfgSell) then
                entry.buy_price  = cfgBuy
                entry.sell_price = cfgSell
                MySQL.update.await("UPDATE vorp_shop_stock SET buy_price=@b, sell_price=@l WHERE shop_id=@s AND item=@i;",
                    { b = cfgBuy, l = cfgSell, s = def.id, i = s.item })
            end
        end
    end

    local empRows = MySQL.query.await("SELECT charid, perms FROM vorp_shop_employees WHERE shop_id=@id;", { id = def.id }) or {}
    local employees = {}
    for _, e in ipairs(empRows) do
        employees[tonumber(e.charid)] = tonumber(e.perms) or 0
    end

    ShopCache[def.id] = {
        def = def,
        row = row,
        stock = stock,
        employees = employees,
        currentViewer = nil,
    }
end

function ShopService.LoadAll()
    if not Shops.List then return end
    for _, def in ipairs(Shops.List) do
        local ok, err = pcall(loadShop, def)
        if not ok then
            print("^1[vorp_inventory][shops]^7 failed to load shop '" .. tostring(def.id) .. "': " .. tostring(err))
        end
    end
    print("^2[vorp_inventory][shops]^7 loaded " .. tostring(#Shops.List) .. " shops")
end

local function shopRole(shop, charid)
    if isOwner(shop, charid) then return "owner" end
    if shop.employees[tonumber(charid)] then return "employee" end
    return "customer"
end

local function buildItemListForUI(shop)
    local list = {}
    local infinite = (shop.def.type == "npc")
    local seen = {}
    local slot = 1
    if shop.def.stock then
        for _, s in ipairs(shop.def.stock) do
            local entry = shop.stock[s.item]
            if entry then
                local itemRow = ServerItems[s.item] or {}
                table.insert(list, {
                    name       = s.item,
                    label      = itemRow.label or s.item,
                    desc       = itemRow.desc or "",
                    type       = "item_standard",
                    weight     = 0,
                    count      = infinite and 999 or entry.qty,
                    buy_price  = entry.buy_price,
                    sell_price = entry.sell_price,
                    infinite   = infinite,
                    slot       = slot,
                    group      = 1,
                    canRemove  = false,
                    canUse     = false,
                })
                seen[s.item] = true
                slot = slot + 1
            end
        end
    end
    for item, entry in pairs(shop.stock) do
        if not seen[item] then
            local itemRow = ServerItems[item] or {}
            table.insert(list, {
                name       = item,
                label      = itemRow.label or item,
                desc       = itemRow.desc or "",
                type       = "item_standard",
                weight     = 0,
                count      = infinite and 999 or entry.qty,
                buy_price  = entry.buy_price,
                sell_price = entry.sell_price,
                infinite   = infinite,
                slot       = slot,
                group      = 1,
                canRemove  = false,
                canUse     = false,
            })
            slot = slot + 1
        end
    end
    return list
end

local function buildPayload(shop, charid, role)
    return {
        id          = shop.def.id,
        name        = shop.def.name,
        type        = shop.def.type,
        capacity    = defOrDefault(shop.def, "capacity"),
        role        = role,
        isOpen      = isShopOpen(shop),
        balance     = tonumber(shop.row.balance) or 0,
        openHour    = (shop.row and shop.row.open_hour) or defOrDefault(shop.def, "openHour"),
        closeHour   = (shop.row and shop.row.close_hour) or defOrDefault(shop.def, "closeHour"),
        enforceHours = ((shop.row and shop.row.enforce_hours ~= nil) and tonumber(shop.row.enforce_hours) == 1) or defOrDefault(shop.def, "enforceHours"),
        forceClosed = shop.row and tonumber(shop.row.force_closed) == 1 or false,
        buyback     = (defOrDefault(shop.def, "buyback") and isFeatureOn("BuybackFromPlayer")),
        ownerCharId = shop.row and tonumber(shop.row.owner_charid) or nil,
        purchasable = isFeatureOn("PlayerOwnership") and (defOrDefault(shop.def, "purchasable") ~= false) and (shop.row.owner_charid == nil) and shop.def.type == "player",
        purchasePrice = defOrDefault(shop.def, "purchasePrice"),
        features    = Shops.Features,
        empPerms    = Shops.EmployeePerms,
        items       = buildItemListForUI(shop),
    }
end

function ShopService.Get(shopId)
    return ShopCache[shopId]
end

function ShopService.GetAllForClient()
    local out = {}
    for _, def in ipairs(Shops.List or {}) do
        local shop = ShopCache[def.id]
        out[#out+1] = {
            id          = def.id,
            name        = def.name,
            type        = def.type,
            coord       = def.coord,
            ped         = def.ped,
            blip        = def.blip or Shops.Defaults.blip,
            interactDistance = defOrDefault(def, "interactDistance"),
            drawDistance     = defOrDefault(def, "drawDistance"),
            promptKey   = defOrDefault(def, "promptKey"),
            holdDuration= defOrDefault(def, "holdDuration"),
            owned       = shop and shop.row and shop.row.owner_charid ~= nil or false,
            purchasable = isFeatureOn("PlayerOwnership") and (defOrDefault(def, "purchasable") ~= false) and def.type == "player",
            purchasePrice = defOrDefault(def, "purchasePrice"),
        }
    end
    return out
end

function ShopService.Open(src, shopId)
    local shop = ShopCache[shopId]
    if not shop then return notify(src, T("shop_notfound")) end
    local char = getChar(src); if not char then return end
    local charid = char.charIdentifier

    if shop.def.type == "npc" and shop.def.jobs and shop.def.jobs ~= "all" then
        local ok = false
        for _, j in ipairs(shop.def.jobs) do if j == char.job then ok = true break end end
        if not ok then return notify(src, T("shop_no_browse_perm")) end
    end

    local role = shopRole(shop, charid)

    if role == "customer" and not isShopOpen(shop) then
        return notify(src, T("shop_closed"))
    end

    if shop.def.type == "player" and shop.currentViewer and shop.currentViewer ~= src then
        return notify(src, T("shop_in_use"))
    end
    shop.currentViewer = src
    ViewerShop[src] = shopId

    local payload = buildPayload(shop, charid, role)
    TriggerClientEvent("vorp_inventory:Shop:Open", src, payload)
end

function ShopService.Close(src)
    local shopId = ViewerShop[src]
    if not shopId then return end
    local shop = ShopCache[shopId]
    if shop and shop.currentViewer == src then shop.currentViewer = nil end
    ViewerShop[src] = nil
end

local function refresh(src, shop, charid)
    local payload = buildPayload(shop, charid, shopRole(shop, charid))
    TriggerClientEvent("vorp_inventory:Shop:Refresh", src, payload)
end

function ShopService.Buy(src, shopId, itemName, qty)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    local char = getChar(src); if not char then return end
    qty = math.max(1, math.floor(tonumber(qty) or 1))

    if shopRole(shop, char.charIdentifier) ~= "owner" and not isShopOpen(shop) then
        return notify(src, T("shop_closed"))
    end

    local entry = shop.stock[itemName]
    if not entry then return notify(src, T("shop_item_unavailable")) end
    if entry.buy_price <= 0 then return notify(src, T("shop_not_for_sale")) end

    local infinite = (shop.def.type == "npc")
    if not infinite and entry.qty < qty then
        return notify(src, T("shop_not_enough_stock"))
    end

    local total = entry.buy_price * qty
    if (char.money or 0) < total then
        return notify(src, T("shop_not_enough_money"))
    end

    local canCarry = false
    exports.vorp_inventory:canCarryItem(src, itemName, qty, function(can) canCarry = can end)
    Wait(0)
    if not canCarry then return notify(src, T("shop_cant_carry")) end

    char.removeCurrency(0, total)

    exports.vorp_inventory:addItem(src, itemName, qty, {})

    if not infinite then
        entry.qty = entry.qty - qty
        MySQL.update("UPDATE vorp_shop_stock SET qty=@q WHERE shop_id=@s AND item=@i;", { q = entry.qty, s = shopId, i = itemName })
    end
    if isFeatureOn("ShopBalance") and shop.row.owner_charid ~= nil then
        shop.row.balance = (tonumber(shop.row.balance) or 0) + total
        MySQL.update("UPDATE vorp_shops SET balance=@b WHERE id=@s;", { b = shop.row.balance, s = shopId })
    end

    logEvent(shopId, "buy", src, char.charIdentifier, { item = itemName, qty = qty, price = total, balance = shop.row.balance })
    notify(src, T("shop_purchased", qty, itemName, total), 2500)
    refresh(src, shop, char.charIdentifier)
end

function ShopService.Sell(src, shopId, itemName, qty)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    if not isFeatureOn("BuybackFromPlayer") or not defOrDefault(shop.def, "buyback") then
        return notify(src, T("shop_no_buyback"))
    end
    local char = getChar(src); if not char then return end
    qty = math.max(1, math.floor(tonumber(qty) or 1))

    if shopRole(shop, char.charIdentifier) ~= "owner" and not isShopOpen(shop) then
        return notify(src, T("shop_closed"))
    end

    local entry = shop.stock[itemName]
    if not entry then return notify(src, T("shop_item_not_accepted")) end
    if entry.sell_price <= 0 then return notify(src, T("shop_item_no_buyback")) end

    local playerItem = exports.vorp_inventory:getItem(src, itemName)
    if not playerItem or (playerItem.count or 0) < qty then
        return notify(src, T("shop_dont_have_many"))
    end

    local payout = entry.sell_price * qty

    local needsBalance = (shop.def.type == "player") and isFeatureOn("ShopBalance")
    if needsBalance and (tonumber(shop.row.balance) or 0) < payout then
        return notify(src, T("shop_cant_afford_buyback"))
    end

    exports.vorp_inventory:subItem(src, itemName, qty, playerItem.metadata)
    char.addCurrency(0, payout)
    if shop.def.type ~= "npc" then
        entry.qty = (entry.qty or 0) + qty
        MySQL.update("UPDATE vorp_shop_stock SET qty=@q WHERE shop_id=@s AND item=@i;", { q = entry.qty, s = shopId, i = itemName })
    end
    if needsBalance then
        shop.row.balance = (tonumber(shop.row.balance) or 0) - payout
        MySQL.update("UPDATE vorp_shops SET balance=@b WHERE id=@s;", { b = shop.row.balance, s = shopId })
    end

    logEvent(shopId, "sell", src, char.charIdentifier, { item = itemName, qty = qty, price = payout, balance = shop.row.balance })
    notify(src, T("shop_sold", qty, itemName, payout), 2500)
    refresh(src, shop, char.charIdentifier)
end

function ShopService.Restock(src, shopId, itemName, qty)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    if shop.def.type == "npc" then return notify(src, T("shop_npc_no_restock")) end
    local char = getChar(src); if not char then return end
    if not hasPerm(shop, char.charIdentifier, Shops.EmployeePerms.RESTOCK) then
        return notify(src, T("shop_no_restock_perm"))
    end
    qty = math.max(1, math.floor(tonumber(qty) or 1))

    local playerItem = exports.vorp_inventory:getItem(src, itemName)
    if not playerItem or (playerItem.count or 0) < qty then
        return notify(src, T("shop_dont_have_many"))
    end

    local entry = shop.stock[itemName]
    if not entry then
        entry = { qty = 0, buy_price = 0, sell_price = 0 }
        shop.stock[itemName] = entry
        MySQL.insert("INSERT INTO vorp_shop_stock (shop_id, item, qty, buy_price, sell_price) VALUES (@s,@i,0,0,0);", { s = shopId, i = itemName })
    end

    exports.vorp_inventory:subItem(src, itemName, qty, playerItem.metadata)
    entry.qty = (entry.qty or 0) + qty
    MySQL.update("UPDATE vorp_shop_stock SET qty=@q WHERE shop_id=@s AND item=@i;", { q = entry.qty, s = shopId, i = itemName })

    logEvent(shopId, "restock", src, char.charIdentifier, { item = itemName, qty = qty })
    notify(src, T("shop_stocked", qty, itemName), 2000)
    refresh(src, shop, char.charIdentifier)
end

function ShopService.WithdrawStock(src, shopId, itemName, qty)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    if shop.def.type == "npc" then return notify(src, T("shop_npc_no_stock_wd")) end
    local char = getChar(src); if not char then return end
    if not hasPerm(shop, char.charIdentifier, Shops.EmployeePerms.RESTOCK) then
        return notify(src, T("shop_no_perm"))
    end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local entry = shop.stock[itemName]
    if not entry or entry.qty < qty then return notify(src, T("shop_not_enough_stock")) end

    local canCarry = false
    exports.vorp_inventory:canCarryItem(src, itemName, qty, function(can) canCarry = can end)
    Wait(0)
    if not canCarry then return notify(src, T("shop_cant_carry")) end

    exports.vorp_inventory:addItem(src, itemName, qty, {})
    entry.qty = entry.qty - qty
    MySQL.update("UPDATE vorp_shop_stock SET qty=@q WHERE shop_id=@s AND item=@i;", { q = entry.qty, s = shopId, i = itemName })

    logEvent(shopId, "wd_stock", src, char.charIdentifier, { item = itemName, qty = qty })
    refresh(src, shop, char.charIdentifier)
end

function ShopService.SetPrice(src, shopId, itemName, buyPrice, sellPrice)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    local char = getChar(src); if not char then return end
    if not hasPerm(shop, char.charIdentifier, Shops.EmployeePerms.SETPRICES) then
        return notify(src, T("shop_no_price_perm"))
    end
    if shop.def.type == "npc" then return notify(src, T("shop_npc_prices_fixed")) end
    local entry = shop.stock[itemName]
    if not entry then return notify(src, T("shop_item_not_in_shop")) end
    buyPrice  = math.max(0, math.floor(tonumber(buyPrice) or 0))
    sellPrice = math.max(0, math.floor(tonumber(sellPrice) or 0))
    entry.buy_price  = buyPrice
    entry.sell_price = sellPrice
    MySQL.update("UPDATE vorp_shop_stock SET buy_price=@b, sell_price=@l WHERE shop_id=@s AND item=@i;", { b = buyPrice, l = sellPrice, s = shopId, i = itemName })
    logEvent(shopId, "price", src, char.charIdentifier, { item = itemName, extra = string.format("buy=$%d sell=$%d", buyPrice, sellPrice) })
    refresh(src, shop, char.charIdentifier)
end

function ShopService.WithdrawBalance(src, shopId, amount)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    if not isFeatureOn("ShopBalance") then return end
    local char = getChar(src); if not char then return end
    if not hasPerm(shop, char.charIdentifier, Shops.EmployeePerms.WITHDRAW) then
        return notify(src, T("shop_no_withdraw_perm"))
    end
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    if (tonumber(shop.row.balance) or 0) < amount then return notify(src, T("shop_insufficient_balance")) end
    shop.row.balance = (tonumber(shop.row.balance) or 0) - amount
    MySQL.update("UPDATE vorp_shops SET balance=@b WHERE id=@s;", { b = shop.row.balance, s = shopId })
    char.addCurrency(0, amount)
    logEvent(shopId, "withdraw", src, char.charIdentifier, { price = amount, balance = shop.row.balance })
    notify(src, T("shop_withdrew", amount), 2000)
    refresh(src, shop, char.charIdentifier)
end

function ShopService.SetHours(src, shopId, openHour, closeHour, enforce)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    local char = getChar(src); if not char then return end
    if not hasPerm(shop, char.charIdentifier, Shops.EmployeePerms.HOURS) then
        return notify(src, T("shop_no_hours_perm"))
    end
    openHour  = math.max(0, math.min(23, math.floor(tonumber(openHour) or 0)))
    closeHour = math.max(0, math.min(23, math.floor(tonumber(closeHour) or 0)))
    local enforceI = enforce and 1 or 0
    MySQL.update("UPDATE vorp_shops SET open_hour=@o, close_hour=@c, enforce_hours=@e WHERE id=@s;", { o = openHour, c = closeHour, e = enforceI, s = shopId })
    shop.row.open_hour     = openHour
    shop.row.close_hour    = closeHour
    shop.row.enforce_hours = enforceI
    logEvent(shopId, "hours", src, char.charIdentifier, { extra = string.format("open=%02d close=%02d enforce=%s", openHour, closeHour, tostring(enforce and true or false)) })
    refresh(src, shop, char.charIdentifier)
end

function ShopService.SetForceClosed(src, shopId, forceClosed)
    local shop = ShopCache[shopId]; if not shop then return end
    if ViewerShop[src] ~= shopId then return end
    local char = getChar(src); if not char then return end
    if not isOwner(shop, char.charIdentifier) then return notify(src, T("shop_only_owner_toggle")) end
    local v = forceClosed and 1 or 0
    MySQL.update("UPDATE vorp_shops SET force_closed=@v WHERE id=@s;", { v = v, s = shopId })
    shop.row.force_closed = v
    logEvent(shopId, "forced", src, char.charIdentifier, { extra = (v == 1) and "force-closed" or "reopened" })
    refresh(src, shop, char.charIdentifier)
end

function ShopService.SetEmployee(src, shopId, targetCharId, perms)
    local shop = ShopCache[shopId]; if not shop then return end
    local char = getChar(src); if not char then return end
    if not isOwner(shop, char.charIdentifier) then return notify(src, T("shop_only_owner_employees")) end
    if not isFeatureOn("Employees") or not defOrDefault(shop.def, "allowEmployees") then
        return notify(src, T("shop_employees_disabled"))
    end
    targetCharId = tonumber(targetCharId)
    perms = math.max(0, math.floor(tonumber(perms) or 0))
    if not targetCharId then return notify(src, T("shop_invalid_character")) end
    if perms == 0 then
        MySQL.update("DELETE FROM vorp_shop_employees WHERE shop_id=@s AND charid=@c;", { s = shopId, c = targetCharId })
        shop.employees[targetCharId] = nil
        notify(src, T("shop_employee_removed"), 2000)
    else
        MySQL.update("INSERT INTO vorp_shop_employees (shop_id, charid, perms) VALUES (@s,@c,@p) ON DUPLICATE KEY UPDATE perms=@p;", { s = shopId, c = targetCharId, p = perms })
        shop.employees[targetCharId] = perms
        notify(src, T("shop_employee_updated"), 2000)
    end
    logEvent(shopId, "employee", src, char.charIdentifier, { target = "charid " .. tostring(targetCharId), perms = perms })
    if ViewerShop[src] == shopId then refresh(src, shop, char.charIdentifier) end
end

function ShopService.PurchaseShop(src, shopId)
    local shop = ShopCache[shopId]; if not shop then return end
    if not isFeatureOn("PlayerOwnership") then return notify(src, T("shop_ownership_disabled")) end
    if shop.def.type ~= "player" then return notify(src, T("shop_cant_be_owned")) end
    if defOrDefault(shop.def, "purchasable") == false then return notify(src, T("shop_not_for_sale_shop")) end
    if shop.row.owner_charid ~= nil then return notify(src, T("shop_already_owned")) end
    local char = getChar(src); if not char then return end
    local price = defOrDefault(shop.def, "purchasePrice")
    if (char.money or 0) < price then return notify(src, T("shop_cant_afford_shop", price)) end

    char.removeCurrency(0, price)
    MySQL.update.await("UPDATE vorp_shops SET owner_identifier=@id, owner_charid=@c WHERE id=@s;", {
        id = char.identifier, c = char.charIdentifier, s = shopId
    })
    shop.row.owner_identifier = char.identifier
    shop.row.owner_charid     = char.charIdentifier

    logEvent(shopId, "purchase", src, char.charIdentifier, { price = price })
    notify(src, T("shop_now_owner", shop.def.name), 4000)
    TriggerClientEvent("vorp_inventory:Shop:OwnershipChanged", -1, shopId, char.charIdentifier)

    if ViewerShop[src] == shopId then
        refresh(src, shop, char.charIdentifier)
    end
end

function ShopService.AdminSetOwner(src, shopId, targetCharId)
    local shop = ShopCache[shopId]; if not shop then return notify(src, T("shop_notfound")) end
    targetCharId = tonumber(targetCharId)
    if targetCharId == nil or targetCharId <= 0 then
        MySQL.update.await("UPDATE vorp_shops SET owner_identifier=NULL, owner_charid=NULL WHERE id=@s;", { s = shopId })
        shop.row.owner_identifier = nil
        shop.row.owner_charid     = nil
        notify(src, T("shop_owner_cleared", shopId), 3000)
    else
        local row = MySQL.single.await("SELECT identifier FROM characters WHERE charidentifier=@c;", { c = targetCharId })
        if not row then return notify(src, T("shop_character_not_found")) end
        MySQL.update.await("UPDATE vorp_shops SET owner_identifier=@id, owner_charid=@c WHERE id=@s;", { id = row.identifier, c = targetCharId, s = shopId })
        shop.row.owner_identifier = row.identifier
        shop.row.owner_charid     = targetCharId
        notify(src, T("shop_owner_set", shopId, targetCharId), 3000)
    end
    logEvent(shopId, "assign", src, nil, { target = "charid " .. tostring(targetCharId or 0) })
    TriggerClientEvent("vorp_inventory:Shop:OwnershipChanged", -1, shopId, shop.row.owner_charid)
end

function ShopService.Reset(src, shopId)
    local shop = ShopCache[shopId]; if not shop then return notify(src, T("shop_notfound")) end
    MySQL.update.await("UPDATE vorp_shops SET owner_identifier=NULL, owner_charid=NULL, balance=0, open_hour=NULL, close_hour=NULL, enforce_hours=NULL, force_closed=0 WHERE id=@s;", { s = shopId })
    MySQL.update.await("DELETE FROM vorp_shop_employees WHERE shop_id=@s;", { s = shopId })
    MySQL.update.await("DELETE FROM vorp_shop_stock WHERE shop_id=@s;", { s = shopId })
    ShopCache[shopId] = nil
    loadShop(shop.def)
    logEvent(shopId, "reset", src, nil, nil)
    notify(src, T("shop_reset", shopId), 3000)
    TriggerClientEvent("vorp_inventory:Shop:OwnershipChanged", -1, shopId, nil)
end

exports("getShopService", function() return ShopService end)
