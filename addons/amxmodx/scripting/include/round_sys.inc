#if defined _round_sys_included
  #endinput
#endif
#define _round_sys_included
#include <cstrike_const>

enum aGameState
{
    STATE_DORMANT = 0, //no players are online
    STATE_WARMUP, //warmup process
    STATE_STARTING, //warmup ended, next round starts the game
    STATE_ONGOING, //current active game
    STATE_ENDED, //the end, no more game allowed
}

/**
 * Gets Terrorist victories since match start
 *
 * @return int Terrorist victories since match start
 */
native RoundSys_GetTerrorVictories();

/**
 * Gets Counter-Terrorist victories since match start
 *
 * @return int Counter-Terrorist victories since match start
 */
native RoundSys_GetCTVictories();

/**
 * Gets the current game state
 *
 * @return aGameState Current game state
 */
native aGameState:RoundSys_GetGameState();

/**
 * Gets if the current game is overtime
 *
 * @return bool If the current game is overtime
 */
native RoundSys_IsOverTime();

/**
 * Called when the plugin does a game reset
 *
 * @param bSoftReset    If true, player/team scores won't be reset, likely due to team switch
 *
 * @note               Ignores return value
 */
forward RoundSys_GameReset(bool:bSoftReset);

/**
 * Called when a second passes in warmup phase
 *
 * @param iTimeLeft    How long for the match to start, on infinite warmup this value is always 0
 *
 * @note               Ignores return value
 */
forward RoundSys_WarmUpClockTick(iTimeLeft);


forward RoundSys_Reset();

/**
 * Called when warmup starts
 *
 * @note               Ignores return value
 */
forward RoundSys_WarmUpStart();

/**
 * Called when warmup ends
 *
 * @note               Ignores return value
 */
forward RoundSys_MatchStart(iNumTerror, iNumCT);

/**
 * Called when the match ends
 *
 * @param iWinningTeam    The team that won the match (CsTeams enum)
 *
 * @note                 Ignores return value
 */
forward RoundSys_MatchEnded(CsTeams:iWinningTeam);