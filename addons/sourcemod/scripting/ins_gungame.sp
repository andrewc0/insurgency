#include <sourcemod>
#include <sdktools>

enum INS_Weapon
{
	String:weaponName[32],
	String:weaponFullName[32],
	weaponId,
	magCount,
	String:deathMsg[32],
	String:auxWeaponName[32],
	auxWeaponId
}

// For 64 players, max 50 levels (see if you can make this better looking)
new ggLevels[MAXPLAYERS+1]
new INS_Weapon:ggWeapons[51][2][INS_Weapon]
new ggMaxLevel = 0

public Plugin:myinfo =
{
	name = "Insurgency GunGame",
	author = "MrBS",
	description = "Adds Insurgency GunGame",
	version = "2.00",
}

new Handle:hGameConfig
new Handle:hPlayerAmmo
new Handle:hPlayerTeam
new Handle:hRoundWon

new Handle:ggWeaponsKV
//new Handle:ggFFA - Make this a cvar, not hooking via loaded plugin check

// Dirty FFA workaround for now
new bool:isFFA = true

// To grab the occupy waves object
new objWaves

// TODO: See if you can't remove the end round win conditions for firefight, since that would be
// more exciting with 3 objs
// But then how do you make the objs work in FFA?
// Leave them uncapped and just blink them if someone is on?
// Give bonus to players on obj

// Team checks and suicide timer (for seeing if team swap was cause of suicide)
new teamCheck[MAXPLAYERS+1]
new Handle:suicideTimers[MAXPLAYERS+1] = { INVALID_HANDLE, ... }

public OnPluginStart()
{
	LoadTranslations("common.phrases")
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre)
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post)
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre)
	HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post)
  
	RegAdminCmd("gg_levelup", Command_GGLevelUp, ADMFLAG_SLAY, "gg_level <name>")
}

public OnAllPluginsLoaded()
{
	// Change the read data/hooks to happen on map change, so server hosts can change the levels and not have to restart the server, also allows dynamic level allocation for fancy stuff.
	ReadData()
	CreateHooks()
	
	CreateTimer(300.0, Timer_PrintMessage, _, TIMER_REPEAT)
}

public OnMapStart()
{
	// Grab objective object to hook into waves count
	objWaves = FindEntityByClassname(-1, "ins_objective_resource")
	
	// State if found or not
	if(objWaves < 0)
	{
		SetFailState("Fatal Error: Unable to find spawn waves entity!")
	}
	else
	{
		PrintToServer("[GG] Waves entity hooked!", objWaves)
	}
}

// Handles global message to server
public Action:Timer_PrintMessage(Handle:timer)
{
	PrintMessage(0)
}

// The global message
public PrintMessage(user)
{
	decl String:msg[192]
	Format(msg, sizeof(msg), "[GG] Questions, bug reports, suggestions: insmods@gmail.com")
	
	if(user == 0)
		PrintToChatAll(msg)
	else
		PrintToChat(user, msg)
}

// Level up via console command for 'testing' ;)
public Action:Command_GGLevelUp(client, args)
{
	decl String:arg1[32]
	GetCmdArg(1, arg1, sizeof(arg1))
	
	new target = FindTarget(client, arg1)
	
	if(target == -1)
	{
		PrintToConsole(client, "[GG] Target not found.")
		return Plugin_Handled
	}
	
	Handle_LevelEvent(target, false, false)
	Handle_WeaponEvent(target)
	
	return Plugin_Handled
}

// Where the magic happens
// On death, handle if it is a teamkill (non-FFA), good kill, or suicide.
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Grab all the data for the users
	new victimId = GetEventInt(event, "userid")
	new attackerId = GetEventInt(event, "attacker")
	
	new victim = GetClientOfUserId(victimId)
	new attacker = GetClientOfUserId(attackerId)
	
	new victimTeam = GetPlayerTeam(victim)
	new attackerTeam = GetPlayerTeam(attacker)
	
	// Get the attacker weapon
	decl String:atkWeapon[64]
	GetEventString(event, "weapon", atkWeapon, sizeof(atkWeapon))
	Format(atkWeapon, sizeof(atkWeapon), "weapon_%s", atkWeapon)
	
	// Update master team list
	teamCheck[victim] = victimTeam
	
	// Check for suicide (will check if it was a team swap, so it doesn't count)
	if(victim == attacker)
	{
		suicideTimers[victim] = CreateTimer(1.0, Timer_VerifySuicide, victim)
		return Plugin_Continue
	}
	
	// Check for team kill
	if(!isFFA && (victimTeam == attackerTeam))
	{
		Handle_LevelEvent(attacker, true, false)
		Handle_WeaponEvent(attacker)
		return Plugin_Continue
	}
	
	// Get attacker level & team ID
	new attackerLvl = ggLevels[attacker]
	new teamId = GetPlayerTeam(attacker)
	
	// Get level weapon, aux weapon, and kill str (if special)
	decl String:lvlWeapon[32], String:auxWep[32], String:killStr[32]
	strcopy(lvlWeapon, sizeof(lvlWeapon), ggWeapons[attackerLvl][teamId][weaponName])
	strcopy(auxWep, sizeof(auxWep), ggWeapons[attackerLvl][teamId][auxWeaponName])
	strcopy(killStr, sizeof(killStr), ggWeapons[attackerLvl][teamId][deathMsg])
	
	// Check if attack weapon matches level weapon OR if attack weapon matches kill str (like rocket, since it is different than the weapon)
	// Handle resupply if the aux weapon was used for the kill
	if(strcmp(atkWeapon,lvlWeapon) == 0 || strcmp(atkWeapon,killStr) == 0)
	{
		Handle_LevelEvent(attacker, false, false)
		Handle_WeaponEvent(attacker)
	}
	else if(strcmp(atkWeapon,auxWep) == 0)
	{
		Handle_WeaponResupply(attacker, lvlWeapon)
	}
	
	return Plugin_Continue
}

// Delay to check against team to see if it was a simple team swap
// If team swap, don't punish. Let people balance the teams.
public Action:Timer_VerifySuicide(Handle:timer, any:client)
{
	suicideTimers[client] = INVALID_HANDLE
	
	if (!IsClientInGame(client))
	{
		return Plugin_Continue
	}
	
	new clientTeam = GetPlayerTeam(client)
	
	if(teamCheck[client] == clientTeam)
		Handle_LevelEvent(client, false, true)
	
	return Plugin_Continue
}

// On spawn, handle level weapon, and increase wave count, so it never runs out.
public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid")
	new user = GetClientOfUserId(userId)
	
	// Give level weapon
	Handle_WeaponEvent(user)
	
	// Infinite waves, never ends
	SetEntProp(objWaves, Prop_Send, "000", 99, 2)
	SetEntProp(objWaves, Prop_Send, "001", 99, 2)
	
	return Plugin_Handled
}

// If disconnect be sure to clean up handles
public Action:Event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid")
	new client = GetClientOfUserId(userId)
	
	if(client < 0 || client > 64)
		return Plugin_Continue
	
	if(suicideTimers[client] != INVALID_HANDLE)
		CloseHandle(suicideTimers[client])

	return Plugin_Continue
}

// When player joins, set their level
public Action:Event_PlayerActivate(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid")
	new client = GetClientOfUserId(userId)
	
	if(client < 0 || client > 64)
		return Plugin_Continue
	
	// TODO: Add logic that will do adjustments based off how far the person is first is compared to the rest.
	ggLevels[client] = 1
	
	return Plugin_Continue
}

// Handles the users level up/down/win
public Handle_LevelEvent(client, bool:tk, bool:suicide)
{
	new String:clientName[64]
	GetClientName(client, clientName, sizeof(clientName))
	
	new curLevel = ggLevels[client]
	new nextLevel = curLevel
	
	if(suicide || tk)
	{
		if(curLevel > 1)
			nextLevel = curLevel - 1
	}
	else
		nextLevel = curLevel + 1
	
	if (nextLevel > ggMaxLevel)
	{
		PrintToChatAll("[GG] %s won!", clientName)
		
		SDKCall(hRoundWon, client, 0, 0, "", "")
	}
	else
	{
		if(nextLevel < curLevel)
		{
			if(suicide)
				PrintToChat(client,"[GG] Suicide! Level %i/%i.", nextLevel, ggMaxLevel)
			else if(tk)
				PrintToChat(client,"[GG] Team kill! Level %i/%i.", nextLevel, ggMaxLevel)
			ggLevels[client] = nextLevel
		}
		else if(nextLevel == curLevel)
		{
			if(suicide)
				PrintToChat(client,"[GG] Suicide! No level change.")
			else if(tk)
				PrintToChat(client,"[GG] Team Kill! No level change.")
		}
		else
		{
			ggLevels[client] = nextLevel
			new teamId = GetPlayerTeam(client)
			
			decl String:newWeapon[32]
			strcopy(newWeapon, sizeof(newWeapon), ggWeapons[nextLevel][teamId][weaponFullName])
			
			PrintToChat(client,"[GG] Level %i/%i (%s)", nextLevel, ggMaxLevel, newWeapon)
		}
	}
}

// Handle giving them their weapons, etc.
public Handle_WeaponEvent(client)
{
	new teamId = GetPlayerTeam(client)
	
	if(client < 1 || teamId < 0)
		return;
	
	new index = 0
	
	while(index < 5)
	{
			new weapon = GetPlayerWeaponSlot(client, index)
			
			// Check if valid and not knife
			if(IsValidEntity(weapon) && index != 2)
			{
				// Remove weapon
				RemovePlayerItem(client, weapon)
			}
			else
			{
				index = index + 1
			}
	}
	
	new level = ggLevels[client]
	
	decl String:newWeapon[32]
	strcopy(newWeapon, sizeof(newWeapon), ggWeapons[level][teamId][weaponName])
	new wepId =  ggWeapons[level][teamId][weaponId]
	new mags =  ggWeapons[level][teamId][magCount]
	
	new auxId = ggWeapons[level][teamId][auxWeaponId]
	
	if(auxId > 0)
	{
		new curAuxMags = GetAmmoCount(client, auxId)
		new newAuxMags = 10-curAuxMags
		
		decl String:auxWeapon[32]
		strcopy(auxWeapon, sizeof(auxWeapon), ggWeapons[level][teamId][auxWeaponName])
		
		SDKCall(hPlayerAmmo, client, newAuxMags, auxId, true)
		GivePlayerItem(client, auxWeapon)
	}
	
	new curMags = GetAmmoCount(client, wepId)
	new newMags = mags-curMags
	
	if(wepId >= 0)
	{
		if(newMags > 0)
    {
			SDKCall(hPlayerAmmo, client, newMags, wepId, true)
    }
	}
	
	GivePlayerItem(client, newWeapon)
	FakeClientCommandEx(client, "use %s", newWeapon)
}

// Resupply their level weapon (rockets, etc.)
public Action:Handle_WeaponResupply(client, String:weapon[32])
{
	new level = ggLevels[client]
	new teamId = GetPlayerTeam(client)
	
	new ammoId = ggWeapons[level][teamId][weaponId]
	new mags = ggWeapons[level][teamId][magCount]
	
	SDKCall(hPlayerAmmo, client, mags, ammoId, true)
	GivePlayerItem(client, weapon)
	
	PrintToChat(client, "[GG] You have been resupplied!")
}

// Get the ammo count from the ammoId
public GetAmmoCount(client, any:ammoId)
{
	if(ammoId >=0 && ammoId <= 255)
	{
		new ammo = GetEntProp(client, Prop_Send, "m_iAmmo", 2, ammoId)
		return ammo
	}
	else
	{
		return 0
	}
}

// Get the team
public GetPlayerTeam(client)
{
	// 3 = Insurgents
	// 2 = Security
	
	if(IsClientInGame(client))
	{
		return (SDKCall(hPlayerTeam, client) - 2)
	}
	else
		return 0
}

// Read in all the cfgs
public ReadData()
{
	ggWeaponsKV = CreateKeyValues("Weapons")
	if(!FileToKeyValues(ggWeaponsKV, "cfg/insgg/insurgency.equipment.txt"))
	{
		SetFailState("Fatal Error: Missing File insurgency.equipment.txt!")
	}
	
	new Handle:ggLevelsKV = CreateKeyValues("Levels")
	if(FileToKeyValues(ggLevelsKV, "cfg/insgg/insurgency.levels.txt"))
	{
		decl String:indexStr[32]
		new index = 1
		new bool:keysToFind = true
		
		while(keysToFind)
		{
			IntToString(index, indexStr, sizeof(indexStr))
			
			new String:ggLevelStr[64]
			KvGetString(ggLevelsKV, indexStr, ggLevelStr, sizeof(ggLevelStr))
			
			decl String:newWeapon[2][32]
			new wepCount = ExplodeString(ggLevelStr, ";", newWeapon, sizeof(newWeapon), sizeof(newWeapon[]))
			
			new wepNum = 0
			for(new i = 0; i < 2; i++)
			{
				wepNum = i
				if(wepCount < 2)
					wepNum = 0
				
				KvJumpToKey(ggWeaponsKV, newWeapon[wepNum])
				strcopy(ggWeapons[index][i][weaponName], 32, newWeapon[wepNum])
				
				decl String:fullWepName[32]
				KvGetString(ggWeaponsKV, "fullName", fullWepName, sizeof(fullWepName))
				strcopy(ggWeapons[index][i][weaponFullName],32,fullWepName)
				
				ggWeapons[index][i][weaponId] = KvGetNum(ggWeaponsKV, "ammoId")
				ggWeapons[index][i][magCount] = KvGetNum(ggWeaponsKV, "mags")
				
				decl String:wepDeathMsg[32]
				KvGetString(ggWeaponsKV, "death_msg", wepDeathMsg, sizeof(wepDeathMsg))
				strcopy(ggWeapons[index][i][deathMsg], 32, wepDeathMsg)
				
				decl String:auxWeapon[32]
				KvGetString(ggWeaponsKV, "aux", auxWeapon, sizeof(auxWeapon))
				new bool:hasAux = !(strcmp(auxWeapon, "") == 0)
				
				KvRewind(ggWeaponsKV)
				
				if(hasAux)
				{
					strcopy(ggWeapons[index][i][auxWeaponName], 32, auxWeapon)
					KvJumpToKey(ggWeaponsKV, auxWeapon)
					ggWeapons[index][i][auxWeaponId] = KvGetNum(ggWeaponsKV, "ammoId")
					KvRewind(ggWeaponsKV)
				}
				else
				{
					strcopy(ggWeapons[index][i][auxWeaponName], 32, "")
					ggWeapons[index][i][auxWeaponId] = 0
				}
			}
			
			keysToFind = strcmp(ggLevelStr,"") != 0
			
			if(keysToFind)
				ggMaxLevel = index
			
			index++
		}
	}
	else
	{
		SetFailState("Fatal Error: Missing File gungame.insurgency.levels.txt!")
	}
	
	CloseHandle(ggLevelsKV)
	CloseHandle(ggWeaponsKV)
}

public CreateHooks()
{
	hGameConfig = LoadGameConfigFile("insurgency.hooks")
	
	if (hGameConfig == INVALID_HANDLE)
	{
		SetFailState("Fatal Error: Missing File insurgency.hooks!")
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConfig, SDKConf_Virtual, "GiveAmmo")
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain)
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain)
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain)
	hPlayerAmmo = EndPrepSDKCall()
	
	if (hPlayerAmmo == INVALID_HANDLE)
	{
		SetFailState("Fatal Error: Unable to offset for ammo function!")
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConfig, SDKConf_Signature, "GetTeam")
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue)
	hPlayerTeam = EndPrepSDKCall()
	
	if (hPlayerTeam == INVALID_HANDLE)
	{
		SetFailState("Fatal Error: Unable to offset for get team!")
	}
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGameConfig, SDKConf_Signature, "RoundWon")
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer)
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer)
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer)
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer)
	hRoundWon = EndPrepSDKCall()
	
	if (hRoundWon == INVALID_HANDLE)
	{
		SetFailState("Fatal Error: Unable to find signature for RoundWon!")
	}
}