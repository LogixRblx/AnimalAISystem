local Behaviour = {}

--// Behaviour Module for animal actions //--

local Species = script.Parent.Species

local Settings = require(script.Parent.Settings)

local PathfindingService = game:GetService("PathfindingService")

--// Used by animals to move to a valid position //--

function Behaviour.NextWaypoint(Animal : Model)
	task.spawn(function()
		if not Animal then warn("[Behaviour]: Animal does not exist anymore!") return false end
		if Animal:GetAttribute("WaypointInProgress") == true or Animal:GetAttribute("Fleeing") == true or Animal:GetAttribute("PauseForChase") == true then return end
		Animal:SetAttribute("WaypointInProgress", true)

		local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
		if not MoveConfig then warn("[Behaviour]: Animal has no MoveConfig!") return false end
		local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
		if not Humanoid then warn("[Behaviour]: Animal has no humanoid! Kill animal?") return Behaviour.Died(Animal) end
		local Module = Species:WaitForChild(Animal.Name, 1)
		if not Module then warn("[Behaviour]: Animal has no module!") return false end
		local Data = require(Module)

		if Humanoid.Health <= 0 then print("[Behaviour]: Animal is dead!") return false end

		local AgentData = Data.Agent

		local Success = false

		repeat
			local OrigPos = Animal.PrimaryPart.Position
			local Offset = Vector3.new(math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance), 0, math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance))
			local TargetPos = OrigPos + Offset

			if Humanoid.Health <= 0 then
				break
			end

			local Path = PathfindingService:CreatePath({
				AgentRadius = AgentData.AgentRadius,
				AgentHeight = AgentData.AgentHeight,
				AgentCanJump = AgentData.CanJump,
				AgentMaxSlope = AgentData.AgentMaxSlope,
			})

			Path:ComputeAsync(OrigPos, TargetPos)

			if Path.Status == Enum.PathStatus.NoPath then
				print("[Behaviour]: Path was not successful! Trying again...")
				Success = false
				return
			end

			local Waypoints = Path:GetWaypoints()

			for i, Wp in Waypoints do
				if Animal:GetAttribute("PauseMovementForIdle") == true or Animal:GetAttribute("Fleeing") == true or Animal:GetAttribute("PauseForChase") == true then Animal:SetAttribute("WaypointInProgress", false) return end
				MoveConfig:SetAttribute("Walking", true)
				MoveConfig:SetAttribute("Idle", false)
				Humanoid:MoveTo(Wp.Position)
				Humanoid.MoveToFinished:Wait()
				if Humanoid.Health <= 0 then
					break
				end
			end
			MoveConfig:SetAttribute("Walking", false)
			MoveConfig:SetAttribute("Idle", true)
			Success = true
		until Success == true

		task.wait(Settings.WaypointWait)
		Animal:SetAttribute("WaypointInProgress", false)
	end)
end

--// Used by animals to check if they can see a target //--

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function CheckLOS(Animal : Model, Character : Model)
	if not Animal or not Character then
		warn("[Behaviour]: Didnt receive Animal model or Player Character!")
		return false
	end
	
	if not Animal.PrimaryPart or not Character.PrimaryPart then
		warn("[Behaviour]: Missing PrimaryPart on Animal or Character!")
		return false
	end
	
	RayParams.FilterDescendantsInstances = { Animal, Character }
	
	local origin = Animal.PrimaryPart.Position
	local direction = Character.PrimaryPart.Position - origin
	
	local result = workspace:Raycast(origin, direction, RayParams)
	
	if not result then
		return true
	end
	
	return result.Instance:IsDescendantOf(Character)
end

--// Helper for chase //--

local function Chase(Animal : Model, State : boolean)
	local Config = Animal.MoveConfig
	Animal:SetAttribute("PauseForChase", State)
	Config:SetAttribute("Running", State)
	Config:SetAttribute("Idle", (not State))
	Config:SetAttribute("Walking", (not State))
	Animal:SetAttribute("PauseMovementForIdle", State)
	Animal:SetAttribute("Chasing", State)
end

--// Function for chasing players if an animal is aggressive //--

function Behaviour.Chase(Animal : Model, Character : Model)
	if not Animal or not Character then return end
	if Animal:GetAttribute("Type") == "Friendly" then return end
	if Animal:GetAttribute("Chasing") == true then return end

	local TargetHum = Character:WaitForChild("Humanoid", 2)
	if not TargetHum then return end

	local Module = Species:WaitForChild(Animal.Name, 1)
	if not Module then return end
	local Data = require(Module)

	local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
	if not MoveConfig then return end
	local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
	if not Humanoid then return end

	Humanoid.WalkSpeed = Data.HumStats.RunSpeed or 16
	Chase(Animal, true)

	task.spawn(function()
		while Animal:GetAttribute("PauseForChase") == true do
			if TargetHum.Health <= 0 then break end

			local delta = Animal.PrimaryPart.Position - Character.PrimaryPart.Position
			local distance = delta.Magnitude

			if distance > (Data.Behaviour.MaxChaseDistance or 30) then
				break
			end

			if distance <= (Data.Behaviour.AttackRange or 5)
				and Animal:GetAttribute("AttackCooldown") == false then

				TargetHum:TakeDamage(Data.HumStats.Damage or 15)
				Animal:SetAttribute("AttackCooldown", true)

				task.delay(Data.Behaviour.AttackCooldown or 1.25, function()
					if Animal then
						Animal:SetAttribute("AttackCooldown", false)
					end
				end)
			end

			if not CheckLOS(Animal, Character) then
				break
			end

			MoveConfig:SetAttribute("Running", true)
			MoveConfig:SetAttribute("Walking", false)
			MoveConfig:SetAttribute("Idle", false)

			Humanoid:MoveTo(Character.PrimaryPart.Position)
			task.wait(Settings.ChaseRefreshRate)
		end

		Humanoid.WalkSpeed = Data.HumStats.WalkSpeed or 10
		MoveConfig:SetAttribute("Running", false)
		MoveConfig:SetAttribute("Walking", false)
		MoveConfig:SetAttribute("Idle", true)

		Chase(Animal, false)
	end)
end

--// Helper to cancel chase //--

function Behaviour.CancelChase(Animal : Model)
	Chase(Animal, false)
end

--// Used by animals to flee when getting hit etc. //--

function Behaviour.Flee(Animal : Model)
	if not Animal then warn("[Behaviour]: Animal does not exist anymore!") return false end
	
	if Animal:GetAttribute("Fleeing") == true then return end
	Animal:SetAttribute("Fleeing", true)
	
	local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
	if not MoveConfig then warn("[Behaviour]: Animal has no MoveConfig!") return false end
	local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
	if not Humanoid then warn("[Behaviour]: Animal has no humanoid! Kill animal?") return false end
	local Module = Species:WaitForChild(Animal.Name, 1)
	if not Module then warn("[Behaviour]: Animal has no module!") return false end
	local Data = require(Module)
	
	Humanoid.WalkSpeed = Data.HumStats.RunSpeed
	
	local AgentData = Data.Agent
	
	local minFlee : number = Data.Behaviour.MinFleeTime or 2
	local maxFlee : number = Data.Behaviour.MaxFleeTime or 10
	
	local TimeFleeing : number = os.clock() + math.random(minFlee, maxFlee)
	
	local FleeTask = task.spawn(function()
		while os.clock()  < TimeFleeing do
			local OrigPos = Animal.PrimaryPart.Position
			local Offset = Vector3.new(math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance), 0, math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance))
			local TargetPos = OrigPos + Offset

			if Humanoid.Health <= 0 then
				break
			end

			local Path = PathfindingService:CreatePath({
				AgentRadius = AgentData.AgentRadius,
				AgentHeight = AgentData.AgentHeight,
				AgentCanJump = AgentData.CanJump,
				AgentMaxSlope = AgentData.AgentMaxSlope,
			})

			Path:ComputeAsync(OrigPos, TargetPos)

			if Path.Status == Enum.PathStatus.NoPath then
				print("[Behaviour]: Path was not successful! Trying again...")
				return
			end

			local Waypoints = Path:GetWaypoints()

			for i, Wp in Waypoints do
				if Animal:GetAttribute("PauseMovementForIdle") == true then Animal:SetAttribute("WaypointInProgress", false) return end
				MoveConfig:SetAttribute("Running", true)
				MoveConfig:SetAttribute("Walking", false)
				MoveConfig:SetAttribute("Idle", false)
				Humanoid:MoveTo(Wp.Position)
				Humanoid.MoveToFinished:Wait()
				if Humanoid.Health <= 0 then
					break
				end
			end
			MoveConfig:SetAttribute("Running", false)
			MoveConfig:SetAttribute("Walking", false)
			MoveConfig:SetAttribute("Idle", true)
			task.wait()
		end
	end)
	task.cancel(FleeTask)
	
	Animal:SetAttribute("Fleeing", false)
end

--// Ragdoll function //--

function Behaviour.Died(Animal : Model)
	if not Animal then warn("[Behaviour]: Animal does not exist anymore!") return false end
	
	local Humanoid = Animal:WaitForChild("Humanoid", 1)
	if Humanoid then Humanoid:Destroy() end
	
	Animal.Parent = workspace.DeadAnimals
	
	for _, Joint in Animal:GetDescendants() do
		if Joint:IsA("Part") or Joint:IsA("MeshPart") then
			Joint.CanCollide = true
		elseif Joint:IsA("Motor6D") and Joint.Parent.Name ~= "HumanoidRootPart" then
			
			local Part0 = Joint.Part0
			local Part1 = Joint.Part1
			if not Part0 or not Part1 then continue end

			local Attachment0 = Instance.new("Attachment")
			Attachment0.CFrame = Joint.C0
			Attachment0.Parent = Part0

			local Attachment1 = Instance.new("Attachment")
			Attachment1.CFrame = Joint.C1
			Attachment1.Parent = Part1

			local Constraint = Instance.new("BallSocketConstraint")
			Constraint.Attachment0 = Attachment0
			Constraint.Attachment1 = Attachment1
			Constraint.Parent = Part0

			Joint.Enabled = false
		endend
	end
end

--// Injured function //--

local function BloodPoolHelper(Model : Model, Amount : number)
	task.spawn(function()
		for i = 1, Amount do
			local origin = Model.PrimaryPart.Position + Vector3.new(0, 2, 0)
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { Model }
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true

			local direction = Vector3.new(0, -500, 0)
			local result : RaycastResult = workspace:Raycast(origin, direction, params)

			local BloodPool = Instance.new("Part")
			BloodPool.Name = "BloodPool"
			BloodPool.Size = Vector3.new(1,1,1)
			BloodPool.Anchored = true
			BloodPool.CanCollide = false
			BloodPool.Transparency = 0.5
			BloodPool.Color = Color3.fromRGB(255,0,0)
			BloodPool.Position = result.Position + Vector3.new(0, 0.01, 0)
			BloodPool.Orientation = Vector3.new(0, math.random(0, 360), 0)
			BloodPool.Parent = workspace.BloodPools
			task.wait(math.random(1, 2))
		end
	end)
end

function Behaviour.BloodPool(Animal : Model, LostHP : number)
	if not Animal or not LostHP then warn("[Behaviour]: Animal does not exist anymore or no LostHP number given!") return false end
	
	print("[Behaviour]: Animal lost HP. Spawning pool of blood!")
	
	BloodPoolHelper(Animal, LostHP / 10)
end

return Behaviour
