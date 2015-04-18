#include <sourcemod>
#include <sdktools>

public Plugin:myinfo =
{
	name = "Insurgency Free For All",
	author = "MrBS",
	description = "Modifies logic to be free for all",
	version = "1.02",
}

public OnAllPluginsLoaded()
{
	LoadTranslations("common.phrases")
	
	// Info area
	// UserMessage ID = UserMessage = Description
	// 5 = HintText = This is the blinky friendly fire text at bottom of screen
	// 9 = SayText2 = User Chat
	// 10 = TextMsg = Print to chat (friendly fire msg) (also print to chat hud_center)
	// 41 = HQAudio = When you are on a point/someone contests/etc.
	
	// TODO: Make sv_hud_deathmessages report the correct weapon on teamkill
	// TODO: Suppress console reporting 'User attacked a teammate' (just annoying) (probably requires extension)
	
	//Suppression of friendly fire messages
	HookUserMessage(GetUserMessageId("HintText"), Block_FFHint, true)
	HookUserMessage(GetUserMessageId("TextMsg"), Block_FFMsg, true)
	
	// Block friendly fire sounds
	AddNormalSoundHook(Hook_NormalSound);
	
	CreateTimer(300.0, Timer_PrintMessage, _, TIMER_REPEAT)
}

public Action:Timer_PrintMessage(Handle:timer)
{
	PrintMessage(0)
}

public PrintMessage(user)
{
	decl String:msg[192]
	Format(msg, sizeof(msg), "[FFA] This server is a free for all.")
	
	if(user == 0)
		PrintToChatAll(msg)
	else
		PrintToChat(user, msg)
}

public OnMapStart()
{
	// Make friendly fire damage 100%
	SetConVarInt(FindConVar("mp_friendlyfire_damage"),1)
	SetConVarInt(FindConVar("mp_friendlyfire_damage_spawnarea"),1)
	
	// Remove tk punishment
	SetConVarInt(FindConVar("mp_tkpunish"),0)
	SetConVarInt(FindConVar("mp_autokick"),0)
	
	// No spotting people
	SetConVarInt(FindConVar("mp_player_spotting"),0)
	
	// No indicators on anyone
	SetConVarInt(FindConVar("sv_hud_targetindicator"),0)
	
	// Talking
	SetConVarInt(FindConVar("sv_alltalk"),1)
	SetConVarInt(FindConVar("sv_alltalk_dead"),1)
	SetConVarInt(FindConVar("sv_deadchat"),1)
	SetConVarInt(FindConVar("sv_deadvoice"),1)
	SetConVarInt(FindConVar("sv_deadchat_team"),1)
	
	// Clean up crew (for performance)
	SetConVarInt(FindConVar("sv_weapon_manager_max_count"),0)
	SetConVarInt(FindConVar("sv_ragdoll_maxcount"),0)
	
	PrintToServer("[FFA] Free for all enabled.")
}

public OnMapEnd()
{
}

public Action:Block_FFHint(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	// Block flashy hint at bottom of screen
	return Plugin_Handled
}

public Action:Block_FFMsg(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	// Skip first two
	BfReadByte(bf) // was 3 always for chat | was 4 & 2 on game_restart_in_sec
	BfReadByte(bf) // 35 = Center, 91 = chat
	decl String:str[256]
	BfReadString(bf, str, sizeof(str), true)
	
	// First one is chat message, second one is centered on player's screen
	if(StrEqual(str, "Game_teammate_attack") || StrEqual(str, "Killed_Teammate"))
		return Plugin_Handled
	
	return Plugin_Continue
}

public Action:Hook_NormalSound(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	// If it tries to act as if a friendly fire, block it
	if(StrContains(sample, "watchfire", false) > 0 || StrContains(sample, "subdown", false) > 0 || StrContains(sample, "leaddown", false) > 0)
	{
		return Plugin_Handled
	}
	
	return Plugin_Continue
}