#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
//#include <CustomPlayerSkins>
//#include <dds>

#pragma semicolon 1
#pragma newdecls required

EngineVersion g_Game; // 게임 체크

#define PLUGIN_VERSION "1.4"

public Plugin myinfo =
{
	name = "Third Person Mod",
	author = "Trostal",
	description = "3인칭 시스템을 담당하는 모드입니다.",
	version = PLUGIN_VERSION,
	url = "https://github.com/Hatser/Third-Person-Mod"
};

// Floats and Vectors
float CameraDistanceOffset[MAXPLAYERS+1];
float ToggleCoolDown[MAXPLAYERS+1];
float PlayerEyeAngleOffsets[MAXPLAYERS+1][3];
float PreEyeAngle[MAXPLAYERS+1][3];

// Booleans
bool IsPlayerInThirdPersonView[MAXPLAYERS+1] = false;
bool AllowOnceTriggerTouch[MAXPLAYERS+1][1025];
bool AvoidTriggerTouching[MAXPLAYERS+1] = true;

// For indexes
int CameraIndex[MAXPLAYERS+1] = -1;
int ViewEntity[MAXPLAYERS+1] = -1;

//죽거나 리스폰할 경우 리셋!
public void OnPluginStart()
{
	HookEvent("player_death", Player_Death);
	HookEvent("player_spawn", Player_Death);
	RegConsoleCmd("sm_3", Cmd_ThirdPerson);
	RegConsoleCmd("sm_tp", Cmd_ThirdPerson);
	RegConsoleCmd("sm_thirdperson", Cmd_ThirdPerson);
	RegConsoleCmd("sm_lookself", Cmd_ThirdPerson);
	
	AddCommandListener(SayHook, "say");
	AddCommandListener(SayHook, "say_team");
	
	g_Game = GetEngineVersion();
}

public Action SayHook(int client, const char[] command, int args)
{
	char Msg[256];
	GetCmdArgString(Msg, sizeof(Msg));
	Msg[strlen(Msg)-1] = '\0';

	if(StrEqual(Msg[1], "!3인칭", false))
	{
		Cmd_ThirdPerson(client, 0);
	}
	
	return Plugin_Continue;
}

public void OnMapStart()
{
	if(g_Game == Engine_CSS)
		PrecacheModel("models/blackout.mdl", true);
	else if(g_Game == Engine_CSGO)
		PrecacheModel("models/ghost/ghost.mdl", true);
		
}

public void OnClientPutInServer(int client)
{
	ZeroVector(PlayerEyeAngleOffsets[client]);
	ZeroVector(PreEyeAngle[client]);
	CameraDistanceOffset[client] = 0.0;
	ToggleCoolDown[client] = 0.0;
	
	SDKHook(client, SDKHook_SetTransmit, SetTransmit);
}

public void OnClientDisconnect(int client)
{
	if(IsPlayerInThirdPersonView[client])
		FirstPersonView(client);
	
	ZeroVector(PlayerEyeAngleOffsets[client]);
	ZeroVector(PreEyeAngle[client]);
	CameraDistanceOffset[client] = 0.0;
	ToggleCoolDown[client] = 0.0;
	
	SDKUnhook(client, SDKHook_SetTransmit, SetTransmit);
}

public Action Player_Death(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
	if(IsPlayerInThirdPersonView[client])
		FirstPersonView(client);
	
	for(int i;i<sizeof(AllowOnceTriggerTouch[]);i++)
	{
		if(!AllowOnceTriggerTouch[client][i])
			AllowOnceTriggerTouch[client][i] = true;
	}
	
	ToggleCoolDown[client] = 0.0;
	
	if (!IsValidClient(client)) return Plugin_Continue;
//	if (GetEventInt(event, "death_flags") & 32) return; // 팀포2 에서의 스파이 데드링어로 인한 페이크데스 무시
	int ViewEnt = GetClientViewEntity(client);
	
	if (ViewEnt > MaxClients)
	{
		char cls[25];
		GetEntityClassname(ViewEnt, cls, sizeof(cls));
		if (StrEqual(cls, "point_viewcontrol", false)) SetClientViewEntity(client, client);
	}
	
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "trigger_") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, OnTriggerEntityTrigger);
		SDKHook(entity, SDKHook_EndTouch, OnTriggerEntityTrigger);
	}
}

public void OnEntityDestroyed(int entity)
{
	char classname[64];
	if(IsValidEdict(entity))
	{
		GetEntityClassname(entity, classname, sizeof(classname));
		if(StrContains(classname, "trigger_") != -1)
		{
			SDKUnhook(entity, SDKHook_StartTouch, OnTriggerEntityTrigger);
			SDKUnhook(entity, SDKHook_EndTouch, OnTriggerEntityTrigger);
		}
	}
}

public Action OnTriggerEntityTrigger(int entity, int other)
{
	if(IsValidPlayer(other))
	{		
		if(IsPlayerInThirdPersonView[other])
		{
			if(AllowOnceTriggerTouch[other][entity])
			{
				AllowOnceTriggerTouch[other][entity] = false;
				return Plugin_Continue;
			}
			else
			{
				return Plugin_Handled;
			}
		}
		if(AvoidTriggerTouching[other])
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action Cmd_ThirdPerson(int client, int args)
{
	Command_ThirdPersonMenu(client, NULL_STRING, -1);
}

public Action Command_ThirdPersonMenu(int client, const char[] command, int args)
{
	if(!IsValidPlayer(client))	return Plugin_Handled;
	
	Menu menu = new Menu(Menu_ThirdPersonMenu);
	menu.SetTitle("*** 3인칭 ***\n마우스를 움직여 카메라 이동이 가능합니다.\n앞, 뒤 이동키로 줌 인/아웃이 가능합니다.");
	
	if(!IsPlayerInThirdPersonView[client])
		menu.AddItem("Third person ON", "3인칭 ON");
	else
		menu.AddItem("Third person OFF", "3인칭 OFF");
		
	menu.ExitButton = true;
	
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Menu_ThirdPersonMenu(Menu menu, MenuAction action, int client, int select)
{
	if(action == MenuAction_Select && IsValidPlayer(client))
	{
		if(select == 0)
		{
			if(IsPlayerAlive(client))
			{
				IsPlayerInThirdPersonView[client] ? FirstPersonView(client) : ThirdPersonView(client);
				Command_ThirdPersonMenu(client, NULL_STRING, -1);
			}
		}
	}
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if(IsPlayerInThirdPersonView[client])
	{
		if(buttons & IN_FORWARD && !(buttons & IN_BACK))
		{
			if(CameraDistanceOffset[client] > 16.0)
				CameraDistanceOffset[client] -= 1.0;
		}
		if(buttons & IN_BACK && !(buttons & IN_FORWARD))
		{
			if(CameraDistanceOffset[client] < 128.0)
				CameraDistanceOffset[client] += 1.0;
		}
//		if(vel[0] == 0.0 && vel[1] == 0.0 && vel[2] == 0.0)	SetEntityMoveType(client, MOVETYPE_NONE);
//		else
		ZeroVector(vel);
		return Plugin_Changed;

//		if(buttons & IN_FORWARD || buttons & IN_BACK || buttons & IN_MOVELEFT || buttons & IN_MOVERIGHT)
//			return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void Think(int client)
{
	if(!IsValidPlayer(client))	return;
	
	float NowAngle[3];
	GetClientEyeAngles(client, NowAngle);
	
	ClampAngle(PreEyeAngle[client]);
	ClampAngle(NowAngle);
	
	// pre(179) - Now(-179)
	PlayerEyeAngleOffsets[client][0] += (PreEyeAngle[client][0] - NowAngle[0]);
	PlayerEyeAngleOffsets[client][1] += (PreEyeAngle[client][1] - NowAngle[1])/**1.15*/;
	PlayerEyeAngleOffsets[client][2] += (PreEyeAngle[client][2] - NowAngle[2]);
//	PlayerEyeAngleOffsets[client][0] = (PreEyeAngle[client][0] - NowAngle[0]);
//	PlayerEyeAngleOffsets[client][1] = (PreEyeAngle[client][1] - NowAngle[1]);
//	PlayerEyeAngleOffsets[client][2] = (PreEyeAngle[client][2] - NowAngle[2]);
	PlayerEyeAngleOffsets[client][1] = -PlayerEyeAngleOffsets[client][1];
	
	ClampAngle(PlayerEyeAngleOffsets[client]);
	
	float CameraPosition[3], CameraAngle[3];
	GetCameraPositionAndAngle(client, CameraPosition, CameraAngle, PlayerEyeAngleOffsets[client], CameraDistanceOffset[client]);
	
	ClampAngle(PlayerEyeAngleOffsets[client]);
	TeleportEntity(client, NULL_VECTOR, PreEyeAngle[client], NULL_VECTOR);
	
	/*
	float NowPosition[3], float MoveCameraVector[3];
	GetEntPropVector(CameraIndex[client], Prop_Data, "m_vecOrigin", NowPosition);
	MakeVectorFromPoints(NowPosition, CameraPosition, MoveCameraVector);
	NormalizeVector(MoveCameraVector, MoveCameraVector);
	SetEntityMoveType(CameraIndex[client], MOVETYPE_NOCLIP);
	ScaleVector(MoveCameraVector, 100.0);
	TeleportEntity(CameraIndex[client], NULL_VECTOR, CameraAngle, MoveCameraVector);
	*/
	ClampAngle(CameraAngle);
	TeleportEntity(CameraIndex[client], CameraPosition, CameraAngle, NULL_VECTOR);
}
	
public void FirstPersonView(int client)
{
	if(!IsValidPlayer(client))	return;
	
	IsPlayerInThirdPersonView[client] = false;
	
	SDKUnhook(client, SDKHook_PreThink, Think);
	SDKUnhook(client, SDKHook_PreThinkPost, Think);
	SDKUnhook(client, SDKHook_PostThink, Think);
	SDKUnhook(client, SDKHook_PostThinkPost, Think);
	if(IsValidEntity(ViewEntity[client]))
		SetClientViewEntity(client, ViewEntity[client]);
	else
		SetClientViewEntity(client, client);
	
	ViewEntity[client] = -1;
	
	if(IsValidEntity(CameraIndex[client]))
		AcceptEntityInput(CameraIndex[client], "Kill");
		
	CameraIndex[client] = -1;
	
//	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", -1);
	SetEntProp(client, Prop_Send, "m_iObserverMode", 0);
//	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
	CreateTimer(0.25, ToggleAboidTrigger, client);
	ToggleCoolDown[client] = GetGameTime() + 3.0;
	
	ZeroVector(PlayerEyeAngleOffsets[client]);
	ZeroVector(PreEyeAngle[client]);
	CameraDistanceOffset[client] = 0.0;
	
//	CPS_SetTransmit(client, client, 0);
}

public Action ToggleAboidTrigger(Handle timer, int client)
{
	AvoidTriggerTouching[client] = IsPlayerInThirdPersonView[client];
}

public void ThirdPersonView(int client)
{
	if(!IsValidPlayer(client))	return;
	
	if(ToggleCoolDown[client] > GetGameTime())
	{
		PrintHintText(client, "%.1f초 후에 다시 시도해주세요", ToggleCoolDown[client]-GetGameTime());
		return;
	}
	
	ZeroVector(PlayerEyeAngleOffsets[client]);
	ZeroVector(PreEyeAngle[client]);
	CameraDistanceOffset[client] = 0.0;
	
	IsPlayerInThirdPersonView[client] = true;
	
	ViewEntity[client] = GetClientViewEntity(client);

	int ent = CreateEntityByName("prop_dynamic_override");
	
	if(g_Game == Engine_CSS)
		DispatchKeyValue(ent, "model", "models/blackout.mdl");
	else if(g_Game == Engine_CSGO)
		DispatchKeyValue(ent, "model", "models/ghost/ghost.mdl");
	
	
	char steamid[64], TargetName[128];
	GetClientAuthId(client, AuthId_Steam2, steamid, 64);
	Format(TargetName, 128, "TP Camera(%i): %s", ent, steamid);
	DispatchKeyValue(ent, "targetname", TargetName);

	DispatchKeyValue(ent, "spawnflags", "4");
	SetEntProp(ent, Prop_Data, "m_CollisionGroup", 2);
	SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", client);
	
	DispatchSpawn(ent);
	AcceptEntityInput(ent, "TurnOn", ent, ent, 0);
	
	SetEntityRenderMode(ent, RENDER_NONE);
	SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 0.000001);
	
	CameraIndex[client] = ent;
	
	float Init_CameraPosition[3], Init_CameraAngle[3];
	CameraDistanceOffset[client] = 80.0;
	GetCameraPositionAndAngle(client, Init_CameraPosition, Init_CameraAngle, NULL_VECTOR, CameraDistanceOffset[client]);
	
	TeleportEntity(ent, Init_CameraPosition, Init_CameraAngle, NULL_VECTOR); 
	
	GetClientEyeAngles(client, PreEyeAngle[client]);
	PlayerEyeAngleOffsets[client][0] = PreEyeAngle[client][0];
	PlayerEyeAngleOffsets[client][1] = PreEyeAngle[client][1];
	SDKHook(client, SDKHook_PreThink, Think);
	SDKHook(client, SDKHook_PreThinkPost, Think);
	SDKHook(client, SDKHook_PostThink, Think);
	SDKHook(client, SDKHook_PostThinkPost, Think);
	SetClientViewEntity(client, ent);
	
//	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", ent);
	SetEntProp(client, Prop_Send, "m_iObserverMode", 1);
//	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
	CreateTimer(0.25, ToggleAboidTrigger, client);
	
//	CPS_SetTransmit(client, client, 1);
}

stock void GetCameraPositionAndAngle(int client, float resultPosition[3], float resultAngle[3], float ClientCameraOffsets[3]=NULL_VECTOR, float distance=64.0)
{
	float ClientPosition[3], ClientEyeAngles[3];
	
	GetClientEyePosition(client, ClientPosition);
	GetClientEyeAngles(client, ClientEyeAngles);
	
	
//	ClientPosition[2] = 48.0;
	ClientEyeAngles[2] = 0.0;
	
	ClampAngle(ClientCameraOffsets);
		
//	PrintCenterText(client, "PreEyeAngle: %f %f %f\nClientEyeAngles: %f %f %f\nClientCameraOffsets: %f %f %f", PreEyeAngle[client][0], PreEyeAngle[client][1], PreEyeAngle[client][2], ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2], ClientCameraOffsets[0], ClientCameraOffsets[1], ClientCameraOffsets[2]);

	Handle trace = TR_TraceRayFilterEx(ClientPosition, ClientCameraOffsets, CONTENTS_SOLID, RayType_Infinite, TraceEntityFilter);
	
	if (TR_DidHit(trace))
	{
		/*
		if (TR_GetEntityIndex(trace) > 0) {
			CloseHandle(trace);
			return false;
		}
		*/
		float EndPosition[3];
		TR_GetEndPosition(EndPosition, trace);
		
		if (GetVectorDistance(ClientPosition, EndPosition) <= distance)
		{
			CopyVector(EndPosition, resultPosition);
		}
		else
		{
			float EyeAngleVectors[3];
			GetAngleVectors(ClientCameraOffsets, EyeAngleVectors, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(EyeAngleVectors, EyeAngleVectors);
			ScaleVector(EyeAngleVectors, distance);
			
			AddVectors(ClientPosition, EyeAngleVectors, resultPosition);
		}
		
		float CameraToClientVectors[3];
		MakeVectorFromPoints(resultPosition, ClientPosition, CameraToClientVectors);
		GetVectorAngles(CameraToClientVectors, resultAngle);
		ClampAngle(resultAngle);
	}
	
	CloseHandle(trace);
}

public bool TraceEntityFilter(int entity, int contentsMask)
{
	return entity == 0;
}

stock bool IsValidClient(int client)
{
	if(client > 0 && client < MaxClients)
	{
		if(IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && !IsClientReplay(client))
		{
			return true;
		}
		else
		{
			return false;
		}
	}
	else
	{
		return false;
	}
}

stock int GetClientViewEntity(int client)
{
	return GetEntPropEnt(client, Prop_Data, "m_hViewEntity");
}

stock bool IsValidPlayer(int client)
{
	if(IsValidClient(client) && IsPlayerAlive(client))
	{
		return true;
	}
	else
	{
		return false;
	}
}

stock void ClampAngle(float angles[3])
{
	if (angles[0] > 89.5 && angles[0] <= 180.0)
	{
		angles[0] = 89.5;
	}
	if (angles[0] > 180.0)
	{
		angles[0] -= 360.0;
	}
	if (angles[0] < -89.5)
	{
		angles[0] = -89.5;
	}
	if (angles[1] > 180.0)
	{
		angles[1] -= 360.0;
	}
	if (angles[1] < -180.0)
	{
		angles[1] += 360.0;
	}
	if (angles[2] != 0.0)
	{
		angles[2] = 0.0;
	}
}

stock void ZeroVector(float vector[3])
{
	vector[0] = 0.0;
	vector[1] = 0.0;
	vector[2] = 0.0;
}

stock void CopyVector(const float input[3], float output[3])
{
	output[0] = input[0];
	output[1] = input[1];
	output[2] = input[2];
}

public Action SetTransmit(int target, int client)
{
	if(IsValidPlayer(client))
	{
		if(IsPlayerInThirdPersonView[client])
		{
			if(IsValidClient(target))
			{
				if(client != target)
				{
					return Plugin_Handled;
				}
			}
		}
	}
	return Plugin_Continue;
}
