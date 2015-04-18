#include <sourcemod>
#include <sdktools>

// Spawns
new Handle:kvSpawns
new spawnCount = 0
new String:spawnFile[192]

// First Spawn
new Handle:firstHandle = INVALID_HANDLE
new firstSpawnId[MAXPLAYERS+1]
new bool:firstSpawn

// Spawn protection
new Float:protectTime = 3.0
new Handle:timers[MAXPLAYERS+1]

public Plugin:myinfo =
{
	name = "Random Spawns",
	author = "MrBS",
	description = "Modifies spawn to be at random predetermined locations",
	version = "1.02",
}

public OnAllPluginsLoaded()
{
	// TODO
	// 1. Make spawns less random (meaning make them organized so that people dont spawn ontop of each other)
	//		a. Backlog the last 1/4 of spawns, and make them spawn elsewhere
	//		b. Retire a spawn number for a certain number of time (could lead to issues if retired spawn number gets selected a bunch in a row
	LoadTranslations("common.phrases")
	
	HookEvent("player_spawn", Event_PlayerSpawn)
	HookEvent("round_start", Event_RoundStart)
	HookEvent("weapon_fire", Event_WeaponFire)
	
	RegAdminCmd("sr_add", Command_RegSpawn, ADMFLAG_SLAY, "sr_add <name> - Add spawn with name")
	RegAdminCmd("sr_del", Command_DelSpawn, ADMFLAG_SLAY, "sr_del <name> - Delete spawn with name")
	RegAdminCmd("sr_delid", Command_DelSpawnId, ADMFLAG_SLAY, "sr_delid <id> - Delete spawn with id")
	RegAdminCmd("sr_tele", Command_TeleSpawn, ADMFLAG_SLAY, "sr_tele <name> - Teleport to spawn with name")
	RegAdminCmd("sr_teleid", Command_TeleSpawnId, ADMFLAG_SLAY, "sr_teleid <id> - Teleport to spawn with id")
	RegAdminCmd("sr_list", Command_ListSpawn, ADMFLAG_SLAY, "sr_list - List spawns for current map")
	RegAdminCmd("sr_protect", Command_Protect, ADMFLAG_SLAY, "sr_protect <name> - Test the protection on a target")
}

public OnMapStart()
{
	kvSpawns = CreateKeyValues("Spawns")
	
	decl String:mapName[64]
	GetCurrentMap(mapName, sizeof(mapName))
	
	Format(spawnFile, sizeof(spawnFile), "cfg/spawnrandomizer/%s.spawns.txt", mapName)
	
	if(FileExists(spawnFile))
		FileToKeyValues(kvSpawns, spawnFile)
	else
		PrintToServer("[Spawn Randomizer] %s was not found, will use default spawns.", spawnFile)
	
	new bool:hasSpawns = KvGotoFirstSubKey(kvSpawns, true)
	
	if(hasSpawns)
	{
		new count = 1
		while(KvGotoNextKey(kvSpawns, true))
		{
			count++
		}
		
		spawnCount = count
	}
	
	KvRewind(kvSpawns)
	
	if(spawnCount > 0)
	{
		Remove_Restricted()
		PrintToServer("[Spawn Randomizer] Removing restricted areas since there are random spawns.")
	}
	else
	{
		PrintToServer("[Spawn Randomizer] No random spawns, not removing restricted areas.")
	}
	
	firstSpawn = true
	
	FirstSpawn()
}

public OnMapEnd()
{
	ClearSpawnList()
	CloseHandle(kvSpawns)
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid")
	new client = GetClientOfUserId(userId)
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue
	
	if(client < 0 || client > 64)
		return Plugin_Continue
		
	if(spawnCount <= 0)
		return Plugin_Continue
	
	// Teleport to random spawn here
	
	new spawnId = GetRandomInt(1, spawnCount)
	
	if(firstSpawn)
		spawnId = firstSpawnId[client]
	
	decl Float:origin[3], Float:angles[3]
	decl String:spawnName[64]
	
	GetSpawnById(spawnId, spawnName, sizeof(spawnName), origin, angles)
	
	TeleportEntity(client, origin, angles, NULL_VECTOR)
	
	SpawnProtection(client)
	
	return Plugin_Continue
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	firstSpawn = true
	
	if(firstHandle != INVALID_HANDLE)
	{
		CloseHandle(firstHandle)
		firstHandle = INVALID_HANDLE
	}
	
	FirstSpawn()
	
	firstHandle = CreateTimer(20.0, Timer_EndFirstSpawn, _)
	
	return Plugin_Continue
}

public FirstSpawn()
{
	PrintToServer("[Spawn Randomizer] Generating first spawns.")

	new seed = GetRandomInt(1,spawnCount)
	
	for(new i = 1; i <= 16; i++)
	{
		firstSpawnId[i] = ((i+seed) % (spawnCount)) + 1
	}
}

public Action:Timer_EndFirstSpawn(Handle:timer, any:client)
{
	firstSpawn = false
	
	firstHandle = INVALID_HANDLE
	
	return Plugin_Continue
}

public Action:Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid")
	new client = GetClientOfUserId(userId)
	
	if (timers[client] == INVALID_HANDLE) {
		return
	}
	
	CloseHandle(timers[client])

	EndSpawnProtection(client)
}

public Action:Command_RegSpawn(client, args)
{
	decl String:spawnName[64]
	GetCmdArg(1, spawnName, sizeof(spawnName))
	
	decl Float:spawnOrg[3], Float:spawnAng[3]
	GetClientAbsOrigin(client, spawnOrg)
	GetClientEyeAngles(client, spawnAng)
	
	new bool:spawnCreated = AddSpawn(spawnName, spawnOrg, spawnAng)
	
	if(spawnCreated)
		PrintToChat(client, "Spawn \"%s\" created.", spawnName)
	else
		PrintToChat(client, "Spawn \"%s\" not created, name already exists.", spawnName)
	
	return Plugin_Handled
}

public Action:Command_DelSpawn(client, args)
{
	decl String:spawnName[64]
	GetCmdArg(1, spawnName, sizeof(spawnName))
	
	new bool:spawnDeleted = DelSpawn(spawnName)
	
	if(spawnDeleted)
		PrintToChat(client, "Spawn \"%s\" deleted.", spawnName)
	else
		PrintToChat(client, "Spawn \"%s\" not deleted, name doesn't exist.", spawnName)
	
	return Plugin_Handled
}

public Action:Command_DelSpawnId(client, args)
{
	decl String:spawnIdStr[64]
	GetCmdArg(1, spawnIdStr, sizeof(spawnIdStr))
	new spawnId = StringToInt(spawnIdStr)
	
	if(spawnId > spawnCount || spawnId < 1)
	{
		PrintToChat(client, "Spawn id must be between 1 and %i.", spawnCount)
		return Plugin_Handled
	}
	
	decl Float:origin[3], Float:angles[3]
	decl String:spawnName[64]
	
	GetSpawnById(spawnId, spawnName, sizeof(spawnName), origin, angles)
	
	new bool:spawnDeleted = DelSpawn(spawnName)
	
	if(spawnDeleted)
		PrintToChat(client, "Spawn id %i (%s) deleted.", spawnId, spawnName)
	else
		PrintToChat(client, "Spawn id %i (%s) not deleted, name doesn't exist.", spawnId, spawnName)
	
	return Plugin_Handled
}

public Action:Command_TeleSpawn(client, args)
{
	decl String:spawnName[64]
	GetCmdArg(1, spawnName, sizeof(spawnName))
	
	decl Float:origin[3], Float:angles[3]
	
	new bool:hasSpawn = GetSpawnByName(spawnName, origin, angles)
	
	if(hasSpawn)
	{
		TeleportEntity(client, origin, angles, NULL_VECTOR)
		PrintToChat(client, "Teleported to \"%s\".", spawnName)
	}
	else
	{
		PrintToChat(client, "No spawn with name \"%s\".", spawnName)
	}
	
	return Plugin_Handled
}

public Action:Command_TeleSpawnId(client, args)
{
	decl String:spawnIdStr[64]
	GetCmdArg(1, spawnIdStr, sizeof(spawnIdStr))
	new spawnId = StringToInt(spawnIdStr)
	
	if(spawnId > spawnCount || spawnId < 1)
	{
		PrintToChat(client, "Spawn id must be between 1 and %i.", spawnCount)
		return Plugin_Handled
	}
	
	decl Float:origin[3], Float:angles[3]
	decl String:spawnName[64]
	
	GetSpawnById(spawnId, spawnName, sizeof(spawnName), origin, angles)
	
	TeleportEntity(client, origin, angles, NULL_VECTOR)
	PrintToChat(client, "Teleported to %i (%s).", spawnId, spawnName)
	
	return Plugin_Handled
}

public Action:Command_ListSpawn(client, args)
{
	PrintSpawns(client)
	
	return Plugin_Handled
}

public Action:Command_Protect(client, args)
{
	decl String:targetStr[64]
	GetCmdArg(1, targetStr, sizeof(targetStr))
	
	new target = FindTarget(client, targetStr)
	
	SpawnProtection(target)
	
	return Plugin_Handled
}

public Remove_Restricted()
{
	new entId = -1
	
	for(;;)
	{
		entId = FindEntityByClassname(entId, "ins_blockzone")
		
		if(entId < 0)
			break
		
		AcceptEntityInput(entId, "Kill")
	}
}

public SpawnProtection(client)
{
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1)
	
	timers[client] = CreateTimer(protectTime, Timer_EndSpawnProtection, client)
	
	PrintToChat(client, "[Spawn Protection] Protected for %i seconds.", RoundToNearest(protectTime))
}

public Action:Timer_EndSpawnProtection(Handle:timer, any:client)
{
	EndSpawnProtection(client)
}

public EndSpawnProtection(client)
{
	timers[client] = INVALID_HANDLE
	
	if ( !IsClientInGame(client) || !IsPlayerAlive(client) )
	{
		return
	}

	SetEntProp(client, Prop_Data, "m_takedamage", 2, 1)
	
	PrintToChat(client, "[Spawn Protection] Protection over.")
}

public bool:SpawnExists(const String:name[])
{
	new bool:exists = KvJumpToKey(kvSpawns, name)
	KvRewind(kvSpawns)
	
	return exists
}

public bool:AddSpawn(const String:name[], Float:origin[3], Float:angles[3])
{
	if(SpawnExists(name))
		return false
	
	// No up/down
	angles[0] = 0.0
	angles[2] = 0.0
	
	KvJumpToKey(kvSpawns, name, true)
	KvSetVector(kvSpawns, "origin", origin)
	KvSetVector(kvSpawns, "angles", angles)
	KvRewind(kvSpawns)
	
	KeyValuesToFile(kvSpawns, spawnFile)
	
	spawnCount++
	
	return true
}

public bool:DelSpawn(const String:name[])
{
	if(!SpawnExists(name))
		return false
	
	KvJumpToKey(kvSpawns, name)
	KvDeleteThis(kvSpawns)
	KvRewind(kvSpawns)
	
	KeyValuesToFile(kvSpawns, spawnFile)
	
	spawnCount--
	
	return true
}

public ClearSpawnList()
{
	if(!KvGotoFirstSubKey(kvSpawns))
		return
	
	for (;;)
	{
		if (KvDeleteThis(kvSpawns) < 1)
		{
			break
		}
	}
	
	spawnCount = 0
}

public bool:GetSpawnByName(const String:name[], Float:retOrigin[3], Float:retAngles[3])
{
	if(!SpawnExists(name))
		return false
	
	KvJumpToKey(kvSpawns, name)
	KvGetVector(kvSpawns, "origin", retOrigin)
	KvGetVector(kvSpawns, "angles", retAngles)
	KvRewind(kvSpawns)
	
	return true
}

public bool:GetSpawnById(id, String:name[], maxLength, Float:retOrigin[3], Float:retAngles[3])
{
	if(id > spawnCount)
		return false
	
	decl String:spawnName[64]
	
	KvGotoFirstSubKey(kvSpawns, true)

	new count = 1
	while(count < id)
	{
		KvGotoNextKey(kvSpawns, true)
		count++
	}
	
	KvGetSectionName(kvSpawns, spawnName, sizeof(spawnName))
	
	KvGetVector(kvSpawns, "origin", retOrigin)
	KvGetVector(kvSpawns, "angles", retAngles)
	
	KvRewind(kvSpawns)
	
	strcopy(name, maxLength, spawnName)
	
	return true
}

public PrintSpawns(client)
{
	if(spawnCount <= 0)
	{
		PrintToConsole(client, "Spawn list empty.")
		return
	}
	
	PrintToConsole(client, "Spawn list:")
	PrintToConsole(client, "<id>: <name>")
	
	KvGotoFirstSubKey(kvSpawns, true)
	
	decl String:spawnName[64]
	
	new count = 1
	while(count <= spawnCount)
	{
		KvGetSectionName(kvSpawns, spawnName, sizeof(spawnName))
		PrintToConsole(client, "%i: %s", count, spawnName)
		
		KvGotoNextKey(kvSpawns, true)
		count++
	}
	
	KvRewind(kvSpawns)
}