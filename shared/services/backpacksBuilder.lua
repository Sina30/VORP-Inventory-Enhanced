if not BackPacks or not BackPacks.BackpackSettings then return end

local function normalizeJobs(jobs)
    if not jobs or jobs == false then return false end
    local out = {}
    for k, v in pairs(jobs) do
        if type(v) == 'table' and v.job then
            out[v.job] = v.grade or 0
        elseif type(v) == 'string' then
            out[v] = 0
        elseif type(k) == 'string' then
            out[k] = v or 0
        end
    end
    return next(out) and out or false
end

local function convertProp(prop)
    if not prop then return BackPacks.BackpackSettings.Props.Default end

    local nested   = prop.position or prop.Position
    local position = prop.Position or prop.position
    local rotation = prop.Rotation or prop.rotation

    if type(nested) == 'table' and nested.position then
        position = nested.position
        rotation = nested.rotation or rotation
    end

    return {
        Model    = prop.Model or prop.model or prop.prop,
        Bone     = prop.Bone or prop.bone or 'CP_Back',
        Position = position,
        Rotation = rotation,
    }
end

local function addBagItem(items, itemName, source, overrides)
    if not itemName or not source then return end
    overrides = overrides or {}
    local label = overrides.name or source.name or itemName
    local desc  = overrides.desc or ('Backpack: ' .. label)
    items[itemName] = {
        label             = label,
        extraWeight       = tonumber(overrides.storage or source.storage or 0.0) or 0.0,
        allowedCategories = overrides.allowedCategories or source.allowedCategories or false,
        jobs              = normalizeJobs(overrides.jobs ~= nil and overrides.jobs or source.jobs),
        acceptWeapons     = source.acceptWeapons,
        durability        = source.durability,
        blacklist         = source.blacklist,
        -- "capacity" or "container"; nil means inherit Mode from BackpackSettings.
        mode              = overrides.mode or source.mode,
        db = {
            desc   = desc,
            weight = overrides.weight or source.weight or 1.0,
            limit  = overrides.limit or 1,
        },
        prop = convertProp(overrides.prop or source.prop),
    }
end

BackPacks.Bags = {
    Enabled                          = BackPacks.BackpackSettings.Enabled,
    RequireEquipped                  = BackPacks.BackpackSettings.RequireEquipped,
    AllowOnlyOneActiveBag            = BackPacks.BackpackSettings.AllowOnlyOneActiveBag,
    RemoveBonusIfBagMissing          = BackPacks.BackpackSettings.RemoveBonusIfBagMissing,
    PreventBagRemovalWhenOverweight  = BackPacks.BackpackSettings.PreventBagRemovalWhenOverweight,
    Props                            = BackPacks.BackpackSettings.Props,
    AutoImportItems                  = BackPacks.BackpackSettings.AutoImportItems,
    UpdateImportedItems              = BackPacks.BackpackSettings.UpdateImportedItems,
    DefaultItemData                  = BackPacks.BackpackSettings.DefaultItemData,
    Categories                       = BackPacks.BackpackSettings.Categories,
    Items                            = {},
}

for _, backpack in pairs(BackPacks.Backpacks or {}) do
    addBagItem(BackPacks.Bags.Items, backpack.item, backpack)
end

for itemName, alias in pairs(BackPacks.BackpackAliases or {}) do
    addBagItem(BackPacks.Bags.Items, itemName, BackPacks.Backpacks[alias.from], alias)
end

for itemName, alias in pairs(BackPacks.ExtraBackpackItems or {}) do
    addBagItem(BackPacks.Bags.Items, itemName, BackPacks.Backpacks[alias.from], alias)
end
