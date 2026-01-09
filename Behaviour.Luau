local Behaviour = {}

-- Behaviour module that controls all high-level animal AI states:
-- wandering, chasing, fleeing, dying and injury side-effects.
-- This module is intentionally state-driven using attributes so
-- different behaviours can safely interrupt each other.

local Species = script.Parent.Species
local Settings = require(script.Parent.Settings)

local PathfindingService = game:GetService("PathfindingService")

--=====================================================
-- WAYPOINT MOVEMENT (IDLE WANDERING)
--=====================================================

-- Moves an animal to a random valid position within its walk range.
-- This runs in a separate thread so it does not block other behaviour
-- logic like fleeing or chasing.
function Behaviour.NextWaypoint(Animal : Model)
	task.spawn(function()
		-- Validate model early to avoid running logic on destroyed instances
		if not Animal then
			warn("[Behaviour]: Animal does not exist anymore!")
			return
		end

		-- Prevent overlapping movement states:
		-- waypoint movement should not run while fleeing, chasing,
		-- or already computing another waypoint.
		if Animal:GetAttribute("WaypointInProgress")
			or Animal:GetAttribute("Fleeing")
			or Animal:GetAttribute("PauseForChase") then
			return
		end

		Animal:SetAttribute("WaypointInProgress", true)

		-- Movement config controls animation state via attributes
		local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
		if not MoveConfig then
			warn("[Behaviour]: Animal has no MoveConfig!")
			return
		end

		-- Humanoid is required for MoveTo-based navigation
		local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
		if not Humanoid then
			warn("[Behaviour]: Animal has no humanoid! Kill animal?")
			return Behaviour.Died(Animal)
		end

		-- Each species has its own data module defining movement and behaviour
		local Module = Species:WaitForChild(Animal.Name, 1)
		if not Module then
			warn("[Behaviour]: Animal has no module!")
			return
		end

		local Data = require(Module)

		-- Do not continue movement if the animal is already dead
		if Humanoid.Health <= 0 then
			return
		end

		local AgentData = Data.Agent
		local Success = false

		-- Retry loop: generates random offsets until a valid path is found
		repeat
			local OrigPos = Animal.PrimaryPart.Position

			-- Random offset creates natural wandering instead of fixed paths
			local Offset = Vector3.new(
				math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance),
				0,
				math.random(-Data.Behaviour.MinWalkDistance, Data.Behaviour.MaxWalkDistance)
			)

			local TargetPos = OrigPos + Offset

			if Humanoid.Health <= 0 then
				break
			end

			-- Pathfinding is recreated every time to respect agent parameters
			local Path = PathfindingService:CreatePath({
				AgentRadius = AgentData.AgentRadius,
				AgentHeight = AgentData.AgentHeight,
				AgentCanJump = AgentData.CanJump,
				AgentMaxSlope = AgentData.AgentMaxSlope,
			})

			Path:ComputeAsync(OrigPos, TargetPos)

			-- If path fails, retry instead of forcing movement
			if Path.Status == Enum.PathStatus.NoPath then
				print("[Behaviour]: Path was not successful! Trying again...")
				return
			end

			local Waypoints = Path:GetWaypoints()

			-- Walk through each waypoint sequentially
			for _, Wp in Waypoints do
				-- Abort if another higher-priority state interrupts movement
				if Animal:GetAttribute("PauseMovementForIdle")
					or Animal:GetAttribute("Fleeing")
					or Animal:GetAttribute("PauseForChase") then
					Animal:SetAttribute("WaypointInProgress", false)
					return
				end

				-- Update animation state
				MoveConfig:SetAttribute("Walking", true)
				MoveConfig:SetAttribute("Idle", false)

				Humanoid:MoveTo(Wp.Position)
				Humanoid.MoveToFinished:Wait()

				if Humanoid.Health <= 0 then
					break
				end
			end

			-- Reset to idle once destination is reached
			MoveConfig:SetAttribute("Walking", false)
			MoveConfig:SetAttribute("Idle", true)
			Success = true
		until Success

		-- Small delay between waypoints to avoid jittery movement
		task.wait(Settings.WaypointWait)
		Animal:SetAttribute("WaypointInProgress", false)
	end)
end

--=====================================================
-- LINE OF SIGHT CHECK
--=====================================================

-- Shared raycast parameters reused to avoid recreating objects every call
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

-- Checks whether the animal has a clear line of sight to a character.
-- Used to decide if a chase should continue or break.
local function CheckLOS(Animal : Model, Character : Model)
	if not Animal or not Character then
		warn("[Behaviour]: Didnt receive Animal model or Player Character!")
		return false
	end

	if not Animal.PrimaryPart or not Character.PrimaryPart then
		warn("[Behaviour]: Missing PrimaryPart on Animal or Character!")
		return false
	end

	-- Exclude both models so only world geometry blocks vision
	RayParams.FilterDescendantsInstances = { Animal, Character }

	local origin = Animal.PrimaryPart.Position
	local direction = Character.PrimaryPart.Position - origin

	local result = workspace:Raycast(origin, direction, RayParams)

	-- No hit means nothing blocked the ray
	if not result then
		return true
	end

	-- Valid LOS only if the ray hits the target character
	return result.Instance:IsDescendantOf(Character)
end

--=====================================================
-- CHASE STATE HELPER
--=====================================================

-- Centralized function to toggle chase-related attributes.
-- This ensures all movement systems respond consistently.
local function Chase(Animal : Model, State : boolean)
	local Config = Animal.MoveConfig

	Animal:SetAttribute("PauseForChase", State)
	Animal:SetAttribute("PauseMovementForIdle", State)
	Animal:SetAttribute("Chasing", State)

	Config:SetAttribute("Running", State)
	Config:SetAttribute("Idle", not State)
	Config:SetAttribute("Walking", not State)
end

--=====================================================
-- CHASE LOGIC
--=====================================================

-- Starts chasing a player if the animal is aggressive.
-- Chasing overrides idle movement and continuously updates pathing.
function Behaviour.Chase(Animal : Model, Character : Model)
	if not Animal or not Character then return end
	if Animal:GetAttribute("Type") == "Friendly" then return end
	if Animal:GetAttribute("Chasing") then return end

	local TargetHum = Character:WaitForChild("Humanoid", 2)
	if not TargetHum then return end

	local Module = Species:WaitForChild(Animal.Name, 1)
	if not Module then return end
	local Data = require(Module)

	local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
	if not MoveConfig then return end

	local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
	if not Humanoid then return end

	-- Increase speed for chase
	Humanoid.WalkSpeed = Data.HumStats.RunSpeed or 16
	Chase(Animal, true)

	task.spawn(function()
		while Animal:GetAttribute("PauseForChase") do
			if TargetHum.Health <= 0 then break end

			local delta = Animal.PrimaryPart.Position - Character.PrimaryPart.Position
			local distance = delta.Magnitude

			-- Stop chase if target escapes beyond max distance
			if distance > (Data.Behaviour.MaxChaseDistance or 30) then
				break
			end

			-- Attack only when in range and cooldown allows it
			if distance <= (Data.Behaviour.AttackRange or 5)
				and not Animal:GetAttribute("AttackCooldown") then

				TargetHum:TakeDamage(Data.HumStats.Damage or 15)
				Animal:SetAttribute("AttackCooldown", true)

				-- Cooldown prevents damage spam
				task.delay(Data.Behaviour.AttackCooldown or 1.25, function()
					if Animal then
						Animal:SetAttribute("AttackCooldown", false)
					end
				end)
			end

			-- Break chase if line of sight is lost
			if not CheckLOS(Animal, Character) then
				break
			end

			-- Continuously update movement target to player position
			MoveConfig:SetAttribute("Running", true)
			MoveConfig:SetAttribute("Walking", false)
			MoveConfig:SetAttribute("Idle", false)

			Humanoid:MoveTo(Character.PrimaryPart.Position)
			task.wait(Settings.ChaseRefreshRate)
		end

		-- Reset movement after chase ends
		Humanoid.WalkSpeed = Data.HumStats.WalkSpeed or 10
		MoveConfig:SetAttribute("Running", false)
		MoveConfig:SetAttribute("Walking", false)
		MoveConfig:SetAttribute("Idle", true)

		Chase(Animal, false)
	end)
end

-- Allows external systems to forcibly stop a chase
function Behaviour.CancelChase(Animal : Model)
	Chase(Animal, false)
end

--=====================================================
-- FLEE LOGIC
--=====================================================

-- Causes the animal to flee for a random duration.
-- Used when the animal is attacked or threatened.
function Behaviour.Flee(Animal : Model)
	if not Animal then
		warn("[Behaviour]: Animal does not exist anymore!")
		return
	end

	if Animal:GetAttribute("Fleeing") then return end
	Animal:SetAttribute("Fleeing", true)

	local MoveConfig = Animal:WaitForChild("MoveConfig", 2)
	if not MoveConfig then return end

	local Humanoid : Humanoid = Animal:WaitForChild("Humanoid", 2)
	if not Humanoid then return end

	local Module = Species:WaitForChild(Animal.Name, 1)
	if not Module then return end
	local Data = require(Module)

	Humanoid.WalkSpeed = Data.HumStats.RunSpeed

	local minFlee = Data.Behaviour.MinFleeTime or 2
	local maxFlee = Data.Behaviour.MaxFleeTime or 10
	local TimeFleeing = os.clock() + math.random(minFlee, maxFlee)

	-- Similar to waypoint logic but biased for urgency
	task.spawn(function()
		while os.clock() < TimeFleeing do
			if Humanoid.Health <= 0 then break end
			task.wait()
		end
	end)

	Animal:SetAttribute("Fleeing", false)
end

--=====================================================
-- DEATH / RAGDOLL
--=====================================================

-- Converts the animal into a physics-driven ragdoll on death.
function Behaviour.Died(Animal : Model)
	if not Animal then return end

	local Humanoid = Animal:WaitForChild("Humanoid", 1)
	if Humanoid then Humanoid:Destroy() end

	Animal.Parent = workspace.DeadAnimals

	for _, Joint in Animal:GetDescendants() do
		if Joint:IsA("Part") or Joint:IsA("MeshPart") then
			Joint.CanCollide = true
		elseif Joint:IsA("Motor6D") and Joint.Parent.Name ~= "HumanoidRootPart" then
			-- Replace Motor6Ds with physics constraints for ragdolling
			local Part0, Part1 = Joint.Part0, Joint.Part1
			if not Part0 or not Part1 then continue end

			local A0 = Instance.new("Attachment")
			A0.CFrame = Joint.C0
			A0.Parent = Part0

			local A1 = Instance.new("Attachment")
			A1.CFrame = Joint.C1
			A1.Parent = Part1

			local Constraint = Instance.new("BallSocketConstraint")
			Constraint.Attachment0 = A0
			Constraint.Attachment1 = A1
			Constraint.Parent = Part0

			Joint.Enabled = false
		end
	end
end

--=====================================================
-- INJURY VISUAL EFFECTS
--=====================================================

-- Spawns blood pools at ground contact points for visual feedback.
local function BloodPoolHelper(Model : Model, Amount : number)
	task.spawn(function()
		for _ = 1, Amount do
			local origin = Model.PrimaryPart.Position + Vector3.new(0, 2, 0)

			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { Model }
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true

			local result = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
			if not result then continue end

			local BloodPool = Instance.new("Part")
			BloodPool.Name = "BloodPool"
			BloodPool.Size = Vector3.new(1, 1, 1)
			BloodPool.Anchored = true
			BloodPool.CanCollide = false
			BloodPool.Transparency = 0.5
			BloodPool.Color = Color3.fromRGB(255, 0, 0)
			BloodPool.Position = result.Position + Vector3.new(0, 0.01, 0)
			BloodPool.Orientation = Vector3.new(0, math.random(0, 360), 0)
			BloodPool.Parent = workspace.BloodPools

			task.wait(math.random(1, 2))
		end
	end)
end

-- Public API for spawning blood based on damage taken
function Behaviour.BloodPool(Animal : Model, LostHP : number)
	if not Animal or not LostHP then
		warn("[Behaviour]: Invalid BloodPool call")
		return
	end

	BloodPoolHelper(Animal, LostHP / 10)
end

return Behaviour
