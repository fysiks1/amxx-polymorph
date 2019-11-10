/*
 *	This plugin must be named mapchooser.amxx for 
 *	gungame and polymorph to be compatible.
 */
#include <amxmodx>
// #include <polymorph>

native polyn_endofmap()

public plugin_init()
{
	register_plugin("Polymorph: Mapchooser Emulator", "0.2", "Fysiks")
}

// Called by gungame.
public voteNextmap()
{
	polyn_endofmap()
}