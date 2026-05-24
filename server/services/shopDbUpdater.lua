local Tables = {
    {
        name   = "vorp_shops",
        script = "vorp_inventory",
        sql = [[
            CREATE TABLE IF NOT EXISTS `vorp_shops` (
                `id` VARCHAR(64) NOT NULL,
                `owner_identifier` VARCHAR(64) NULL DEFAULT NULL,
                `owner_charid` INT NULL DEFAULT NULL,
                `balance` INT NOT NULL DEFAULT 0,
                `open_hour` INT NULL DEFAULT NULL,
                `close_hour` INT NULL DEFAULT NULL,
                `enforce_hours` TINYINT NULL DEFAULT NULL,
                `force_closed` TINYINT NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            )
            COLLATE='utf8mb4_general_ci'
            ENGINE=InnoDB;
        ]]
    },
    {
        name   = "vorp_shop_stock",
        script = "vorp_inventory",
        sql = [[
            CREATE TABLE IF NOT EXISTS `vorp_shop_stock` (
                `shop_id` VARCHAR(64) NOT NULL,
                `item` VARCHAR(64) NOT NULL,
                `qty` INT NOT NULL DEFAULT 0,
                `buy_price` INT NOT NULL DEFAULT 0,
                `sell_price` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`shop_id`, `item`)
            )
            COLLATE='utf8mb4_general_ci'
            ENGINE=InnoDB;
        ]]
    },
    {
        name   = "vorp_shop_employees",
        script = "vorp_inventory",
        sql = [[
            CREATE TABLE IF NOT EXISTS `vorp_shop_employees` (
                `shop_id` VARCHAR(64) NOT NULL,
                `charid` INT NOT NULL,
                `perms` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`shop_id`, `charid`)
            )
            COLLATE='utf8mb4_general_ci'
            ENGINE=InnoDB;
        ]]
    },
}

local tries = 10
local currentry = 1
local function getCore()
    TriggerEvent("getCore", function(core)
        if not core.dbUpdateAddTables then
            if currentry < tries then
                currentry = currentry + 1
                Wait(500)
                getCore()
            end
        else
            core.dbUpdateAddTables(Tables)
        end
    end)
end

CreateThread(function()
    getCore()
end)
