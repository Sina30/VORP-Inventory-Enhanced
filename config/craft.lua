Config = Config or {}

Config.CraftItems = {
    ["consumable_breakfast"] = { -- here is the reward
        rewardAmount = 1,
        timerForPerAmount = 25000, -- miliseconds
        requiredItems = {
            {
                name = "meat",
                requiredAmount = 1,
            },
            {
                name = "salt",
                requiredAmount = 1,
            }
        }
    },
    ["consumable_applepie"] = {
        rewardAmount = 1,
        timerForPerAmount = 35000, -- miliseconds
        requiredItems = {
            {
                name = "apple",
                requiredAmount = 1,
            },
            {
                name = "water",
                requiredAmount = 1,
            },
            {
                name = "sugar",
                requiredAmount = 1,
            },
            {
                name = "flour",
                requiredAmount = 1,
            },
            {
                name = "eggs",
                requiredAmount = 1,
            },
        }
    }
}

Config.CraftSlots = 20

Config.CraftLocations = {
    {
        coord = vector3(-369.51, 796.07, 116.2),
    }
}