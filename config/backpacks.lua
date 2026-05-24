BackPacks = BackPacks or {}

BackPacks.BackpackSettings = {
    Enabled = true,
    RequireEquipped = true,
    AllowOnlyOneActiveBag = true, -- true = only one equipped backpack counts; false = multiple backpacks can stack kg
    RemoveBonusIfBagMissing = true,
    PreventBagRemovalWhenOverweight = true, -- blocks drop/give/stash/delete/unequip if removing backpack would make inventory overweight

    Props = {
        Enabled = true,
        Default = {
            prop = 'p_bag01x',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.12, -0.02, -0.04),
                rotation = vector3(-70.0, 0.0, -90.0),
            }
        },
    },

    AutoImportItems = true,
    UpdateImportedItems = true,

    -- Default behavior when a backpack item is used.
    --   "capacity"  : adds extraWeight to the player's inventory capacity (current behavior).
    --   "container" : opens a separate secondary inventory for that backpack (its own slots/weight).
    --                 Items stored inside still count against the player's main inventory weight,
    --                 so a heavy bag is heavy to carry. Each backpack instance has its own
    --                 container, keyed by the items_crafted.id (e.g. "bp_42").
    -- A per-bag `mode = "container"` field in Backpacks/Aliases/Extras overrides this default.
    Mode = "container",
    DefaultItemData = {
        limit = 1,
        canRemove = 1,
        type = "item_standard",
        usable = 1,
        weight = 1.0,
        groupId = 1,
        desc = "A backpack that increases carry capacity when equipped.",
    },

    Categories = {
        hunting = {
            meat = true, pelt = true, hide = true, feather = true, claw = true, tooth = true, antler = true,
        },
        medical = {
            bandage = true, medicine = true, syringe = true, tonic = true, healthtonic = true, medic_kit = true,
        },
        evidence = {
            evidence_bag_item = true, weapon_service_receipt = true, case_file = true,
        },
        weapon_evidence = {
            weapon_evidence_bag = true,
        },
    },
}

-- Main backpack list
BackPacks.Backpacks = {
    [1] = {
        item = 'backpack1',
        jobs = false,
        name = 'Torba 1',
        storage = 30,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'doctorbackpack',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.12, -0.02, -0.04),
                rotation = vector3(-70.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [2] = {
        item = 'backpack2',
        jobs = false,
        name = 'Torba 2',
        storage = 40,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'fisherbackpack',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.38, -0.01, 0.02),
                rotation = vector3(-70.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [3] = {
        item = 'backpack3',
        jobs = false,
        name = 'Torba 3',
        storage = 35,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'herbalistbackpack',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.40, -0.01, -0.04),
                rotation = vector3(-75.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [4] = {
        item = 'backpack4',
        jobs = false,
        name = 'Torba 4',
        storage = 45,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'minerbackpack',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.40, -0.01, -0.05),
                rotation = vector3(-75.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [5] = {
        item = 'backpack5',
        jobs = false,
        name = 'Torba 5',
        storage = 45,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'nativebag',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.12, 0.0, 0.04),
                rotation = vector3(-80.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [6] = {
        item = 'backpack6',
        jobs = false,
        name = 'Torba 6',
        storage = 45,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'nativebag2',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.46, 0.0, 0.05),
                rotation = vector3(80.0, 0.0, 90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [7] = {
        item = 'backpack7',
        jobs = false,
        name = 'Torba 7',
        storage = 45,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'trapperbackpack',
            bone = 'CP_Back',
            position = {
                position = vector3(-0.17, -0.01, 0.02),
                rotation = vector3(-75.0, 0.0, -90.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },

    [8] = {
        item = 'backpack8',
        jobs = false,
        name = 'Torba 8',
        storage = 50,
        acceptWeapons = false,
        durability = 100,
        prop = {
            prop = 'p_bag01x',
            bone = 'SKEL_L_HAND',
            position = {
                position = vector3(0.45, 0.0, 0.0),
                rotation = vector3(0.0, -90.0, -65.0),
            }
        },
        blacklist = { 'backpack1','backpack2','backpack3','backpack4','backpack5','backpack6','backpack7','backpack8' },
    },
}

-- Compatibility aliases from the previous inventory update. If you already gave players bag1-bag4,
-- they will still work. You can delete these entries if you only want backpack1-backpack8.
BackPacks.BackpackAliases = {
    bag1 = { from = 1, storage = 10, name = 'Bag 1', desc = 'A small carry bag that increases carry capacity when equipped.' },
    bag2 = { from = 2, storage = 20, name = 'Bag 2', desc = 'A hunting carry bag for meat, pelts and hunting materials.', allowedCategories = { 'hunting' } },
    bag3 = { from = 3, storage = 15, name = 'Bag 3', desc = 'A medical carry bag for doctor and medic supplies.', allowedCategories = { 'medical' }, jobs = { doctor = 0, medic = 0 } },
    bag4 = { from = 4, storage = 30, name = 'Bag 4', desc = 'A law evidence carry bag for sheriff and police evidence.', allowedCategories = { 'evidence', 'weapon_evidence' }, jobs = { sheriff = 0, police = 0 } },
}

-- Existing names from earlier versions remain available.
BackPacks.ExtraBackpackItems = {
    small_satchel = { from = 1, storage = 10, name = 'Small Satchel', desc = 'A small satchel that increases carry capacity when equipped.' },
    hunting_bag = { from = 2, storage = 20, name = 'Hunting Bag', desc = 'A hunting bag for pelts, meat and hunting materials.', allowedCategories = { 'hunting' } },
    medic_bag = { from = 3, storage = 15, name = 'Medic Bag', desc = 'A medical bag for doctor and medic supplies.', allowedCategories = { 'medical' }, jobs = { doctor = 0, medic = 0 } },
    evidence_bag = { from = 4, storage = 30, name = 'Evidence Bag', desc = 'A law evidence bag for sheriff and police evidence.', allowedCategories = { 'evidence', 'weapon_evidence' }, jobs = { sheriff = 0, police = 0 } },
}

