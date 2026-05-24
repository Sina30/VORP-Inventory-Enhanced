Logs = {
    WebHook = {
        -- =================== INVENTORY LOGS =====================--

        webhookname             = "INVENTORY LOGS",
        webhook                 = "LOG URL HERR",

        --Gold Logs Color
        colorpickedgold         = 65280,
        colorgiveGold           = 4286945,
        colorDropGold           = 16711680,

        --Money log color
        colorgiveMoney          = 4286945,
        colormoneypickup        = 65280,
        colorDropMoney          = 16711680,

        --Item log color
        coloritemDrop           = 16711680,
        coloritempickup         = 65280,
        colorgiveitem           = 4286945,

        --Weapon log color
        colorweppickupd         = 65280,
        colorgiveWep            = 4286945,
        colordropedwep          = 16711680,
        -- =================== CUSTOM INVENTORY LOGS =====================--

        cuscolor                = 16711680,
        custitle                = "CUSTOM INV LOGS",
        cusavatar               = "",
        cuslogo                 = "",
        cusfooterlogo           = "",
        cuswebhookname          = "CUSTOM INV LOGS",
        CustomInventoryTakeFrom = "Took From LOG URL HERR ",
        CustomInventoryMoveTo   = "Moved Item To LOG URL HERR ",
    },


    -- =================== SHOP LOGS =====================--
    -- Sent by the shop system (config/shops.lua + server/services/shopService.lua).
    -- Set `Active = false` to silently skip every shop webhook without removing the URL.
    ShopWebHook = {
        Active        = true,
        webhook       = "",                -- Discord webhook URL
        webhookname   = "SHOP LOGS",       -- Bot/webhook author name
        avatar        = "",                -- Avatar URL (optional)
        logo          = "",                -- Embed image (optional)
        footerlogo    = "",                -- Footer image (optional)

        -- Per-event embed colors (decimal RGB)
        colorBuy      = 65280,             -- green   — customer purchases
        colorSell     = 16776960,          -- yellow  — customer sells to shop
        colorRestock  = 4286945,           -- blue    — owner/employee deposits stock
        colorWithdraw = 16711680,          -- red     — money or stock pulled out
        colorPurchase = 16753920,          -- orange  — player buys the shop
        colorAdmin    = 10038562,          -- purple  — /shopowner /shopreset / employee changes
        colorPrices   = 8421504,           -- grey    — price edits
        colorHours    = 8421504,           -- grey    — opening hours / force close

        -- Per-event titles. Localized at send time via T("WebHookLang").shop_*; these
        -- are only used as a fallback if the locale entry is missing.
        TitleFallback = {
            buy       = "Shop Purchase",
            sell      = "Shop Buyback",
            restock   = "Shop Restock",
            wd_stock  = "Stock Withdrawal",
            withdraw  = "Balance Withdrawal",
            purchase  = "Shop Ownership Bought",
            assign    = "Admin Owner Change",
            employee  = "Employee Permissions",
            reset     = "Shop Reset",
            price     = "Price Updated",
            hours     = "Hours Updated",
            forced    = "Force-Close Toggled",
        },
    },

    NetDupWebHook = {
        -- somone tries to use dev tools to cheat
        Active = true,
        color = 16711680,
        webhook = "",
        Language = {
            title = "Possible Cheater Detected",
            descriptionstart = "Invalid NUI Callback performed by...\n **Playername** `",
            descriptionend = "`\n"
        }
    },

}
