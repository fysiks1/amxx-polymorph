# Polymorph: Mod Manager
This is a map chooser replacement. It allows voting for the next mod (GunGame, HNS, etc.). It does not pause plugins so plugins from the mods are not loaded unless it is being played.

## Admin Commands

### `amx_nextmod`

Console command to show/choose the next MOD to be played. When you change the next MOD it will choose a random map from the MOD's map list to be the default map.

### `amx_votemod`

Starts a vote for the next MOD (and consequently the next map). Then it changes the map.

## Cvars

### `poly_mode <#>`

Modes:

0. Always stay on one mod unless changed manually with admin command. (Map votes only)
1. Play X maps then next mod will default to next in polymorph folder (Map votes only)
2. Play X maps then next mod will be chosen by vote. (Map and Mod votes)

Default: 2

### `poly_extendmod <1|0>`

Allow extending the current mod (Mode 2).

Default: 1

### `amx_extendmap_max <minutes>`

Maximum number of minutes to which the map can be extended.  Same as the original mapchooser plugin.

Default: 90

### `amx_extendmap_step <minutes>`

Number of minutes added when the map is extended.  Same as the original mapchooser plugin.

Default: 15

## Setup

- Install polymorph.amxx like any other plugin.
- Create the folder /addons/amxmodx/configs/polymorph/.
- Create MOD initialization files:
  - File must be in the polymorph folder.
  - File must begin with a number.
  - Example file 0_MyFirstMod.ini
    ```
    ; Mod Cofiguration
    ; Comments here.

    [mod]
    name "Mod Name"
    mapsfile maps1.ini
    mapspermod 2

    [cfg]
    sv_gravity 900
    sv_alltalk 0
    hostname "This server is running ModName"

    [plugins]
    plugin1.amxx
    plugin1b.amxx
    ```

  - "mapsfile" must be in the polymorph folder. It should contain all the maps that you want to be eligible to be played with the MOD

- If a mod comes with a `plugins-<modname>.ini` file (like Zombie Plague), it must removed.
- If you want a plugin running for all mods then place it in plugins.ini. If you want it running for only certain mods, list it in your mod's .ini file in the polymorph folder.

## Startup
The plugin will fail the first time it is run. Simply restart the server to create the plugins-polymorph.ini file.