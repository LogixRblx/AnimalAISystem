local AnimationHandler = {}

local Species = script.Parent.Species

--// Function to stop running animations //--

local function StopAllAnimations(Animator : Animator)
	for _, track in Animator:GetPlayingAnimationTracks() do
		track:Stop(0.25)
	end
end

--// Helper for playing according animations --> Danger/Safety //--

local function IdleHelper(IdleStorage : Folder, Animator : Animator, Animal : Model)
	local NormalIdle = IdleStorage:WaitForChild("Idle", 2)
	local SafeIdle = IdleStorage:WaitForChild("Safe", 2)
	local DangerIdle = IdleStorage:WaitForChild("Danger", 2)
	
	if not NormalIdle or not SafeIdle or not DangerIdle then
		warn("[AnimationHandler]: Can´t find every needed Idle Animation for animal:", Animator.Name)
		return nil
	end
	
	local Safety = Animal:GetAttribute("Safety") or 100
	local chosenAnimation
	
	if Safety <= 50 then
		chosenAnimation = (math.random() < 0.5) and DangerIdle or NormalIdle
	else
		chosenAnimation = (math.random() < 0.5) and SafeIdle or NormalIdle
	end
	
	local track = Animator:LoadAnimation(chosenAnimation)
	track.Looped = true
	return track
end

--// Function for setting up animations //--

function AnimationHandler.InitAnimal(Animal : Model, MoveConfig : Configuration)
	local Storage = Species:FindFirstChild(Animal.Name)

	local Hum : Humanoid = Animal:WaitForChild("Humanoid", 2)
	if not Hum then return end

	local Animator : Animator = Hum:WaitForChild("Animator", 2)
	if not Animator then return end

	local Idles = Storage.Idles

	local WalkAnim = Animator:LoadAnimation(Storage.Walk)
	local RunAnim = Animator:LoadAnimation(Storage.Run)

	WalkAnim.Looped = true
	RunAnim.Looped = true

	local CurrentIdleTrack : AnimationTrack? = nil
	
	local function PlayIdle()
		if CurrentIdleTrack then
			CurrentIdleTrack:Stop()
			CurrentIdleTrack = nil
		end
		
		StopAllAnimations(Animator)
		
		CurrentIdleTrack = IdleHelper(Idles, Animator, Animal)
		if CurrentIdleTrack then
			CurrentIdleTrack:Play()
		end
	end
	
	PlayIdle()
	
	local RunCon = MoveConfig:GetAttributeChangedSignal("Running"):Connect(function()
		if MoveConfig:GetAttribute("Running") then
			StopAllAnimations(Animator)
			RunAnim:Play()
		else
			PlayIdle()
		end
	end)
	
	local WalkCon = MoveConfig:GetAttributeChangedSignal("Walking"):Connect(function()
		if MoveConfig:GetAttribute("Walking") then
			StopAllAnimations(Animator)
			WalkAnim:Play()
		else
			PlayIdle()
		end
	end)
	
	local IdleCon = MoveConfig:GetAttributeChangedSignal("Idle"):Connect(function()
		if MoveConfig:GetAttribute("Idle") then
			PlayIdle()
		else
			if CurrentIdleTrack then
				CurrentIdleTrack:Stop()
				CurrentIdleTrack = nil
			end
		end
	end)
	
	Hum.Died:Connect(function()
		if WalkCon then WalkCon:Disconnect() end
		if RunCon then RunCon:Disconnect() end
		if IdleCon then IdleCon:Disconnect() end
		StopAllAnimations(Animator)
	end)
end

return AnimationHandler
