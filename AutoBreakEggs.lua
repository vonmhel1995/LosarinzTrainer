-- Distribution URLs. Fill these in with your GitHub raw URLs once the repo exists;
-- until then the script loads LosarinzUI and re-executes from local files.
local LOSARINZ_UI_URL = ""
local MAIN_SCRIPT_URL = ""

-- Executed too early: wait for the game to finish loading before touching
-- ReplicatedStorage children, otherwise dot-indexing can throw and kill the script.
if not game:IsLoaded() then
	repeat task.wait() until game:IsLoaded()
end

-- Re-execution guard, stops the previous loops, UI and ESP.
if getgenv().AutoFarm then
	getgenv().AutoFarm.running = false

	for _, connection in ipairs(getgenv().AutoFarm.connections or {}) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	pcall(function()
		getgenv().AutoFarm.rayfield:Destroy()
	end)

	pcall(function()
		getgenv().AutoFarm.espFolder:Destroy()
	end)
end

local AutoFarm = {
	running = true,
	autoFarm = false,
	autoSteal = false,
	autoSell = false,
	sellBelow = 0,
	sellAbove = 0,
	autoGrab = true,
	autoIndex = false,
	autoEquipPickaxe = false,
	autoEquipPets = false,
	autoTreadmill = false,
	treadmillRun = false,
	autoMount = false,
	autoBuyMount = false,
	autoFuse = false,
	buyMountKeep = 0,
	rideName = "",
	treadmillMinutes = 60,
	treadmillUntil = 0,
	autoBuyPickaxe = false,
	autoEquipTrail = false,
	autoReconnect = true,
	autoPen = false,
	autoPlaceEggs = false,
	failedEggTools = {},
	autoHatchEggs = false,
	giveSpot = Vector3.zero,
	giveUntil = 0,
	zoneCenterFn = function(_zone: string): Vector3? return nil end,
	autoMerge = false,
	antiAfk = true,
	autoEnchantPickaxe = false,
	autoEnchantPets = false,
	enchantTargetTier = 3,
	enchantPickaxeTarget = "SwingSpeed",
	enchantGemReserve = 500,
	merge = { rarities = {}, below = 0, above = 0 },
	webhook = { enabled = false, url = "", ping = "", minValue = 0 },
	antiRagdoll = false,
	waitForHatch = false,
	titanicFirst = false,
	maxEggHp = 0,
	attack = "Direct Hit",
	priority = "Nearest",
	zone = "Auto",
	eggTypes = {},
	swingDelay = 0.5,
	autoHitDelay = true,
	knownEggs = {},
	afterSteal = "Sell",
	stealDelay = 3,
	stealRange = 60,
	huntFar = false,
	filter = {
		rarities = {},
		mutations = {},
		sizes = {},
		above = 0,
		below = 0,
		alsoMutations = {},
		mutatedRarities = {},
		mutatedAbove = 0,
	},
	espEggs = false,
	espAnimals = false,
	espRange = 300,
	state = "idle",
	lastJudge = "none yet",
	stealState = "off",
	currentEgg = nil,
	lastStealAt = 0,
	eggsBroken = 0,
	farmStartedAt = os.clock(),
	pickups = 0,
	steals = 0,
	junk = 0,
	delivers = 0,
	stealLog = {},
	connections = {},
}
getgenv().AutoFarm = AutoFarm

-- Constants.
local EGG_TAG = "BreakableEgg"
local ANIMAL_TOOL_TAG = "AnimalTool"
local PROMPT_TAG = "SmartPrompt"
local TOOL_KEYWORD = "pickaxe"
local RAYFIELD_URL = "https://sirius.menu/rayfield"
local FALLBACK_SAFE_SPOT = Vector3.new(25, 104, 11)
local MAX_STEAL_LOG = 8
local MAX_ESP = 40

local RARITIES = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret",
	"Cosmic", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal", "Primordial",
}
local SIZES = { "BIG", "HUGE", "TITANIC" }
local FALLBACK_MUTATIONS = { "Shiny", "Golden", "Diamond", "Radioactive", "Rainbow" }
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local MULTIPLIERS = {
	k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18,
	sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30, dc = 1e33,
}

-- Services.
local playersService = game:GetService("Players")
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- State.
local localPlayer = playersService.LocalPlayer
local sharedFolder = replicatedStorage:WaitForChild("Shared")
local controllers = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
local eggHitRequest = replicatedStorage:WaitForChild("EggHitRequest", 10)
local masterySwingRemote = replicatedStorage:FindFirstChild("MasteryPickaxeSwing")
local sellRemote = replicatedStorage:FindFirstChild("BackpackSellRemote")
local placeAnimalRemote = replicatedStorage:FindFirstChild("PlaceAnimalRemote")
local fuseRemote = replicatedStorage:FindFirstChild("FuseMachineRequest")
local indexRemote = replicatedStorage:FindFirstChild("IndexRemote")
local pickaxeShopRemote = replicatedStorage:FindFirstChild("PickaxeShopRequest")
local petsRemote = replicatedStorage:FindFirstChild("PetsInventoryRemote")
local upgradeTreadmillRemote = replicatedStorage:FindFirstChild("UpgradeTreadmillRequest")
local trailShopRemote = replicatedStorage:FindFirstChild("TrailShopRequest")
local upgradePlotRemote = replicatedStorage:FindFirstChild("UpgradePlotRequest")
local mergeRemote = replicatedStorage:FindFirstChild("MergeMachineRemote")
local placeSequence = 0
local rng = Random.new()

---Require a module from ReplicatedStorage.Shared safely.
---@param name string
---@return table?
local function requireModule(name)
	local module = sharedFolder:FindFirstChild(name)
	if not module then return end

	local success, value = pcall(require, module)
	return success and value or nil
end

-- Game modules, required at identity 2 so our environment is not exposed.
setthreadidentity(2)
local eggTargeting = requireModule("EggTargeting")
local eggConfig = requireModule("EggConfig")
local pickaxeConfig = requireModule("PickaxeConfig")
local zonesConfig = requireModule("ZonesConfig")
local potionConfig = requireModule("PotionConfig")
local masteryConfig = requireModule("MasteryConfig")
local backpackSellConfig = requireModule("BackpackSellConfig")
local mutationConfig = requireModule("MutationConfig")
local eggRewards = requireModule("EggRewards")
local eggTypeConfig = requireModule("EggTypeConfig")
local zoneDisplayInfo = requireModule("ZoneDisplayInfo")
local robuxShopConfig = requireModule("RobuxShopConfig")
local trailsConfig = requireModule("TrailsConfig")
local plotUpgradeConfig = requireModule("PlotUpgradeConfig")
local safeZoneQuery = requireModule("SafeZoneQuery")
local treadmillUpgradeConfig = requireModule("TreadmillUpgradeConfig")

local eggLocalHits
local eggLocalHitsModule = controllers:FindFirstChild("EggLocalHits")
if eggLocalHitsModule then
	local success, value = pcall(require, eggLocalHitsModule)
	eggLocalHits = success and value or nil
end

local gameAutoSwing
local gameAutoSwingModule = controllers:FindFirstChild("AutoSwingController")
if gameAutoSwingModule then
	local success, value = pcall(require, gameAutoSwingModule)
	gameAutoSwing = success and type(value) == "table" and value or nil
end
setthreadidentity(8)

local hitRange = eggConfig and type(eggConfig.HitRange) == "number" and eggConfig.HitRange or 14

---Format a number with a short suffix, like 10.5T.
---@param value number?
---@return string
local function formatNumber(value)
	if type(value) ~= "number" or value ~= value then return "?" end

	local scaled = math.abs(value)
	local index = 1

	while scaled >= 1000 and index < #SUFFIXES do
		scaled = scaled / 1000
		index = index + 1
	end

	local sign = value < 0 and "-" or ""
	if index == 1 then
		if scaled % 1 == 0 then
			return sign .. tostring(scaled)
		end

		return sign .. string.format("%.2f", scaled)
	end

	return string.format("%s%.2f%s", sign, scaled, SUFFIXES[index])
end

---Parse an amount like 10T or 500b. Empty text is 0, invalid text is nil.
---@param text string
---@return number?
local function parseAmount(text)
	local cleaned = tostring(text or ""):lower():gsub("[%s,%$]", "")
	if cleaned == "" then return 0 end

	local number, suffix = cleaned:match("^([%d%.]+)(%a*)$")
	local base = tonumber(number)
	if not base then return end
	if suffix == "" then return base end

	local multiplier = MULTIPLIERS[suffix]
	if not multiplier then return end

	return base * multiplier
end

---Turn dropdown options into a set.
---@param options table
---@param lowerCase boolean?
---@return table
local function toSet(options, lowerCase)
	local set = {}

	for _, option in ipairs(options) do
		if type(option) == "string" and option ~= "None" and option ~= "--" then
			set[lowerCase and option:lower() or option] = true
		end
	end

	return set
end

---Read an attribute without erroring.
---@param instance Instance
---@param name string
---@return any
local ANIMAL_ATTRIBUTES = { CashPerSecond = true, AnimalName = true, Rarity = true, WeightBracket = true }

local function readAttribute(instance, name)
	local success, value = pcall(instance.GetAttribute, instance, name)
	if success and value ~= nil and value ~= false then return value end

	-- Animal data can sit on a child part of the model instead of the model itself.
	if ANIMAL_ATTRIBUTES[name] and typeof(instance) == "Instance" and instance:IsA("Model") then
		for _, descendant in ipairs(instance:GetDescendants()) do
			local ok, found = pcall(descendant.GetAttribute, descendant, name)
			if ok and found ~= nil then return found end
		end
	end

	return nil
end

---Get the player's character parts.
---@return Model?, BasePart?, Humanoid?
local function getCharacter()
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if rootPart and humanoid and humanoid.Health > 0 then
		return character, rootPart, humanoid
	end

	return nil
end

---Read a numeric player attribute.
---@param name string
---@return number
local function getNumberAttribute(name)
	local value = localPlayer:GetAttribute(name)
	return typeof(value) == "number" and value or 0
end

---Get how many animals the player carries.
---@return number
local function getCarryCount()
	return getNumberAttribute("CarryCount")
end

---Get how many animals the player can carry.
---@return number
local function getSatchelCapacity()
	local value = getNumberAttribute("SatchelCapacity")
	return value > 0 and value or 1
end

---Get the zone number from an instance's ancestors.
---@param instance Instance
---@return number?
local function getZoneNumber(instance)
	local node = instance

	while node and node ~= workspace do
		local number = tonumber(string.match(node.Name, "^Zone(%d+)$"))
		if number then
			return number
		end

		node = node.Parent
	end

	return nil
end

---Check whether an egg is in the chosen zone, or reachable on Auto.
---@param egg Instance
---@return boolean
local function isZoneAllowed(egg)
	local number = getZoneNumber(egg)
	if not number then return false end

	if AutoFarm.zone ~= "Auto" then
		return ("Zone" .. number) == AutoFarm.zone
	end

	local zone = zonesConfig and zonesConfig.Zones and zonesConfig.Zones[number]
	if not zone then return false end

	return getNumberAttribute("SpeedPower") >= (zone.RequiredPower or 0)
end

---Check that an egg can still be hit.
---@param egg Instance
---@return boolean
local function isEggLive(egg)
	return egg.Parent ~= nil
		and not egg:GetAttribute("Broken")
		and not egg:GetAttribute("Hatching")
		and not egg:GetAttribute("Despawning")
end

---Distance to the egg surface, like the game's own hit check.
---@param egg BasePart
---@param position Vector3
---@return number
local function getSurfaceDistance(egg, position)
	if eggTargeting and eggTargeting.SurfaceDistance then
		return eggTargeting.SurfaceDistance(egg, position)
	end

	return (egg.Position - position).Magnitude
end

---Get the egg type name, without the zone order prefix.
---@param egg Instance
---@return string
local function getEggTypeName(egg)
	-- The game's own display name, from the EggType attribute on the egg or the model around it.
	if type(eggTypeConfig) == "table" and type(eggTypeConfig.Get) == "function" then
		local node = egg

		for _ = 1, 3 do
			if not node or node == workspace then break end

			local ok, config = pcall(eggTypeConfig.Get, node:GetAttribute("EggType"))

			if ok and type(config) == "table" and type(config.DisplayName) == "string" then
				return config.DisplayName
			end

			node = node.Parent
		end
	end

	local raw = egg.Name

	if egg.Name == "Egg" and egg.Parent and egg.Parent ~= workspace then
		raw = egg.Parent.Name
	end

	raw = raw:gsub("^%d+:%s*", "")

	-- Nest eggs are called Zone_7_Nest, show which zone they are in.
	local zoneNumber = string.match(raw, "^Zone_(%d+)_Nest$")

	if zoneNumber then
		local info = type(zoneDisplayInfo) == "table" and zoneDisplayInfo["Zone" .. zoneNumber]
		local zoneName = type(info) == "table" and info.Name or ("Zone " .. zoneNumber)

		return ("%s Egg (Zone %s)"):format(zoneName, zoneNumber)
	end

	return raw
end

---Check that an egg matches the Break Eggs selection, none selected means all.
---@param egg Instance
---@return boolean
local function isEggTypeAllowed(egg)
	if next(AutoFarm.eggTypes) == nil then return true end

	return AutoFarm.eggTypes[getEggTypeName(egg)] == true
end

---Score an egg for the Luckiest and Biggest priorities.
---@param egg Instance
---@param mode string
---@return number
local function getEggScore(egg, mode)
	local luck = tonumber(readAttribute(egg, "HatchLuck")) or tonumber(readAttribute(egg, "Luck")) or 0
	local weight = tonumber(readAttribute(egg, "WeightKg")) or 0
	local bracket = tostring(readAttribute(egg, "WeightBracket") or ""):lower()
	local titanic = (bracket:find("titanic") or collectionService:HasTag(egg, "TitanicEgg")) and 1 or 0

	if mode == "Luckiest" then
		return luck * 1e9 + titanic * 1e6 + weight
	end

	return titanic * 1e18 + weight * 1e6 + luck
end

---Pick the egg to farm based on the priority.
---@param position Vector3
---@return BasePart?, number?
local function pickEgg(position)
	local best, bestDistance, bestScore, bestTitan

	for _, egg in ipairs(collectionService:GetTagged(EGG_TAG)) do
		if not (egg:IsA("BasePart") and isEggLive(egg) and isZoneAllowed(egg) and isEggTypeAllowed(egg)) then continue end

		-- Max Egg HP skips eggs that take too long to break, 0 means no limit.
		local maxHp = AutoFarm.maxEggHp or 0
		if maxHp > 0 and (tonumber(egg:GetAttribute("Health")) or 0) > maxHp then continue end

		local distance = getSurfaceDistance(egg, position)
		local score = AutoFarm.priority ~= "Nearest" and getEggScore(egg, AutoFarm.priority) or nil
		local titan = AutoFarm.titanicFirst and egg:GetAttribute("Titanic") == true or false
		local better

		if best and titan ~= bestTitan then
			better = titan
		elseif score then
			better = bestScore == nil or score > bestScore or (score == bestScore and distance < bestDistance)
		else
			better = bestDistance == nil or distance < bestDistance
		end

		if better then
			best, bestDistance, bestScore, bestTitan = egg, distance, score, titan
		end
	end

	return best, bestDistance
end

---Get the ZoneBuilds folder.
---@return Instance?
local function getZoneBuilds()
	local build = workspace:FindFirstChild("Build")
	return build and build:FindFirstChild("ZoneBuilds")
end

---Sort names by the first number inside them.
---@param names table
local function sortByNumber(names)
	table.sort(names, function(a, b)
		local numberA = tonumber(a:match("%d+")) or 0
		local numberB = tonumber(b:match("%d+")) or 0

		if numberA == numberB then
			return a < b
		end

		return numberA < numberB
	end)
end

---List the zone names, with Auto first.
---@return table
local function getZoneNames()
	local names = { "Auto" }
	local zoneBuilds = getZoneBuilds()
	if not zoneBuilds then return names end

	local zones = {}
	for _, zone in ipairs(zoneBuilds:GetChildren()) do
		table.insert(zones, zone.Name)
	end

	sortByNumber(zones)
	for _, name in ipairs(zones) do
		table.insert(names, name)
	end

	return names
end

---List every egg type found in the zones.
---@return table
local function getEggTypeNames()
	local names, seen = {}, {}

	local function add(name)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	-- Eggs of zones that are loaded right now.
	local zoneBuilds = getZoneBuilds()

	for _, zone in ipairs(zoneBuilds and zoneBuilds:GetChildren() or {}) do
		local eggs = zone:FindFirstChild("Eggs")

		for _, egg in ipairs(eggs and eggs:GetChildren() or {}) do
			add(getEggTypeName(egg))
		end
	end

	-- Every egg seen in the session is remembered, far zones only stream in when you are near.
	for _, egg in ipairs(collectionService:GetTagged("BreakableEgg")) do
		add(getEggTypeName(egg))
	end

	for name in pairs(AutoFarm.knownEggs) do
		add(name)
	end

	-- Every egg the game's own EggConfig knows, so far zones appear without visiting them.
	-- The config is the source of truth, it updates with the game (v1472 has 46 eggs).
	if type(eggConfig) == "table" and type(eggConfig.Eggs) == "table" then
		for name in pairs(eggConfig.Eggs) do
			add(tostring(name))
		end
	end

	for name in pairs(seen) do
		AutoFarm.knownEggs[name] = true
	end

	table.sort(names)
	return names
end

---Compute the damage the game would send for this egg.
---@param egg Instance?
---@return number
local function getPickaxeDamage(egg)
	local fixed = egg and readAttribute(egg, "FixedDamage")
	local damage

	if type(fixed) == "number" and fixed > 0 then
		damage = fixed
	else
		local character = getCharacter()
		local tool = character and character:FindFirstChildOfClass("Tool")
		local tier = tool and tool:GetAttribute("PickaxeTier")

		if typeof(tier) ~= "number" then
			tier = localPlayer:GetAttribute("PickaxeTier")
		end

		if typeof(tier) == "number" and pickaxeConfig and pickaxeConfig.GetDamage then
			local success, value = pcall(pickaxeConfig.GetDamage, tier)
			if success and type(value) == "number" then
				damage = value
			end
		end
	end

	damage = damage or 1

	-- Same product the game uses: potion x mastery x pass, each takes the player first.
	local function factor(module, method, ...)
		if type(module) ~= "table" or type(module[method]) ~= "function" then return 1 end

		local success, value = pcall(module[method], localPlayer, ...)
		return success and type(value) == "number" and value > 0 and value or 1
	end

	damage = damage * factor(potionConfig, "MultiplierFor", "Damage")
		* factor(masteryConfig, "MultiplierFor", "Power")
		* factor(robuxShopConfig, "DamageMultiplierFor")

	return damage
end

---Get the swing cooldown with passes, potions and mastery applied.
---@return number
local function getSwingCooldown()
	local base = pickaxeConfig and type(pickaxeConfig.SwingCooldown) == "number" and pickaxeConfig.SwingCooldown or 0.5

	-- The game's own formula: passes, potions and the Swinging mastery all count.
	if robuxShopConfig and type(robuxShopConfig.SwingMultiplierFor) == "function" then
		local success, value = pcall(robuxShopConfig.SwingMultiplierFor, localPlayer)

		if success and type(value) == "number" and value > 0 then
			return base / value
		end
	end

	-- The x2 Swing Speed ad potion counts on top of the pass multiplier.
	if potionConfig and type(potionConfig.MultiplierFor) == "function" then
		local success, value = pcall(potionConfig.MultiplierFor, localPlayer, "SwingSpeed")

		if success and type(value) == "number" and value > 0 then
			return base / value
		end
	end

	if localPlayer:GetAttribute("FastSwingOwned") == true then
		base = base * 0.5
	end

	return base
end

---Time between swings: the game's limit when Auto Hit Delay is on, otherwise the slider too.
---@return number
local function getSwingPace()
	local limit = getSwingCooldown() * rejectStretch

	if AutoFarm.autoHitDelay then
		return limit + 0.02
	end

	return math.max(limit, AutoFarm.swingDelay * rejectStretch)
end

---Find the pickaxe tool, equipping it if needed.
---@return Tool?
local function equipPickaxe()
	local character, _, humanoid = getCharacter()
	if not character then return end

	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") and tool.Name:lower():find(TOOL_KEYWORD) then
			return tool
		end
	end

	local backpack = localPlayer:FindFirstChild("Backpack")
	if not backpack then return end

	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") and tool.Name:lower():find(TOOL_KEYWORD) then
			humanoid:EquipTool(tool)
			return tool
		end
	end

	return nil
end

---Hit an egg using the game's own damage pipeline.
---@param egg BasePart
local function directHit(egg)
	local announced = getPickaxeDamage(egg)

	if eggLocalHits and eggLocalHits.Announce then
		local success, value = pcall(eggLocalHits.Announce, egg, announced)
		if success and type(value) == "number" then
			announced = value
		end
	end

	-- Re-find the remote if the startup wait timed out before ReplicatedStorage finished.
	if not (eggHitRequest and eggHitRequest.Parent) then
		eggHitRequest = replicatedStorage:FindFirstChild("EggHitRequest")
	end

	if eggHitRequest then
		eggHitRequest:FireServer(egg, announced)
	end

	if masterySwingRemote then
		pcall(function()
			masterySwingRemote:FireServer()
		end)
	end
end

-- Reject-adaptive pacing: the server sometimes tightens hit validation (lag spikes,
-- crowd servers). Track confirms/rejects and stretch the pace only while rejects
-- actually happen, so throughput stays at the game's own cadence otherwise.
local rejectStretch = 1

table.insert(AutoFarm.connections, replicatedStorage.EggHitConfirmed.OnClientEvent:Connect(function()
	if rejectStretch > 1 then
		rejectStretch = math.max(1, rejectStretch * 0.9)
	end
end))

table.insert(AutoFarm.connections, replicatedStorage.EggHitRejected.OnClientEvent:Connect(function()
	rejectStretch = math.min(rejectStretch * 1.6, 3)
end))

---Step toward a position at the live WalkSpeed, no teleport.
---@param rootPart BasePart
---@param humanoid Humanoid
---@param target Vector3
---@param delta number
local function stepToward(rootPart, humanoid, target, delta)
	local flat = Vector3.new(target.X - rootPart.Position.X, 0, target.Z - rootPart.Position.Z)
	if flat.Magnitude < 0.1 then return end

	local step = math.min(humanoid.WalkSpeed * delta, flat.Magnitude)
	local direction = flat.Unit
	rootPart.CFrame = CFrame.lookAt(rootPart.Position + direction * step, rootPart.Position + direction * 10)
end

---Walk to a position until arrived, timed out or cancelled.
---@param position Vector3
---@param timeout number
---@param arriveDistance number
---@param isCancelled function?
---@return boolean
local function walkTo(position, timeout, arriveDistance, isCancelled)
	local startedAt = os.clock()
	local lastTime = startedAt
	local lastPosition, lastProgress = nil, startedAt

	while AutoFarm.running and os.clock() - startedAt < timeout do
		if isCancelled and isCancelled() then return false end

		local _, rootPart, humanoid = getCharacter()
		if not rootPart then return false end

		local flat = Vector3.new(position.X - rootPart.Position.X, 0, position.Z - rootPart.Position.Z)
		if flat.Magnitude <= arriveDistance then
			humanoid:MoveTo(rootPart.Position)
			return true
		end

		local now = os.clock()
		stepToward(rootPart, humanoid, position, now - lastTime)
		lastTime = now

		-- Jump when stuck.
		if lastPosition and (rootPart.Position - lastPosition).Magnitude < 0.5 and now - lastProgress > 2.5 then
			humanoid.Jump = true
			lastProgress = now
		elseif not lastPosition or (rootPart.Position - lastPosition).Magnitude >= 0.5 then
			lastPosition = rootPart.Position
			lastProgress = now
		end

		task.wait(0.05)
	end

	return false
end

---Fire a proximity prompt.
---@param prompt ProximityPrompt
local function triggerPrompt(prompt)
	if not (prompt and prompt.Parent) then return end

	local holdDuration = prompt.HoldDuration

	-- The prompt needs a 0.35s hold, so skip it, then fall back to a real hold.
	if fireproximityprompt then
		pcall(function()
			prompt.HoldDuration = 0
		end)
		pcall(fireproximityprompt, prompt)
		task.wait(0.15)
		pcall(function()
			prompt.HoldDuration = holdDuration
		end)

		if getCarryCount() > 0 then return end
	end

	pcall(function()
		prompt:InputHoldBegin()
		task.wait(math.max(0.1, holdDuration) + 0.12)
		prompt:InputHoldEnd()
	end)
end

---List the tools in the backpack and character that match a check.
---@param isMatch function
---@return table
local function collectTools(isMatch)
	local list = {}

	for _, container in ipairs({ localPlayer:FindFirstChild("Backpack"), localPlayer.Character }) do
		if not container then continue end

		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and isMatch(tool) then
				table.insert(list, tool)
			end
		end
	end

	return list
end

---Get the animal tool the player is carrying.
---@return Tool?
local function getCarriedTool()
	return collectTools(function(tool)
		return collectionService:HasTag(tool, ANIMAL_TOOL_TAG)
	end)[1]
end

---List the animal tools that can be sold.
---@return table
local function getSellableTools()
	return collectTools(function(tool)
		if backpackSellConfig and backpackSellConfig.IsSellable then
			local success, sellable = pcall(backpackSellConfig.IsSellable, tool)
			return success and sellable == true
		end

		return collectionService:HasTag(tool, ANIMAL_TOOL_TAG)
	end)
end

---Sell tools in chunks.
---@param tools table
---@return boolean
local function sellTools(tools)
	if not (sellRemote and #tools > 0) then return false end

	local maxPerRequest = backpackSellConfig and type(backpackSellConfig.MaxPerRequest) == "number"
		and backpackSellConfig.MaxPerRequest or 200

	for index = 1, #tools, maxPerRequest do
		local chunk = {}
		for i = index, math.min(index + maxPerRequest - 1, #tools) do
			table.insert(chunk, tools[i])
		end

		pcall(function()
			sellRemote:InvokeServer(chunk)
		end)

		task.wait(0.3)
	end

	return true
end

---Get the nearest safe zone position.
---@param fromPosition Vector3?
---@return Vector3
local function getSafeTarget(fromPosition)
	if safeZoneQuery and safeZoneQuery.GetSafeParts then
		local success, parts = pcall(safeZoneQuery.GetSafeParts)

		if success and type(parts) == "table" then
			local best, bestDistance

			for _, part in ipairs(parts) do
				if typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent then
					local distance = (part.Position - (fromPosition or Vector3.zero)).Magnitude

					if not bestDistance or distance < bestDistance then
						best, bestDistance = part.Position, distance
					end
				end
			end

			if best then
				return best
			end
		end
	end

	return FALLBACK_SAFE_SPOT
end

---Check whether a position is inside a safe zone.
---@param position Vector3
---@return boolean
local function isAtSafeSpot(position)
	if safeZoneQuery and safeZoneQuery.IsPositionSafe then
		local success, safe = pcall(safeZoneQuery.IsPositionSafe, position)
		if success then
			return safe == true
		end
	end

	return (getSafeTarget(position) - position).Magnitude <= 12
end

---Get the mutation name of an animal or animal tool.
---@param instance Instance
---@return string?
local function getMutation(instance)
	if not (mutationConfig and mutationConfig.Attribute) then return end

	local value = readAttribute(instance, mutationConfig.Attribute)
	if value == nil or value == "" or value == false then return end

	local data = type(mutationConfig.Mutations) == "table" and mutationConfig.Mutations[value]
	local name = type(data) == "table" and data.Name

	return type(name) == "string" and name ~= "" and name or tostring(value)
end

---List the mutation names for the dropdowns.
---@return table
local function getMutationNames()
	local names, seen = {}, {}

	if mutationConfig and type(mutationConfig.Mutations) == "table" then
		for id, data in pairs(mutationConfig.Mutations) do
			local name = type(data) == "table" and data.Name or id

			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end

		table.sort(names)
	end

	return #names > 0 and names or FALLBACK_MUTATIONS
end

---Check a set filter, an empty set accepts everything.
---@param set table
---@param value string?
---@param lenient boolean
---@return boolean
local function matchesSet(set, value, lenient)
	if next(set) == nil then return true end
	if value == nil or value == "" then return lenient end

	return set[value] == true
end

---Cash per second of an animal. Dropped animals have no CashPerSecond attribute, so it is worked out
---with the game's own EggRewards.PlacedCashPerSecond(name, sizeMult, mutation, weightKg, variant).
---@param instance Instance
---@return number?
local function getAnimalCash(instance)
	local direct = tonumber(readAttribute(instance, "CashPerSecond"))
	if direct then return direct end

	local name = readAttribute(instance, "AnimalName")
	if not (name and type(eggRewards) == "table" and type(eggRewards.PlacedCashPerSecond) == "function") then return nil end

	local mutation = mutationConfig and mutationConfig.Attribute and readAttribute(instance, mutationConfig.Attribute)
	if mutation == nil or mutation == "" then
		mutation = readAttribute(instance, "Mutation")
	end

	local success, value = pcall(
		eggRewards.PlacedCashPerSecond,
		name,
		tonumber(readAttribute(instance, "SizeMult")),
		mutation ~= "" and mutation or nil,
		tonumber(readAttribute(instance, "WeightKg")),
		readAttribute(instance, "Variant")
	)

	return success and type(value) == "number" and value or nil
end

---Check a cash per second range, 0 means no limit.
---@param cash number?
---@param minimum number
---@param maximum number
---@param lenient boolean
---@return boolean
local function inCashRange(cash, minimum, maximum, lenient)
	if cash == nil then
		return lenient or (minimum <= 0 and maximum <= 0)
	end

	if cash < minimum then return false end
	if maximum > 0 and cash > maximum then return false end

	return true
end

---Check an animal or animal tool against the steal filter.
---@param instance Instance
---@param lenient boolean Missing attributes pass, used on the tool we already hold.
---@return boolean
local function passesStealFilter(instance, lenient)
	local filter = AutoFarm.filter
	local rarity = readAttribute(instance, "Rarity")
	local bracket = readAttribute(instance, "WeightBracket")
	local cash = getAnimalCash(instance)
	local mutation = getMutation(instance)

	rarity = rarity ~= nil and tostring(rarity) or nil
	bracket = bracket ~= nil and tostring(bracket):upper() or nil

	local main = matchesSet(filter.rarities, rarity, lenient)
		and matchesSet(filter.sizes, bracket, lenient)
		and inCashRange(cash, filter.above, filter.below, lenient)

	if main and next(filter.mutations) ~= nil then
		main = mutation ~= nil and filter.mutations[mutation:lower()] == true
	end

	if main then return true end

	-- Mutations on the Also Steal list use their own rarity and cash rules.
	if mutation and filter.alsoMutations[mutation:lower()] then
		return matchesSet(filter.mutatedRarities, rarity, lenient)
			and inCashRange(cash, filter.mutatedAbove, 0, lenient)
	end

	return false
end

local stealCache, stealCacheAt = {}, 0

---List the hatched animals other players dropped, refreshed every 2 seconds.
---Animals placed on plots have no prompt, so only dropped pickups can be stolen.
---@return table
---Animals we just dropped for a friend must not be grabbed again.
---@param model Instance
---@return boolean
local function isGivenAway(model)
	local spot = AutoFarm.giveSpot
	if not spot or os.clock() > (AutoFarm.giveUntil or 0) then return false end

	local ok, pivot = pcall(function()
		return (model :: Model):GetPivot().Position
	end)

	return ok and (pivot - spot).Magnitude < 80
end

local function refreshStealables()
	if os.clock() - stealCacheAt < 2 then return stealCache end

	stealCacheAt = os.clock()
	stealCache = {}

	for _, model in ipairs(collectionService:GetTagged("AnimalPickup")) do
		if not (model:IsA("Model") and model.Parent) or readAttribute(model, "Despawning") or isGivenAway(model) then continue end

		-- Still reserved for its owner, the server would refuse the grab.
		local reserved = readAttribute(model, "ReservedUserId")
		if reserved ~= nil and reserved ~= 0 and reserved ~= localPlayer.UserId then continue end

		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			table.insert(stealCache, { model = model, root = part })
		end
	end

	return stealCache
end

---List the animals that pass the filter within a radius, nearest first.
---@param position Vector3
---@param radius number
---@return table
local function getPassingSteals(position, radius)
	local passing = {}

	for _, item in ipairs(refreshStealables()) do
		if not (item.model.Parent and item.root.Parent) then continue end

		local distance = (item.root.Position - position).Magnitude
		if distance <= radius and passesStealFilter(item.model, false) then
			table.insert(passing, { model = item.model, root = item.root, distance = distance })
		end
	end

	table.sort(passing, function(a, b)
		return a.distance < b.distance
	end)

	return passing
end

---Find the nearest steal prompt.
---@param position Vector3
---@param radius number
---@return ProximityPrompt?, BasePart?
local function nearestStealPrompt(position, radius)
	local best, bestRoot, bestDistance

	for _, anchor in ipairs(collectionService:GetTagged(PROMPT_TAG)) do
		local prompt = anchor:IsA("ProximityPrompt") and anchor or anchor:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not (prompt and prompt.Enabled and prompt.Name:find("Steal")) then continue end

		local root = anchor:IsA("BasePart") and anchor
			or (anchor:IsA("Model") and (anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart", true)))
			or anchor:FindFirstChildWhichIsA("BasePart", true)
			or (prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent)
		if not root then continue end

		local distance = (root.Position - position).Magnitude
		if distance <= radius and (not bestDistance or distance < bestDistance) then
			best, bestRoot, bestDistance = prompt, root, distance
		end
	end

	return best, bestRoot
end

---Stop steal actions when Auto Steal is turned off.
---@return boolean
local function isStealCancelled()
	return not AutoFarm.autoSteal
end

---Record a pickup or steal in the log.
---@param tool Tool?
---@param model Instance?
local function logSteal(tool, model)
	local function readFrom(name)
		return (tool and readAttribute(tool, name)) or (model and readAttribute(model, name)) or nil
	end

	local name = readFrom("AnimalName") or (tool and tool.Name) or "?"
	local rarity = readFrom("Rarity") or "?"
	local value = tonumber(readFrom("CashPerSecond")) or getAnimalCash(tool or model)

	if not value and tool and backpackSellConfig and backpackSellConfig.ToolValue then
		local success, result = pcall(backpackSellConfig.ToolValue, tool)
		if success and type(result) == "number" then
			value = result
		end
	end

	if AutoFarm.postWebhook then
		AutoFarm.postWebhook(
			"Animal collected",
			string.format("%s (%s) %s/s", tostring(name), tostring(rarity), value and formatNumber(value) or "?"),
			value
		)
	end

	table.insert(AutoFarm.stealLog, 1, {
		time = os.date("%H:%M"),
		name = tostring(name),
		rarity = tostring(rarity),
		value = value,
	})

	while #AutoFarm.stealLog > MAX_STEAL_LOG do
		table.remove(AutoFarm.stealLog)
	end
end

---Get the position of the player's own base.
---@return Vector3?
local function getBaseTarget()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end

	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
			local hitbox = plot:FindFirstChild("Hitbox")

			if hitbox and hitbox:IsA("BasePart") then
				return hitbox.Position
			end
		end
	end

	return nil
end

---Deliver the carried animal. Hatched animals sell where you stand or go to the base,
---stolen animals go to the safe zone first.
---@param isHatch boolean?
---@return string "ok" | "dropped" | "fail"
local function deliverCarried(isHatch)
	AutoFarm.stealState = "delivering"

	local selling = AutoFarm.afterSteal == "Sell"

	-- Give To Friend: walk to Zone 1 and drop the animal there, nothing is sold or placed.
	if AutoFarm.afterSteal == "Give" then
		local getCenter = AutoFarm.zoneCenterFn
		local spot = getCenter and getCenter("Zone1")
		local dropRemote = replicatedStorage:FindFirstChild("DropCarriedRemote")

		if not (spot and dropRemote) then
			AutoFarm.state = "Give: Zone 1 or DropCarriedRemote not found"
			return "fail"
		end

		AutoFarm.state = "walking to Zone 1 to give"
		walkTo(spot, 90, 12, function()
			if isHatch then return not AutoFarm.autoFarm end
			return isStealCancelled()
		end)

		local _, root = getCharacter()
		if not root or getCarryCount() == 0 then return "dropped" end
		if (Vector3.new(spot.X, root.Position.Y, spot.Z) - root.Position).Magnitude > 40 then return "fail" end

		AutoFarm.giveSpot, AutoFarm.giveUntil = root.Position, os.clock() + 90
		dropRemote:FireServer()
		AutoFarm.state = "gave the animal in Zone 1"
		task.wait(1)

		return "ok"
	end

	local function shouldStop()
		if isHatch then
			return not AutoFarm.autoFarm
		end

		return isStealCancelled()
	end

	for _ = 1, 3 do
		local _, rootPart, humanoid = getCharacter()
		if not rootPart then return "fail" end

		if not (isHatch and selling) then
			local destination, arriveDistance = nil, 8

			if isHatch then
				destination, arriveDistance = getBaseTarget(), 5
			elseif not isAtSafeSpot(rootPart.Position) then
				destination = getSafeTarget(rootPart.Position)
			end

			if destination then
				AutoFarm.state = isHatch and "walking to base" or "walking to safe zone"
				walkTo(destination, 60, arriveDistance, function()
					return shouldStop() or getCarryCount() == 0
				end)
			end
		end

		if getCarryCount() == 0 then
			AutoFarm.stealState = "dropped, will re-grab"
			return "dropped"
		end

		if shouldStop() then return "fail" end

		-- Wait until we stand on the ground before placing or selling.
		local startedAt = os.clock()
		while os.clock() - startedAt < 2 and humanoid.FloorMaterial == Enum.Material.Air do
			task.wait(0.1)
		end

		local tool = getCarriedTool()
		if selling then
			AutoFarm.state = "selling"
			if tool then
				sellTools({ tool })
			end
		else
			AutoFarm.state = "placing"
			if tool and placeAnimalRemote then
				local offset = Vector3.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5))
				-- The server does Vector3 math on this argument, a CFrame errors out the remote handler.
				placeAnimalRemote:FireServer(tool, rootPart.Position + offset, placeSequence)
				placeSequence = placeSequence + 1
			end
		end

		task.wait(1.5)

		if getCarryCount() == 0 then
			AutoFarm.delivers = AutoFarm.delivers + 1
			AutoFarm.stealState = "delivered"
			equipPickaxe()
			return "ok"
		end
	end

	AutoFarm.stealState = "delivery failed, try the other After Grab option"
	return "fail"
end

---Walk to an animal and take it with the steal prompt.
---@param target table
---@return boolean
local function grabAnimal(target)
	local before = getCarryCount()

	AutoFarm.state = "approaching steal"
	walkTo(target.root.Position, 20, 5, isStealCancelled)

	local _, rootPart = getCharacter()
	if not (AutoFarm.autoSteal and rootPart) then return false end

	local prompt, promptRoot = nearestStealPrompt(rootPart.Position, 40)
	if not prompt then
		prompt, promptRoot = nearestStealPrompt(target.root.Position, 40)
	end

	if not (prompt and promptRoot) then
		AutoFarm.stealState = "no steal prompt at the target"
		task.wait(1)
		return false
	end

	-- The prompt must belong to the target, not to another animal.
	if (promptRoot.Position - target.root.Position).Magnitude > 20 then
		AutoFarm.stealState = "skip: nearest prompt belongs to another animal"
		task.wait(1.5)
		return false
	end

	AutoFarm.state = "grabbing"
	for _ = 1, 3 do
		if isStealCancelled() then break end

		triggerPrompt(prompt)

		local startedAt = os.clock()
		while os.clock() - startedAt < 2 and getCarryCount() <= before do
			task.wait(0.2)
		end

		if getCarryCount() > before then break end
	end

	if getCarryCount() <= before then return false end

	-- The server picks the animal, so judge what we actually got.
	local carried = getCarriedTool()
	if carried and not passesStealFilter(carried, true) then
		AutoFarm.junk = AutoFarm.junk + 1
		AutoFarm.stealState = "junk, selling it"
		sellTools({ carried })
		equipPickaxe()
		task.wait(1)
		return true
	end

	AutoFarm.steals = AutoFarm.steals + 1
	logSteal(carried, target.model)
	deliverCarried()

	return true
end

---One steal step. Returns true when it used the turn, false to let farming continue.
---@return boolean
local function stealStep()
	local _, rootPart = getCharacter()
	if not rootPart then return false end

	-- Finish delivering whatever is carried first.
	if getCarryCount() > 0 then
		deliverCarried()
		return true
	end

	local target = getPassingSteals(rootPart.Position, AutoFarm.stealRange)[1]

	if not target then
		if AutoFarm.autoFarm and not AutoFarm.huntFar then
			AutoFarm.stealState = ("no passing steal within %d studs (Auto Farm is on)"):format(AutoFarm.stealRange)
			return false
		end

		local far = getPassingSteals(rootPart.Position, math.huge)[1]
		if not far then
			AutoFarm.stealState = ("no steal passes the filter (stealables: %d)"):format(#refreshStealables())
			return false
		end

		AutoFarm.state = "hunting"
		AutoFarm.stealState = ("heading to %s (%dm)"):format(
			tostring(readAttribute(far.model, "AnimalName")),
			math.floor(far.distance)
		)
		walkTo(far.root.Position, 25, 6, isStealCancelled)

		return true
	end

	AutoFarm.stealState = ("target: %s (%s/s, %dm)"):format(
		tostring(readAttribute(target.model, "AnimalName")),
		formatNumber(getAnimalCash(target.model)),
		math.floor(target.distance)
	)

	if os.clock() - AutoFarm.lastStealAt < AutoFarm.stealDelay then return false end
	AutoFarm.lastStealAt = os.clock()

	return grabAnimal(target)
end

-- Every proximity prompt in the workspace, used to find the hatched animal.
local promptAnchors = {}
local MACHINE_PROMPTS = { FuseMachine = true, EggMachine = true, Furnace = true, MergeMachine = true }
local PREFERRED_PROMPT_WORDS = { "steal", "collect", "pick", "grab", "take" }

---Track a proximity prompt.
---@param instance Instance
local function indexPrompt(instance)
	if instance:IsA("ProximityPrompt") and instance.Parent then
		promptAnchors[instance] = instance.Parent
	end
end

task.spawn(function()
	for _, instance in ipairs(workspace:GetDescendants()) do
		indexPrompt(instance)
	end

	table.insert(AutoFarm.connections, workspace.DescendantAdded:Connect(indexPrompt))
	table.insert(AutoFarm.connections, workspace.DescendantRemoving:Connect(function(instance)
		promptAnchors[instance] = nil
	end))
end)

---Get the part a prompt is attached to.
---@param anchor Instance
---@return BasePart?
local function getPromptRoot(anchor)
	if anchor:IsA("BasePart") then return anchor end

	if anchor:IsA("Attachment") and anchor.Parent and anchor.Parent:IsA("BasePart") then
		return anchor.Parent
	end

	return anchor:FindFirstChildWhichIsA("BasePart", true)
end

---Check whether a prompt looks like a steal or collect prompt.
---@param prompt ProximityPrompt
---@return boolean
local function isPreferredPrompt(prompt)
	local label = (prompt.Name .. " " .. prompt.ActionText):lower()

	for _, word in ipairs(PREFERRED_PROMPT_WORDS) do
		if label:find(word, 1, true) then
			return true
		end
	end

	return false
end

---Find the prompt of the hatched animal around a position.
---@param position Vector3
---@param radius number
---@return ProximityPrompt?, BasePart?
local function getCollectTarget(position, radius)
	local best, bestRoot, bestDistance, bestPreferred

	for prompt, anchor in pairs(promptAnchors) do
		if not (prompt.Parent and prompt.Enabled) then continue end

		local model = prompt:FindFirstAncestorOfClass("Model")
		if model and MACHINE_PROMPTS[model.Name] then continue end

		local root = getPromptRoot(anchor)
		if not root then continue end

		local distance = (root.Position - position).Magnitude
		if distance > radius then continue end

		local preferred = isPreferredPrompt(prompt)
		local better = best == nil
			or (preferred and not bestPreferred)
			or (preferred == bestPreferred and distance < bestDistance)

		if better then
			best, bestRoot, bestDistance, bestPreferred = prompt, root, distance, preferred
		end
	end

	return best, bestRoot
end

---Find the dropped animal (tag AnimalPickup) nearest to a position.
---@param position Vector3
---@param radius number
---@return BasePart?, Model?
local function getPickupRoot(position, radius)
	local best, bestModel, bestDistance

	for _, model in ipairs(collectionService:GetTagged("AnimalPickup")) do
		if not (model:IsA("Model") and model.Parent) or readAttribute(model, "Despawning") or isGivenAway(model) then continue end

		-- Animals reserved for another player are not ours, never judge or chase them.
		local reserved = readAttribute(model, "ReservedUserId")
		if reserved ~= nil and reserved ~= localPlayer.UserId then continue end

		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not part then continue end

		local distance = (part.Position - position).Magnitude
		if distance <= radius and (not bestDistance or distance < bestDistance) then
			best, bestModel, bestDistance = part, model, distance
		end
	end

	return best, bestModel
end

---Check a dropped animal against the steal filter before walking to it.
---@param model Model
---@return boolean
local function pickupPasses(model)
	-- Without any animal data we cannot judge it: take it only when no filter is set.
	if readAttribute(model, "AnimalName") == nil and readAttribute(model, "CashPerSecond") == nil then
		local filter = AutoFarm.filter
		return (filter.above or 0) <= 0 and (filter.below or 0) <= 0
			and next(filter.rarities) == nil and next(filter.sizes) == nil and next(filter.mutations) == nil
	end

	return passesStealFilter(model, false)
end

---Grab the hatched animal right after the egg breaks, like pressing E.
---@param anchor Vector3
---@return boolean
local function collectHatched(anchor, target)
	AutoFarm.state = "grabbing the hatched animal"

	local offsets = { Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3) }
	local deadline = os.clock() + 16
	local sweep, attempts = 0, 0
	local startedWaiting = os.clock()

	local function shouldStop()
		return not AutoFarm.autoFarm
	end

	while AutoFarm.running and AutoFarm.autoFarm and getCarryCount() == 0 and os.clock() < deadline do
		-- The game tags dropped animals "AnimalPickup", find that one first and then its prompt.
		local pickup, pickupModel = getPickupRoot(anchor, 40)
		local prompt, root

		-- A specific animal was chosen, ignore the other pickups near it.
		if target then
			pickup = target.Parent and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)) or nil
			pickupModel = pickup and target or nil
			if not pickup then return false end
		end

		-- Does not meet the filter: leave it, it despawns by itself, and go break the next egg.
		if pickupModel and not pickupPasses(pickupModel) then
			AutoFarm.junk = AutoFarm.junk + 1
			local seen = getAnimalCash(pickupModel)
			AutoFarm.state = string.format(
				"skipped %s: %s/s (filter %s to %s)",
				tostring(readAttribute(pickupModel, "AnimalName") or "animal"),
				seen and formatNumber(seen) or "no cash/s",
				formatNumber(AutoFarm.filter.above or 0),
				(AutoFarm.filter.below or 0) > 0 and formatNumber(AutoFarm.filter.below) or "no limit"
			)
			return false
		end

		if pickup then
			prompt, root = getCollectTarget(pickup.Position, 15)
		end

		-- The server only anchors the prompt once we are close to the animal, so walk to it first.
		if pickup and not prompt then
			AutoFarm.state = "walking to the animal"
			walkTo(pickup.Position, 10, 5, shouldStop)
			prompt, root = getCollectTarget(pickup.Position, 15)
		end

		if not prompt then
			prompt, root = getCollectTarget(anchor, 25)
		end

		if prompt and root then
			-- The prompt works within its own activation distance, no need to stand on it.
			local reach = math.max(3, math.min(prompt.MaxActivationDistance - 2, 8))
			walkTo(root.Position, 10, reach, shouldStop)
			triggerPrompt(prompt)

			local startedAt = os.clock()
			while os.clock() - startedAt < 3 and getCarryCount() == 0 do
				task.wait(0.2)
			end

			attempts = attempts + 1
			if attempts >= 3 then break end
		else
			-- Nothing to grab yet, stand still while the animal appears, only sweep after a while.
			AutoFarm.state = "waiting for the animal"
			task.wait(0.25)

			if os.clock() - startedWaiting > 5 then
				sweep = sweep + 1
				AutoFarm.state = "looking for the animal"
				walkTo(anchor + offsets[(sweep - 1) % #offsets + 1], 5, 1, shouldStop)
				startedWaiting = os.clock() - 3
			end
		end
	end

	return getCarryCount() > 0
end

---Filter, then deliver, the animal that was just grabbed.
local function processGrabbed()
	AutoFarm.pickups = AutoFarm.pickups + 1

	local carried = getCarriedTool()

	if carried and not passesStealFilter(carried, true) then
		AutoFarm.junk = AutoFarm.junk + 1
		AutoFarm.state = "animal below the filter, selling"
		sellTools({ carried })
		equipPickaxe()
		return
	end

	logSteal(carried, nil)
	deliverCarried(true)
	equipPickaxe()
end

---Print what the steal engine sees, so it can be shared when something does not work.
local function debugSteal()
	local _, rootPart = getCharacter()
	local position = rootPart and rootPart.Position or Vector3.zero
	local lines = {}

	local function add(text)
		table.insert(lines, text)
	end

	add("[StealDebug] ----------------------------")
	add(("state=%s | steal=%s"):format(AutoFarm.state, AutoFarm.stealState))
	add(("autoSteal=%s autoFarm=%s huntFar=%s afterSteal=%s range=%d"):format(
		tostring(AutoFarm.autoSteal),
		tostring(AutoFarm.autoFarm),
		tostring(AutoFarm.huntFar),
		AutoFarm.afterSteal,
		AutoFarm.stealRange
	))
	add(("carry=%d/%d | character=%s"):format(
		math.floor(getCarryCount()),
		math.floor(getSatchelCapacity()),
		tostring(rootPart ~= nil)
	))
	add(("modules: mutation=%s safeZone=%s sell=%s | placeRemote=%s sellRemote=%s"):format(
		tostring(mutationConfig ~= nil),
		tostring(safeZoneQuery ~= nil),
		tostring(backpackSellConfig ~= nil),
		tostring(placeAnimalRemote ~= nil),
		tostring(sellRemote ~= nil)
	))

	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			local animals = 0

			for _, descendant in ipairs(plot:GetDescendants()) do
				if descendant:IsA("Model") and readAttribute(descendant, "AnimalName") then
					animals = animals + 1
				end
			end

			add(("plot %s owner=%s animals=%d"):format(plot.Name, tostring(plot:GetAttribute("OwnerUserId")), animals))
		end
	else
		add("workspace.Plots was not found")
	end

	stealCacheAt = 0
	local stealables = refreshStealables()
	local inRange = getPassingSteals(position, AutoFarm.stealRange)
	local anywhere = getPassingSteals(position, math.huge)
	add(("stealables=%d | passing in range=%d | passing anywhere=%d"):format(#stealables, #inRange, #anywhere))

	for index = 1, math.min(#stealables, 3) do
		local item = stealables[index]
		local attributes = {}

		for name, value in pairs(item.model:GetAttributes()) do
			table.insert(attributes, ("%s=%s"):format(name, tostring(value)))
		end

		add(("animal %s | passes=%s | %dm | %s"):format(
			item.model:GetFullName(),
			tostring(passesStealFilter(item.model, false)),
			math.floor((item.root.Position - position).Magnitude),
			table.concat(attributes, ", ")
		))
	end

	local tagged = collectionService:GetTagged(PROMPT_TAG)
	local stealPrompts = 0

	for _, anchor in ipairs(tagged) do
		local prompt = anchor:IsA("ProximityPrompt") and anchor or anchor:FindFirstChildWhichIsA("ProximityPrompt", true)

		if prompt and prompt.Name:find("Steal") then
			stealPrompts = stealPrompts + 1

			if stealPrompts <= 5 then
				add(("prompt %s | enabled=%s | %s"):format(prompt.Name, tostring(prompt.Enabled), prompt:GetFullName()))
			end
		end
	end

	add(("%s tagged=%d | steal prompts=%d"):format(PROMPT_TAG, #tagged, stealPrompts))

	local nearPrompt, nearRoot = nearestStealPrompt(position, 40)
	if nearPrompt and nearRoot then
		add(("nearest steal prompt within 40: %s (%dm)"):format(
			nearPrompt:GetFullName(),
			math.floor((nearRoot.Position - position).Magnitude)
		))
	else
		add("nearest steal prompt within 40: none")
	end

	local safeTarget = getSafeTarget(position)
	add(("safe target=%s | at safe spot=%s"):format(tostring(safeTarget), tostring(isAtSafeSpot(position))))

	warn(table.concat(lines, "\n"))
end

---Sell everything sellable in the backpack.
local function sellAllBackpack()
	local below, above = AutoFarm.sellBelow or 0, AutoFarm.sellAbove or 0
	local tools = {}

	for _, tool in ipairs(getSellableTools()) do
		if below <= 0 and above <= 0 then
			table.insert(tools, tool)
		else
			-- With a filter set, an animal whose $/s is unknown is kept, never sold by guess.
			local cash = getAnimalCash(tool)

			if cash and (below <= 0 or cash < below) and cash >= above then
				table.insert(tools, tool)
			end
		end
	end

	if #tools == 0 then return end

	AutoFarm.state = "selling backpack"
	sellTools(tools)
end

---Walk toward the chosen zone so its eggs stream in.
---@param rootPart BasePart
---@return boolean
---Get the world position of a zone, Zone13 and other far zones only stream in near the player.
---@param zoneName string
---@return Vector3?
local function getZoneCenter(zoneName)
	local number = tonumber(string.match(zoneName, "%d+"))
	if not number then return nil end

	-- ZoneHitboxes is always replicated, the zone builds are not and sit at the origin until streamed.
	local build = workspace:FindFirstChild("Build")
	local hitboxes = build and build:FindFirstChild("ZoneHitboxes")
	local hitbox = hitboxes and hitboxes:FindFirstChild(tostring(number))

	if hitbox and hitbox:IsA("BasePart") then
		return hitbox.Position
	elseif hitbox and hitbox:IsA("Model") then
		return hitbox:GetPivot().Position
	end

	local zoneBuilds = getZoneBuilds()
	local zone = zoneBuilds and zoneBuilds:FindFirstChild(zoneName)

	if zone then
		local pivot = zone:GetPivot().Position
		if pivot.Magnitude > 1 then
			return pivot
		end
	end

	return nil
end

local function travelToZone(rootPart)
	if AutoFarm.zone == "Auto" then return false end

	local position = getZoneCenter(AutoFarm.zone)
	if not position then
		AutoFarm.state = "cannot find the position of " .. AutoFarm.zone
		return false
	end

	-- Close enough for the zone to stream in, wait for its eggs instead of walking on.
	if (Vector3.new(position.X, rootPart.Position.Y, position.Z) - rootPart.Position).Magnitude <= 60 then
		return false
	end

	AutoFarm.state = "traveling to " .. AutoFarm.zone
	walkTo(position, 25, 30, function()
		if not AutoFarm.autoFarm then return true end

		local _, root = getCharacter()
		return root ~= nil and pickEgg(root.Position) ~= nil
	end)

	return true
end

AutoFarm.zoneCenterFn = getZoneCenter

---Stop the player from walking.
local function stopWalking()
	local _, rootPart, humanoid = getCharacter()

	if rootPart then
		humanoid:MoveTo(rootPart.Position)
	end
end

---Merged egg tools in the backpack (or in the hand).
---@return {Tool}
local function getMergeEggTools()
	local list = {}
	local character = localPlayer.Character
	local backpack = localPlayer:FindFirstChild("Backpack")

	for _, container in ipairs({ backpack, character }) do
		for _, child in ipairs(container and container:GetChildren() or {}) do
			if child:IsA("Tool") and collectionService:HasTag(child, "MergeEggTool") then
				table.insert(list, child)
			end
		end
	end

	return list
end

---A merged egg that is worth trying now: a new one, or one that failed more than 2 minutes ago.
---@return Tool?
local function nextEggToPlace()
	for _, tool in ipairs(getMergeEggTools()) do
		local failedAt = AutoFarm.failedEggTools[tool:GetAttribute("EggId") or tool.Name]

		if not failedAt or os.clock() - failedAt > 120 then
			return tool
		end
	end

	return nil
end

local failedEggSpots = {}
local mergeConfigModule = requireModule("MergeConfig")

-- Placement strategy: measure the ACTUAL bounding boxes of placed eggs (EggFinalHeight
-- estimates the FINAL grown size — placed eggs start small and grow into it, so formula
-- footprints over-refuse). Each candidate spot gets a min-gap score against every egg's
-- real XZ half-extent, and the roomiest corner is placed first: the fresh merge egg
-- is small at placement time (MergedScale ~= 20 studs tall, ~5 stud half-width), so the
-- roomiest spot is both legal now and safest as it grows. When the plot has no spot
-- at the safe clearance, the clearance relaxes one step per retry cycle and exactly
-- ONE borderline spot is probed — the server's true threshold is learned from its
-- own refusals instead of spamming them.
local eggOwnHalfWidth = 5
local eggClearance = 1
local EGG_CLEARANCE_FLOOR = -6
local eggClearanceStep = -2

---Final size of an egg (a tool or a placed egg), from the game's own formula.
---@param instance Instance
---@return number
local function eggFootprint(instance)
	local name = readAttribute(instance, "AnimalName")

	if name and type(mergeConfigModule) == "table" and type(mergeConfigModule.EggFinalHeight) == "function" then
		local ok, height = pcall(mergeConfigModule.EggFinalHeight, name, tonumber(readAttribute(instance, "WeightKg")))

		if ok and type(height) == "number" and height > 0 and height < 1000 then
			return height
		end
	end

	return 12
end

---Free ground positions on our own plot, roomiest corner first.
---@param plot Instance
---@param hitbox BasePart
---@param from Vector3
---@param newSize number
---@return {position: Vector3, minGap: number}
local function findEggSpots(plot, hitbox, from, newSize)
	local excluded = { hitbox }
	local occupied = {}

	for _, tag in ipairs({ "PlacedAnimal", "MergeEggPlaced" }) do
		for _, instance in ipairs(collectionService:GetTagged(tag)) do
			table.insert(excluded, instance)

			local ok, pivot = pcall(function()
				return (instance :: Model):GetPivot().Position
			end)

			-- The game only refuses spots too close to another egg, animals do not count.
			if ok and tag == "MergeEggPlaced" then
				-- Real bounding box: eggs grow, the attribute formula only guesses.
				local boxOk, halfExtent = pcall(function()
					local _, size = (instance :: Model):GetBoundingBox()
					return math.max(size.X, size.Z) / 2
				end)

				table.insert(occupied, {
					position = pivot,
					radius = (boxOk and halfExtent or eggFootprint(instance)) + eggClearance,
				})
			end
		end
	end

	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player.Character then table.insert(excluded, player.Character) end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded

	local spacing, now = 4, os.clock()
	local margin = 4
	local spots = {}
	local halfX, halfZ = math.max(0, hitbox.Size.X / 2 - margin), math.max(0, hitbox.Size.Z / 2 - margin)

	for x = -halfX, halfX, spacing do
		for z = -halfZ, halfZ, spacing do
			local top = hitbox.CFrame:PointToWorldSpace(Vector3.new(x, 0, z)) + Vector3.new(0, 40, 0)
			local hit = workspace:Raycast(top, Vector3.new(0, -150, 0), params)

			if hit then
				local position, minGap, legal = hit.Position, math.huge, true

				for _, other in ipairs(occupied) do
					local gap = (Vector3.new(other.position.X, position.Y, other.position.Z) - position).Magnitude
					minGap = math.min(minGap, gap - other.radius - eggOwnHalfWidth)
				end

				-- Too deep inside an existing egg's footprint, or blacklisted recently.
				if minGap < -eggClearance then legal = false end

				if legal then
					for _, bad in ipairs(failedEggSpots) do
						if now - bad.at < 120 and (bad.position - position).Magnitude < 3 then
							legal = false
							break
						end
					end
				end

				if legal then table.insert(spots, { position = position, minGap = minGap }) end
			end
		end
	end

	-- Roomiest corner first: fewest refusals, and the most room to grow into.
	table.sort(spots, function(a, b)
		if math.abs(a.minGap - b.minGap) > 2 then
			return a.minGap > b.minGap
		end
		return (a.position - from).Magnitude < (b.position - from).Magnitude
	end)

	return spots
end

---Walk to our plot and put merged eggs on free spots. One egg per call.
---@return boolean Used the turn.
local function placeMergedEggs()
	local mergeRemoteNow = replicatedStorage:FindFirstChild("MergeMachineRemote")
	local tool = nextEggToPlace()

	if not (mergeRemoteNow and tool) then return false end

	local _, rootPart, humanoid = getCharacter()
	if not rootPart then return false end

	local plots = workspace:FindFirstChild("Plots")
	local plot, hitbox

	for _, candidate in ipairs(plots and plots:GetChildren() or {}) do
		if candidate:GetAttribute("OwnerUserId") == localPlayer.UserId then
			plot, hitbox = candidate, candidate:FindFirstChild("Hitbox")
			break
		end
	end

	if not (plot and hitbox and hitbox:IsA("BasePart")) then
		AutoFarm.state = "Place Egg: own plot not found"
		return false
	end

	local function shouldStop()
		return not (AutoFarm.autoPlaceEggs or AutoFarm.autoFarm)
	end

	if (Vector3.new(hitbox.Position.X, rootPart.Position.Y, hitbox.Position.Z) - rootPart.Position).Magnitude > 25 then
		AutoFarm.state = "walking to plot to place the egg"
		walkTo(hitbox.Position, 60, 12, shouldStop)
	end

	_, rootPart, humanoid = getCharacter()
	if not rootPart then return false end

	local spots = findEggSpots(plot, hitbox, rootPart.Position, eggFootprint(tool))

	-- The exact server rule says none of these spots fit: relax the clearance one step
	-- and wait. The next cycle probes exactly one borderline spot, so the server's real
	-- threshold is learned without "too close to another egg" spam.
	if #spots == 0 then
		if eggClearance > EGG_CLEARANCE_FLOOR then
			eggClearance = eggClearance + eggClearanceStep
		end

		AutoFarm.state = ("no legal spot for this egg (clearance %.0f), retrying in 2 minutes"):format(eggClearance)
		AutoFarm.failedEggTools[tool:GetAttribute("EggId") or tool.Name] = os.clock()
		equipPickaxe()
		return true
	end

	AutoFarm.state = "placing the merged egg"
	pcall(function()
		humanoid:EquipTool(tool)
	end)
	task.wait(0.3)

	-- One probe per cycle: the roomiest spot only. A refusal relaxes the clearance.
	local candidate = spots[1]
	local spot = candidate.position
	mergeRemoteNow:FireServer("PlaceEgg", tool, spot)
	task.wait(0.6)

	if not tool.Parent or (tool.Parent ~= localPlayer.Character and tool.Parent ~= localPlayer:FindFirstChild("Backpack")) then
		AutoFarm.state = "merged egg placed"
		eggClearance = 1 -- reset to safe spacing after a success
		equipPickaxe()
		return true
	end

	table.insert(failedEggSpots, { position = spot, at = os.clock() })
	eggClearance = math.max(EGG_CLEARANCE_FLOOR, eggClearance + eggClearanceStep)
	equipPickaxe()
	return true
end

---One full farm cycle: walk, break, sell.
-- Eggs that broke but have not hatched yet: we keep breaking and come back when the animal drops.
local pendingHatches = {}
local judgedPickups = setmetatable({}, { __mode = "k" })
local firstSeenPickups = setmetatable({}, { __mode = "k" })

---Collect hatched animals of the eggs we already broke, only the ones that pass the filter.
---@return boolean Used the turn.
local function collectPending()
	local now = os.clock()

	for index = #pendingHatches, 1, -1 do
		if now - pendingHatches[index].at > 45 then
			table.remove(pendingHatches, index)
		end
	end

	if #pendingHatches == 0 then return false end

	for index, entry in ipairs(pendingHatches) do
		for _, model in ipairs(collectionService:GetTagged("AnimalPickup")) do
			if not (model:IsA("Model") and model.Parent) or judgedPickups[model] then continue end
			if readAttribute(model, "Despawning") or isGivenAway(model) then continue end

			local reserved = readAttribute(model, "ReservedUserId")
			if reserved ~= nil and reserved ~= localPlayer.UserId then continue end

			local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if not part or (part.Position - entry.pos).Magnitude > 40 then continue end

			-- The attributes can arrive a moment after the model, give them time before judging.
			firstSeenPickups[model] = firstSeenPickups[model] or now
			if getAnimalCash(model) == nil and now - firstSeenPickups[model] < 2 then continue end

			table.remove(pendingHatches, index)

			if not pickupPasses(model) then
				judgedPickups[model] = true
				AutoFarm.junk = AutoFarm.junk + 1

				local seen = getAnimalCash(model)
				AutoFarm.lastJudge = string.format(
					"SKIP %s %s/s (filter %s to %s)",
					tostring(readAttribute(model, "AnimalName") or "animal"),
					seen and formatNumber(seen) or "no cash/s",
					formatNumber(AutoFarm.filter.above or 0),
					(AutoFarm.filter.below or 0) > 0 and formatNumber(AutoFarm.filter.below) or "no limit"
				)
				AutoFarm.state = AutoFarm.lastJudge

				return false
			end

			judgedPickups[model] = true
			AutoFarm.lastJudge = string.format(
				"TAKE %s %s/s",
				tostring(readAttribute(model, "AnimalName") or "animal"),
				formatNumber(getAnimalCash(model))
			)
			if getCarryCount() > 0 or collectHatched(part.Position, model) then
				processGrabbed()
			end

			return true
		end
	end

	return false
end

---A merged egg waits in the backpack, it goes to the plot before any farming.
---@return boolean
local function hasEggToPlace()
	return AutoFarm.autoPlaceEggs and nextEggToPlace() ~= nil
end

local function farmStep()
	local _, rootPart = getCharacter()
	if not rootPart then return end

	if AutoFarm.autoGrab and collectPending() then return end
	if hasEggToPlace() and getCarryCount() == 0 and placeMergedEggs() then return end

	local egg, distance = pickEgg(rootPart.Position)
	if not egg then
		AutoFarm.currentEgg = nil
		if travelToZone(rootPart) then return end

		AutoFarm.state = "no eggs found in " .. AutoFarm.zone
		task.wait(1)
		return
	end

	AutoFarm.currentEgg = egg

	-- Walk until the egg is in reach.
	AutoFarm.state = "walking to " .. getEggTypeName(egg)
	if distance > hitRange then
		walkTo(egg.Position, 90, math.max(4, hitRange * 0.6), function()
			return not AutoFarm.autoFarm or hasEggToPlace()
		end)
	end

	local _, hitRoot = getCharacter()
	if not (AutoFarm.autoFarm and hitRoot and egg.Parent and getSurfaceDistance(egg, hitRoot.Position) <= hitRange) then
		return
	end

	-- Hit until the egg is gone.
	AutoFarm.state = "hitting " .. getEggTypeName(egg)
	local pickaxe = equipPickaxe()
	local lastSwing = 0
	local useGameSwing = AutoFarm.attack == "Game Auto Swing" and gameAutoSwing ~= nil

	while AutoFarm.running and AutoFarm.autoFarm and isEggLive(egg) and not hasEggToPlace() do
		local _, root = getCharacter()
		if not root then break end
		if getSurfaceDistance(egg, root.Position) > hitRange + 3 then break end

		if useGameSwing then
			-- The game's own auto swing picks the egg and swings, we only keep it on.
			if not gameAutoSwing.IsOn() then
				pcall(gameAutoSwing.SetOn, true)
			end

			pickaxe = equipPickaxe()
		else
			local pace = getSwingPace()
			if os.clock() - lastSwing >= pace then
				if AutoFarm.attack == "Direct Hit" then
					directHit(egg)
				elseif pickaxe then
					pickaxe:Activate()
				end

				lastSwing = os.clock()
			end
		end

		task.wait(0.05)
	end

	-- Turn the game's auto swing off again so it does not swing while we walk or carry.
	if useGameSwing and gameAutoSwing.IsOn() then
		pcall(gameAutoSwing.SetOn, false)
	end

	local broken = not isEggLive(egg)
	if broken then
		AutoFarm.eggsBroken = AutoFarm.eggsBroken + 1
	end

	local _, afterRoot = getCharacter()
	local anchor = afterRoot and afterRoot.Position
	stopWalking()

	-- Grab the hatched animal right after the egg breaks, like pressing E.
	if broken and AutoFarm.autoGrab and AutoFarm.autoFarm and anchor then
		if getCarryCount() > 0 then
			processGrabbed()
		elseif AutoFarm.waitForHatch then
			-- Wait For Hatch: stay and take the animal before the next egg.
			if collectHatched(anchor) then
				processGrabbed()
			end
		else
			-- Do not wait for the hatch, break the next egg and come back for the animal.
			table.insert(pendingHatches, { pos = anchor, at = os.clock() })
		end
	end

	if AutoFarm.autoSell and AutoFarm.autoFarm then
		sellAllBackpack()
		equipPickaxe()
	end
end

-- ESP.
local espParent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
local espFolder = Instance.new("Folder")
espFolder.Name = "AutoFarmEsp"
espFolder.Parent = espParent
AutoFarm.espFolder = espFolder

local espEntries = {}

---Create or update one ESP label.
---@param key Instance
---@param adornee BasePart
---@param text string
---@param color Color3
local function setEsp(key, adornee, text, color)
	local entry = espEntries[key]

	if not entry then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Esp"
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(220, 44)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.Adornee = adornee
		gui.Parent = espFolder

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextStrokeTransparency = 0.4
		label.Parent = gui

		entry = { gui = gui, label = label }
		espEntries[key] = entry
	end

	entry.gui.Adornee = adornee
	entry.label.Text = text
	entry.label.TextColor3 = color
end

---Remove every ESP label.
local function clearEsp()
	for key, entry in pairs(espEntries) do
		entry.gui:Destroy()
		espEntries[key] = nil
	end
end

---Refresh the egg and animal labels.
local function updateEsp()
	local _, rootPart = getCharacter()
	if not rootPart then return end

	local seen = {}

	if AutoFarm.espEggs then
		local list = {}

		for _, egg in ipairs(collectionService:GetTagged(EGG_TAG)) do
			if not (egg:IsA("BasePart") and isEggLive(egg)) then continue end

			local distance = (egg.Position - rootPart.Position).Magnitude
			if distance <= AutoFarm.espRange then
				table.insert(list, { egg = egg, distance = distance })
			end
		end

		table.sort(list, function(a, b)
			return a.distance < b.distance
		end)

		for index = 1, math.min(#list, MAX_ESP) do
			local egg = list[index].egg
			local luck = tonumber(readAttribute(egg, "HatchLuck")) or tonumber(readAttribute(egg, "Luck"))
			local text = getEggTypeName(egg)

			if luck then
				text = ("%s x%s"):format(text, formatNumber(luck))
			end

			seen[egg] = true
			setEsp(egg, egg, ("%s\n%dm"):format(text, math.floor(list[index].distance)), Color3.fromRGB(255, 220, 90))
		end
	end

	if AutoFarm.espAnimals then
		local list = {}

		for _, item in ipairs(refreshStealables()) do
			if not (item.model.Parent and item.root.Parent) then continue end

			local distance = (item.root.Position - rootPart.Position).Magnitude
			if distance <= AutoFarm.espRange then
				table.insert(list, { item = item, distance = distance })
			end
		end

		table.sort(list, function(a, b)
			return a.distance < b.distance
		end)

		for index = 1, math.min(#list, MAX_ESP) do
			local item = list[index].item
			local cash = getAnimalCash(item.model)
			local text = ("%s | %s\n%s/s"):format(
				tostring(readAttribute(item.model, "AnimalName")),
				tostring(readAttribute(item.model, "Rarity") or "?"),
				formatNumber(cash)
			)
			local color = passesStealFilter(item.model, false) and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(220, 220, 220)

			seen[item.model] = true
			setEsp(item.model, item.root, text, color)
		end
	end

	for key, entry in pairs(espEntries) do
		if not seen[key] then
			entry.gui:Destroy()
			espEntries[key] = nil
		end
	end
end

-- Load Rayfield through the custom request function.
local response = request({ Url = RAYFIELD_URL, Method = "GET" })
if not (response and response.Success) then
	return warn("Failed to fetch Rayfield.")
end

-- Menu: the custom Losarinz dashboard UI (LosarinzUI.luau, sits next to this file in
-- the executor workspace or on a hosted URL). Real Rayfield stays as the fallback.
local rayfield
do
	local ok, result = pcall(function()
		local source

		if isfile and readfile and isfile("LosarinzUI.luau") then
			source = readfile("LosarinzUI.luau")
		elseif LOSARINZ_UI_URL ~= "" then
			source = game:HttpGet(LOSARINZ_UI_URL, true)
		end

		local lib = loadstring(source)()

		if typeof(lib) ~= "table" or typeof(lib.CreateRayfieldCompat) ~= "function" then
			return nil
		end

		return lib.CreateRayfieldCompat()
	end)

	if ok and result then
		rayfield = result
	else
		warn("[AutoBreakEggs] LosarinzUI failed, falling back to Rayfield: " .. tostring(result))

		local okRayfield, rayfieldErr = pcall(function()
			rayfield = loadstring(response.Body)()
		end)

		if not (okRayfield and rayfield) then
			return warn("[AutoBreakEggs] No menu library available: " .. tostring(rayfieldErr))
		end
	end
end
AutoFarm.rayfield = rayfield

local window = rayfield:CreateWindow({
	Name = "Losarinz Trainer",
	LoadingTitle = "Losarinz Trainer",
	LoadingSubtitle = "Break and Steal an Egg",
	Theme = "Amethyst",
	ConfigurationSaving = { Enabled = true, FolderName = "AutoBreakEggs", FileName = "settings" },
	KeySystem = false,
})

local farmTab = window:CreateTab("Farm", 4483362458)
local collectTab = window:CreateTab("Collect", 4483362458)
local stealTab = window:CreateTab("Steal", 4483362458)
local petsTab = window:CreateTab("Pets", 4483362458)
local enchantTab = window:CreateTab("Enchant", 4483362458)
local progressionTab = window:CreateTab("Upgrades", 4483362458)
local visualsTab = window:CreateTab("Visuals", 4483362458)
local webhookTab = window:CreateTab("Webhook", 4483362458)
local miscTab = window:CreateTab("Misc", 4483362458)

---Plain amount input without the steal filter notification.
---@param tab table
---@param name string
---@param flag string
---@param placeholder string
---@param apply function
local function createPlainAmountInput(tab, name, flag, placeholder, apply)
	tab:CreateInput({
		Name = name,
		CurrentValue = "",
		PlaceholderText = placeholder,
		RemoveTextAfterFocusLost = false,
		Flag = flag,
		Callback = function(text)
			local value = parseAmount(text)

			if value == nil then
				rayfield:Notify({ Title = "Invalid amount", Content = "Use a format like 500b, 10T or 1qa.", Duration = 4 })
				return
			end

			apply(value)
		end,
	})
end

---Create an input that accepts amounts like 10T.
---@param tab table
---@param name string
---@param flag string
---@param apply function
local function createAmountInput(tab, name, flag, apply)
	tab:CreateInput({
		Name = name,
		CurrentValue = "",
		PlaceholderText = "e.g. 10T",
		RemoveTextAfterFocusLost = false,
		Flag = flag,
		Callback = function(text)
			local value = parseAmount(text)

			if value == nil then
				rayfield:Notify({
					Title = "Invalid amount",
					Content = "Use a format like 500b, 10T or 1qa.",
					Duration = 4,
				})
				return
			end

			apply(value)

			local filter = AutoFarm.filter
			local above, below = filter.above or 0, filter.below or 0

			if below > 0 and below <= above then
				rayfield:Notify({
					Title = "Filter conflict",
					Content = "Steal Below must be higher than Steal Above (or 0 for no limit), otherwise nothing passes.",
					Duration = 6,
				})
			else
				rayfield:Notify({
					Title = "Filter saved",
					Content = string.format("Steal range: %s to %s", formatNumber(above), below > 0 and formatNumber(below) or "no limit"),
					Duration = 3,
				})
			end
		end,
	})
end

-- Farm tab: everything about breaking eggs.
farmTab:CreateToggle({
	Name = "Auto Farm Eggs",
	CurrentValue = false,
	Flag = "AutoFarm",
	Callback = function(value)
		AutoFarm.autoFarm = value

		if value then
			AutoFarm.eggsBroken = 0
			AutoFarm.farmStartedAt = os.clock()
		end
	end,
})

farmTab:CreateSection("Targets")

local eggDropdown = farmTab:CreateDropdown({
	Name = "Break Eggs",
	Options = getEggTypeNames(),
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "EggTypes",
	Callback = function(options)
		AutoFarm.eggTypes = toSet(options)
	end,
})

local zoneDropdown = farmTab:CreateDropdown({
	Name = "Zone",
	Options = getZoneNames(),
	CurrentOption = { "Auto" },
	MultipleOptions = false,
	Flag = "Zone",
	Callback = function(options)
		AutoFarm.zone = options[1]
	end,
})

farmTab:CreateDropdown({
	Name = "Target Priority",
	Options = { "Nearest", "Luckiest", "Biggest" },
	CurrentOption = { "Nearest" },
	MultipleOptions = false,
	Flag = "Priority",
	Callback = function(options)
		AutoFarm.priority = options[1]
	end,
})

farmTab:CreateToggle({
	Name = "Prioritize Titanic Egg",
	CurrentValue = false,
	Flag = "TitanicFirst",
	Callback = function(value)
		AutoFarm.titanicFirst = value
	end,
})

createPlainAmountInput(farmTab, "Max Egg HP", "MaxEggHp", "e.g. 500t, 1qa", function(value)
	AutoFarm.maxEggHp = value
end)

farmTab:CreateSection("Attack")

farmTab:CreateDropdown({
	Name = "Attack",
	Options = { "Direct Hit", "Pickaxe Swing", "Game Auto Swing" },
	CurrentOption = { "Direct Hit" },
	MultipleOptions = false,
	Flag = "AttackMode",
	Callback = function(options)
		AutoFarm.attack = options[1]
	end,
})

farmTab:CreateToggle({
	Name = "Auto Hit Delay (fastest the game allows)",
	CurrentValue = true,
	Flag = "AutoHitDelay",
	Callback = function(value)
		AutoFarm.autoHitDelay = value
	end,
})

farmTab:CreateSlider({
	Name = "Hit Delay",
	Range = { 0.1, 1.5 },
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = 0.5,
	Flag = "HitDelay",
	Callback = function(value)
		AutoFarm.swingDelay = value
	end,
})

farmTab:CreateButton({
	Name = "Refresh Lists",
	Callback = function()
		eggDropdown:Refresh(getEggTypeNames())
		zoneDropdown:Refresh(getZoneNames())
	end,
})

farmTab:CreateSection("Status")

-- Collect tab: the hatched-animal pipeline, from grabbing to selling.
collectTab:CreateSection("Hatched Animals")

collectTab:CreateToggle({
	Name = "Auto Grab Hatched",
	CurrentValue = true,
	Flag = "AutoGrab",
	Callback = function(value)
		AutoFarm.autoGrab = value
	end,
})

collectTab:CreateToggle({
	Name = "Wait For Hatch",
	CurrentValue = false,
	Flag = "WaitForHatch",
	Callback = function(value)
		AutoFarm.waitForHatch = value
	end,
})

collectTab:CreateSection("After Grab")

collectTab:CreateDropdown({
	Name = "After Grab",
	Options = { "Sell", "Place", "Give" },
	CurrentOption = { "Sell" },
	MultipleOptions = false,
	Flag = "AfterSteal",
	Callback = function(options)
		AutoFarm.afterSteal = options[1]
	end,
})

collectTab:CreateToggle({
	Name = "Anti Ragdoll",
	CurrentValue = false,
	Flag = "AntiRagdoll",
	Callback = function(value)
		AutoFarm.antiRagdoll = value
	end,
})

collectTab:CreateSection("Selling")

collectTab:CreateToggle({
	Name = "Auto Sell Backpack (uses Below/Above $/s)",
	CurrentValue = false,
	Flag = "AutoSell",
	Callback = function(value)
		AutoFarm.autoSell = value
	end,
})

createPlainAmountInput(collectTab, "Sell Below $/s", "SellBelow", "e.g. 16.75T (empty = no limit)", function(value)
	AutoFarm.sellBelow = value
end)

createPlainAmountInput(collectTab, "Sell Above $/s", "SellAbove", "e.g. 10m (sell only at or above this)", function(value)
	AutoFarm.sellAbove = value
end)

progressionTab:CreateSection("Index")

progressionTab:CreateToggle({
	Name = "Auto Claim Index",
	CurrentValue = false,
	Flag = "AutoIndex",
	Callback = function(value)
		AutoFarm.autoIndex = value
	end,
})

progressionTab:CreateSection("Pickaxe")

progressionTab:CreateToggle({
	Name = "Auto Equip Best Pickaxe",
	CurrentValue = false,
	Flag = "AutoEquipPickaxe",
	Callback = function(value)
		AutoFarm.autoEquipPickaxe = value
	end,
})

progressionTab:CreateToggle({
	Name = "Auto Buy Best Pickaxe",
	CurrentValue = false,
	Flag = "AutoBuyPickaxe",
	Callback = function(value)
		AutoFarm.autoBuyPickaxe = value
	end,
})

progressionTab:CreateSection("Treadmill")

progressionTab:CreateToggle({
	Name = "Auto Upgrade Treadmill",
	CurrentValue = false,
	Flag = "AutoTreadmill",
	Callback = function(value)
		AutoFarm.autoTreadmill = value
	end,
})

-- Auto Fuse (Fuse Machine / SciFi Trade-In): protocol learned by reading FuseMachineController.
-- "Sync" asks the server for the current state; it answers "State" with which named slots are
-- filled (by animal name) and which animal name each of the 3 slots currently wants this session.
-- "Deposit" takes the animal name and the backpack tool, "Fuse" needs all 3 slots filled first.
-- Enchant (game v1472): EnchantRequest:InvokeServer("Roll", "Animals", petTool)
-- or ("Roll", "Pickaxes", tierNumber) answers {Ok=bool, Key="Id:tier", Reason=?}.
-- Pet rolls cost gems by rarity (Common 50 .. Primordial 10000), pickaxe costs 5000.
-- Rolls overwrite the item's current enchant. Gems = the Diamonds attribute.
-- Scoped in a do-block so only AutoFarm.enchant stays live: the chunk sits near
-- Luau's 200-local register limit, every top-level local counts.
do
	local enchantRequest = replicatedStorage:FindFirstChild("EnchantRequest")
	local enchantConfig = requireModule("EnchantConfig")
	local ENCHANT_PET_TARGETS = {
		Team = true, CriticalEarner = true, Banker = true,
		GreedyEarner = true, CelestialBond = true, Cash = true,
	}
	local lastNote = "off"

	---Gems the player holds right now.
	---@return number
	local function getGems()
		return getNumberAttribute("Diamonds")
	end

	---Read the current enchant key of an item.
	---@param itemType string
	---@param ref any
	---@return string?
	local function getEnchantKey(itemType, ref)
		if itemType == "Pickaxes" then
			local raw = localPlayer:GetAttribute("PickaxeEnchants")
			if type(raw) ~= "string" then return nil end

			local tier = tostring(typeof(ref) == "number" and ref or getNumberAttribute("PickaxeTier"))

			for entry in string.gmatch(raw, "[^,]+") do
				local entryTier, key = entry:match('"?(%d+)"?%s*:%s*"([^"]+)"')

				if entryTier == tier then
					return key
				end
			end

			return nil
		end

		return typeof(ref) == "Instance" and ref:GetAttribute("Enchant") or nil
	end

	---Does an enchant key match the wanted ids at the wanted tier or better?
	---@param key string?
	---@param wanted table
	---@param minTier number
	---@return boolean
	local function enchantMatches(key, wanted, minTier)
		if type(key) ~= "string" then return false end

		local id, tier = key:match("^([%w]+):(%d+)$")

		if not id then
			id, tier = key, "1"
		end

		return wanted[id] == true and (tonumber(tier) or 1) >= minTier
	end

	---One enchant roll. Returns ok, keyOrReason.
	---@param itemType string
	---@param ref any
	---@return boolean, string
	local function enchantRoll(itemType, ref)
		if not (enchantRequest and enchantRequest.Parent) then
			enchantRequest = replicatedStorage:FindFirstChild("EnchantRequest")

			if not enchantRequest then return false, "NotReady" end
		end

		local success, result = pcall(function()
			return enchantRequest:InvokeServer("Roll", itemType, ref)
		end)

		if not success or typeof(result) ~= "table" then return false, "NotReady" end
		if not result.Ok then return false, type(result.Reason) == "string" and result.Reason or "NotReady" end

		AutoFarm.rolls = (AutoFarm.rolls or 0) + 1
		AutoFarm.gemsSpent = (AutoFarm.gemsSpent or 0) + (
			itemType == "Pickaxes"
			and ((enchantConfig and enchantConfig.PickaxeCost) or 5000)
			or ((enchantConfig and enchantConfig.AnimalCosts and enchantConfig.AnimalCosts[tostring(readAttribute(ref, "Rarity"))]) or 250)
		)

		return true, tostring(result.Key)
	end

	---One enchant step: at most one roll per tick, one item at a time.
	local function enchantStep()
		if not (enchantRequest and enchantRequest.Parent) then
			enchantRequest = replicatedStorage:FindFirstChild("EnchantRequest")
		end

		if not enchantRequest then
			lastNote = "EnchantRequest not found"
			return
		end

		local minTier = AutoFarm.enchantTargetTier or 3
		local reserve = tonumber(AutoFarm.enchantGemReserve) or 0

		if getGems() <= reserve then
			if AutoFarm.autoEnchantPickaxe or AutoFarm.autoEnchantPets then
				lastNote = ("out of gems (reserve %s)"):format(formatNumber(reserve))
			elseif lastNote ~= "off" then
				lastNote = "off"
			end

			return
		end

		if AutoFarm.autoEnchantPickaxe then
			local tier = getNumberAttribute("PickaxeTier")

			if tier > 0 then
				local wanted = { [AutoFarm.enchantPickaxeTarget or "SwingSpeed"] = true }
				local current = getEnchantKey("Pickaxes", tier)

				if enchantMatches(current, wanted, minTier) then
					lastNote = ("pickaxe done: %s"):format(tostring(current))
				else
					local ok, key = enchantRoll("Pickaxes", tier)

					lastNote = ok and ("pickaxe: rolled " .. key) or ("pickaxe: " .. key)
				end
			end

			return
		end

		if AutoFarm.autoEnchantPets then
			for _, tool in ipairs(collectTools(function(tool)
				return collectionService:HasTag(tool, ANIMAL_TOOL_TAG)
			end)) do
				local current = getEnchantKey("Animals", tool)

				if enchantMatches(current, ENCHANT_PET_TARGETS, minTier) then
					lastNote = ("pet done: %s on %s"):format(tostring(current), tool.Name)
				else
					local ok, key = enchantRoll("Animals", tool)

					lastNote = ok and (tool.Name .. ": rolled " .. key) or (tool.Name .. ": " .. key)
					return -- one roll per tick
				end
			end

			lastNote = "every pet has a combo enchant"
		end
	end

	AutoFarm.enchant = {
		step = enchantStep,
		gems = getGems,
		note = function() return lastNote end,
	}
end

-- Auto Fuse (Fuse Machine / SciFi Trade-In): protocol learned by reading FuseMachineController.
-- "Sync" asks the server for the current state; it answers "State" with which named slots are
-- filled (by animal name) and which animal name each of the 3 slots currently wants this session.
-- "Deposit" takes the animal name and the backpack tool, "Fuse" needs all 3 slots filled first.
local fuseRecipe = {} -- slot number -> required animal name, for this session
local fuseFilled = {} -- animal name -> true once deposited
local fuseConnected = false
local lastFuseSyncAt = 0

local function ensureFuseListener()
	if fuseConnected or not fuseRemote then return end
	fuseConnected = true

	table.insert(AutoFarm.connections, fuseRemote.OnClientEvent:Connect(function(event, filled, recipe)
		if event ~= "State" then return end

		fuseFilled = {}
		if type(filled) == "table" then
			for name in pairs(filled) do
				if type(name) == "string" then fuseFilled[name] = true end
			end
		end

		fuseRecipe = {}
		if type(recipe) == "table" then
			for slot, name in pairs(recipe) do
				if type(name) == "string" then fuseRecipe[slot] = name end
			end
		end
	end))
end

local function fuseStep()
	if not (AutoFarm.autoFuse and fuseRemote) then return end
	ensureFuseListener()

	local now = os.clock()
	if now - lastFuseSyncAt >= 5 then
		lastFuseSyncAt = now
		fuseRemote:FireServer("Sync")
	end

	if next(fuseRecipe) == nil then
		AutoFarm.state = "Auto Fuse: waiting for the machine's recipe"
		return
	end

	local backpack = localPlayer:FindFirstChild("Backpack")
	if not backpack then return end

	local allFilled = true

	for _, name in pairs(fuseRecipe) do
		if not fuseFilled[name] then
			allFilled = false

			local best, bestCash
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and collectionService:HasTag(tool, "AnimalTool") and readAttribute(tool, "AnimalName") == name then
					local cash = getAnimalCash(tool) or 0
					if not best or cash < bestCash then
						best, bestCash = tool, cash
					end
				end
			end

			if best then
				fuseRemote:FireServer("Deposit", name, best)
				fuseFilled[name] = true -- optimistic, corrected by the next Sync
				AutoFarm.state = "Auto Fuse: deposited " .. name
			else
				AutoFarm.state = "Auto Fuse: needs a " .. name
			end
		end
	end

	if allFilled then
		fuseRemote:FireServer("Fuse")
		fuseFilled = {}
		AutoFarm.state = "Auto Fuse: fused!"
	end
end

-- Auto Mount: RideRemote:FireServer("Mount", name) and ("Dismount"), captured with RemoteSpy.
-- The best ride is the owned one with the highest SpeedBonus in the game's RideConfig.
local rideRemote = replicatedStorage:FindFirstChild("RideRemote")
local rideConfig = requireModule("RideConfig")

---@return string?
local function getBestRide()
	local owned = {}

	for name in string.gmatch(tostring(localPlayer:GetAttribute("OwnedRideables") or ""), "[^,]+") do
		owned[name] = true
	end

	local best, bestBonus

	for _, animal in ipairs(type(rideConfig) == "table" and rideConfig.Animals or {}) do
		if owned[animal.Name] and (not bestBonus or animal.SpeedBonus > bestBonus) then
			best, bestBonus = animal.Name, animal.SpeedBonus
		end
	end

	return best
end

local function mountRide()
	if not rideRemote then
		AutoFarm.state = "RideRemote not found"
		return
	end

	local override = AutoFarm.rideName
	local name = (type(override) == "string" and override ~= "") and override or getBestRide()

	if not name then
		AutoFarm.state = "Auto Mount: no owned ride found"
		return
	end

	local mounted = localPlayer:GetAttribute("Mounted") == true
	local riding = localPlayer:GetAttribute("RidingAnimal")

	if mounted and (riding == nil or riding == name) then return end

	if mounted then
		rideRemote:FireServer("Dismount", nil)
		task.wait(0.8)
	end

	rideRemote:FireServer("Mount", name)
	AutoFarm.state = "mounted " .. name
end

local function dismountRide()
	if rideRemote and localPlayer:GetAttribute("Mounted") == true then
		rideRemote:FireServer("Dismount", nil)
	end
end

-- Auto Buy Mount (Diamond Shop): RideEggRemote:InvokeServer("Hatch", "Mounted", count), captured with RemoteSpy.
-- Buys 8 at a time while it can, up to the game's own per-click max, and keeps the chosen diamond reserve.
local rideEggRemote = replicatedStorage:FindFirstChild("RideEggRemote")
local rideEggConfig = requireModule("RideEggConfig")

local function buyMounts()
	if not rideEggRemote then
		AutoFarm.state = "RideEggRemote not found"
		return
	end

	local maxPerPurchase = (type(rideEggConfig) == "table" and tonumber(rideEggConfig.MaxPerPurchase)) or 1
	local prices = type(rideEggConfig) == "table" and type(rideEggConfig.Prices) == "table" and rideEggConfig.Prices.Mounted
	local pricePerOne = (type(prices) == "table" and tonumber(prices[1])) or 1000

	local diamonds = tonumber(localPlayer:GetAttribute("Diamonds")) or 0
	local keep = tonumber(AutoFarm.buyMountKeep) or 0
	local spendable = diamonds - keep
	if spendable < pricePerOne then return end

	local count = math.min(maxPerPurchase, math.floor(spendable / pricePerOne))
	if count < 1 then return end

	local ok, err = pcall(function()
		rideEggRemote:InvokeServer("Hatch", "Mounted", count)
	end)

	if ok then
		AutoFarm.state = ("bought %d mount egg(s)"):format(count)
	else
		warn(err)
	end
end

progressionTab:CreateSection("Rides")

progressionTab:CreateToggle({
	Name = "Auto Buy Mount (Diamond Shop)",
	CurrentValue = false,
	Flag = "AutoBuyMount",
	Callback = function(value)
		AutoFarm.autoBuyMount = value
	end,
})

createPlainAmountInput(progressionTab, "Keep this many Diamonds", "BuyMountKeep", "e.g. 50000 (empty = spend all)", function(value)
	AutoFarm.buyMountKeep = value
end)

progressionTab:CreateInput({
	Name = "Ride Name (empty = best owned)",
	CurrentValue = "",
	PlaceholderText = "empty = automatic best",
	RemoveTextAfterFocusLost = false,
	Flag = "RideNameOverride",
	Callback = function(text)
		AutoFarm.rideName = (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end,
})

progressionTab:CreateToggle({
	Name = "Auto Mount Best Ride / Dismount",
	CurrentValue = false,
	Flag = "AutoMount",
	Callback = function(value)
		AutoFarm.autoMount = value

		task.spawn(function()
			if value then
				pcall(mountRide)
			else
				pcall(dismountRide)
			end
		end)
	end,
})

-- Keep the ride on: mount again after a respawn, a teleport or a fall.
task.spawn(function()
	while AutoFarm.running do
		task.wait(5)

		pcall(function()
			if not AutoFarm.autoMount then return end

			local _, _, humanoid = getCharacter()
			if not humanoid or humanoid.Health <= 0 then return end

			if localPlayer:GetAttribute("Mounted") ~= true then
				mountRide()
			end
		end)
	end
end)

progressionTab:CreateSection("Treadmill Run")

progressionTab:CreateToggle({
	Name = "Auto Treadmill Run (stand on it)",
	CurrentValue = false,
	Flag = "TreadmillRun",
	Callback = function(value)
		AutoFarm.treadmillRun = value
	end,
})

progressionTab:CreateSlider({
	Name = "Treadmill Duration (minutes)",
	Range = { 1, 480 },
	Increment = 1,
	Suffix = " min",
	CurrentValue = 60,
	Flag = "TreadmillMinutes",
	Callback = function(value)
		AutoFarm.treadmillMinutes = value
	end,
})

progressionTab:CreateSection("Pen & Trails")

progressionTab:CreateToggle({
	Name = "Auto Upgrade Pen",
	CurrentValue = false,
	Flag = "AutoPen",
	Callback = function(value)
		AutoFarm.autoPen = value
	end,
})

progressionTab:CreateToggle({
	Name = "Auto Buy + Equip Best Trail",
	CurrentValue = false,
	Flag = "AutoEquipTrail",
	Callback = function(value)
		AutoFarm.autoEquipTrail = value
	end,
})

local statsParagraph = farmTab:CreateParagraph({ Title = "Stats", Content = "Waiting..." })

-- Steal tab.
stealTab:CreateSection("Other Players' Hatches")

stealTab:CreateToggle({
	Name = "Steal Other Hatches",
	CurrentValue = false,
	Flag = "AutoSteal",
	Callback = function(value)
		AutoFarm.autoSteal = value

		if not value then
			AutoFarm.stealState = "off"
		end
	end,
})

stealTab:CreateSlider({
	Name = "Steal Range",
	Range = { 10, 500 },
	Increment = 5,
	Suffix = " studs",
	CurrentValue = 60,
	Flag = "StealRange",
	Callback = function(value)
		AutoFarm.stealRange = value
	end,
})

stealTab:CreateSlider({
	Name = "Steal Cooldown",
	Range = { 0, 10 },
	Increment = 0.5,
	Suffix = "s",
	CurrentValue = 3,
	Flag = "StealDelay",
	Callback = function(value)
		AutoFarm.stealDelay = value
	end,
})

stealTab:CreateToggle({
	Name = "Hunt Far Steals",
	CurrentValue = false,
	Flag = "HuntFar",
	Callback = function(value)
		AutoFarm.huntFar = value
	end,
})

stealTab:CreateSection("Debug")

stealTab:CreateButton({
	Name = "Debug Steal (F9)",
	Callback = function()
		local success, errorMessage = pcall(debugSteal)

		rayfield:Notify({
			Title = "Debug Steal",
			Content = success and "Printed to the console (F9)." or tostring(errorMessage),
			Duration = 4,
		})
	end,
})

stealTab:CreateButton({
	Name = "Debug Pickups (F9)",
	Callback = function()
		local count = 0
		local filter = AutoFarm.filter

		local function countKeys(set)
			local total = 0

			for _ in pairs(set) do
				total = total + 1
			end

			return total
		end

		warn(("[Pickup] FILTER above=%s below=%s rarities=%d sizes=%d mutations=%d alsoMutations=%d"):format(
			formatNumber(filter.above or 0),
			formatNumber(filter.below or 0),
			countKeys(filter.rarities),
			countKeys(filter.sizes),
			countKeys(filter.mutations),
			countKeys(filter.alsoMutations)
		))

		for _, model in ipairs(collectionService:GetTagged("AnimalPickup")) do
			count = count + 1
			local attributes = {}

			for key, value in pairs(model:GetAttributes()) do
				table.insert(attributes, key .. "=" .. tostring(value))
			end

			warn(("[Pickup] %s | cash/s=%s | passes=%s | %s"):format(
				model:GetFullName(),
				tostring(getAnimalCash(model)),
				tostring(pickupPasses(model)),
				table.concat(attributes, ", ")
			))
		end

		rayfield:Notify({
			Title = "Debug Pickups",
			Content = ("%d dropped animals printed to the console (F9)."):format(count),
			Duration = 4,
		})
	end,
})

stealTab:CreateSection("Steal Filter")

stealTab:CreateDropdown({
	Name = "Pet Rarities",
	Options = RARITIES,
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "FilterRarities",
	Callback = function(options)
		AutoFarm.filter.rarities = toSet(options)
	end,
})

stealTab:CreateDropdown({
	Name = "Mutations",
	Options = getMutationNames(),
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "FilterMutations",
	Callback = function(options)
		AutoFarm.filter.mutations = toSet(options, true)
	end,
})

stealTab:CreateDropdown({
	Name = "Sizes",
	Options = SIZES,
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "FilterSizes",
	Callback = function(options)
		AutoFarm.filter.sizes = toSet(options)
	end,
})

createAmountInput(stealTab, "Steal Above $/s", "FilterAbove", function(value)
	AutoFarm.filter.above = value
end)

createAmountInput(stealTab, "Steal Below $/s (0 = no limit)", "FilterBelow", function(value)
	AutoFarm.filter.below = value
end)

stealTab:CreateDropdown({
	Name = "Also Steal Mutations",
	Options = getMutationNames(),
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "FilterAlsoMutations",
	Callback = function(options)
		AutoFarm.filter.alsoMutations = toSet(options, true)
	end,
})

stealTab:CreateDropdown({
	Name = "Mutated Rarities",
	Options = RARITIES,
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "FilterMutatedRarities",
	Callback = function(options)
		AutoFarm.filter.mutatedRarities = toSet(options)
	end,
})

createAmountInput(stealTab, "Mutated Steal Above $/s", "FilterMutatedAbove", function(value)
	AutoFarm.filter.mutatedAbove = value
end)

local stealLogParagraph = stealTab:CreateParagraph({ Title = "Steals", Content = "No steals yet" })

-- Visuals tab.
visualsTab:CreateToggle({
	Name = "Egg ESP",
	CurrentValue = false,
	Flag = "EspEggs",
	Callback = function(value)
		AutoFarm.espEggs = value
	end,
})

visualsTab:CreateToggle({
	Name = "Animal ESP",
	CurrentValue = false,
	Flag = "EspAnimals",
	Callback = function(value)
		AutoFarm.espAnimals = value
	end,
})

visualsTab:CreateSlider({
	Name = "ESP Range",
	Range = { 50, 1000 },
	Increment = 10,
	Suffix = " studs",
	CurrentValue = 300,
	Flag = "EspRange",
	Callback = function(value)
		AutoFarm.espRange = value
	end,
})

---Build the stats text.
---@return string
local function buildStats()
	local egg = AutoFarm.currentEgg
	local target = "-"

	if egg and egg.Parent then
		target = getEggTypeName(egg)

		local luck = tonumber(readAttribute(egg, "HatchLuck")) or tonumber(readAttribute(egg, "Luck"))
		if luck then
			target = ("%s x%s"):format(target, formatNumber(luck))
		end
	end

	local pace = getSwingPace()
	local elapsed = os.clock() - AutoFarm.farmStartedAt
	local perHour = AutoFarm.autoFarm and elapsed > 30 and AutoFarm.eggsBroken / elapsed * 3600 or 0

	return table.concat({
		("Target: %s"):format(target),
		("Damage: %s | %.1f hits/s"):format(formatNumber(getPickaxeDamage(egg)), 1 / pace),
		("Eggs broken: %d (%d/hr)"):format(AutoFarm.eggsBroken, math.floor(perHour)),
		("Carry: %d/%d | Pickups: %d | Steals: %d | Junk: %d"):format(
			math.floor(getCarryCount()),
			math.floor(getSatchelCapacity()),
			AutoFarm.pickups,
			AutoFarm.steals,
			AutoFarm.junk
		),
		("State: %s"):format(AutoFarm.state),
		("Steal: %s"):format(AutoFarm.stealState),
		("Filter: above %s, below %s"):format(
			formatNumber(AutoFarm.filter.above or 0),
			(AutoFarm.filter.below or 0) > 0 and formatNumber(AutoFarm.filter.below) or "no limit"
		),
		("Last animal: %s"):format(AutoFarm.lastJudge),
	}, "\n")
end

---Build the steal log text.
---@return string
local function buildStealLog()
	if #AutoFarm.stealLog == 0 then return "No steals yet" end

	local lines = {}
	for _, entry in ipairs(AutoFarm.stealLog) do
		table.insert(lines, ("%s  %s  %s  %s"):format(
			entry.time,
			entry.name,
			entry.rarity,
			entry.value and formatNumber(entry.value) or "?"
		))
	end

	return table.concat(lines, "\n")
end

-- UI refresh loop.
task.spawn(function()
	while AutoFarm.running do
		pcall(function()
			statsParagraph:Set({ Title = "Stats", Content = buildStats() })
			stealLogParagraph:Set({ Title = "Steals", Content = buildStealLog() })
		end)

		task.wait(1)
	end
end)

-- Enchant tab (game v1472): rolls the EnchantRequest remote toward a target combo.
-- Pet rolls cost gems by the pet's rarity, pickaxe rolls cost 5000, and every roll
-- overwrites the item's current enchant. Gems never drop below the reserve.
enchantTab:CreateParagraph({
	Title = "How it works",
	Content = "Pets cost gems by rarity (Common 50 - Primordial 10000), pickaxe rolls cost 5000. Every roll overwrites the current enchant, so chasing a target can take many rolls. Gems never drop below the reserve.",
})

enchantTab:CreateToggle({
	Name = "Auto Roll Pickaxe",
	CurrentValue = false,
	Flag = "AutoEnchantPickaxe",
	Callback = function(value)
		AutoFarm.autoEnchantPickaxe = value
	end,
})

enchantTab:CreateDropdown({
	Name = "Pickaxe Target",
	Options = { "SwingSpeed", "CriticalHit", "DamageGrinder", "LuckySwing", "GemWhisperer", "LuxuriousSwing", "Collector" },
	CurrentOption = { "SwingSpeed" },
	MultipleOptions = false,
	Flag = "EnchantPickaxeTarget",
	Callback = function(options)
		AutoFarm.enchantPickaxeTarget = options[1]
	end,
})

enchantTab:CreateToggle({
	Name = "Auto Roll Pets (Cash Combo)",
	CurrentValue = false,
	Flag = "AutoEnchantPets",
	Callback = function(value)
		AutoFarm.autoEnchantPets = value
	end,
})

enchantTab:CreateSlider({
	Name = "Target Tier",
	Range = { 1, 3 },
	Increment = 1,
	CurrentValue = 3,
	Flag = "EnchantTargetTier",
	Callback = function(value)
		AutoFarm.enchantTargetTier = value
	end,
})

createPlainAmountInput(enchantTab, "Gem Reserve (never spend below)", "EnchantGemReserve", "e.g. 50000", function(value)
	AutoFarm.enchantGemReserve = value
end)

	enchantTab:CreateButton({
		Name = "Enchant Status (F9 not needed)",
		Callback = function()
			rayfield:Notify({
				Title = "Enchant",
				Content = ("%s | gems %s, spent %s on %d rolls"):format(
					AutoFarm.enchant.note(),
					formatNumber(AutoFarm.enchant.gems()),
					formatNumber(AutoFarm.gemsSpent or 0),
					AutoFarm.rolls or 0
				),
				Duration = 6,
			})
		end,
	})

-- Pets tab: Auto Merge, three animals of the same species become one bigger egg.
petsTab:CreateParagraph({
	Title = "Auto Merge",
	Content = "Merges three animals of the same species from the backpack. Mutated and variant animals are never merged. Pick a rarity or Only Merge Below $/s, otherwise it will not run.",
})

petsTab:CreateToggle({
	Name = "Auto Equip Best Pets",
	CurrentValue = false,
	Flag = "AutoEquipPets",
	Callback = function(value)
		AutoFarm.autoEquipPets = value
	end,
})

petsTab:CreateToggle({
	Name = "Auto Fuse (Celestial Egg)",
	CurrentValue = false,
	Flag = "AutoFuse",
	Callback = function(value)
		AutoFarm.autoFuse = value
	end,
})

petsTab:CreateToggle({
	Name = "Auto Place Merged Egg",
	CurrentValue = false,
	Flag = "AutoPlaceEggs",
	Callback = function(value)
		AutoFarm.autoPlaceEggs = value
	end,
})

petsTab:CreateToggle({
	Name = "Auto Open Growing Eggs",
	CurrentValue = false,
	Flag = "AutoHatchEggs",
	Callback = function(value)
		AutoFarm.autoHatchEggs = value
	end,
})

petsTab:CreateSection("Merge Settings")

petsTab:CreateToggle({
	Name = "Auto Merge",
	CurrentValue = false,
	Flag = "AutoMerge",
	Callback = function(value)
		AutoFarm.autoMerge = value
	end,
})

petsTab:CreateDropdown({
	Name = "Merge Rarities",
	Options = RARITIES,
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "MergeRarities",
	Callback = function(options)
		AutoFarm.merge.rarities = toSet(options)
	end,
})

createPlainAmountInput(petsTab, "Merge Below $/s", "MergeBelow", "e.g. 16.75T", function(value)
	AutoFarm.merge.below = value
end)

createPlainAmountInput(petsTab, "Merge Above $/s", "MergeAbove", "e.g. 10m, 1b", function(value)
	AutoFarm.merge.above = value
end)

-- Webhook tab.
local HttpService = game:GetService("HttpService")
local lastWebhookAt = 0

---Send a Discord embed, only to a real Discord webhook url.
---@param title string
---@param description string
---@param value number?
AutoFarm.postWebhook = function(title, description, value)
	local hook = AutoFarm.webhook
	if not (hook.enabled and hook.url ~= "") then return end
	if value and hook.minValue > 0 and value < hook.minValue then return end
	if os.clock() - lastWebhookAt < 1 then return end

	lastWebhookAt = os.clock()

	task.spawn(function()
		pcall(function()
			local send = request or http_request
			if not send then return end

			send({
				Url = hook.url,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					content = hook.ping ~= "" and ("<@" .. hook.ping .. ">") or nil,
					embeds = { {
						title = title,
						description = description,
						color = 16746026,
						footer = { text = localPlayer.Name },
					} },
				}),
			})
		end)
	end)
end

webhookTab:CreateSection("Discord")

webhookTab:CreateToggle({
	Name = "Enable Webhook",
	CurrentValue = false,
	Flag = "WebhookEnabled",
	Callback = function(value)
		AutoFarm.webhook.enabled = value
	end,
})

webhookTab:CreateInput({
	Name = "Webhook URL",
	CurrentValue = "",
	PlaceholderText = "https://discord.com/api/webhooks/...",
	RemoveTextAfterFocusLost = false,
	Flag = "WebhookUrl",
	Callback = function(text)
		local clean = tostring(text or ""):gsub("%s", "")

		if clean ~= "" and not (clean:find("^https://discord%.com/api/webhooks/") or clean:find("^https://discordapp%.com/api/webhooks/")) then
			rayfield:Notify({ Title = "Webhook", Content = "Only Discord webhook urls are accepted.", Duration = 4 })
			AutoFarm.webhook.url = ""
			return
		end

		AutoFarm.webhook.url = clean
	end,
})

webhookTab:CreateInput({
	Name = "Discord User ID",
	CurrentValue = "",
	PlaceholderText = "123456789012345678",
	RemoveTextAfterFocusLost = false,
	Flag = "WebhookPing",
	Callback = function(text)
		AutoFarm.webhook.ping = tostring(text or ""):gsub("%D", "")
	end,
})

createPlainAmountInput(webhookTab, "Min $/s to Notify", "WebhookMin", "e.g. 1b", function(value)
	AutoFarm.webhook.minValue = value
end)

webhookTab:CreateButton({
	Name = "Send Test Post",
	Callback = function()
		local hook = AutoFarm.webhook
		local wasEnabled = hook.enabled

		hook.enabled = hook.url ~= ""
		lastWebhookAt = 0
		AutoFarm.postWebhook("Test", "Webhook works.", nil)
		hook.enabled = wasEnabled

		rayfield:Notify({
			Title = "Webhook",
			Content = hook.url ~= "" and "Test sent." or "Set a Discord webhook url first.",
			Duration = 3,
		})
	end,
})

-- Misc tab.
miscTab:CreateSection("Utility")

miscTab:CreateToggle({
	Name = "Anti AFK",
	CurrentValue = true,
	Flag = "AntiAfk",
	Callback = function(value)
		AutoFarm.antiAfk = value
	end,
})

table.insert(AutoFarm.connections, localPlayer.Idled:Connect(function()
	if not AutoFarm.antiAfk then return end

	pcall(function()
		local virtualUser = game:GetService("VirtualUser")
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end))

miscTab:CreateToggle({
	Name = "FPS Boost",
	CurrentValue = false,
	Flag = "FpsBoost",
	Callback = function(value)
		if not value then return end

		pcall(function()
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			game:GetService("Lighting").GlobalShadows = false
		end)

		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
				pcall(function()
					descendant.Enabled = false
				end)
			end
		end
	end,
})

miscTab:CreateSection("Server and Control")

miscTab:CreateButton({
	Name = "Stop Everything",
	Callback = function()
		AutoFarm.autoFarm = false
		AutoFarm.autoSteal = false
		AutoFarm.autoSell = false
		AutoFarm.autoMerge = false
		AutoFarm.autoPlaceEggs = false
		AutoFarm.autoHatchEggs = false
		AutoFarm.autoIndex = false
		AutoFarm.autoEquipPickaxe = false
		AutoFarm.autoBuyPickaxe = false
		AutoFarm.autoEquipTrail = false
		AutoFarm.autoPen = false
		AutoFarm.autoTreadmill = false
		AutoFarm.treadmillRun = false
		AutoFarm.autoMount = false
		AutoFarm.autoBuyMount = false
		AutoFarm.autoFuse = false
		AutoFarm.autoEquipPets = false
		stopWalking()

		-- Switch the saved toggles off too, otherwise they would come back on after a rejoin.
		pcall(function()
			for _, flag in pairs(rayfield.Flags) do
				if flag.Type == "Toggle" and flag.CurrentValue == true then
					flag:Set(false)
				end
			end
		end)

		rayfield:Notify({ Title = "Stopped", Content = "All automation is off. Toggles in the menu may still look on.", Duration = 4 })
	end,
})

miscTab:CreateToggle({
	Name = "Auto Reconnect and Auto Re-execute",
	CurrentValue = true,
	Flag = "AutoReconnect",
	Callback = function(value)
		AutoFarm.autoReconnect = value
	end,
})

miscTab:CreateButton({
	Name = "Rejoin",
	Callback = function()
		pcall(function()
			game:GetService("TeleportService"):Teleport(game.PlaceId, localPlayer)
		end)
	end,
})

miscTab:CreateButton({
	Name = "Server Hop",
	Callback = function()
		task.spawn(function()
			local ok, message = pcall(function()
				local send = request or http_request
				local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
				local response = send({ Url = url, Method = "GET" })
				local data = HttpService:JSONDecode(response.Body)

				for _, server in ipairs(data.data or {}) do
					if server.id ~= game.JobId and server.playing < server.maxPlayers then
						game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, server.id, localPlayer)
						return
					end
				end

				error("no other server found")
			end)

			if not ok then
				rayfield:Notify({ Title = "Server Hop", Content = tostring(message), Duration = 4 })
			end
		end)
	end,
})

miscTab:CreateParagraph({
	Title = "Job ID",
	Content = tostring(game.JobId),
})

-- Anti Ragdoll: keep the ragdoll states off and stand back up.
task.spawn(function()
	while AutoFarm.running do
		task.wait(0.3)

		if AutoFarm.antiRagdoll then
			pcall(function()
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not humanoid then return end

				local states = {
					Enum.HumanoidStateType.Ragdoll,
					Enum.HumanoidStateType.FallingDown,
					Enum.HumanoidStateType.PlatformStanding,
				}

				for _, state in ipairs(states) do
					humanoid:SetStateEnabled(state, false)
				end

				if table.find(states, humanoid:GetState()) then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end

				humanoid.PlatformStand = false
			end)
		end
	end
end)

-- Automation loop: index claims and best-equip, args captured from the game with RemoteSpy.
local lastIndexAt, lastPetsAt, lastEquipAt, lastTreadmillAt = 0, 0, 0, 0
local lastBuyAt, lastTrailAt, lastPenAt, lastMergeAt, lastPlaceAt, lastHatchAt, lastAutoSellAt, lastBuyMountAt = 0, 0, 0, 0, 0, 0, 0, 0
local openedEggs = {}

task.spawn(function()
	while AutoFarm.running do
		pcall(function()
			local now = os.clock()

			if AutoFarm.autoIndex and indexRemote and now - lastIndexAt >= 60 then
				lastIndexAt = now
				indexRemote:FireServer("ClaimAllNormal")
				task.wait(0.5)
				indexRemote:FireServer("ClaimAllMutations")
			end

			-- PickaxeTier is the equipped tier, the owned ones are listed in OwnedPickaxes ("1,2,3").
			if AutoFarm.autoEquipPickaxe and pickaxeShopRemote and now - lastEquipAt >= 5 then
				local equipped = getNumberAttribute("PickaxeTier")
				local best = equipped
				local owned = localPlayer:GetAttribute("OwnedPickaxes")

				if type(owned) == "string" then
					for text in string.gmatch(owned, "[^,]+") do
						local tier = tonumber(text)

						if tier and tier > best then
							best = tier
						end
					end
				end

				if best > equipped then
					lastEquipAt = now
					pickaxeShopRemote:FireServer("Equip", best)
				end
			end

			-- Upgrade our own treadmill whenever the next level is affordable, cost is nil at max.
			if AutoFarm.autoTreadmill and upgradeTreadmillRemote and treadmillUpgradeConfig and now - lastTreadmillAt >= 3 then
				local plots = workspace:FindFirstChild("Plots")

				for _, plot in ipairs(plots and plots:GetChildren() or {}) do
					if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
						local level = treadmillUpgradeConfig.ClampLevel(
							plot:GetAttribute("TreadmillLevel") or treadmillUpgradeConfig.DefaultLevel
						)
						local cost = treadmillUpgradeConfig.UpgradeCost(level)

						if type(cost) == "number" and getNumberAttribute("Cash") >= cost then
							lastTreadmillAt = now
							upgradeTreadmillRemote:FireServer()
						end

						break
					end
				end
			end

			-- Buy the best affordable pickaxe tier, the equip toggle then puts it on.
			if AutoFarm.autoBuyPickaxe and pickaxeShopRemote and pickaxeConfig and type(pickaxeConfig.Tiers) == "table" and now - lastBuyAt >= 5 then
				local owned, top = {}, tonumber(pickaxeConfig.DefaultTier) or 1
				local ownedText = localPlayer:GetAttribute("OwnedPickaxes")

				if type(ownedText) == "string" then
					for text in string.gmatch(ownedText, "[^,]+") do
						local tier = tonumber(text)

						if tier then
							owned[tier] = true
							top = math.max(top, tier)
						end
					end
				end

				local cash, buy = getNumberAttribute("Cash"), nil

				for tier, data in pairs(pickaxeConfig.Tiers) do
					local price = type(data) == "table" and tonumber(data.Price) or nil

					if type(tier) == "number" and tier > top and not owned[tier] and price and price > 0 and price <= cash and (not buy or tier > buy) then
						buy = tier
					end
				end

				if buy then
					lastBuyAt = now
					pickaxeShopRemote:FireServer("Buy", buy)
				end
			end

			-- Trails: buy the best affordable one, then equip the owned one with the highest multiplier.
			if AutoFarm.autoEquipTrail and trailShopRemote and trailsConfig and type(trailsConfig.Trails) == "table" and now - lastTrailAt >= 5 then
				local owned = {}
				local ownedText = localPlayer:GetAttribute("OwnedTrails")
				local equipped = tonumber(localPlayer:GetAttribute("EquippedTrail")) or 0

				if type(ownedText) == "string" then
					for text in string.gmatch(ownedText, "[^,]+") do
						local id = tonumber(text)
						if id then owned[id] = true end
					end
				end

				if equipped ~= 0 then owned[equipped] = true end

				local cash = getNumberAttribute("Cash")
				local bestOwned, bestOwnedMult, bestBuy, bestBuyMult = nil, 0, nil, 0

				for id, data in pairs(trailsConfig.Trails) do
					local mult = type(data) == "table" and tonumber(data.Multiplier) or 0
					local price = type(data) == "table" and tonumber(data.Price) or nil

					if owned[id] then
						if mult > bestOwnedMult then bestOwned, bestOwnedMult = id, mult end
					elseif price and price > 0 and price <= cash and mult > bestBuyMult then
						bestBuy, bestBuyMult = id, mult
					end
				end

				if bestBuy and bestBuyMult > bestOwnedMult then
					lastTrailAt = now
					trailShopRemote:FireServer("Buy", bestBuy)
				elseif bestOwned and bestOwned ~= equipped then
					lastTrailAt = now
					trailShopRemote:FireServer("Equip", bestOwned)
				end
			end

			-- Pen (plot) upgrade, the game charges UpgradeCost(PlotLevel) up to MaxLevel.
			if AutoFarm.autoPen and upgradePlotRemote and plotUpgradeConfig and now - lastPenAt >= 3 then
				local plots = workspace:FindFirstChild("Plots")

				for _, plot in ipairs(plots and plots:GetChildren() or {}) do
					if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
						local level = plotUpgradeConfig.ClampLevel(plot:GetAttribute("PlotLevel") or plotUpgradeConfig.DefaultLevel)
						local cost = level < plotUpgradeConfig.MaxLevel and plotUpgradeConfig.UpgradeCost(level) or nil

						if type(cost) == "number" and getNumberAttribute("Cash") >= cost then
							lastPenAt = now
							upgradePlotRemote:FireServer()
						end

						break
					end
				end
			end

			-- Open our merged eggs once they finished growing, the same call as the Open button.
			if AutoFarm.autoHatchEggs and mergeRemote and now - lastHatchAt >= 2 then
				lastHatchAt = now

				for _, egg in ipairs(collectionService:GetTagged("MergeEggPlaced")) do
					if egg:IsA("Model") and egg.Parent and egg:GetAttribute("OwnerUserId") == localPlayer.UserId then
						local eggId = egg:GetAttribute("EggId")
						local readyAt = tonumber(egg:GetAttribute("ReadyAtServerTime"))
						local ready = egg:GetAttribute("Ready") == true or (readyAt ~= nil and readyAt <= workspace:GetServerTimeNow())

						if ready and eggId and now - (openedEggs[eggId] or -100) > 10 then
							openedEggs[eggId] = now
							mergeRemote:FireServer("HatchEgg", eggId)

							if AutoFarm.postWebhook then
								AutoFarm.postWebhook("Egg opened", tostring(egg:GetAttribute("AnimalName") or "merged egg"), nil)
							end

							break
						end
					end
				end
			end

			-- Place merged eggs on our plot when Auto Farm is not already doing it.
			if hasEggToPlace() and not AutoFarm.autoFarm and now - lastPlaceAt >= 5 then
				lastPlaceAt = now
				placeMergedEggs()
			end

			-- Auto Merge: three of the same species, never mutated or variant animals.
			if AutoFarm.autoMerge and mergeRemote and now - lastMergeAt >= 8 then
				local settings = AutoFarm.merge
				local backpack = localPlayer:FindFirstChild("Backpack")

				if next(settings.rarities) == nil and (settings.below or 0) <= 0 then
					AutoFarm.state = "Auto Merge needs a rarity or Only Merge Below"
				elseif backpack then
					local groups = {}

					for _, tool in ipairs(backpack:GetChildren()) do
						if tool:IsA("Tool") and collectionService:HasTag(tool, "AnimalTool") then
							local name = readAttribute(tool, "AnimalName")
							local rarity = readAttribute(tool, "Rarity")
							local cash = getAnimalCash(tool)
							local plain = readAttribute(tool, "Mutation") == nil and readAttribute(tool, "Variant") == nil

							if plain and name and cash
								and (next(settings.rarities) == nil or settings.rarities[rarity])
								and ((settings.below or 0) <= 0 or cash < settings.below)
								and cash >= (settings.above or 0) then
								groups[name] = groups[name] or {}
								table.insert(groups[name], { tool = tool, cash = cash })
							end
						end
					end

					for name, list in pairs(groups) do
						if #list >= 3 then
							table.sort(list, function(a, b) return a.cash < b.cash end)
							lastMergeAt = now
							mergeRemote:FireServer("Merge", { list[1].tool, list[2].tool, list[3].tool })

							if AutoFarm.postWebhook then
								AutoFarm.postWebhook("Merge", "Merged three " .. tostring(name), nil)
							end

							break
						end
					end
				end
			end

			if AutoFarm.autoEquipPets and petsRemote and now - lastPetsAt >= 60 then
				lastPetsAt = now
				petsRemote:FireServer("EquipBest")
			end

			if AutoFarm.autoBuyMount and now - lastBuyMountAt >= 5 then
				lastBuyMountAt = now
				buyMounts()
			end

			if AutoFarm.autoFuse then
				fuseStep()
			end

			if AutoFarm.autoEnchantPickaxe or AutoFarm.autoEnchantPets then
				pcall(function()
					AutoFarm.enchant.step()
				end)
			end

			-- Independent of Auto Farm: sells whatever is sellable right now, so the toggle works by itself.
			if AutoFarm.autoSell and getCarryCount() == 0 and now - lastAutoSellAt >= 3 then
				lastAutoSellAt = now
				sellAllBackpack()
			end
		end)

		task.wait(5)
	end
end)

-- Keep the menu alive: it can be removed or hidden when the character dies or the game cleans the PlayerGui.
local function findRayfieldGui()
	local roots = { game:GetService("CoreGui"), localPlayer:FindFirstChildOfClass("PlayerGui") }

	if typeof(gethui) == "function" then
		local ok, hidden = pcall(gethui)
		if ok and hidden then table.insert(roots, hidden) end
	end

	for _, root in ipairs(roots) do
		local found = root and root:FindFirstChild("Rayfield")
		if found and found:IsA("ScreenGui") then return found end
	end

	return nil
end

local watchedGui = findRayfieldGui()

task.spawn(function()
	while AutoFarm.running do
		task.wait(3)

		pcall(function()
			if not (watchedGui and watchedGui.Parent) then
				-- Removed without being destroyed: put it back, or pick up a new one.
				if watchedGui and watchedGui.Parent == nil then
					pcall(function()
						watchedGui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
					end)
				end

				if not (watchedGui and watchedGui.Parent) then
					watchedGui = findRayfieldGui()
				end
			end

			if watchedGui then
				watchedGui.ResetOnSpawn = false

				-- PlayerGui is wiped by some games, the hidden UI container is not.
				local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
				if playerGui and watchedGui.Parent == playerGui and typeof(gethui) == "function" then
					watchedGui.Parent = gethui()
				end
			else
				AutoFarm.state = "menu was removed by the game, loops still run"
			end
		end)

		-- Do not let the caches grow forever on long sessions.
		while #failedEggSpots > 60 do table.remove(failedEggSpots, 1) end

		for eggId, at in pairs(openedEggs) do
			if os.clock() - at > 300 then openedEggs[eggId] = nil end
		end
	end
end)

-- ESP loop.
task.spawn(function()
	while AutoFarm.running do
		if AutoFarm.espEggs or AutoFarm.espAnimals then
			local success, errorMessage = pcall(updateEsp)
			if not success then
				warn(errorMessage)
			end
		elseif next(espEntries) ~= nil then
			clearEsp()
		end

		task.wait(0.5)
	end

	clearEsp()
end)

-- Auto Treadmill Run: walk onto our treadmill, stay for the chosen minutes, then step off and go back to work.
local treadmillWasOn = false

local function getTreadmillSpot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end

	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
			for _, model in ipairs(plot:GetChildren()) do
				if model:IsA("Model") and string.find(model.Name, "Treadmill") and not string.find(model.Name, "Board") then
					local hitbox = model:FindFirstChild("Hitbox", true)

					if hitbox and hitbox:IsA("BasePart") then
						return hitbox.Position
					end
				end
			end
		end
	end

	return nil
end

---@return boolean true when the treadmill handled this tick
local function treadmillStep()
	if AutoFarm.treadmillRun then
		if not treadmillWasOn then
			treadmillWasOn = true
			AutoFarm.treadmillUntil = os.clock() + (AutoFarm.treadmillMinutes or 60) * 60
		end

		if os.clock() >= AutoFarm.treadmillUntil then
			AutoFarm.treadmillRun = false

			pcall(function()
				rayfield.Flags.TreadmillRun:Set(false)
			end)

			return true
		end

		-- A carried animal is delivered first by the steal logic.
		if getCarryCount() > 0 then return false end

		local spot = getTreadmillSpot()
		if not spot then
			AutoFarm.state = "treadmill not found on your plot"
			return true
		end

		local _, root = getCharacter()
		if not root then return true end

		if (Vector3.new(spot.X, root.Position.Y, spot.Z) - root.Position).Magnitude > 2.5 then
			AutoFarm.state = "walking to the treadmill"
			walkTo(spot, 60, 2, function() return not AutoFarm.treadmillRun end)
		else
			AutoFarm.state = ("on the treadmill, %d min left"):format(math.ceil((AutoFarm.treadmillUntil - os.clock()) / 60))
		end

		return true
	elseif treadmillWasOn then
		treadmillWasOn = false

		-- Step off: walk to the plot base so the treadmill session ends.
		local base = getBaseTarget()
		local spot = getTreadmillSpot()

		if base and spot and (base - spot).Magnitude > 12 then
			AutoFarm.state = "stepping off the treadmill"
			walkTo(base, 30, 6, function() return AutoFarm.treadmillRun end)
		elseif spot then
			local _, root = getCharacter()
			local humanoid = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")

			if humanoid then
				humanoid:MoveTo(root.Position + Vector3.new(20, 0, 0))
				task.wait(2)
			end
		end
	end

	return false
end

-- Main loop, stealing has priority and farming runs when there is nothing to steal.
task.spawn(function()
	while AutoFarm.running do
	local loopOk, loopError = pcall(function()
		local used = false

		if treadmillStep() then return end

		-- A new merged egg is placed first, before stealing or farming.
		if hasEggToPlace() and getCarryCount() == 0 then
			local success, errorMessage = pcall(placeMergedEggs)

			if not success then
				warn(errorMessage)
				AutoFarm.state = "error"
				task.wait(1)
			end
		end

		if AutoFarm.autoSteal then
			local success, result = pcall(stealStep)

			if success then
				used = result == true
			else
				warn(result)
				AutoFarm.stealState = "error"
				task.wait(1)
			end
		end

		if not used and AutoFarm.autoFarm then
			local success, errorMessage = pcall(farmStep)

			if not success then
				warn(errorMessage)
				AutoFarm.state = "error"
				task.wait(1)
			end
		end

		if not (AutoFarm.autoFarm or AutoFarm.autoSteal) then
			AutoFarm.state = "idle"
		end
	end)

	if not loopOk then
		warn(loopError)
		AutoFarm.state = "error, retrying"
		task.wait(1)
	end

	task.wait(0.2)
	end
end)

-- Keep alive: survive death, being caught, kicks and server teleports, runs until Stop, client close or leave.
local teleportService = game:GetService("TeleportService")
local scriptFile

for _, name in ipairs({ "AutoBreakEggs.lua", "AutoBreakEggs.luau", "AutoBreakEggs.txt" }) do
	if typeof(isfile) == "function" and isfile(name) then
		scriptFile = name
		break
	end
end

local function queueSelf()
	if typeof(queue_on_teleport) ~= "function" then return end

	if scriptFile then
		-- Local install: re-read the file after hops and rejoins.
		pcall(queue_on_teleport, string.format(
			"repeat task.wait() until game:IsLoaded() task.wait(3) loadstring(readfile(%q))()",
			scriptFile
		))
	elseif MAIN_SCRIPT_URL ~= "" then
		-- Hosted install: re-execute straight from the repo.
		pcall(queue_on_teleport, string.format(
			"repeat task.wait() until game:IsLoaded() task.wait(3) loadstring(game:HttpGet(%q))()",
			MAIN_SCRIPT_URL
		))
	end
end

queueSelf()

-- The queue is used up by each teleport, so queue again right before the next one.
table.insert(AutoFarm.connections, localPlayer.OnTeleport:Connect(queueSelf))

-- Respawn: drop any stale walking and carry on, the loops keep running.
local function onCharacterAdded(character)
	AutoFarm.state = "respawned, resuming"

	task.spawn(function()
		pcall(stopWalking)
		pcall(function() character:WaitForChild("Humanoid", 10) end)
		task.wait(1.5)
		pcall(equipPickaxe)
	end)
end

table.insert(AutoFarm.connections, localPlayer.CharacterAdded:Connect(onCharacterAdded))

-- Kick or disconnect prompt: rejoin the same game, the queued script restarts the farm.
task.spawn(function()
	local reconnecting = false

	while AutoFarm.running do
		task.wait(3)

		pcall(function()
			if not AutoFarm.autoReconnect or reconnecting then return end

			local prompt = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
			local overlay = prompt and prompt:FindFirstChild("promptOverlay")

			if overlay and overlay:FindFirstChild("ErrorPrompt") then
				reconnecting = true
				AutoFarm.state = "disconnected, rejoining"
				queueSelf()
				task.wait(2)

				for _ = 1, 10 do
					pcall(function()
						teleportService:Teleport(game.PlaceId, localPlayer)
					end)
					task.wait(15)
				end

				reconnecting = false
			end
		end)
	end
end)

-- Restore the saved toggles last, after every element exists.
pcall(function() rayfield:LoadConfiguration() end)
