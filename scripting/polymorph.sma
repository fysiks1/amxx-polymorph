// #define DEBUG

/*
	Modes:
		0: Always stay on one mod unless changed manually with admin command.  (Map votes only)
		1: Play # maps then next mod will default to next in polymorph.ini (Map votes only)
		2: Play # maps then next mod will be chosen by vote. (Map and Mod votes)
		
	Changelog:
		0.6
			Added function to set the default nextmap to be used when nextmod is set.
			Added functionality to mod vote to choose options randomly and quantity can be limited with SELECTMODS (default 5) (requires re-compile)
			Added current next mod indicator in cmdSetNextmod() function (aka amx_nextmod).
			Drastically improved reading the .ini file (IMO).
			Added beta amx_votemod which just starts the default vote for mod (which then calls the map vote)
		0.7
			Added check to disallow end of map vote if vote is already in progress from amx_votemod.
			Added confirmation to the cmdSetNextMod() function (mod and map)
			Added chat time (using mp_chattime cvar) when map is changed due to amx_votemod.
			Fixed server crash when changing map due to amx_votemod.
		0.8
			Changed to using a folder for .ini and .cfg files.  /addons/amxmodx/configs/polymorph/ for readability
			Added dynamic natives to enable retreiving and executing local variables and functions.
			Removed gamename stuff because it can be done with a separate plugin with natives.
			Added cvars for thismod and nextmod (used for example in Polymorph: GameName)
			Added ML :(
		1.0
			Changed loading of MODs.  Mods are now loaded modularly.  One .ini file for each mod (in /polymorph).  No more polymorph.ini.  If MOD fails to load the whole plugin does not fail!
		1.0.1
			Added check for 0 mods loaded.  Set's plugin as failed.
		1.0.2
			Increased string length for variabls used for cvars in initModLoad() and loadMod() (now using STRLEN_DATA)
		1.0.3 (2010/04/18)
			Bug fix:  Nextmap is updated to reflect the nextmod's maps when there are no votes.
		1.1.0
			Removed cvar poly_mapspermod and moved setting to MOD file.
		1.1.1
			Updated error handling to be more accurate in initModLoad().
		1.1.2
			Fixed error when UpdatePluginFile() called with no mods loaded.

*/

#include <amxmodx>
#include <amxmisc>

// String Lengths
#define STRLEN_DATA 128	// data from file and 'etc.' data
#define STRLEN_PATH 128	// full file path
#define STRLEN_NAME 32	// plugin Name e.g. "GunGame Mod"
#define STRLEN_FILE 32	// single filename w/o path
#define STRLEN_MAP 32	// map name

// Limits
#define MODS_MAX 10		// Maximum number of mods.

// Number of main options in vote
#define SELECTMODS 5
#define SELECTMAPS 5

// Task IDs lol
#define TASK_ENDOFMAP 3141
#define TASK_FORCED_MAPCHANGE 314159

// ammount of time left (in seconds) to trigger end of map vote
#define TIMELEFT_TRIGGER 129

#if defined DEBUG
	new debug_voters = 0
#endif

new g_szModNames[MODS_MAX][STRLEN_NAME]	// Mod Names
new Array:g_aModMaps[MODS_MAX]			// Per-mod Map Names List
new Array:g_aModPlugins[MODS_MAX]		// Per-mod Plugin Names List
new Array:g_aCfgList					// Array to hold cvars for 'ThisMod'

new g_iMapNums[MODS_MAX]			// Number of maps for each mod
new g_szThisMod[STRLEN_NAME]		// Name of 'ThisMod'

new g_iThisMod = -1			// Index of 'ThisMod'
new g_iNextMod = 0			// Index of 'NextMod'
new g_iModCount = 0			// Number of MODs loaded

new g_iMapsPlayed			// Number of maps played on current MOD.
new g_iMapsPerMod[MODS_MAX]	// Number of maps played before a MOD change.

new bool:g_isLastMap = false			// Number of maps played on current mod.
new bool:g_selected = false

// Voting stuff
new g_voteNum
new g_nextName[SELECTMAPS]
new g_voteMapCount[SELECTMAPS + 2]
new g_nextModId[MODS_MAX]
new g_voteModCount[MODS_MAX + 2]

// Compatibility vars
new g_teamScore[2]
new g_coloredMenus

/* Cvar Pointers */
// My cvars
new g_pMode
new g_pExtendMod // bool; allow extending mod
new g_pExtendStep
new g_pExtendMax
new g_pThisMod
new g_pNextMod

// Existing cvars
new g_pNextmap
new g_pTimeLimit
new g_pVoteAnswers
new g_pChatTime

/* Constants */
// Voting delays
new const iVoteTime = 15 // Time to display the menu.
new const Float:fVoteTime = 15.0 // Time to choose an option.
new const Float:fBetweenVote = 15.0 // Time between mod vote ending and map vote starting.


public plugin_init()
{
	register_plugin("Polymorph: Mod Manager", "1.1.2", "Fysiks")
	register_cvar("Polymorph", "v1.1.2 by Fysiks", FCVAR_SERVER|FCVAR_SPONLY)
	
	register_dictionary("mapchooser.txt")
	// register_dictionary("polymorph.txt")
	// register_dictionary("common.txt")
	
	/* Register Cvars */
	g_pExtendMax = register_cvar("amx_extendmap_max", "90")
	g_pExtendStep = register_cvar("amx_extendmap_step", "15")
	g_pMode = register_cvar("poly_mode", "2")
	g_pExtendMod = register_cvar("poly_extendmod", "1")
	g_pThisMod = register_cvar("poly_thismod", "")
	g_pNextMod = register_cvar("poly_nextmod", "")
	
	/* Client Commands */
	register_clcmd("say nextmod", "sayNextmod")
	register_clcmd("say thismod", "sayThismod")
	
	/* Console Commands */
	register_concmd("amx_nextmod", "cmdSetNextmod", ADMIN_MAP, " - Set the next mod manually")
	register_concmd("amx_votemod", "cmdVoteMod", ADMIN_MAP, " - Start a vote for the next mod")

	/* Server Commands */
#if defined DEBUG
	register_srvcmd("list", "function") // Debug
#endif

	/* Compatibility */
	g_coloredMenus = colored_menus()
	if (cstrike_running())
		register_event("TeamScore", "team_score", "a")

	/* Register Menus */
	register_menucmd(register_menuid("Choose Nextmap:"), (-1^(-1<<(SELECTMAPS+2))), "countMapVotes")
	register_menucmd(register_menuid("Choose Nextmod:"), (-1^(-1<<(SELECTMODS+2))), "countModVotes")
	
}

public plugin_cfg()
{
	/* Get Cvar Pointers */
	g_pNextmap = get_cvar_pointer("amx_nextmap")
	g_pTimeLimit = get_cvar_pointer("mp_timelimit")
	g_pVoteAnswers = get_cvar_pointer("amx_vote_answers")
	g_pChatTime = get_cvar_pointer("mp_chattime")

	new szData[STRLEN_DATA]
	new szFilepath[STRLEN_PATH], szConfigDir[STRLEN_PATH]
	
	get_configsdir(szConfigDir, charsmax(szConfigDir))

	/* Get ThisMod Name */
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "plugins-polymorph.ini")
	new f = fopen(szFilepath, "rt")
	if(f)
	{
		fgets(f, szData, charsmax(szData))
		fclose(f)
		replace(szData, charsmax(szData), ";ThisMod:", "")
		trim(szData)
		parse(szData, g_szThisMod, charsmax(g_szThisMod))
	}
	
	/*
		Check for folder "/polymorph/"
		If it exists, load MODs.
	 */
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "polymorph")
	if( dir_exists(szFilepath) )
	{
		/* Load MODs */
		initModLoad()
	}
	else
	{
		new error[64]
		formatex(error, charsmax(error), "%s/ does not exist.", szFilepath)
		set_fail_state(error)
	}
	
	/* Set default nextmod/map depending on maps played and mode */
	new szMapsPlayed[4]
	get_localinfo("mapcount", szMapsPlayed, charsmax(szMapsPlayed))
	g_iMapsPlayed = str_to_num(szMapsPlayed)
	g_iMapsPlayed++

	switch( get_pcvar_num(g_pMode) )
	{
		case 0:
		{
			setNextMod(g_iThisMod)
			g_isLastMap = false
		}
		case 1,2:
		{
			// Set default nextmod depending on how many maps have been played on this mod
			if( !( g_iMapsPlayed < g_iMapsPerMod[g_iThisMod] ) ) // Do this in end map task too? to allow changing cvar mid map.
			{
				g_isLastMap = true
				setNextMod((g_iThisMod + 1) % g_iModCount)
			}
			else
			{
				setNextMod(g_iThisMod)
			}
		}
		default: // Mode 0
		{
			setNextMod(g_iThisMod)
			g_isLastMap = false
		}
	}
	setDefaultNextmap()
	
	/* Set task to check when map ends */
	set_task(20.0, "taskEndofMap", TASK_ENDOFMAP, "", 0, "b")
}

public plugin_end()
{
	// If this map still qualifies to be the last then reset mapcount for next mod.
	if( !( g_iMapsPlayed < g_iMapsPerMod[g_iThisMod] ) )
	{
		g_iMapsPlayed = 0
	}

	new szMapsPlayed[4]
	num_to_str(g_iMapsPlayed, szMapsPlayed, charsmax(szMapsPlayed))
	set_localinfo("mapcount", szMapsPlayed)
	
	if( g_iThisMod != g_iNextMod )
	{
		UpdatePluginFile()
	}
}

/*
	Plugin Natives
*/
public plugin_natives()
{
	// Polymorph Natives.  Make it modular!
	register_library("polymorph")
	register_native("polyn_endofmap", "_polyn_endofmap")
	register_native("polyn_get_thismod", "_polyn_get_thismod")
	register_native("polyn_get_nextmod", "_polyn_get_nextmod")
	register_native("polyn_votemod", "_polyn_votemod")
}

// Native: Execute the end of map vote.
public _polyn_endofmap(iPlugin, iParams)
{
	execEndofMap()
}

// Native: Get this mod's name and return it's id
public _polyn_get_thismod(iPlugin, iParams)
{
	new iChars = get_param(2)
	new szModName[STRLEN_NAME]
	copy(szModName, charsmax(szModName), g_szModNames[g_iThisMod])
	set_string(1, szModName, iChars)
	return g_iThisMod
}

// Native: Get the next mod's name and returns it's id
public _polyn_get_nextmod(iPlugin, iParams)
{
	new iChars = get_param(2)
	new szModName[STRLEN_NAME]
	copy(szModName, charsmax(szModName), g_szModNames[g_iNextMod])
	set_string(1, szModName, iChars)
	return g_iNextMod
}

// Native: Start Mod Vote (and map vote), force mapchange.
public _polyn_votemod()
{
	startModVote()
	set_task(50.0, "intermission", TASK_FORCED_MAPCHANGE)
}


/*
 *	Admin commands
 */
public cmdSetNextmod(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED
	
	if(read_argc() == 1)
	{
		console_print(id, "You are currently playing %s", g_szModNames[g_iThisMod]) // Need ML
		console_print(id, "Available MODs are:") // Need ML
		
		// Print available mods (menu-like)
		for(new i = 0; i < g_iModCount; i++)
		{
			console_print(id, i == g_iNextMod ? "%d) %s <<< Current nextmod" : "%d) %s", i+1, g_szModNames[i])
			// console_print(id, i == g_iNextMod ? "%d) %s <<< Current nextmod" : "%d) %s", i+1, g_szModNames[i]) // Need ML
		}
		
		new szCmdName[32]
		read_argv(0, szCmdName, charsmax(szCmdName))
		console_print(id, "To set the next mod, type ^"%s #^"", szCmdName)
		// console_print(id, "%L", id, "SET_NEXTMOD", szCmdName) // ML
	}
	else
	{
		new szArg[3]
		read_argv(1, szArg, charsmax(szArg))
		if( isdigit(szArg[0]) )
		{
			new modid = str_to_num(szArg) - 1
			if( 0 <= modid < g_iModCount )
			{
				if( modid == g_iNextMod )
				{
					console_print(id, "Next mod is already %s", g_szModNames[g_iNextMod]) // Need ML
				}
				else
				{
					setNextMod(modid)
					setDefaultNextmap()
					// Reset g_iMapsPlayed ??
					console_print(id, "The next mod is now %s", g_szModNames[g_iNextMod])
					// console_print(id, "%L", id, "NEXTMOD_NOW", g_szModNames[g_iNextMod]) // ML

					new szNextMap[STRLEN_MAP]
					get_pcvar_string(g_pNextmap, szNextMap, charsmax(szNextMap))
					console_print(id, "The next map is now %s", szNextMap)
					// console_print(id, "%L", id, "NEXTMAP_NOW", szNextMap) // ML
				}
			}
			else
			{
				console_print(id, "Invalid Option")
				// console_print(id, "%L", id, "INVALID_OPTION") // ML
			}
		}
		else
		{
			console_print(id, "Invalid Option")
			// console_print(id, "%L", id, "INVALID_OPTION") // ML
		}
	}
	return PLUGIN_HANDLED
}

public cmdVoteMod(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED

	// Start vote.
	// if(vote task is running) then don't allow
	if( get_timeleft() > TIMELEFT_TRIGGER && !task_exists(TASK_FORCED_MAPCHANGE) )
	{
		startModVote()
		set_task(50.0, "intermission", TASK_FORCED_MAPCHANGE)
	}
	else
	{
		console_print(id, "Vote not allowed at this time.")
		// console_print(id, "%L", id, "VOTE_NOT_ALLOWED") // ML
	}
	
	return PLUGIN_HANDLED
}

/*
 *	Say functions
 */
public sayNextmod()
{
	client_print(0, print_chat, "Next Mod: %s", g_szModNames[g_iNextMod])
	// client_print(0, print_chat, "%L %s", LANG_PLAYER, "NEXT_MOD", g_szModNames[g_iNextMod]) // ML
}

public sayThismod()
{
	client_print(0, print_chat, "This Mod: %s", g_szModNames[g_iThisMod])
	// client_print(0, print_chat, "%L %s", LANG_PLAYER, "THIS_MOD", g_szModNames[g_iThisMod]) // ML
}


/*
 *	End of Map functions
 */
public taskEndofMap()
{
	new winlimit = get_cvar_num("mp_winlimit")   // Not using pcvars to allow cross-mod compatibility
	new maxrounds = get_cvar_num("mp_maxrounds")
	
	if (winlimit)
	{
		new c = winlimit - 2
		
		if ((c > g_teamScore[0]) && (c > g_teamScore[1]))
		{
			g_selected = false
			return
		}
	}
	else if (maxrounds)
	{
		if ((maxrounds - 2) > (g_teamScore[0] + g_teamScore[1]))
		{
			g_selected = false
			return
		}
	}
	else
	{
		new timeleft = get_timeleft()
		
		if (timeleft < 1 || timeleft > TIMELEFT_TRIGGER)
		{
			g_selected = false
			return
		}
	}
	
	if (g_selected)
		return

	g_selected = true
	
	execEndofMap()
}

public execEndofMap()
{
	// Disallow vote if someone put up vote for new mod already.
	if( task_exists(TASK_FORCED_MAPCHANGE) )
		return
	
	switch( get_pcvar_num(g_pMode) )
	{
		case 0,1:
		{
			startMapVote()
		}
		case 2:
		{
			if( g_isLastMap )
			{ // Time to decide on new mod.
				startModVote()
			}
			else
			{ // Stay on this mod ( so only do map vote)
				startMapVote() 
			}
		}
		default: // Mode 0
		{
			startMapVote()
		}
	}
	
	// g_selected = true
}

/*
 *	Vote functions
 */
public startModVote()
{
	// Display Mod Menu
	
	new menu[512], a = 0, mkeys = (1<<SELECTMODS + 1) // The "None" key
	new pos = format(menu, 511, g_coloredMenus ? "\y%s:\w^n^n" : "%s:^n^n", "Choose the Next Mod")
	// new pos = format(menu, 511, g_coloredMenus ? "\y%L:\w^n^n" : "%L:^n^n", LANG_SERVER, "CHOOSE_NEXTMOD") // ML
	new modNum = g_iModCount - 1 // -1 because we exclude current running mod.
	new dmax = (modNum > SELECTMODS) ? SELECTMODS : modNum
	
	for (g_voteNum = 0; g_voteNum < dmax; ++g_voteNum)
	{
		do
			a++ // = random(g_iModCount)
		while ( a == g_iThisMod || isModInMenu(a) )
		
		g_nextModId[g_voteNum] = a
		pos += format(menu[pos], 511, "%d. %s^n", g_voteNum + 1, g_szModNames[a]);
		mkeys |= (1<<g_voteNum)
		g_voteModCount[g_voteNum] = 0
		// a++
	}
	
	menu[pos++] = '^n'
	g_voteModCount[SELECTMODS] = 0
	g_nextModId[SELECTMODS] = g_iThisMod
	g_voteModCount[SELECTMODS + 1] = 0
	
	if( get_pcvar_num(g_pExtendMod) )
	{
		pos += format(menu[pos], 511, "%d. Extend %s^n", SELECTMODS + 1, g_szModNames[g_iThisMod])
		// pos += format(menu[pos], 511, "%d. %L^n", SELECTMAPS + 1, LANG_SERVER, "EXTEND_MOD", g_szModNames[g_iThisMod]) // ML
		mkeys |= (1<<SELECTMODS)
	}

	format(menu[pos], 511, "%d. %L", SELECTMODS+2, LANG_SERVER, "NONE")
	
	show_menu(0, mkeys, menu, iVoteTime, "Choose Nextmod:")
	
	set_task(fVoteTime, "checkModVotes")
	client_print(0, print_chat, "It's time to choose the next mod.")
	// client_print(0, print_chat, "%L", LANG_SERVER, "TIME_CHOOSE_MOD") // ML
	client_cmd(0, "spk Gman/Gman_Choose2")
	log_amx("Vote: Voting for the next mod started")
}

public countModVotes(id, key)
{
	// Count Mod Votes

	if (get_pcvar_num(g_pVoteAnswers))
	{
		new name[32]
		get_user_name(id, name, 31)
		
		if (key == SELECTMODS)
			client_print(0, print_chat, "%s chose mod extending", name)
			// client_print(0, print_chat, "%L", LANG_PLAYER, "CHOSE_EXT_MOD", name) // ML
		else if (key < SELECTMODS)
			client_print(0, print_chat, "%L", LANG_PLAYER, "X_CHOSE_X", name, g_szModNames[g_nextModId[key]])
	}
	++g_voteModCount[key]

#if defined DEBUG
	debug_voters++
	client_print(0, print_chat, "POLY_DEBUG: Someone just voted for %d", key)
	server_print("POLY_DEBUG: Someone just voted for %d", key)
#endif
	
	return PLUGIN_HANDLED
}

public checkModVotes()
{
#if defined DEBUG
	client_print(0, print_chat, "POLY_DEBUG: # of voters: %d", debug_voters)
	server_print("POLY_DEBUG: # of voters: %d", debug_voters)
	debug_voters = 0
#endif
	
	// Check Mod Votes
	new b = 0
	
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteModCount[b] < g_voteModCount[a])
			b = a

	
	if (g_voteModCount[SELECTMODS] > g_voteModCount[b] )
	{
		setNextMod(g_iThisMod)
		client_print(0, print_chat, "%s has been extended for one map", g_szModNames[g_iNextMod])
		// client_print(0, print_chat, "%L", LANG_PLAYER, "CHO_FIN_EXT_MOD", g_szModNames[g_iNextMod]) // ML
		
		// Decrement maps played to only extend mod by one map.
		new szMapsPlayed[4]
		g_iMapsPlayed--
		num_to_str(g_iMapsPlayed, szMapsPlayed, charsmax(szMapsPlayed))
		set_localinfo("mapcount", szMapsPlayed)
	}
	else
	{
		setNextMod(g_nextModId[b]) // Set g_iNextMod
		
		client_print(0, print_chat, "Choosing finished.  The nextmod will be %s", g_szModNames[g_iNextMod])
		// client_print(0, print_chat, "%L", LANG_PLAYER, "CHO_FIN_NEXT_MOD", g_szModNames[g_iNextMod]) // ML
		log_amx("Vote: Voting for the next mod finished. The nextmod will be %s", g_szModNames[g_iNextMod])
	}

	// Set new default map to correspond to the next mod.
	setDefaultNextmap()
	
	set_task(fBetweenVote, "startMapVote")
}

public startMapVote()
{
	// Display Map Menu
	
	new menu[512], a, mkeys = (1<<SELECTMAPS + 1)

	new pos = format(menu, 511, g_coloredMenus ? "\y%L:\w^n^n" : "%L:^n^n", LANG_SERVER, "CHOOSE_NEXTM")
	new mapNum = g_iMapNums[g_iNextMod]
	new dmax = (mapNum > SELECTMAPS) ? SELECTMAPS : mapNum
	
	for (g_voteNum = 0; g_voteNum < dmax; ++g_voteNum)
	{
		a = random_num(0, mapNum - 1)
		
		while (isInMenu(a))
			if (++a >= mapNum) a = 0
		
		g_nextName[g_voteNum] = a
		pos += format(menu[pos], 511, "%d. %a^n", g_voteNum + 1, ArrayGetStringHandle(g_aModMaps[g_iNextMod], a));
		mkeys |= (1<<g_voteNum)
		g_voteMapCount[g_voteNum] = 0
	}
	
	menu[pos++] = '^n'
	g_voteMapCount[SELECTMAPS] = 0
	g_voteMapCount[SELECTMAPS + 1] = 0
	

	new mapname[32]
	get_mapname(mapname, 31)
	if( g_iThisMod == g_iNextMod ) // If staying on this mod allow extending the map.
	{
		if( get_pcvar_float(g_pTimeLimit) < get_pcvar_float(g_pExtendMax) )
		{
			pos += format(menu[pos], 511, "%d. %L^n", SELECTMAPS + 1, LANG_SERVER, "EXTED_MAP", mapname)
			mkeys |= (1<<SELECTMAPS)
		}
	}

	format(menu[pos], 511, "%d. %L", SELECTMAPS+2, LANG_SERVER, "NONE")
	
	show_menu(0, mkeys, menu, iVoteTime, "Choose Nextmap:")
	set_task(fVoteTime, "checkMapVotes")
	client_print(0, print_chat, "%L", LANG_SERVER, "TIME_CHOOSE")
	client_cmd(0, "spk Gman/Gman_Choose2")
	log_amx("Vote: Voting for the nextmap started")
}

public countMapVotes(id, key)
{
	if (get_pcvar_num(g_pVoteAnswers))
	{
		new name[32]
		get_user_name(id, name, 31)
		
		if (key == SELECTMAPS)
			client_print(0, print_chat, "%L", LANG_PLAYER, "CHOSE_EXT", name)
		else if (key < SELECTMAPS)
		{
			new map[32];
			ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[key], map, charsmax(map))
			client_print(0, print_chat, "%L", LANG_PLAYER, "X_CHOSE_X", name, map)
		}
	}
	++g_voteMapCount[key]
	
	return PLUGIN_HANDLED
}

public checkMapVotes()
{
	new b = 0
	
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteMapCount[b] < g_voteMapCount[a])
			b = a

	
	if (g_voteMapCount[SELECTMAPS] > g_voteMapCount[b]
	    && g_voteMapCount[SELECTMAPS] > g_voteMapCount[SELECTMAPS+1])
	{
		new mapname[32]
		
		get_mapname(mapname, 31)
		new Float:steptime = get_pcvar_float(g_pExtendStep)
		set_pcvar_float(g_pTimeLimit, get_pcvar_float(g_pTimeLimit) + steptime)
		client_print(0, print_chat, "%L", LANG_PLAYER, "CHO_FIN_EXT", steptime)
		log_amx("Vote: Voting for the nextmap finished. Map %s will be extended to next %.0f minutes", mapname, steptime)
		
		return
	}
	
	new smap[32]
	if (g_voteMapCount[b] && g_voteMapCount[SELECTMAPS + 1] <= g_voteMapCount[b])
	{
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[b], smap, charsmax(smap));
		set_pcvar_string(g_pNextmap, smap);
	}
	else // added 1.0.3
	{
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[0], smap, charsmax(smap));
		set_pcvar_string(g_pNextmap, smap);
	}
	
	get_pcvar_string(g_pNextmap, smap, 31)
	client_print(0, print_chat, "%L", LANG_PLAYER, "CHO_FIN_NEXT", smap)
	log_amx("Vote: Voting for the nextmap finished. The nextmap will be %s", smap)
}


/*
 *	Auxillary Functions
 */

/* Set the 'NextMod' index */
stock setNextMod(index)
{
	g_iNextMod = index
	set_pcvar_string(g_pNextMod, g_szModNames[g_iNextMod])
}

/* Set the default nextmap for the next mod */
stock setDefaultNextmap()
{
	new szMapName[32]
	ArrayGetString(g_aModMaps[g_iNextMod], 0, szMapName, charsmax(szMapName))
	set_pcvar_string(g_pNextmap, szMapName)
}

stock bool:loadMaps(szConfigDir[], szMapFile[], iModIndex)
{
	new szFilepath[STRLEN_PATH], szData[STRLEN_MAP]

	g_iMapNums[iModIndex] = 0
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, szMapFile)

	new f = fopen(szFilepath, "rt")

	if(!f)
		return false

	while(!feof(f))
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
		if(!szData[0] || szData[0] == ';' || (szData[0] == '/' && szData[1] == '/'))
			continue
		if(is_map_valid(szData))
		{
			ArrayPushString(g_aModMaps[iModIndex], szData)
			g_iMapNums[iModIndex]++
		}
	}
	fclose(f)
	return true
}

/**
 *  Rewrite plugins-polymorph.ini for the next mod.
 *  Will create the file if it does not exist.
 *  Use only when you need to change the mod!!!
 */
stock UpdatePluginFile()
{
	new szMainFilePath[STRLEN_PATH]
	new pMainFile
	
	get_configsdir(szMainFilePath, charsmax(szMainFilePath))
	format(szMainFilePath, charsmax(szMainFilePath), "%s/plugins-polymorph.ini", szMainFilePath)
	
	pMainFile = fopen(szMainFilePath, "wt")
	
	if(pMainFile)
	{
		fprintf(pMainFile, ";ThisMod:^"%s^"^r^n", g_szModNames[g_iNextMod])
		fputs(pMainFile, "; Warning: This file is re-written by Polymorph plugin.^r^n")
		fprintf(pMainFile, "; Any content added manually will be lost.^r^n")
		
		if( g_iModCount > 0 )
		{
			new iPlugins_num, szPluginName[STRLEN_NAME]
			
			iPlugins_num = ArraySize(g_aModPlugins[g_iNextMod])
				
			for(new j = 0; j < iPlugins_num; j++)
			{
				ArrayGetString(g_aModPlugins[g_iNextMod], j, szPluginName, charsmax(szPluginName))
				fprintf(pMainFile, "%s^r^n", szPluginName)
			}
		}
		else
		{
			fputs(pMainFile, ";;;  ERROR  ;;;\r\n;;; No MODs Loaded ;;;")
		}
		fclose(pMainFile)
	}
}

bool:isInMenu(id)
{
	for (new a = 0; a < g_voteNum; ++a)
		if (id == g_nextName[a])
			return true
	return false
}

bool:isModInMenu(id)
{
	for (new a = 0; a < g_voteNum; ++a)
		if (id == g_nextModId[a])
			return true
	return false
}

public team_score()
{
	new team[2]
	
	read_data(1, team, 1)
	g_teamScore[(team[0]=='C') ? 0 : 1] = read_data(2)
}

/* Show Scoreboard to everybody. */
public intermission()
{
	message_begin(MSG_ALL, SVC_INTERMISSION)
	message_end()
	set_task(get_pcvar_float(g_pChatTime), "changeMap")
}

/* Change map. */
public changeMap()
{
	new szNextmap[32]
	get_pcvar_string(g_pNextmap, szNextmap, charsmax(szNextmap))
	server_cmd("changelevel %s", szNextmap)
}

/* Exec Cvars */
public execCfg()
{
	new cfg_num = ArraySize(g_aCfgList)
	for(new i = 0; i < cfg_num; i++)
		server_cmd("%a", ArrayGetStringHandle(g_aCfgList, i))
	ArrayDestroy(g_aCfgList)
}

/* Initiate loading the MODs */
stock initModLoad()
{
	g_iModCount = 0
	new szFilepath[STRLEN_PATH], szConfigDir[STRLEN_PATH]
	get_configsdir(szConfigDir, charsmax(szConfigDir))
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "polymorph")

	new filename[32]
	g_aCfgList = ArrayCreate(STRLEN_DATA)

	new pDir = open_dir(szFilepath, filename, charsmax(filename))
	if(pDir)
	{
		do
		{
			if( 47 < filename[0] < 58 )
			{
				g_aModMaps[g_iModCount] = ArrayCreate(STRLEN_FILE)
				g_aModPlugins[g_iModCount] = ArrayCreate(STRLEN_FILE)
				if( loadMod(szFilepath, filename) )
				{
					server_print("MOD LOADED: %s %s", g_szModNames[g_iModCount], g_iThisMod == g_iModCount ? "<<<<<" : "") // Debug
					g_iModCount++
				}
				else
				{
					ArrayDestroy(g_aModMaps[g_iModCount])
					ArrayDestroy(g_aModPlugins[g_iModCount])
				}
			}

		} while( next_file(pDir, filename, charsmax(filename)) && g_iModCount < MODS_MAX )
		close_dir(pDir)
	}
	
	/* Exec Configs if Mod found */
	if( g_iModCount == 0 )
	{
		/* Zero mods loaded, set as failed */
		setNextMod(0)
		UpdatePluginFile()
		log_amx("[Polymorph] Zero (0) mods loaded.")
		set_fail_state("[Polymorph] Zero (0) mods were loaded.")
	}
	else if( g_iThisMod == -1 )
	{
		/* No mod found, set as failed, restart to fix. */
		setNextMod(0)
		UpdatePluginFile()
		log_amx("[Polymorph] Mod not found. Restart server.")
		set_fail_state("[Polymorph] Mod not found. Restart server.")
	}
	else
	{
		/* Set poly_thismod cvar */
		set_pcvar_string(g_pThisMod, g_szModNames[g_iThisMod])
		
		/* Execute Mod Config */
		set_task(4.0, "execCfg")
	}
}

/* Load individual MOD.  Return true on success */
stock bool:loadMod(szPath[], szModConfig[])
{
	new filepath[STRLEN_PATH]
	new szData[STRLEN_DATA], szPreCommentData[STRLEN_DATA]
	new key[STRLEN_MAP], value[STRLEN_MAP]
	
	formatex(filepath, charsmax(filepath), "%s/%s", szPath, szModConfig)
	new f = fopen(filepath, "rt")

	if(!f)
		return loadFail(szModConfig, "failed read mod's .ini file")

	/* Traverse header space */
	while(!feof(f) && szData[0] != '[')
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
	}

	/* Load MOD specific variables */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)

		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		parse(szData, key, charsmax(key), value, charsmax(value))

		if(equali(key, "name"))
		{
			copy(g_szModNames[g_iModCount], charsmax(g_szModNames[]), value)
			if( equal(value, g_szThisMod) )
			{
				g_iThisMod = g_iModCount
			}
		}
		else if(equali(key, "mapspermod"))
		{
			g_iMapsPerMod[g_iModCount] = str_to_num(value) ? str_to_num(value) : 2 // Default to 2
		}
		else if(equali(key, "mapsfile"))
		{
			if( !loadMaps(szPath, value, g_iModCount) )
			{
				fclose(f)
				return loadFail(szModConfig, "'mapsfile' failed to load")
			}
		}
	}

	/* Load MOD specific cvars */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
		
		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		/* Retain cvars if we are loading 'ThisMod' */
		if( g_iThisMod == g_iModCount )
		{
			strtok(szData, szPreCommentData, charsmax(szPreCommentData), "", 0, ';')
			trim(szPreCommentData)
			ArrayPushString(g_aCfgList, szPreCommentData)
		}

	}

	/* Load Plugins */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)

		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		strtok(szData, szPreCommentData, charsmax(szPreCommentData), "", 0, ';')
		trim(szPreCommentData)
		ArrayPushString(g_aModPlugins[g_iModCount], szPreCommentData)
	}
	// if all loads well increment g_iModCount
	// else clear used arrays and DO NOT increment g_iModCount
	fclose(f)
	return true
}

/* Log "failed to load mod" message. return false (meaning "failed to load") */
stock bool:loadFail(szModFile[], szComment[] = "")
{
	server_print("Failed to load mod from %s (%s)", szModFile, szComment) // Debug
	log_amx("[Polymorph] Failed to load configuration file %s (%s)", szModFile, szComment)
	return false
}

#if defined DEBUG
/* Debugging function */
public function()
{
	server_print("Printing:")
	for(new i = 0; i < g_iModCount; i++)
	{
		server_print("%s", g_szModNames[i])

		new plugs_num = ArraySize(g_aModPlugins[i])
		new plug_name[32]
		for(new j = 0; j < plugs_num; j++)
		{
			ArrayGetString(g_aModPlugins[i], j, plug_name, charsmax(plug_name))
			server_print("    %s", plug_name)
		}
		
		server_print("Maps:")
		
		new maps_num = ArraySize(g_aModMaps[i])
		new mapname[32]
		for(new j = 0; j < maps_num; j++)
		{
			ArrayGetString(g_aModMaps[i], j, mapname, charsmax(mapname))
			server_print("    %s", mapname)
		}
	}
}
#endif
