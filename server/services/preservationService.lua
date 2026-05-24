PreservationService = {}

local PreservingInvs = {}

local function buildPreservingInvs()
	PreservingInvs = {}
	local cfg = Config.Preservation
	if not cfg or not cfg.Enabled or not Config.Stashes then return end
	local mults = cfg.StashDecayMultipliers or {}
	for _, stash in ipairs(Config.Stashes) do
		if stash.stashType and mults[stash.stashType] ~= nil then
			PreservingInvs[stash.id] = mults[stash.stashType]
		end
	end
end

function PreservationService.GetStashMultiplier(invId)
	return PreservingInvs[invId]
end

function PreservationService.GetWeather()
	local cfg = Config.Preservation
	local weatherCfg = cfg and cfg.Weather

	local syncRes = weatherCfg and weatherCfg.SyncResource
	if syncRes and syncRes ~= "" and GetResourceState(syncRes) == "started" then
		local ok, w = pcall(function() return exports[syncRes]:getWeather() end)
		if ok and type(w) == "string" and w ~= "" then
			return string.upper(w)
		end
	end

	local w = GlobalState.PreservationWeather or GlobalState.weather or GlobalState.Weather
	if type(w) == "string" and w ~= "" then
		return string.upper(w)
	end

	return string.upper((weatherCfg and weatherCfg.DefaultWeather) or "OVERCAST")
end

function PreservationService.GetWeatherMultiplier()
	local cfg = Config.Preservation
	if not cfg or not cfg.Weather then return 1.0 end
	local mults = cfg.Weather.Multipliers or {}
	return mults[PreservationService.GetWeather()] or mults.default or 1.0
end

local function computeFactor(item, invId)
	local stashMult = PreservingInvs[invId]
	if stashMult ~= nil then
		return stashMult
	end

	local cfg = Config.Preservation
	local factor = PreservationService.GetWeatherMultiplier()
	local name = item:getName()
	local meta = item:getMetadata() or {}

	if (cfg.SaltedItems and cfg.SaltedItems[name]) or meta.salted then
		factor = factor * (cfg.SaltedMultiplier or 1.0)
	end
	if cfg.PerishableItems and cfg.PerishableItems[name] then
		factor = factor * (cfg.PerishableMultiplier or 1.0)
	end
	return factor
end

function PreservationService.IsItemRotten(item)
	if not item or not item.getMaxDegradation then return false end
	local maxDeg = item:getMaxDegradation() or 0
	if maxDeg <= 0 then return false end
	local cfg = Config.Preservation
	local threshold = (cfg and cfg.RottenThreshold) or 0
	return (item:getPercentage() or 100) <= threshold
end

local function modulateInventory(items, invId, dt, now, queries)
	for _, item in pairs(items) do
		if type(item) == "table" and item.getMaxDegradation then
			local maxDeg = item:getMaxDegradation() or 0
			local degr = item:getDegradation()
			if maxDeg > 0 and degr and degr > 0 then
				local factor = computeFactor(item, invId)
				if factor ~= 1.0 then
					local newDeg = math.floor(degr + dt * (1 - factor))
					if newDeg > now then newDeg = now end -- never fresher than brand new
					item.degradation = newDeg
					item.percentage = item:getPercentage()
					queries[#queries + 1] = {
						query = "UPDATE character_inventories SET degradation = ?, percentage = ? WHERE item_crafted_id = ?",
						values = { newDeg, item.percentage, item:getId() }
					}
				end
			end
		end
	end
end

local function tick()
	local cfg = Config.Preservation
	if not cfg or not cfg.Enabled then return end

	local dt = (cfg.TickMinutes or 1) * 60
	local now = os.time()
	local queries = {}

	for invKey, invData in pairs(UsersInventories) do
		if type(invData) == "table" then
			if invKey == "default" then
				for _, identInv in pairs(invData) do
					if type(identInv) == "table" then
						modulateInventory(identInv, "default", dt, now, queries)
					end
				end
			else
				local info = CustomInventoryInfos[invKey]
				if info then
					if info:isShared() then
						modulateInventory(invData, invKey, dt, now, queries)
					else
						for _, identInv in pairs(invData) do
							if type(identInv) == "table" then
								modulateInventory(identInv, invKey, dt, now, queries)
							end
						end
					end
				end
			end
		end
	end

	if #queries > 0 then
		MySQL.transaction(queries, function() end)
	end
end

CreateThread(function()
	Wait(5000)
	buildPreservingInvs()

	local cfg = Config.Preservation
	if not cfg or not cfg.Enabled then
		return print("^3[vorp_inventory]^7 Food preservation system disabled.")
	end
	print("^2[vorp_inventory]^7 Food preservation system active (tick: " .. (cfg.TickMinutes or 1) .. "m).")

	while true do
		Wait((cfg.TickMinutes or 1) * 60000)
		local ok, err = pcall(tick)
		if not ok then
			print("^1[vorp_inventory]^7 preservation tick error: " .. tostring(err))
		end
	end
end)

exports("SetPreservationWeather", function(weatherName)
	if type(weatherName) == "string" and weatherName ~= "" then
		GlobalState.PreservationWeather = string.upper(weatherName)
	end
end)

exports("GetPreservationWeather", PreservationService.GetWeather)

exports("IsInventoryPreserving", function(invId)
	return PreservingInvs[invId]
end)
