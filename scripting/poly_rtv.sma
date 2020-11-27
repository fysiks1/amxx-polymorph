/*
 *	RockTheVote for Polymorph
 *	Requires Polymorph v0.8.2 or later
 *
 */

#include <amxmodx>
#include <amxmisc>
// #include <polymorph>

native polyn_votemod()

new bool:g_rockedVote[33], g_rockedVoteCnt
new bool:g_hasbeenrocked = false
new _:{
	SUCCESSFUL = 0,
	HASBEENROCKED,
	ALREADYVOTED,
	TOOEARLY,
	TOOLATE
}

// Cvars
new cvar_rtv_enabled
new cvar_rtv_ratio
new cvar_rtv_wait
new cvar_rtv_show

public plugin_init()
{
	register_plugin("Polymorph: RockTheVote", "1.0", "Fysiks")
	
	register_clcmd("amx_rtv","cmdAdminRTV", ADMIN_MAP, " Manually RockTheVote")
	register_clcmd("admin_rtv","cmdAdminRTV", ADMIN_MAP, " Manually RockTheVote")
	register_clcmd("say rtv", "cmdSayRTV")
	register_clcmd("say rockthevote", "cmdSayRTV")
	
	// Cvars
	cvar_rtv_enabled = register_cvar("rtv_enable", "1")	// <0|1>
	cvar_rtv_ratio = register_cvar("rtv_ratio", "0.51")		// Use amx_votemap_ratio?
	cvar_rtv_wait = register_cvar("rtv_wait", "1")			// Minutes after mapstart you can rtv
	cvar_rtv_show = register_cvar("rtv_show", "1")		// Display how many more votes needed to rtv
}

public cmdAdminRTV(id, level, cid)
{
	if(!cmd_access(id,level,cid,1))
		return PLUGIN_HANDLED
	
	if(g_hasbeenrocked)
	{
		client_print(id,print_console,"[RTV] Vote has already been rocked")
	}
	else
	{
		g_hasbeenrocked = true
		new admin_name[32]
		get_user_name(id, admin_name, 31)
		show_activity(id, admin_name, "has RockedTheVote")
		client_print(id,print_console, "[RTV] You have RockedTheVote")
		set_task(3.5,"announce_vote")
		set_task(5.0,"startRockVote")
	}
	// Add functionality to cancel rocked vote.
	return PLUGIN_HANDLED
}

public client_connect(id)
{
	g_rockedVote[id] = false
}

public client_disconnect(id)
{
	if(g_rockedVote[id])
	{
		g_rockedVote[id] = false
		g_rockedVoteCnt--
	}
}

public cmdSayRTV(id)
{
	if(!get_pcvar_num(cvar_rtv_enabled))
		return PLUGIN_CONTINUE // PLUGIN_HANDLED
	
	new status = SUCCESSFUL
	
	if(g_hasbeenrocked)
	{
		status = HASBEENROCKED
	}
	else if(g_rockedVote[id])
	{
		status = ALREADYVOTED
	}
	else if( get_cvar_float("mp_timelimit") > 0 && get_cvar_float("mp_maxrounds") == 0)
	{
		new Float:vote_wait = get_pcvar_float(cvar_rtv_wait)
		new Float:time_elapsed = get_cvar_float("mp_timelimit") - (float( get_timeleft() ) / 60.0) // Use get_gametime
		
		if( time_elapsed < vote_wait )
		{
			// Can replace all this content with "You cannot RockTheVote yet."
			// which would require no if statement or calculations.

			new Float:time_til_votebegin =  vote_wait - time_elapsed
			if(time_til_votebegin > 1.0)
			{
				new min_to_vote = clamp(floatround(time_til_votebegin),1,floatround(vote_wait))
				client_print(id, print_chat, "[RTV] You cannot RockTheVote for %d more minute%s.", min_to_vote, min_to_vote > 1 ? "s" : "" )
			}
			else // time_til_votebegin <= 1 minute
			{
				client_print(id, print_chat, "[RTV] You cannot RockTheVote for %d more seconds.", floatround(time_til_votebegin * 60) )
			}

			return PLUGIN_HANDLED
		}
		 
		if(get_timeleft() < 240 ) // don't allow rtv 4 minutes before map ends
		{
			client_print(id, print_chat, "[RTV] Too Late to RockTheVote.")
			return PLUGIN_HANDLED
		}
	}
	
	
	switch(status)
	{
		case SUCCESSFUL:
		{
			// You (id) just voted to rock.
			g_rockedVote[id] = true
			g_rockedVoteCnt++
			client_print(id,print_chat, "[RTV] You chose to RockTheVote")
			
			if( g_rockedVoteCnt >= get_RocksNeeded() ) 	// Decide if we rock the vote
			{
				g_hasbeenrocked = true
				client_print(0,print_chat, "[RTV] The Vote has been Rocked!")
				set_task(3.5,"announce_vote")
				set_task(5.0,"startRockVote")
			}
			else
			{
				rtv_remind()
			}
		}
		case HASBEENROCKED:
		{
			client_print(id, print_chat, "[RTV] Vote has already been Rocked.")
		}
		case ALREADYVOTED:
		{
			client_print(id, print_chat, "[RTV] You already voted.")
			rtv_remind()
		}
		default:
		{
			// Do nothing
		}
	}
	
	return PLUGIN_CONTINUE
}

public startRockVote()
{
	polyn_votemod()
}

get_RocksNeeded()
{
	return floatround(get_pcvar_float(cvar_rtv_ratio) * float(get_realplayersnum()), floatround_ceil);
}

stock get_realplayersnum()
{
	new players[32], playerCnt;
	get_players(players, playerCnt, "ch");
	
	return playerCnt;
}

rtv_remind()
{
	if(get_pcvar_num(cvar_rtv_show))
	{  // Not tested yet.
		client_print(0,print_chat, "[RTV] Need %d more players to RockTheVote.", get_RocksNeeded() - g_rockedVoteCnt)
	}
}

public announce_vote()
{
	client_cmd(0, "spk buttons/blip2")  // Moved here from startRockVote to give heads up
}