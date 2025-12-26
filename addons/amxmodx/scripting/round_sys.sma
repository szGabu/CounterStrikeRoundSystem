#include <amxmodx>

#if AMXX_VERSION_NUM < 183
#assert "AMX Mod X versions 1.8.2 and below are not supported."
#endif

#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <fun>
#tryinclude <reapi>

#define     PLUGIN_NAME             "Round System"
#define     PLUGIN_VERSION          "1.0.0-BETA"
#define     PLUGIN_AUTHOR           "szGabu"

#define     MATCHPOINT_SOUND        "misc/matchpoint.wav"
#define     GAME_COMMENCING_TEXT    "#Game_Commencing"
#define     GAME_RESTART_TEXT       "#Game_will_restart_in"

#define     TASK_VOTEROUNDZERO      548178187
#define     TASK_RESPAWN_PLAYER     578187541
#define     TASK_KNIFE_PLAYER       157859764
#define     TASK_WARMUP_CLOCK       471987568

#define     MAX_MONEY               16000

new g_szTerrorModels[][] = {
	"terror",
	"leet",
	"arctic",
    "guerilla",
	"militia"
};

new g_szCTModels[][] = {
	"urban",
	"gsg9",
	"sas",
	"gign",
	"spetsnaz"
};

new g_szWeapons[][] =
{	
	"weapon_p228",
	"weapon_scout",
	"weapon_hegrenade",
	"weapon_xm1014",
	"weapon_mac10",
	"weapon_aug",
	"weapon_smokegrenade",
	"weapon_elite",
	"weapon_fiveseven",
	"weapon_ump45",
	"weapon_sg550",
	"weapon_galil",
	"weapon_famas",
	"weapon_usp",
	"weapon_glock18",
	"weapon_awp",
	"weapon_mp5navy",
	"weapon_m249",
	"weapon_m3",
	"weapon_m4a1",
	"weapon_tmp",
	"weapon_g3sg1",
	"weapon_flashbang",
	"weapon_deagle",
	"weapon_sg552",
	"weapon_ak47",
	"weapon_p90"
};

#define WARMUP_DISABLED		            0
#define WARMUP_FULLBUY		            1
#define WARMUP_KNIVESONLY		        2

#define WARMUP_WINNER_VOTE		        0
#define WARMUP_WINNER_TERRORISTS		1
#define WARMUP_WINNER_CTS		        2

#pragma dynamic                         32768
#pragma semicolon                       1

new g_cvarRoundRestartDelay = INVALID_HANDLE;
new g_cvarTimeLimit = INVALID_HANDLE;
new g_cvarWinLimit = INVALID_HANDLE;

new g_iOriginalTimeLimit = -1;
new g_iOriginalWinLimit = -1;

new g_iCurrentRound = -1;
new g_iMaxRounds = 0;
new g_iRoundVictoriesTerror = 0;
new g_iRoundVictoriesCT = 0;
new g_iRoundZeroType = 0; 
new g_iRoundZeroWinners = 0; 
new g_iRoundZeroWinnersVoteTime = 10;
new g_iCurrentMaxRounds = 0;
new g_iMaxOverTimes = 0; 
new g_iOverTimeExtendAmount = 0;
new g_iOverTimes = 0; 
new g_iOverTimeMoney = 8000;
new g_iWarmUpTime = 60; 
new g_iWarmUpTimeLeft = 0; 
new g_iWarmUpAccelMinPlayers = 0;
new g_iWarmUpAccelTo = 0;
new g_iWarmUpSkipPercent = 0;
new Float:g_fTimeToRestart = 0.0;

new bool:g_bPluginEnabled = false;
new bool:g_bWamUpSkipable = false;
new bool:g_bIsFirstRoundOfSecondHalf = false;
new bool:g_bShouldFreezePlayers = false;
new bool:g_bIsOverTime = false;
new bool:g_bIsOverTimeFirstRound = false;
new bool:g_bOverTimeFullBuy = true;
new g_szCommandToExecuteWhenGameOver[MAX_NAME_LENGTH];

new g_iUsrMsgTeamScore = INVALID_HANDLE;
new g_iUsrMsgTextMsg = INVALID_HANDLE;
new g_iUsrMsgRoundTime = INVALID_HANDLE;
new g_iUsrMsgSendAudio = INVALID_HANDLE;

new g_iPlayerScoreBuffer[MAX_PLAYERS+1][3];
new bool:g_bPlayerReady[MAX_PLAYERS+1] = { false, ... };
new bool:g_bMoneyGivenThisRound[MAX_PLAYERS+1] = { false, ... };

new g_iVoteTerrorist = 0;
new g_iVoteCT = 0;

new g_hResetGameForward; 
new g_hWarmUpClockTickForward;
new g_hResetVariablesForward;
new g_hWarmUpStartForward;
new g_hMatchStartForward;
new g_hMatchEndedForward;

new g_iPluginFlags;

new g_hHudSyncWarmUpReady = INVALID_HANDLE;
new g_hHudSyncWarmUpNotReady = INVALID_HANDLE;

//this is used to display a delayed message at round restart, in theory I could pass it through the task itself but I'm too lazy
new g_szBufferText[128];
new g_iBufferParam = -1;

enum aGameState
{
    STATE_INACTIVE = 0, //plugin is not ready to process anything
	STATE_DORMANT, //no players are online
    STATE_WARMUP, //warmup process
    STATE_STARTING, //warmup ended, next round starts the game
    STATE_ONGOING, //current active game
    STATE_ENDED, //the end, no more game allowed
}

new aGameState:g_hCurrentGameState = STATE_INACTIVE;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    if(!is_running("cstrike") && !is_running("czero"))
        set_fail_state("This plugin is only compatible with Counter-Strike or Condition Zero.");

    register_clcmd("say ready", "Command_SayReady");
    register_clcmd("say /ready", "Command_SayReady");
    register_clcmd("say !ready", "Command_SayReady");
    register_clcmd("say .ready", "Command_SayReady");
    register_clcmd("amx_restart_match", "Command_RestartMatch");
    register_clcmd("say timeleft", "Command_SayTimeLeft");

    //commentary time: manipulating scores IS possible with regular HLDS (+HL25) but we need orpheu
    //HOWEVER, we don't need to! since we're turning off win limit anyway we can make clients believe 
    //we're changing them
    g_iUsrMsgTeamScore = get_user_msgid("TeamScore");
    g_iUsrMsgTextMsg = get_user_msgid("TextMsg");
    g_iUsrMsgRoundTime = get_user_msgid("RoundTime");
    g_iUsrMsgSendAudio = get_user_msgid("SendAudio");

    bind_pcvar_num(create_cvar("amx_rs_enabled", "1", FCVAR_NONE, "Enables the plugin", true, 0.0, true, 1.0), g_bPluginEnabled);
    bind_pcvar_num(create_cvar("amx_rs_warmup_time", "120", FCVAR_NONE, "Determines how much time the server should wait for players before starting, 0 to disable warmup.", true, 0.0, true, 300.0), g_iWarmUpTime);
    bind_pcvar_num(create_cvar("amx_rs_ready_allow", "0", FCVAR_NONE, "Determines if players should be able to end the warm-up time by saying !ready.", true, 0.0, true, 1.0), g_bWamUpSkipable);
    bind_pcvar_num(create_cvar("amx_rs_ready_percent", "60", FCVAR_NONE, "Percentage of players that should be ready in order to skip the warm-up time.", true, 0.0, true, 100.0), g_iWarmUpSkipPercent);
    bind_pcvar_num(create_cvar("amx_rs_accel_min_players", "8", FCVAR_NONE, "Determines how many players must be connected to accelerate warm-up.", true, 2.0, true, 32.0), g_iWarmUpAccelMinPlayers);
    bind_pcvar_num(create_cvar("amx_rs_accel_to", "30", FCVAR_NONE, "Determines to where the warmup time should jump to if the minimum players are met, this will only apply if the remaining warm-up time is higher than this value", true, 0.0, true, 300.0), g_iWarmUpAccelTo);
    bind_pcvar_num(create_cvar("amx_rs_round_zero", "2", FCVAR_NONE, "Determines the type of round zero. A value of 0 disables round zero (game starts as is), a value of 1 makes it a full-buy round, a value of 2 makes it knife-only", true, 0.0, true, 2.0), g_iRoundZeroType);
    bind_pcvar_num(create_cvar("amx_rs_round_zero_winners", "0", FCVAR_NONE, "Determines the team on which the winners of the round zero be transferred to. A value of 0 makes it a vote, a value of 1 will transfer them to the Terrorist side, a value of 2 will transfer them to the CT side", true, 0.0, true, 2.0), g_iRoundZeroWinners);
    bind_pcvar_num(create_cvar("amx_rs_round_zero_winners_vote_time", "10", FCVAR_NONE, "If `amx_rs_round_zero_winners` is 0, how much seconds the winners will have to vote their desired team", true, 1.0, true, 60.0), g_iRoundZeroWinnersVoteTime);
    bind_pcvar_num(create_cvar("amx_rs_max_rounds", "24", FCVAR_NONE, "Determines the amount of rounds, an even value is recommended. For reference, 24 is the amount in Counter-Strike 2 and 30 is the value in GO", true, 1.0), g_iMaxRounds);
    bind_pcvar_num(create_cvar("amx_rs_overtime", "2", FCVAR_NONE, "Select how many overtimes are allowed in the match in case of ties, use 0 for infinite overtimes, -1 to disable overtimes", true, -1.0), g_iMaxOverTimes);
    bind_pcvar_num(create_cvar("amx_rs_overtime_extend_amount", "4", FCVAR_NONE, "In case of an overtime, how many rounds should the game be extended", true, 1.0), g_iOverTimeExtendAmount);
    bind_pcvar_num(create_cvar("amx_rs_overtime_overtime_money", "1", FCVAR_NONE, "Determines if overtime rounds should be full-buy", true, 0.0, true, 1.0), g_bOverTimeFullBuy);
    bind_pcvar_num(create_cvar("amx_rs_overtime_overtime_money_amount", "8000", FCVAR_NONE, "The amount of money players should receive in overtime should amx_rs_overtime_overtime_money is 1", true, 0.0, true, 16000.0), g_iOverTimeMoney);
    bind_pcvar_string(create_cvar("amx_rs_command_ex", "mapm_start_vote", FCVAR_NONE, "Custom command to execute when the match ends. You can use your mapchanger plugin to force a vote (For example, Galileo's `gal_startvote` or Mistrick's `mapm_start_vote`) and let players decide which map they want to play. Command must exist or else the server will be softlocked on match end. Leave blank to perform a normal map change"), g_szCommandToExecuteWhenGameOver, charsmax(g_szCommandToExecuteWhenGameOver));

    #if !defined _reapi_included
    g_cvarRoundRestartDelay = create_cvar("mp_round_restart_delay", "5.0", FCVAR_NONE, "Number of seconds to delay before restarting a round after a win.", true, 0.0);
    #else 
    g_cvarRoundRestartDelay = get_cvar_pointer("mp_round_restart_delay");
    #endif

    bind_pcvar_float(g_cvarRoundRestartDelay, g_fTimeToRestart);

    g_iPluginFlags = plugin_flags();

    AutoExecConfig();
}

public OnConfigsExecuted()
{
    server_print("[DEBUG] %s::OnConfigsExecuted() - Called", __BINARY__);
    create_cvar("amx_rs_version", PLUGIN_VERSION, FCVAR_SERVER);

    if(g_bPluginEnabled)
    {
        #if !defined _reapi_included
        set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime());
        #else
        set_member_game(m_flRestartRoundTime, get_gametime()); // ditto
        #endif
        
        register_dictionary("timeleft.txt");
        register_dictionary("roundsys.txt");

        register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0");
        register_logevent("Event_JoinTeam", 3, "1=joined team");
        register_message(g_iUsrMsgTeamScore, "Event_TeamScore");
        register_message(g_iUsrMsgTextMsg, "Event_GameCommencing");
        register_event("SendAudio", "Event_RoundEnd", "a", "2=%!MRAD_terwin", "2=%!MRAD_ctwin", "2=%!MRAD_rounddraw");
        register_message(g_iUsrMsgSendAudio, "Message_RoundEnd");
        register_event("TeamInfo", "Event_TeamInfo", "a");

        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::OnConfigsExecuted() - Registering Ham Forwards", __BINARY__);
    
        RegisterHam(Ham_CS_RoundRespawn, "player", "Event_Player_RoundRespawn_Pre", false, true);
        RegisterHam(Ham_Killed, "player", "Event_Player_Killed_Post", true, true);

        for(new iCursor = 0; iCursor < sizeof g_szWeapons; iCursor++)
            RegisterHam(Ham_Item_AddToPlayer, g_szWeapons[iCursor], "Event_Item_AddToPlayer_Pre", false);
        
        RegisterHam(Ham_CS_Player_ResetMaxSpeed, "player", "Event_Player_ResetMaxSpeed_Post", true, true);

        g_hHudSyncWarmUpReady = CreateHudSyncObj();
        g_hHudSyncWarmUpNotReady = CreateHudSyncObj();

        g_cvarTimeLimit = get_cvar_pointer("mp_timelimit");
        g_cvarWinLimit = get_cvar_pointer("mp_winlimit");

        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::OnConfigsExecuted() - Storing original values", __BINARY__);
        g_iOriginalTimeLimit = get_pcvar_num(g_cvarTimeLimit);
        g_iOriginalWinLimit = get_pcvar_num(g_cvarWinLimit);

        if(g_iPluginFlags & AMX_FLAG_DEBUG)
        {
            server_print("[DEBUG] %s::OnConfigsExecuted() - g_iOriginalTimeLimit = %d", __BINARY__, g_iOriginalTimeLimit);
            server_print("[DEBUG] %s::OnConfigsExecuted() - g_iOriginalWinLimit = %d", __BINARY__, g_iOriginalWinLimit);
        }

        set_pcvar_num(g_cvarWinLimit, 0);
        RequestFrame("CheckPlayerStatus");
        g_hResetGameForward = CreateMultiForward("RoundSys_GameReset", ET_IGNORE, FP_CELL);
        g_hWarmUpClockTickForward = CreateMultiForward("RoundSys_WarmUpClockTick", ET_IGNORE, FP_CELL);
        g_hResetVariablesForward = CreateMultiForward("RoundSys_Reset", ET_IGNORE);
        g_hWarmUpStartForward = CreateMultiForward("RoundSys_WarmUpStart", ET_IGNORE);
        g_hMatchStartForward = CreateMultiForward("RoundSys_MatchStart", ET_IGNORE, FP_CELL, FP_CELL);
        g_hMatchEndedForward = CreateMultiForward("RoundSys_MatchEnded", ET_IGNORE, FP_CELL);

        g_hCurrentGameState = STATE_DORMANT;
    }
}

public plugin_natives()
{
    register_library("round_sys");
    register_native("RoundSys_GetTerrorVictories", "Native_GetTerrorVictories");
    register_native("RoundSys_GetCTVictories", "Native_GetCTVictories");
    register_native("RoundSys_GetGameState", "Native_GetGameState");
    register_native("RoundSys_IsOverTime", "Native_IsOverTime");
}

public Event_JoinTeam()
{
    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_JoinTeam() - Called. Current state is %d", __BINARY__, g_hCurrentGameState);
    if(g_hCurrentGameState == STATE_INACTIVE)
        return;
        
    else if(g_hCurrentGameState == STATE_WARMUP)
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::Event_JoinTeam() - On Warm-Up", __BINARY__);
        static szLogUser[80], szName[32];
        read_logargv(0, szLogUser, charsmax(szLogUser));
        parse_loguser(szLogUser, szName, charsmax(szName));
        new iClient = get_user_index(szName);
        static szTeam[2];
        read_logargv(2, szTeam, 1);

        switch(szTeam[0])
        {
            case 'T', 'C':
            {
                if(!task_exists(TASK_RESPAWN_PLAYER + get_user_userid(iClient)))
                    RequestFrame("RespawnPlayer", TASK_RESPAWN_PLAYER + get_user_userid(iClient));
            }
        }

        new iTerrorCount = get_playersnum_ex(GetPlayers_MatchTeam | GetPlayers_ExcludeBots, "TERRORIST");
        new iCTCount = get_playersnum_ex(GetPlayers_MatchTeam | GetPlayers_ExcludeBots, "CT");

        if(g_iWarmUpAccelMinPlayers <= (iTerrorCount + iCTCount) && g_iWarmUpTimeLeft > g_iWarmUpAccelTo)
            g_iWarmUpTimeLeft = g_iWarmUpAccelTo;
    }
} 

public Event_Player_ResetMaxSpeed_Post(iClient)
{
    if(g_bShouldFreezePlayers)
        set_pev(iClient, pev_maxspeed, 1.0);
}

public Native_GetTerrorVictories(iPlugin, iParams)
{
    // we can manage backwards compatiblity ths way
    return g_iRoundVictoriesTerror;
}

public Native_GetCTVictories(iPlugin, iParams)
{
    // we can manage backwards compatiblity ths way
    return g_iRoundVictoriesCT;
}

public Native_GetGameState(iPlugin, iParams)
{
    return g_hCurrentGameState;
}

public Native_IsOverTime(iPlugin, iParams)
{
    // we can manage backwards compatiblity ths way
    return g_bIsOverTime;
}

public Task_WarmUpClock()
{
    ExecuteForward(g_hWarmUpClockTickForward, _, g_iWarmUpTimeLeft);
    if(g_iWarmUpTimeLeft > 0)
    {
        if(g_iWarmUpTimeLeft < 10)
        {
            set_hudmessage();
            ShowSyncHudMsg(0, g_hHudSyncWarmUpReady, "");
            set_hudmessage();
            ShowSyncHudMsg(0, g_hHudSyncWarmUpNotReady, "");
        }

        CheckWamUpReadiness();
        client_print(0, print_center, "%L", LANG_PLAYER, "STATE_WARMUP", g_iWarmUpTimeLeft--);

        #if !defined _reapi_included
        set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + 9999999); // this prevents the round from resetting
        set_gamerules_float("CHalfLifeMultiplay", "m_fRoundCount", get_gametime()); // this allows infinite buytime
        set_gamerules_int("CHalfLifeMultiplay", "m_iRoundTimeSecs", 9999999); // this allow infinite round time
        #else
        set_member_game(m_flRestartRoundTime, get_gametime() + 9999999); // ditto
        set_member_game(m_fRoundStartTime, get_gametime()); // ditto
        set_member_game(m_iRoundTimeSecs, 9999999); // ditto
        #endif

        if(g_iUsrMsgRoundTime != INVALID_HANDLE)
        {
            emessage_begin(MSG_ALL, g_iUsrMsgRoundTime);
            ewrite_short(g_iWarmUpTimeLeft);
            emessage_end();
        }

        //loop and respawn dead players, fixes a game bug where bots or players might get stuck in spectator
        for(new iClient = 1; iClient < MaxClients; iClient++)
        {
            if(!is_user_alive(iClient) && !task_exists(TASK_RESPAWN_PLAYER + get_user_userid(iClient)))
            {
                set_task(3.0, "RespawnPlayer", TASK_RESPAWN_PLAYER + get_user_userid(iClient));
                GiveMoney(iClient);
            }
        }

        set_task(1.0, "Task_WarmUpClock", TASK_WARMUP_CLOCK);
    }
    else 
    {
        new iNumTerror = get_playersnum_ex(GetPlayers_ExcludeBots | GetPlayers_MatchTeam, "TERRORIST");
        new iNumCT = get_playersnum_ex(GetPlayers_ExcludeBots | GetPlayers_MatchTeam, "CT");
        ExecuteForward(g_hMatchStartForward, _, iNumTerror, iNumCT);
        g_hCurrentGameState = STATE_STARTING;
        client_print(0, print_center, "%L", LANG_PLAYER, "STATE_WARMUP_ENDED");
        FreezePlayers();
        ResetGame();
    }
}

public plugin_end()
{
    DestroyForward(g_hResetGameForward);
    DestroyForward(g_hWarmUpClockTickForward);
    DestroyForward(g_hResetVariablesForward);
    DestroyForward(g_hWarmUpStartForward);
    DestroyForward(g_hMatchStartForward);
    DestroyForward(g_hMatchEndedForward);

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::plugin_end() - Setting original time limit value: %d", __BINARY__, g_iOriginalTimeLimit);

    if(g_cvarTimeLimit && g_iOriginalTimeLimit != -1)
        set_pcvar_num(g_cvarTimeLimit, g_iOriginalTimeLimit);

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::plugin_end() - Setting original win limit value: %d", __BINARY__, g_iOriginalWinLimit);

    if(g_cvarWinLimit && g_iOriginalWinLimit != -1)
        set_pcvar_num(g_cvarWinLimit, g_iOriginalWinLimit);

    g_hCurrentGameState = STATE_INACTIVE;
}

public Event_Item_AddToPlayer_Pre()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return HAM_IGNORED;

    if(g_hCurrentGameState == STATE_ONGOING && g_iCurrentRound == 0 && g_iRoundZeroType == WARMUP_KNIVESONLY)
        return HAM_SUPERCEDE;
    
    return HAM_IGNORED; 
}

public Command_RestartMatch()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_HANDLED;

    ResetVariables();
    ResetGame();
    return PLUGIN_HANDLED;
}

public Event_GameCommencing()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    if(g_hCurrentGameState != STATE_ENDED)
    {
        static szMsg[22]; 
        get_msg_arg_string(2, szMsg, charsmax(szMsg));

        if(equal(szMsg, GAME_COMMENCING_TEXT))
        {
            if(g_iPluginFlags & AMX_FLAG_DEBUG)
                server_print("[DEBUG] %s::Event_GameCommencing() -  Game tried to commence!", __BINARY__);
            
            return PLUGIN_HANDLED;
        }
    }

    return PLUGIN_CONTINUE;
}

public Event_Player_RoundRespawn_Pre(iClient)
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return HAM_IGNORED;

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_Player_RoundRespawn_Pre() - Called on %n", __BINARY__, iClient);

    if(g_hCurrentGameState == STATE_ENDED)
        return HAM_SUPERCEDE;

    if(g_hCurrentGameState == STATE_WARMUP) 
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::Event_Player_RoundRespawn_Pre() - Giving money to %n", __BINARY__, iClient);
        GiveMoney(iClient);

        if(is_user_alive(iClient))
            return HAM_SUPERCEDE;
    }
    else if(g_hCurrentGameState == STATE_ONGOING && g_iCurrentRound == 0)
    {
        if(g_iRoundZeroType == WARMUP_FULLBUY)
            GiveMoney(iClient);
        else if(g_iRoundZeroType == WARMUP_KNIVESONLY)
            set_task(0.3, "PlayerStripToKnife", TASK_KNIFE_PLAYER + get_user_userid(iClient));
    }
    else if(g_bIsOverTime && g_bOverTimeFullBuy)
        GiveMoney(iClient, g_iOverTimeMoney);

    return HAM_IGNORED;
}

public Event_Player_Killed_Post(iClient)
{
    if(g_hCurrentGameState == STATE_WARMUP && !task_exists(TASK_RESPAWN_PLAYER + get_user_userid(iClient)))
        set_task(3.0, "RespawnPlayer", TASK_RESPAWN_PLAYER + get_user_userid(iClient));
}

public RespawnPlayer(iTaskId)
{
    new iClient = find_player_ex(FindPlayer_MatchUserId, iTaskId - TASK_RESPAWN_PLAYER);

    if(g_iPluginFlags & AMX_FLAG_DEBUG && iClient)
        server_print("[DEBUG] %s::RespawnPlayer() - Called on %n", __BINARY__, iClient);

    if(g_hCurrentGameState != STATE_WARMUP)
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG && iClient)
            server_print("[DEBUG] %s::RespawnPlayer() - Not on warmup. Returning.", __BINARY__);
        return;
    }
    
    if(is_user_connected(iClient) && (cs_get_user_team(iClient) ==  CS_TEAM_CT || cs_get_user_team(iClient) ==  CS_TEAM_T))
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG && iClient)
            server_print("[DEBUG] %s::RespawnPlayer() - Attempting to call Ham_CS_RoundRespawn on %n", __BINARY__, iClient);
        ExecuteHamB(Ham_CS_RoundRespawn, iClient);
    }
}

public PlayerStripToKnife(iTaskId)
{
    new iClient = find_player_ex(FindPlayer_MatchUserId, iTaskId - TASK_KNIFE_PLAYER);

    if(is_user_alive(iClient))
    {
        strip_user_weapons(iClient);
        give_item(iClient, "weapon_knife");
    }
}

public CS_OnBuy(iClient, iWeapon)
{
    if(g_hCurrentGameState == STATE_ONGOING && g_iCurrentRound == 0 && g_iRoundZeroType == WARMUP_KNIVESONLY)
    {
        client_print(iClient, print_center, "%L", LANG_PLAYER, "KNIVESONLY_CANNOT_BUY");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}  

public Command_SayTimeLeft(iClient)
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    client_print(iClient, print_chat, "%L: Best of %d", LANG_PLAYER, "TIME_LEFT", g_iMaxRounds);
    //hack, if we override the command the message won't be displayed so we add a fake one
    new szName[MAX_NAME_LENGTH], szNext[192];
    read_args(szNext, charsmax(szNext));
    remove_quotes(szNext);
    get_user_name(iClient, szName, charsmax(szName));
    new szFormattedMessage[1024];
    formatex(szFormattedMessage, charsmax(szFormattedMessage), "^2%s :  %s ^n", szName, szNext);
    message_begin(MSG_ALL, get_user_msgid("SayText"));
    write_byte(iClient);
    write_string(szFormattedMessage);
    message_end();
    return PLUGIN_HANDLED;
}

public Command_SayReady(iClient)
{
    if(g_hCurrentGameState == STATE_WARMUP && g_bWamUpSkipable)
    {
        g_bPlayerReady[iClient] = !g_bPlayerReady[iClient];
        CheckWamUpReadiness();
    }

    return PLUGIN_CONTINUE;
}

CheckWamUpReadiness()
{
    new iPlayerCount = get_playersnum_ex(GetPlayers_ExcludeBots | GetPlayers_MatchTeam, "CT") + get_playersnum_ex(GetPlayers_ExcludeBots | GetPlayers_MatchTeam, "TERRORIST");
    
    if(iPlayerCount == 0)
        return;

    new iReadyCount = 0;

    new szHudBufferTextReady[256];
    new szHudBufferTextNotReady[256];

    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient) && !is_user_bot(iClient) && (cs_get_user_team(iClient) == CS_TEAM_CT || cs_get_user_team(iClient) == CS_TEAM_T))
        {
            new szName[MAX_NAME_LENGTH];
            get_user_name(iClient, szName, charsmax(szName));
            if(g_bPlayerReady[iClient])
            {
                formatex(szHudBufferTextReady, charsmax(szHudBufferTextReady), "%s^n%s", szHudBufferTextReady, szName);
                formatex(szHudBufferTextNotReady, charsmax(szHudBufferTextNotReady), "%s^n", szHudBufferTextNotReady);
                iReadyCount++;
            }
            else
            {
                formatex(szHudBufferTextReady, charsmax(szHudBufferTextReady), "%s^n", szHudBufferTextReady);
                formatex(szHudBufferTextNotReady, charsmax(szHudBufferTextNotReady), "%s^n%s", szHudBufferTextNotReady, szName);
            }
        }
    }

    if(g_bWamUpSkipable)
    {
        set_hudmessage(56, 155, 46, 0.025, 0.175, 0, 0.0, 2.0, 0.0, 0.0, -1, 255, {56, 155, 46, 0});
        ShowSyncHudMsg(0, g_hHudSyncWarmUpReady, "%L^n^n%s^n^n%L", LANG_PLAYER, "STATE_WARMUP_READY_PLAYERS", szHudBufferTextReady, LANG_PLAYER, "STATE_WARMUP_PERCENT", g_iWarmUpSkipPercent);

        set_hudmessage(150, 150, 150, 0.025, 0.175, 0, 0.0, 2.0, 0.0, 0.0, -1, 255, {56, 155, 46, 0});
        ShowSyncHudMsg(0, g_hHudSyncWarmUpNotReady, "^n^n%s", szHudBufferTextNotReady);
    }

    if(float(iReadyCount) >= (float(iPlayerCount) * (float(g_iWarmUpSkipPercent) / 100.0)))
        g_iWarmUpTimeLeft = 1;
}

public plugin_precache()
{
    new szFile[PLATFORM_MAX_PATH];
    formatex(szFile, charsmax(szFile), "sound/%s", MATCHPOINT_SOUND);
    precache_generic(szFile);
}

public Event_RoundStart()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_RoundStart() - Called", __BINARY__);

    for(new iClient = 1; iClient <= MaxClients; iClient++)
        g_bMoneyGivenThisRound[iClient] = false;
    
    if(g_hCurrentGameState == STATE_STARTING)
        g_hCurrentGameState = STATE_ONGOING;
    
    if(g_hCurrentGameState != STATE_ONGOING)
        return PLUGIN_HANDLED;

    #if !defined _reapi_included
    set_gamerules_int("CHalfLifeMultiplay", "m_bFirstConnected", 1);
    #else
    set_member_game(m_bGameStarted, true);
    #endif

    g_iCurrentRound++;

    UnfreezePlayers();
    SetPluginScores();

    if(g_bIsFirstRoundOfSecondHalf || g_iCurrentRound == 1)
    {
        //restore scores
        RequestFrame("RestoreSingleUserData", 1);
        g_bIsFirstRoundOfSecondHalf = false;
    }

    RequestFrame("CheckMatchPointStatus");

    return PLUGIN_CONTINUE;
}

GiveMoney(iClient, iMoney = MAX_MONEY)
{
    if(is_user_connected(iClient) && !g_bMoneyGivenThisRound[iClient] && (!g_bIsOverTime || (g_bIsOverTime && g_bIsOverTimeFirstRound)))
    {
        g_bMoneyGivenThisRound[iClient] = true;
        
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::CheckMatchPointStatus() - Giving $%d to %n", __BINARY__, iMoney, iClient);
        cs_set_user_money(iClient, iMoney, false);
    }
}

public RestoreSingleUserData(iClient)
{
    if(g_hCurrentGameState != STATE_ENDED && is_user_connected(iClient) && is_user_alive(iClient))
    {
        ExecuteHam(Ham_AddPoints, iClient, g_iPlayerScoreBuffer[iClient][0], true);
        #if defined _reapi_included
        set_member(iClient, m_iDeaths, g_iPlayerScoreBuffer[iClient][1]);
        #else
        set_ent_data(iClient, "CBasePlayer", "m_iDeaths", g_iPlayerScoreBuffer[iClient][1]);
        #endif

        message_begin(MSG_ALL, get_user_msgid("ScoreInfo"));
        write_byte(iClient);
        write_short(g_iPlayerScoreBuffer[iClient][0]);
        write_short(g_iPlayerScoreBuffer[iClient][1]);
        write_short(0);

        //this part restores the player's model
        new bool:bModelFound = false;
        new szPlayerModelBuffer[MAX_NAME_LENGTH];
        cs_get_user_model(iClient, szPlayerModelBuffer[iClient], charsmax(szPlayerModelBuffer));
        switch(cs_get_user_team(iClient))
        {
            case CS_TEAM_T: 
            {
                write_short(1);

                for(new iCursor = 0; iCursor < sizeof g_szTerrorModels; iCursor++)
                {
                    if(equali(g_szTerrorModels[iCursor], szPlayerModelBuffer[iClient]))
                        bModelFound = true;
                }

                if(!bModelFound)
                {
                    new bool:bSubModelFound = false;
                    for(new iCursor = 0; iCursor < sizeof g_szCTModels; iCursor++)
                    {
                        if(equali(g_szCTModels[iCursor], szPlayerModelBuffer[iClient]))
                        {
                            cs_set_user_model(iClient, g_szTerrorModels[iCursor]);
                            bSubModelFound = true;
                        }
                    }

                    if(!bSubModelFound)
                        cs_set_user_model(iClient, "terror");
                }
            }
            case CS_TEAM_CT: 
            {
                write_short(2);

                for(new iCursor = 0; iCursor < sizeof g_szCTModels; iCursor++)
                {
                    if(equali(g_szCTModels[iCursor], szPlayerModelBuffer[iClient]))
                        bModelFound = true;
                }
                
                if(!bModelFound)
                {
                    new bool:bSubModelFound = false;
                    for(new iCursor = 0; iCursor < sizeof g_szTerrorModels; iCursor++)
                    {
                        if(equali(g_szTerrorModels[iCursor], szPlayerModelBuffer[iClient]))
                        {
                            cs_set_user_model(iClient, g_szCTModels[iCursor]);
                            bSubModelFound = true;
                        }
                    }

                    if(!bSubModelFound)
                        cs_set_user_model(iClient, "urban");
                }
            }
            case CS_TEAM_SPECTATOR: //fallback in case of error
                write_short(3);
            default:
                write_short(0);
        }
        
        message_end();

        if(iClient+1 <= MaxClients)
            RequestFrame("RestoreSingleUserData", iClient+1);
    }
    else if(iClient+1 <= MaxClients)
        RequestFrame("RestoreSingleUserData", iClient+1);
}

public CheckMatchPointStatus()
{
    if(g_hCurrentGameState != STATE_ONGOING)
        return;

    // 1-based system: 
    //   Round #1 is the first round, #2 is the second, etc.
    // g_iMaxRounds is the total (initial) rounds in the match.

    // How many rounds in the first half (e.g., if g_iMaxRounds=30, then 15)
    new iHalfGameRounds = g_iMaxRounds / 2; 

    // How many rounds remain AFTER this current round finishes?
    // If we are on round #1, iRoundsLeft = g_iCurrentMaxRounds - 1.
    new iRoundsLeft = g_iCurrentMaxRounds - g_iCurrentRound;

    // ----------------------------------------------------
    // 1) FINAL ROUND:
    //    If we are currently on round #g_iCurrentMaxRounds,
    //    always display “FINAL ROUND” first.
    //    This avoids showing "MATCH POINT" on the last round
    //    even if a tie is possible.
    // ----------------------------------------------------
    if (g_iCurrentRound == g_iCurrentMaxRounds)
    {
        DisplayMessage("ROUND_FINAL");
        client_cmd(0, "spk %s", MATCHPOINT_SOUND);
        return;
    }

    // ----------------------------------------------------
    // 2) MATCH POINT:
    //    A team is on match point if winning THIS round
    //    makes that team unreachable.
    //    “Unreachable” means the other team can’t tie or surpass.
    //    Mathematically:
    //
    //       (TeamWins + 1) > (OtherTeamWins + iRoundsLeft)
    //
    //    We use “>” (strictly greater) to exclude a tie.
    // ----------------------------------------------------
    if (
        (g_iRoundVictoriesTerror+1 > g_iRoundVictoriesCT + iRoundsLeft) ||
        (g_iRoundVictoriesCT+1 > g_iRoundVictoriesTerror + iRoundsLeft)
    )
    {
        DisplayMessage("ROUND_MATCHPOINT", g_iCurrentRound);
        client_cmd(0, "spk %s", MATCHPOINT_SOUND);
        return;
    }

    // ----------------------------------------------------
    // 3) LAST ROUND OF FIRST HALF:
    //    In a 1-based system, the last round of the first half 
    //    is exactly round #iHalfGameRounds.
    //    e.g. if g_iCurrentMaxRounds=30, iHalfGameRounds=15, 
    //    then round #15 is the last one in the first half.
    // ----------------------------------------------------
    if (g_iCurrentRound == iHalfGameRounds && iHalfGameRounds != g_iCurrentMaxRounds)
    {
        DisplayMessage("ROUND_LAST_FIRST_HALF", g_iCurrentRound);
        client_cmd(0, "spk %s", MATCHPOINT_SOUND);
        return;
    }

    if(g_iCurrentRound == 0)
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::CheckMatchPointStatus() - g_iRoundZeroType is %d", __BINARY__, g_iRoundZeroType);
        if(g_iRoundZeroType == WARMUP_DISABLED)
        {
            DisplayMessage("ROUND_STANDARD", ++g_iCurrentRound);
            return;
        }

        DisplayMessage("ROUND_ZERO");
    }
    else 
        DisplayMessage("ROUND_STANDARD", g_iCurrentRound);
}

public Event_TeamInfo()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    new iClient = read_data(1);
    static szTeam[MAX_NAME_LENGTH];

    read_data(2, szTeam, charsmax(szTeam));

    if(!is_user_connected(iClient))
        return PLUGIN_CONTINUE; 

    switch(szTeam[0])
    {
        case 'C', 'T':
        {
            RequestFrame("CheckPlayerStatus");
        }
    }

    return PLUGIN_CONTINUE;
}

public client_remove(iClient)
{
    CheckPlayerStatus();
}

public client_disconnected(iClient)
{
    g_bPlayerReady[iClient] = false;
    CheckPlayerStatus();
}

public Message_RoundEnd()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    static szMsg[22]; 
    get_msg_arg_string(2, szMsg, charsmax(szMsg));
    if(g_hCurrentGameState != STATE_ONGOING && (equal(szMsg, "%!MRAD_terwin") || equal(szMsg, "%!MRAD_ctwin") || equal(szMsg, "%!MRAD_rounddraw")))
        return PLUGIN_HANDLED;
    return PLUGIN_CONTINUE;
}

public Event_RoundEnd()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_RoundEnd() - Called", __BINARY__);

    new szWinningTeam[9];
    read_data(2, szWinningTeam, charsmax(szWinningTeam));

    if(g_hCurrentGameState != STATE_ONGOING)
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::Event_RoundEnd() - Game state is not ongoing, handling.", __BINARY__);
        return PLUGIN_HANDLED;
    }

    new CsTeams:iWinner;

    if (szWinningTeam[7] == 't')
        iWinner = CS_TEAM_T;
    else if (szWinningTeam[7] == 'c')
        iWinner = CS_TEAM_CT;

    RequestFrame("Event_RoundEnd_Post", _:iWinner);

    return PLUGIN_CONTINUE;
}

public Event_RoundEnd_Post(CsTeams:iWinningTeam)
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return;

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_RoundEnd_Post() - Calling on %d", __BINARY__, iWinningTeam);

    #if !defined _reapi_included
    if(g_iPluginFlags & AMX_FLAG_DEBUG)
    {
        server_print("[DEBUG] %s::Event_RoundEnd_Post() - Value of m_fTeamCount is %f", __BINARY__, get_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount"));
        server_print("[DEBUG] %s::Event_RoundEnd_Post() - Setting it to %f", __BINARY__, get_gametime() + g_fTimeToRestart);
    }

    set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + g_fTimeToRestart);

    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::Event_RoundEnd_Post() - Value of m_fTeamCount is %f", __BINARY__, get_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount"));
    #endif

    if(g_iCurrentRound >= 1)
    {
        //do not count warmup rounds
        if (iWinningTeam == CS_TEAM_T)
            g_iRoundVictoriesTerror++;
        else if (iWinningTeam == CS_TEAM_CT)
            g_iRoundVictoriesCT++;
    }
    else
    {
        if(g_iPluginFlags & AMX_FLAG_DEBUG)
            server_print("[DEBUG] %s::Event_RoundEnd_Post() - Value of g_iRoundZeroWinners is %d", __BINARY__, g_iRoundZeroWinners);
        if(g_iRoundZeroWinners == WARMUP_WINNER_VOTE)
        {
            #if !defined _reapi_included
            set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + g_iRoundZeroWinnersVoteTime + g_fTimeToRestart);
            #else
            set_member_game(m_flRestartRoundTime, get_gametime() + g_iRoundZeroWinnersVoteTime + g_fTimeToRestart);
            #endif
            FreezePlayers();
            if(get_playersnum_ex(GetPlayers_MatchTeam | GetPlayers_ExcludeBots, iWinningTeam == CS_TEAM_T ? "TERRORIST" : "CT") == 0)
            {
                //if bots won, they will always choose terrorists, skip the vote
                g_iVoteTerrorist = 999;
                g_iVoteCT = 0;
                DetermineVoteWinner(TASK_VOTEROUNDZERO+_:iWinningTeam);
            }
            else
                GenerateVoteForRoundZeroWinners(iWinningTeam);
        }
        else
        {
            //if CT won, transfer them to T and vice versa
            if(iWinningTeam == (g_iRoundZeroWinners == WARMUP_WINNER_TERRORISTS ? CS_TEAM_CT : CS_TEAM_T))
                RequestFrame("StoreUserData", false);
            else
                ResetGame();
        }

        return;
    }   

    SetPluginScores();
    CheckGameStatus();
}

GenerateVoteForRoundZeroWinners(CsTeams:iWinningTeam)
{
    if(g_iPluginFlags & AMX_FLAG_DEBUG)
        server_print("[DEBUG] %s::GenerateVoteForRoundZeroWinners() - Called on %d", __BINARY__, iWinningTeam);

    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient) && cs_get_user_team(iClient) == iWinningTeam && !is_user_bot(iClient))
        {
            if(g_iPluginFlags & AMX_FLAG_DEBUG)
                server_print("[DEBUG] %s::GenerateVoteForRoundZeroWinners() - %N connected and from winning team", __BINARY__, iClient);

            new szTitle[128], szOption[32];
            formatex(szTitle, charsmax(szTitle), "%L", iClient, "VOTE_TITLE_SELECT_TEAM");
            new hMenu = menu_create(szTitle, "RoundZeroVoteHandle", true);

            // Add accept/reject options
            formatex(szOption, charsmax(szOption), "%L", iClient, "VOTE_TEAM_T");
            menu_additem(hMenu, szOption, "1");
            formatex(szOption, charsmax(szOption), "%L", iClient, "VOTE_TEAM_CT");
            menu_additem(hMenu, szOption, "2");
            formatex(szOption, charsmax(szOption), "%L", iClient, "VOTE_TEAM_DONT_CARE");
            menu_additem(hMenu, szOption, "3");
            
            // Display menu
            menu_display(iClient, hMenu, _, g_iRoundZeroWinnersVoteTime);
        }
    }
    set_task(g_iRoundZeroWinnersVoteTime*1.0, "DetermineVoteWinner", TASK_VOTEROUNDZERO+_:iWinningTeam);
}

public RoundZeroVoteHandle(iClient, hMenu, iItem)
{
    new szInfo[8];
    menu_item_getinfo(hMenu, iItem, _, szInfo, charsmax(szInfo), _, _, _);
    
    new iOption = str_to_num(szInfo);
    switch (iOption) 
    {
        case 1: 
        {
            g_iVoteTerrorist++;
        }
        case 2: 
        {
            g_iVoteCT++;
        }
    }
    
    return PLUGIN_HANDLED;
}

public DetermineVoteWinner(iTaskId)
{
    new CsTeams:iWinningTeam = CsTeams:iTaskId-CsTeams:TASK_VOTEROUNDZERO;

    // to do: why was this not working?
    // for(new iClient = 1; iClient <= MaxClients; iClient++)
    // {
    //     if(is_user_connected(iClient) && cs_get_user_team(iClient) == iWinningTeam && !is_user_bot(iClient))
    //     {
    //         new hOldMenu;
    //         new hMenu;
    //         if(player_menu_info(iClient, hOldMenu, hMenu) && hMenu && menu_)
    //             menu_destroy(hMenu);
    //     }
    // }

    if((iWinningTeam == CS_TEAM_CT && g_iVoteCT < g_iVoteTerrorist) || (iWinningTeam == CS_TEAM_T && g_iVoteCT > g_iVoteTerrorist))
        RequestFrame("StoreUserData", false);
    else 
        ResetGame();
}

CheckGameStatus()
{
    if(g_hCurrentGameState == STATE_ONGOING)
    {   
        if(g_bIsOverTimeFirstRound)
            g_bIsOverTimeFirstRound = false;

        // Determine the halfway and winning round counts based on the format
        new iWinRounds = (g_iCurrentMaxRounds % 2 == 0) ? (g_iCurrentMaxRounds / 2) + 1 : floatround(g_iCurrentMaxRounds/2.0, floatround_ceil);
        new iHalfGameRounds = g_iMaxRounds / 2;

        if (g_iCurrentRound == iHalfGameRounds)
        {
            RequestFrame("PerformHalfTimeSwap");
            return;
        }

        // Check if a team has won the match
        if ( (g_iRoundVictoriesTerror >= iWinRounds) || // victory
            (g_iRoundVictoriesCT >= iWinRounds) || // victory
            (g_iRoundVictoriesCT == iHalfGameRounds && g_iRoundVictoriesTerror == iHalfGameRounds) || // tie
            (g_iCurrentMaxRounds == g_iCurrentRound)) // no more rounds, no matter what
        {
            if(g_iMaxOverTimes != -1 && (g_iMaxOverTimes == 0 || g_iOverTimes < g_iMaxOverTimes) && g_iRoundVictoriesCT == g_iRoundVictoriesTerror)
            {
                g_iOverTimes++;
                client_print(0, print_chat, "%L", LANG_PLAYER, "REACH_OVERTIME", g_iWarmUpTimeLeft--);
                g_iCurrentMaxRounds +=  g_iOverTimeExtendAmount;
                RequestFrame("PerformHalfTimeSwap");
                g_bIsOverTimeFirstRound = true;
                g_bIsOverTime = true;
                return;
            }
            else
                RequestFrame("GameEnded");
            return;
        }
    }
}

public PerformHalfTimeSwap()
{
    RequestFrame("StoreUserData", true);
    g_bIsFirstRoundOfSecondHalf = true;
}

public StoreUserData(bool:bStoreScores)
{
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient))
        {
            if(bStoreScores)
            {
                g_iPlayerScoreBuffer[iClient][0] = get_user_frags(iClient);
                //cs_get_user_deaths(iClient) was returning the WRONG value in reGameDLL, change back if needed
                g_iPlayerScoreBuffer[iClient][1] = get_user_deaths(iClient);
            }
        }
    }

    RequestFrame("SwapTeamScores");
}

public SwapTeamScores()
{
    g_iRoundVictoriesTerror += g_iRoundVictoriesCT;
    g_iRoundVictoriesCT = g_iRoundVictoriesTerror - g_iRoundVictoriesCT;
    g_iRoundVictoriesTerror -= g_iRoundVictoriesCT; 

    RequestFrame("SetPluginScores");
    RequestFrame("PerformTeamSwap");
}

public PerformTeamSwap()
{
    ResetGame(true);
    
    FreezePlayers();

    //check if it's a coop game
    new szCvarBotJoinTeam[5], szCvarHumanJoinTeam[5];
    get_cvar_string("bot_join_team", szCvarBotJoinTeam, charsmax(szCvarBotJoinTeam));
    get_cvar_string("humans_join_team", szCvarHumanJoinTeam, charsmax(szCvarHumanJoinTeam));

    if(equali(szCvarBotJoinTeam, "t"))
        set_cvar_string("bot_join_team", "ct");
    else if(equali(szCvarBotJoinTeam, "ct"))
        set_cvar_string("bot_join_team", "t");

    if(equali(szCvarHumanJoinTeam, "t"))
        set_cvar_string("humans_join_team", "ct");
    else if(equali(szCvarHumanJoinTeam, "ct"))
        set_cvar_string("humans_join_team", "t");

    RequestFrame("PerformSingleTeamSwap", 1);
}

public PerformSingleTeamSwap(iClient)
{
    if(is_user_connected(iClient))
    {
        switch(cs_get_user_team(iClient))
        {
            case CS_TEAM_T: cs_set_user_team(iClient, CS_TEAM_CT, CS_NORESET, true);
            case CS_TEAM_CT: cs_set_user_team(iClient, CS_TEAM_T, CS_NORESET, true);
        }

        if(iClient+1 <= MaxClients)
            RequestFrame("PerformSingleTeamSwap", ++iClient);
    }
    else if(iClient+1 <= MaxClients)
        RequestFrame("PerformSingleTeamSwap", ++iClient);
}

public GameEnded()
{
    //game ended, no more game allowed
    //if we got a command set up execute it
    //otherwise end the map with intermission
    g_hCurrentGameState = STATE_ENDED;

    new CsTeams:iWinningTeam = CS_TEAM_UNASSIGNED;

    if(g_iRoundVictoriesTerror > g_iRoundVictoriesCT)
        iWinningTeam = CS_TEAM_T;
    else if(g_iRoundVictoriesTerror < g_iRoundVictoriesCT) //not else because would override a draw
        iWinningTeam = CS_TEAM_CT;

    ExecuteForward(g_hMatchEndedForward, _, iWinningTeam); 

    #if !defined _reapi_included
    set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + 9999.9);
    #else
    set_member_game(m_flRestartRoundTime, get_gametime() + 9999.9);
    #endif

    FreezePlayers();

    if(strlen(g_szCommandToExecuteWhenGameOver) > 0)
        server_cmd(g_szCommandToExecuteWhenGameOver);
    else
    {
        message_begin(MSG_ALL, SVC_INTERMISSION);
        message_end();
        set_task(get_cvar_float("mp_chattime"), "ChangeMapAfterIntermission");
    }
}

public ChangeMapAfterIntermission()
{
    new szNextMap[64];
    
    // 1. Try to change to map defined in amx_nextmap cvar
    get_cvar_string("amx_nextmap", szNextMap, charsmax(szNextMap));
    if(strlen(szNextMap) > 0 && is_map_valid(szNextMap))
    {
        server_cmd("changelevel %s", szNextMap);
        return;
    }
    
    // 2. Look for current map in mapcycle and get the next one
    new szMapcycleFile[128];
    get_cvar_string("mapcyclefile", szMapcycleFile, charsmax(szMapcycleFile));
    if(strlen(szMapcycleFile) > 0)
    {
        new szCurrentMap[64];
        get_mapname(szCurrentMap, charsmax(szCurrentMap));
        
        new iFile = fopen(szMapcycleFile, "rt");
        if(iFile)
        {
            new szLine[64], bool:bFoundCurrentMap = false;
            new szMapList[128][64], iMapCount = 0;
            
            while(!feof(iFile) && iMapCount < 128)
            {
                fgets(iFile, szLine, charsmax(szLine));
                trim(szLine);
                
                if(strlen(szLine) == 0 || szLine[0] == ';' || szLine[0] == '/' && szLine[1] == '/')
                    continue;
                
                if(is_map_valid(szLine))
                {
                    copy(szMapList[iMapCount], 63, szLine);
                    iMapCount++;
                    
                    // Found current map, next map in cycle will be used
                    if(equali(szLine, szCurrentMap))
                        bFoundCurrentMap = true;
                    else if(bFoundCurrentMap)
                    {
                        // This is the next map after current map
                        fclose(iFile);
                        server_cmd("changelevel %s", szLine);
                        return;
                    }
                }
            }
            
            // 3. If we couldn't find next map in cycle or current map wasn't in cycle,
            // change to a random map from the mapcycle
            if(iMapCount > 0)
            {
                new iRandomIndex = random_num(0, iMapCount - 1);
                server_cmd("changelevel %s", szMapList[iRandomIndex]);
                fclose(iFile);
                return;
            }
            
            fclose(iFile);
        }
    }
    
    // 4. Last resort: change to de_dust2
    server_cmd("changelevel de_dust2");
}

public SetPluginScores()
{
    message_begin(MSG_ALL, g_iUsrMsgTeamScore);
    write_string("TERRORIST");
    write_short(g_iRoundVictoriesTerror);
    message_end();

    message_begin(MSG_ALL, g_iUsrMsgTeamScore);
    write_string("CT");
    write_short(g_iRoundVictoriesCT);
    message_end();
}

public Event_TeamScore()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return PLUGIN_CONTINUE;

    SetPluginScores();

    return PLUGIN_HANDLED;
}

ResetGame(bool:bSoft = false)
{
    ExecuteForward(g_hResetGameForward, _, bSoft);

    if(!bSoft)
    {
        g_iRoundVictoriesTerror = 0;
        g_iRoundVictoriesCT = 0;
    }
    
    #if !defined _reapi_included
    set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + g_fTimeToRestart);
    set_gamerules_int("CGameRules", "m_bFreezePeriod", 0);
    set_gamerules_int("CHalfLifeMultiplay", "m_bCompleteReset", 1);
    #else
    set_member_game(m_flRestartRoundTime, get_gametime() + g_fTimeToRestart);
    set_member_game(m_bFreezePeriod, false);
    set_member_game(m_bCompleteReset, true);
    #endif

    //this part tricks third party plugins into believing the game restarted, so they can flush the stored data
    //fixes the following issues: 
    // - Bot Control by EFFEX returning a player who took a bot to their team before the swap
    // And probably more
    emessage_begin(MSG_ALL, g_iUsrMsgTextMsg, _, _);
    ewrite_byte(print_center);
    ewrite_string(GAME_RESTART_TEXT);
    emessage_end();
    message_begin(MSG_ALL, g_iUsrMsgTextMsg, _, _);
    write_byte(print_center);
    write_string("");
    message_end();
}

public CheckPlayerStatus()
{
    if(g_hCurrentGameState == STATE_INACTIVE)
        return;

    if(g_hCurrentGameState == STATE_ENDED)
        return;

    new iTerrorCount = GetTerrors();
    new iCTCount = GetCTs();

    if(g_hCurrentGameState == STATE_DORMANT && (iTerrorCount + iCTCount) > 0)
    {
        if(g_iWarmUpTime == 0)
            g_hCurrentGameState = STATE_ONGOING;
        else 
        {
            g_hCurrentGameState = STATE_WARMUP;
            ExecuteForward(g_hWarmUpStartForward);
    
            #if !defined _reapi_included
            set_gamerules_float("CHalfLifeMultiplay", "m_fTeamCount", get_gametime() + 5);
            set_gamerules_int("CGameRules", "m_bFreezePeriod", 0);
            set_gamerules_int("CHalfLifeMultiplay", "m_bCompleteReset", 1);
            set_gamerules_int("CHalfLifeMultiplay", "m_bFirstConnected", 1);
            #else
            set_member_game(m_flRestartRoundTime, get_gametime() + 5);
            set_member_game(m_bFreezePeriod, false);
            set_member_game(m_bCompleteReset, true);
            set_member_game(m_bGameStarted, true);
            #endif

            g_iCurrentMaxRounds = g_iMaxRounds;

            for(new iClient = 1; iClient <= MaxClients; iClient++)
            {
                if(is_user_connected(iClient) && (cs_get_user_team(iClient) ==  CS_TEAM_CT || cs_get_user_team(iClient) ==  CS_TEAM_T))
                    ExecuteHamB(Ham_CS_RoundRespawn, iClient);
            }

            g_iWarmUpTimeLeft = g_iWarmUpTime;
            set_task(1.0, "Task_WarmUpClock", TASK_WARMUP_CLOCK);
            if(g_cvarTimeLimit)
                set_pcvar_num(g_cvarTimeLimit, 0);
        }   
    }
    else 
    {
        #if !defined _reapi_included
        set_gamerules_int("CHalfLifeMultiplay", "m_bFirstConnected", 1);
        //set_gamerules_int("CHalfLifeMultiplay", "m_iNumSpawnableTerrorist", iTerrorCount);
        //set_gamerules_int("CHalfLifeMultiplay", "m_iNumSpawnableCT", iCTCount);
        #else
        set_member_game(m_bGameStarted, true);
        //set_member_game(m_iNumSpawnableTerrorist, iTerrorCount);
        //set_member_game(m_iNumSpawnableCT, iCTCount);
        #endif
        if((iTerrorCount + iCTCount) == 0)
        {
            g_hCurrentGameState = STATE_DORMANT;

            ResetVariables();
            ResetGame();

            if(g_cvarTimeLimit)
                set_pcvar_num(g_cvarTimeLimit, g_iOriginalTimeLimit);
        }
        else if((iTerrorCount + iCTCount) > 0 && g_cvarTimeLimit)
            set_pcvar_num(g_cvarTimeLimit, 0);
    }
}

DisplayMessage(const szMessage[], iParam = -1)
{
    g_iBufferParam = iParam;
    copy(g_szBufferText, charsmax(g_szBufferText), szMessage);
    set_task(1.0, "DelayedDisplayMessage");
} 

public DelayedDisplayMessage()
{
    set_dhudmessage(255, 255, 255, -1.0, 0.25, 2, 0.0, 2.0, 0.01, 1.0);
    if(g_bIsOverTime)
    {
        if(g_iBufferParam >= 0)
            show_dhudmessage(0, "%L^n%L", LANG_PLAYER, g_szBufferText, g_iBufferParam, LANG_PLAYER, "ROUND_OVERTIME");
        else
            show_dhudmessage(0, "%L^n%L", LANG_PLAYER, g_szBufferText, LANG_PLAYER, "ROUND_OVERTIME");
    }
    else 
    {
        if(g_iBufferParam >= 0)
            show_dhudmessage(0, "%L", LANG_PLAYER, g_szBufferText, g_iBufferParam);
        else
            show_dhudmessage(0, "%L", LANG_PLAYER, g_szBufferText);
    }
}

ResetVariables()
{
    g_iRoundVictoriesTerror = 0;
    g_iRoundVictoriesCT = 0;
    g_iVoteTerrorist = 0;
    g_iVoteCT = 0;
    g_iCurrentRound = -1;
    g_bIsOverTime = false;
    g_bIsOverTimeFirstRound = false;
    g_bShouldFreezePlayers = false;

    if(task_exists(TASK_VOTEROUNDZERO+_:CS_TEAM_CT))
        remove_task(TASK_VOTEROUNDZERO+_:CS_TEAM_CT);
    else if(task_exists(TASK_VOTEROUNDZERO+_:CS_TEAM_T))
        remove_task(TASK_VOTEROUNDZERO+_:CS_TEAM_T);

    if(task_exists(TASK_WARMUP_CLOCK))
        remove_task(TASK_WARMUP_CLOCK);

    ExecuteForward(g_hResetVariablesForward); 
}

FreezePlayers()
{
    g_bShouldFreezePlayers = true;

    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient))
            set_pev(iClient, pev_maxspeed, 1.0);
    }
}

UnfreezePlayers()
{
    g_bShouldFreezePlayers = false;
}

//get_playersnum/_ex may provide the wrong value due a bug, I'm unable to replicate it consistently, this is the best next thing
GetCTs()
{
    new iRetVal = 0;
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient) && cs_get_user_team(iClient) == CS_TEAM_CT)
            iRetVal++;
    }
    return iRetVal;
}

GetTerrors()
{
    new iRetVal = 0;
    for(new iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(is_user_connected(iClient) && cs_get_user_team(iClient) == CS_TEAM_T)
            iRetVal++;
    }
    return iRetVal;
}