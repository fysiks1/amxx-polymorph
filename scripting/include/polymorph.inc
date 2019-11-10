/*
 *	Include for Polymorph by Fysiks
 */

#if defined _polymorph_included
	#endinput
#endif
#define _polymorph_included

#pragma reqlib "polymorph"


/*
 *	Executes the end of map vote.  Follows the restrictions set by poly_mode.
 */
native polyn_endofmap()

/**
 	Gets the current mod's name and ID.
 
	@param		string to store mod name
	@param		string length
	
	@return		Mod ID
*/
native polyn_get_thismod(modname[], len)

/*
 *	Gets the next mod's name.  Saved in modname[].
 *	Returns the mod's ID.
 */
native polyn_get_nextmod(modname[], len)

/*
 *	Starts mod vote and changes map afterwards.
 */

 native polyn_votemod()
 