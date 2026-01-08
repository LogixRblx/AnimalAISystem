--// Main Manager for all animals! //--

local Storage = script.Parent:WaitForChild("Species", 1)

local BhvrModule = require(script.Parent.Behaviour)
local AnimModule = require(script.Parent.AnimationHandler)

local Animals = workspace.Animals

local Species = {
	BrownBear = {
		Data = require(Storage.BrownBear),
		Folder = Animals.BrownBear
	},
	Moose = {
		Data = require(Storage.Moose),
		Folder = Animals.Moose
	},
}

local ActiveAnimals = {}

local function RegisterAnimal(model)
	local Data = require(Storage:FindFirstChild(model.Name))
	local BehaviourData = Data.Behaviour
	
	--// Changing the network owner
	
	if model and model.PrimaryPart.Anchored == false then
		model.PrimaryPart:SetNetworkOwner(nil)
	end
	
	--// Insert a Config for movement attributes
	
	local MoveConfig = Instance.new("Configuration")
	MoveConfig.Name = "MoveConfig"
	MoveConfig.Parent = model
	
	MoveConfig:SetAttribute("Walking", false)
	MoveConfig:SetAttribute("Running", false)
	MoveConfig:SetAttribute("Idle", false)
	
	--// Init Animations

	AnimModule.InitAnimal(model, MoveConfig)
	
	local Humanoid = model:WaitForChild("Humanoid", 1)
	
	--// Set Humanoid Stats
	
	Humanoid.WalkSpeed = Data.HumStats.WalkSpeed
	Humanoid.MaxHealth = Data.HumStats.Health
	Humanoid.Health = Data.HumStats.Health
	Humanoid.DisplayName = Data.Name
	
	--// Register the animal
	
	local animal = {
		Model = model,
		Data = Data,
		NextThink = os.clock() + math.random(Data.Behaviour.MinIdleTime or 5, Data.Behaviour.MaxIdleTime or 10),
		AlertRange = Data.Behaviour.AlertRange or 30,
		Type = Data.Behaviour.Type or "Friendly",
	}
	
	--// Collision Group
	
	for i, Child in model:GetChildren() do
		if Child:IsA("Part") or Child:IsA("MeshPart") or Child:IsA("UnionOperation") then
			Child.CollisionGroup = "Animal"
		end
	end
	
	--// Add attributes
	
	model:SetAttribute("Species", model.Name)
	model:SetAttribute("WaypointInProgress", false)
	model:SetAttribute("PauseMovementForIdle", false)
	model:SetAttribute("Fleeing", false)
	model:SetAttribute("OldHealth", Humanoid.Health)
	model:SetAttribute("BaseSafety", 100)
	model:SetAttribute("Safety", 100)
	model:SetAttribute("Type", Data.Behaviour.Type or "Friendly")
	model:SetAttribute("PauseForChase", false)
	model:SetAttribute("Chasing", false)
	model:SetAttribute("AttackCooldown", false)

	ActiveAnimals[model] = animal
	
	--// Connections for the animal
	
	model:GetAttributeChangedSignal("Safety"):Connect(function()
		if model:GetAttribute("Safety") < (Data.Safety.FleeingSafety or 20) and model:GetAttribute("Type") == "Friendly" then
			BhvrModule.Flee(model)
		end
	end)
	
	Humanoid.HealthChanged:Connect(function(NewHealth)
		local LostHP = model:GetAttribute("OldHealth") - NewHealth
		if NewHealth < model:GetAttribute("OldHealth") then
			BhvrModule.CancelChase(model)
			BhvrModule.BloodPool(model, LostHP)
			BhvrModule.Flee(model)
		end
		model:SetAttribute("OldHealth", NewHealth)
	end)
	if Humanoid then
		Humanoid.Died:Connect(function()
			BhvrModule.Died(model)
		end)
	end
end

--// Initiate all already existing animals (Mainly for testing since animals will spawn!) //--

local function Init()
	for speciesName, entry in Species do
		if not entry.Folder then
			warn("[Animal-Manager]:", speciesName, "has no folder")
			continue
		end

		for _, model in ipairs(entry.Folder:GetChildren()) do
			if not model:IsA("Model") then continue end
			RegisterAnimal(model, speciesName, entry.Data)
		end
	end
end

Init()

--// Main Loop for animal behaviour //--

task.spawn(function()
	while true do
		local now = os.clock()

		for _, animal in pairs(ActiveAnimals) do
			local model : Model = animal.Model
			if now >= animal.NextThink and not animal.Model:GetAttribute("WaypointInProgress") and not animal.Model:GetAttribute("PauseMovementForIdle") then
				local BehaviourData = animal.Data.Behaviour
				BhvrModule.NextWaypoint(animal.Model)
				animal.NextThink = now + math.random(BehaviourData.MinIdleTime or 5, BehaviourData.MaxIdleTime or 10)
			end
		end
		
		task.wait()
	end
end)

--// Helper for animal distance //--

local Players = game:GetService("Players")

local function GetNearestCharacter(animalModel : Model)
	if not animalModel.PrimaryPart then
		return nil, math.huge
	end
	
	local nearestCharacter = nil
	local nearestDistSq = math.huge
	local animalPos = animalModel.PrimaryPart.Position
	
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character or not character.PrimaryPart then
			continue
		end
		
		local delta = character.PrimaryPart.Position - animalPos
		local distSq = delta.X*delta.X + delta.Z*delta.Z
		
		if distSq < nearestDistSq then
			nearestDistSq = distSq
			nearestCharacter = character
		end
	end
	
	return nearestCharacter, nearestDistSq
end

local function DistanceHelper()
	for Animal, Info in pairs(ActiveAnimals) do
		local model = Info.Model
		local AlertRange = Info.AlertRange
		
		if not model or not model.PrimaryPart or not AlertRange then
			continue
		end
		
		local character, distSq = GetNearestCharacter(model)
		
		if not character then
			model:SetAttribute("Safety", model:GetAttribute("BaseSafety"))
			continue
		end
		
		local alertSq = AlertRange * AlertRange
		
		if distSq > alertSq then
			model:SetAttribute("Safety", model:GetAttribute("BaseSafety"))
			continue
		end
		
		local distance = math.sqrt(distSq)
		local safetyMult = 1 - (distance / AlertRange)
		
		local newSafety = model:GetAttribute("BaseSafety") * safetyMult
		model:SetAttribute("Safety", math.clamp(newSafety, 0, 100))
		
		if Info.Type == "Aggressive" then
			BhvrModule.Chase(Animal, character)
		end
	end
end

--// Checking if players are near animals //--

task.spawn(function()
	while true do
		DistanceHelper()
		task.wait(1)
	end
end)
