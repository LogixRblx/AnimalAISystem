return {
	Name = "Brown Bear", --// General name with spaces for UI etc.
	
	--// HUMANOID STATS //--
	HumStats = {
		WalkSpeed = 10, --// General Speed while roaming
		RunSpeed = 22, --// Speed while fleeing
		Damage = 15, --// Damage if animal is aggressive
		Health = 100, --// Base Health
	},
	
	--// GENERAL BEHAVIOUR //--
	Behaviour = {
		MaxWalkDistance = 35, --// Max distance that the animal will walk
		MinWalkDistance = 5, --// Smallest distance ""
		
		MaxIdleTime = 15, --// Max time the animal will do "nothing"
		MinIdleTime = 2, --// Min time ""
		
		MaxFleeTime = 10, --// Max time the animal will flee
		MinFleeTime = 2, --// Min time ""
		
		MaxFleeDistance = 100, --// Max distance for fleeing
		MinFleeDistance = 20, --// Min distance ""
		
		AlertRange = 30, --// The range in which the animal will detect players and get suspicious OR chase players
		MaxChaseDistance = 35, --// This one is optional --> Needs to exist if the animal is aggressive otherwise the default will be used
		AttackRange = 5, --// Attack range if the animal is aggressive
		AttackCooldown = 1, --// Attack cooldown if the animal is aggressive
		
		Type = "Aggressive" --// ALL TYPES: "Aggressive" and "Friendly". Aggressive = Attacks players; Friendly = Runs away from players
	},
	
	--// SAFETY SETTINGS //--
	Safety = { --// Safety indicates how close players are to animals so if the feel safe/in danger!
		FleeingSafety = 35, --// The higher this number, the faster will the animal flee from players
	},
	
	--// FOR PATHFINDING //--
	Agent = {
		AgentRadius = 4.5, --// Range of the animal
		AgentHeight = 4, --// Height of the animal
		AgentCanJump = false, --// If the animal can jump --> Isnt implemented yet...
		AgentMaxSlope = 85, --// Max slope angle it can walk up
	},
};
