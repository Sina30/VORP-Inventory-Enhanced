if not Shops or not Shops.Enabled then
    return
end

RegisterNetEvent("vorp_inventory:Shop:List", function(list)
    ShopClient.list = list or {}
end)

RegisterNetEvent("vorp_inventory:Shop:Open", function(payload)
    ShopClient.OpenUI(payload)
end)

RegisterNetEvent("vorp_inventory:Shop:Refresh", function(payload)
    ShopClient.Refresh(payload)
end)

RegisterNetEvent("vorp_inventory:Shop:OwnershipChanged", function(shopId, ownerCharId)
    ShopClient.UpdateListEntry(shopId, ownerCharId)
end)

RegisterNUICallback('ShopBuy', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:Buy", data.shopId, data.item, tonumber(data.qty) or 1)
    cb({})
end)

RegisterNUICallback('ShopSell', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:Sell", data.shopId, data.item, tonumber(data.qty) or 1)
    cb({})
end)

RegisterNUICallback('ShopRestock', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:Restock", data.shopId, data.item, tonumber(data.qty) or 1)
    cb({})
end)

RegisterNUICallback('ShopWithdrawStock', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:WithdrawStock", data.shopId, data.item, tonumber(data.qty) or 1)
    cb({})
end)

RegisterNUICallback('ShopSetPrice', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:SetPrice", data.shopId, data.item, tonumber(data.buyPrice) or 0, tonumber(data.sellPrice) or 0)
    cb({})
end)

RegisterNUICallback('ShopWithdrawBalance', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:WithdrawBalance", data.shopId, tonumber(data.amount) or 0)
    cb({})
end)

RegisterNUICallback('ShopSetHours', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:SetHours", data.shopId, tonumber(data.openHour) or 0, tonumber(data.closeHour) or 0, data.enforce == true)
    cb({})
end)

RegisterNUICallback('ShopSetForceClosed', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:SetForceClosed", data.shopId, data.force == true)
    cb({})
end)

RegisterNUICallback('ShopSetEmployee', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:SetEmployee", data.shopId, tonumber(data.charid) or 0, tonumber(data.perms) or 0)
    cb({})
end)

RegisterNUICallback('ShopPurchase', function(data, cb)
    TriggerServerEvent("vorp_inventory:Shop:Purchase", data.shopId)
    cb({})
end)

RegisterNUICallback('ShopClose', function(_, cb)
    TriggerServerEvent("vorp_inventory:Shop:Close")
    ShopClient.CloseUI()
    cb({})
end)
