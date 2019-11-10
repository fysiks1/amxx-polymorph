#include <amxmodx>

//Sets CSDM to active (do not set the cvar!)
native csdm_set_active(on_or_off);

public plugin_init()
{
	register_plugin("Turn CSDM Off", "0.1", "Fysiks")
	csdm_set_active(0)
}