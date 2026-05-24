Shops = {}

Shops.Enabled                     = true

-- Master switches for major features (per-shop flags below can still narrow them).
Shops.Features = {
    PlayerOwnership   = true,   -- players can buy unowned shops in-game
    AdminAssignment   = true,   -- /shopowner <shopId> <playerId>
    Employees         = true,   -- owners can grant employee perms via /shopemployee
    BuybackFromPlayer = true,   -- shops can buy items from players (sell-to-shop)
    OpeningHours      = true,   -- in-game time gating
    NpcPed            = true,   -- spawn vendor peds + interaction prompts
    TransactionLog    = true,   -- log every buy/sell to vorp_shop_logs
    ShopBalance       = true,   -- accumulate revenue in shop balance; owner withdraws
}

-- Admin gating. Players in any of these ACE groups OR VORP groups can run /shop* admin commands.
Shops.AdminAceGroups   = { "admin", "group.admin" }
Shops.AdminVorpGroups  = { "admin", "mod" }

-- ============================== DEFAULTS =========================================
Shops.Defaults = {
    capacity        = 35,           -- slots in the shop panel (matches secondary inventory)
    purchasePrice   = 5000,         -- cost for a player to buy this shop (if Purchasable)
    purchasable     = true,         -- whether players can buy this shop in-game
    allowEmployees  = true,         -- whether owner can grant employee perms
    buyback         = true,         -- whether this shop buys items from players
    openHour        = 6,            -- 0-23, in-game hour at which shop opens
    closeHour       = 22,           -- 0-23, in-game hour at which shop closes
    enforceHours    = true,         -- if false, shop is always open
    drawDistance    = 25.0,         -- distance at which ped becomes visible
    interactDistance = 2.0,         -- distance for the prompt to appear
    promptKey       = 0xCEFD9220,   -- E key
    holdDuration    = 0,            -- 0 = press, >0 = hold ms
    blip = {
        enabled = true,
        sprite  = -776993475,       -- generic shop blip; override per shop
        scale   = 0.2,
        name    = "Shop",
    },
}

-- Prompt labels live in locales/locale.lua (ui.shop_prompt_browse/_purchase/_manage)
-- so they translate automatically. Do not redefine them here.

-- Bitmask values; combine in /shopemployee <shopId> <playerId> <permsInt>
-- ex /shopemployee valentine_general 123456 3  -- restock + set prices
Shops.EmployeePerms = {
    RESTOCK   = 1,  -- can deposit/remove stock
    SETPRICES = 2,  -- can change buy/sell prices
    WITHDRAW  = 4,  -- can withdraw from shop balance
    HOURS     = 8,  -- can change opening hours
}
-- Default perms granted by `/shopemployee` when no perms arg is provided.
Shops.DefaultEmployeePerms = 1

-- ============================== SHOP DEFINITIONS =================================
-- type = "npc" | "player"
--   npc    : config-owned, infinite stock, sells only listed items, can be job-locked.
--   player : startable as unowned, requires physical restock from owner/employee inventory.
--
-- jobs : array of job names OR "all". Only relevant for type="npc".
-- ped  : { model = "u_m_m_..." , heading = 0.0 }  -- nil disables ped for this shop
-- stock: { { item="name", price=10, sellPrice=4, stock=999 }, ... }
--        For npc shops stock is infinite regardless of `stock` value (UI shows ∞).
--        For player shops `stock` is the seed quantity created on first DB insert.
--        `sellPrice` is what the shop pays the player (0 = no buyback for this item).
--
-- Add/remove freely. Reload the resource after editing.
Shops.List = {
    -- ---------- VALENTINE GENERAL STORE (player-purchasable) ----------
    {
        id              = "valentine_general",
        name            = "Valentine General Store",
        type            = "player",
        coord           = vector3(-323.13, 811.27, 116.42),
        purchasePrice   = 7500,
        ped = {
            model   = "U_M_M_NbxGeneralStoreOwner_01",
            heading = 28.0,
        },
        blip = { enabled = true, sprite = -776993475, scale = 0.2, name = "General Store" },
        openHour  = 7,
        closeHour = 21,
        -- Items + default prices (seed stock if shop has no rows in DB yet)
        stock = {
            { item = "banana",         price = 2,  sellPrice = 1,  stock = 25 },
            { item = "carrots",         price = 4,  sellPrice = 2,  stock = 20 },
            { item = "cheesecake",price = 6,  sellPrice = 3,  stock = 15 },
        },
    },

    -- ---------- VALENTINE BUTCHER (job-locked NPC) ----------
    {
        id          = "valentine_butcher",
        name        = "Valentine Butcher",
        type        = "npc",
        coord       = vector3(-184.43, 626.05, 114.05),
        jobs        = { "butcher" },        -- only these jobs can browse; "all" to open to everyone
        ped         = { model = "s_m_m_unibutcher_01", heading = 180.0 },
        blip        = { enabled = true, sprite = -776993475, scale = 0.2, name = "Butcher" },
        enforceHours = true,
        openHour  = 6,
        closeHour = 20,
        buyback   = true,
        stock = {
            { item = "chickenf",          price = 8,  sellPrice = 5 },
            { item = "chickenheart",    price = 12, sellPrice = 7 },
        },
    },

    -- ---------- VALENTINE GUNSMITH (NPC, open to all, no buyback) ----------
    {
        id          = "valentine_gunsmith",
        name        = "Valentine Gunsmith",
        type        = "npc",
        coord       = vector3(-273.95, 802.13, 119.34),
        jobs        = "all",
        ped         = { model = "s_m_m_unigunsmith_01", heading = 90.0 },
        blip        = { enabled = true, sprite = -776993475, scale = 0.2, name = "Gunsmith" },
        buyback     = false,
        enforceHours = false,
        stock = {
            -- prices balanced to be exorbitant — adjust to your economy
            { item = "cigar", price = 3,  sellPrice = 0 },
            { item = "ammopistolexplosive",   price = 4,  sellPrice = 0 },
        },
    },
}
