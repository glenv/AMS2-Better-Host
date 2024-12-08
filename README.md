# What is Better Host?

A lua Addon Script for AMS2 Dedciated Server to help reduce lag between players when host has poor ping to dedciated server. The Host is the first person to join the server.

# How does it choose better host:

  The default is better host will capture all players pings every 15 seconds, then takes the avg of these pings and compares it to other players. 
  If the host has the lowest ping, there is no better host however if a player has a lower ping value, they should be a better host. 
  There is a paramater in the config file called "bh_ms_range" to reduce minor ping variance between players with a default set of 75ms. 
  If the host has a avg ping of 150, a better host would need to have an avg ping of 75 or less to become a better host.

# How does a better host become host?

  In order for the better host to become host, everyone between the current host and the better host needs to be kicked from the server. The affceted players will be notified via in game chat to leave and rejoin server however there is a default limit of 3 reminders whith reminders sent to player in game chat every 10 secs, if they don't leave they will be kicked.
  
  
 PS: The list/index of players is based on jointime to the server, so you might be determined to be the better host but 10 other players had joined server before you, these 10 players will receive message to rejoin server and if ignored will forcefully be removed.


At the moment, better host only runs in Lobby and Practice session, however this might be axtended optionally in future releases.


# How to install:

1. Download latest release.
2. Unzip folder locally
3. Rename folder to "better_host"
4. Upload to AMS2 Dedicated Server folder /lua
  Your lua folder should look/contain these folders:
 ``` 
 better_host
 lib_rotate
 sms_base
 sms_motd
 sms_rotate
 sms_stats
 test
 
``` 

6. To activate this new script, you need to add it to the server.cfg file. Open this file with editor of choice and add "better_host" to the luaApiAddons section.

```
  enableLuaApi : true  
  luaAddonRoot: "lua"
  luaConfigRoot: "lua_config"
  luaOutputRoot: "lua_output"
  luaApiAddons : [  
      "sms_base",
      //"sms_rotate",
      "sms_motd",
      "sms_stats",
      "better_host"
  ]
```
7. Now you can start you server and better host will load up and start gathering player info should 2 or more players be on server and in Lobby or Practice sessions.

You can also type cmd in the ingame chat to get a list of commands you can use to show stats.

If you wish to tweak some of the default settings, please modify the newly created "better_host_config.json" file that is located on the server iunder the lua_config folder.
