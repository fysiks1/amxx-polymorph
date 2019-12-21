/*
 *	This plugin must be named mapchooser.amxx for 
 *	gungame and polymorph to be compatible.
 */
#include <amxmodx>
// #include <polymorph>

native polyn_endofmap()

public plugin_init()
{
	register_plugin("Nextmap Chooser", "0.3", "Polymorph")
}

// Called by gungame.
public voteNextmap()
{
	polyn_endofmap()
}