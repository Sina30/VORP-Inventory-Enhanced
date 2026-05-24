local Core   = exports.vorp_core:GetCore()
ServerItems  = {}
UsersWeapons = { default = {} }

--- load all player weapons
---@param db_weapon table
local function loadAllWeapons(db_weapon)
	local ammo = json.decode(db_weapon.ammo)
	local comp = json.decode(db_weapon.components)
	local comps = db_weapon.comps and json.decode(db_weapon.comps) or {}

	if db_weapon.dropped == 0 then
		local label = db_weapon.custom_label or db_weapon.label
		local weight = SvUtils.GetWeaponWeight(db_weapon.name)
		local weapon = Weapon:New({
			id = db_weapon.id,
			propietary = db_weapon.identifier,
			name = db_weapon.name,
			ammo = ammo,
			components = comp,
			comps = comps,
			used = false,
			used2 = false,
			charId = db_weapon.charidentifier,
			currInv = db_weapon.curr_inv,
			dropped = db_weapon.dropped,
			group = 5,
			label = label,
			serial_number = db_weapon.serial_number,
			custom_label = db_weapon.custom_label,
			custom_desc = db_weapon.custom_desc,
			weight = weight,
			slot = db_weapon.slot,
			ammo_total = db_weapon.ammo_total or 0,
			durability = db_weapon.durability or 100,
		})

		if not UsersWeapons[db_weapon.curr_inv] then
			UsersWeapons[db_weapon.curr_inv] = {}
		end

		UsersWeapons[db_weapon.curr_inv][weapon:getId()] = weapon
	else
		DBService.deleteAsync('DELETE FROM loadout WHERE id = @id', { id = db_weapon.id }, function() end)
	end
end




--- load player default inventory weapons
---@param source number
---@param character table character table data
local function loadPlayerWeapons(source, character)
	local _source = source
	DBService.queryAsync('SELECT * FROM loadout WHERE charidentifier = ? ', { character.charIdentifier },
		function(result)
			if next(result) then
				for _, db_weapon in pairs(result) do
					if db_weapon.charidentifier and db_weapon.curr_inv == "default" then -- only load default inventory
						loadAllWeapons(db_weapon)
					end
				end
			end
		end)
end

-- convert json string to pure lua table
local function luaTable(value)
	if type(value) == "table" then
		local t = {}
		for k, v in pairs(value) do
			t[k] = luaTable(v)
		end
		return t
	else
		return value
	end
end

local function tableHasColumn(columns, column)
	return columns[column] == true
end

local function getItemsTableColumns()
	local rows = MySQL.query.await([[
		SELECT COLUMN_NAME
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE()
		AND TABLE_NAME = 'items'
	]], {}) or {}
	local columns = {}
	for _, row in ipairs(rows) do
		columns[row.COLUMN_NAME or row.column_name or row.Column_name] = true
	end
	return columns
end

local function quoteIdentifier(name)
	return "`" .. tostring(name):gsub("`", "``") .. "`"
end

local function addColumn(columns, column, value, insertColumns, placeholders, params)
	if tableHasColumn(columns, column) then
		insertColumns[#insertColumns + 1] = quoteIdentifier(column)
		placeholders[#placeholders + 1] = "@" .. column
		params[column] = value
	end
end

local function importBackpackItemsFromConfig()
	if not BackPacks or not BackPacks.BackpackSettings then return end
	local settings = BackPacks.BackpackSettings
	if settings.Enabled == false or settings.AutoImportItems == false then return end
	if not BackPacks.Bags or not BackPacks.Bags.Items then return end

	local columns = getItemsTableColumns()
	if not tableHasColumn(columns, "item") then
		print("^1[vorp_inventory]^7 Backpack auto-import skipped: `items.item` column was not found.")
		return
	end

	local defaults = settings.DefaultItemData or {
		limit     = 1,
		canRemove = 1,
		type      = "item_standard",
		usable    = 1,
		weight    = 1.0,
		groupId   = 1,
		desc      = "A backpack that increases carry capacity when equipped.",
	}

	local inserted = 0

	for itemName, bag in pairs(BackPacks.Bags.Items) do
		local db = bag.db or {}
		local insertColumns, placeholders, params = {}, {}, {}

		addColumn(columns, "item",        itemName,                                                                       insertColumns, placeholders, params)
		addColumn(columns, "label",       db.label or bag.label or itemName,                                              insertColumns, placeholders, params)
		addColumn(columns, "limit",       db.limit or defaults.limit or 1,                                                insertColumns, placeholders, params)
		addColumn(columns, "can_remove",  db.canRemove or db.can_remove or defaults.canRemove or defaults.can_remove or 1, insertColumns, placeholders, params)
		addColumn(columns, "type",        db.type or defaults.type or "item_standard",                                    insertColumns, placeholders, params)
		addColumn(columns, "usable",      db.usable or defaults.usable or 1,                                              insertColumns, placeholders, params)
		addColumn(columns, "desc",        db.desc or db.description or defaults.desc or "Backpack.",                      insertColumns, placeholders, params)
		addColumn(columns, "weight",      db.weight or defaults.weight or 1.0,                                            insertColumns, placeholders, params)
		addColumn(columns, "groupId",     db.groupId or db.group or defaults.groupId or defaults.group or 1,              insertColumns, placeholders, params)
		addColumn(columns, "metadata",    db.metadata or defaults.metadata or "{}",                                       insertColumns, placeholders, params)
		addColumn(columns, "degradation", db.degradation or defaults.degradation or 0,                                    insertColumns, placeholders, params)
		addColumn(columns, "useExpired",  db.useExpired or defaults.useExpired or 0,                                      insertColumns, placeholders, params)

		local updateParts = {}
		if settings.UpdateImportedItems then
			for _, col in ipairs({ "label", "limit", "can_remove", "type", "usable", "desc", "weight", "groupId", "metadata", "degradation", "useExpired" }) do
				if tableHasColumn(columns, col) and params[col] ~= nil then
					updateParts[#updateParts + 1] = quoteIdentifier(col) .. " = VALUES(" .. quoteIdentifier(col) .. ")"
				end
			end
		else
			updateParts[#updateParts + 1] = quoteIdentifier("item") .. " = " .. quoteIdentifier("item")
		end

		local sql = ("INSERT INTO `items` (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s")
			:format(table.concat(insertColumns, ", "), table.concat(placeholders, ", "), table.concat(updateParts, ", "))

		MySQL.query.await(sql, params)
		inserted = inserted + 1
	end

	if inserted > 0 then
		print(("^2[vorp_inventory]^7 Auto-imported/updated %s backpack item(s)."):format(inserted))
	end
end

MySQL.ready(function()
	importBackpackItemsFromConfig()

	DBService.queryAsync("SELECT * FROM items", {}, function(result)
		for _, db_item in pairs(result) do
			if db_item.id then
				local meta = {}
				if db_item.metadata ~= "{}" then
					meta = luaTable(json.decode(db_item.metadata))
				end
				local item = Item:New({
					id = db_item.id,
					item = db_item.item,
					metadata = meta,
					label = db_item.label,
					limit = db_item.limit,
					type = db_item.type,
					canUse = db_item.usable,
					canRemove = db_item.can_remove,
					desc = db_item.desc,
					group = db_item.groupId,
					weight = db_item.weight,
					maxDegradation = db_item.degradation,
					useExpired = db_item.useExpired == 0 and false or true,
				})
				ServerItems[item.item] = item
			end
		end
	end)

	DBService.queryAsync("SELECT * FROM loadout", {}, function(result)
		for _, db_weapon in pairs(result) do
			if db_weapon.curr_inv ~= "default" then
				loadAllWeapons(db_weapon)
			end
		end
	end)
end)

local function cacheImages()
	local newtable = {}
	for k, v in pairs(ServerItems) do
		newtable[k] = v.item
	end
	for k, _ in pairs(SharedData.Weapons) do
		newtable[k] = k
	end
	local packed = msgpack.pack(newtable)

	return packed
end

AddEventHandler("vorp:SelectedCharacter", function(source, char)
	loadPlayerWeapons(source, char)

	local packed = cacheImages()
	TriggerClientEvent("vorp_inventory:server:CacheImages", source, packed)
end)

if Config.DevMode then
	RegisterNetEvent("DEV:loadweapons", function()
		local _source = source
		local character = Core.getUser(_source).getUsedCharacter
		loadPlayerWeapons(_source, character)

		local packed = cacheImages()
		TriggerClientEvent("vorp_inventory:server:CacheImages", _source, packed)
	end)
end
