-- TODO's 

local addon_storage = ...

-- Grab config.
local config = addon_storage.config

local addon_data = addon_storage.data
addon_data.memberstore = {}
local memberstore = {}


-- Enable debugging prints This can get very congested in cmd output and also ingame chat.
-- ONLY USE FOR TESTING
local debug = true
local debugchat = false
local fill_ai = false


-- Various times, move to config?
local TICK_UPDATE_DELTA_MS = 1000
local ACTIVE_AUTOSAVE_DELTA_MS = 2 * 60 * 1000
local IDLE_AUTOSAVE_DELTA_MS = 15 * 60 * 1000


-- Current state
local server_state = "Idle"
local session_stage = nil
local session_state = nil
local last_update_time = nil
local last_save_time = nil


-- "Forward declarations" of all local functions, to prevent issues with definition vs calling order.
-- Please maintain this in the same order as the function definitions.
-- Yes, it does not look nice, and if the names here do not match the actual function names exactly, the mismatching definitions will become global functions.
-- Yes, Lua is an ugly language.

local start
local tick
local to_kick = {}
local update_member_ping
local handle_member_attributes
local addon_callback


-- Map from refid to send timer (GetServerUptimeMs)
local scheduled_sends = {}

local member_ping = {}
local counter = 0 
local members_to_go_count = 0
local member_count = 0
local seconds = config.grab_seconds or 15
local warnings = config.warnings or 3
local ping_counts_to_include = config.bh_ping_count_start or 2
local better_host_scan_ms = (config.bh_scan_secs * 1000) or 15000
local member_jointime = {}
local practice_session_enabled = config.bh_enable_in_practice or false
local bh_ms_range = config.bh_ms_range or 50
local rejoin_warnings = config.bh_rejoin_warnings or 3
local rejoin_reminder_ms = (config.bh_rejoin_reminder * 1000) or 10000
local better_ping = nil
local member_ping = nil
local member_ping_count = nil
local previous_better_ping = nil
local previous_better_host_name = 'None'
local previous_better_host = 'None'
local better_host_jointime = nil
local better_host_name = nil
local better_host =  nil
local session_previous_state = 'SessionDestroyed'
local session_current_state = 'SessionDestroyed'
-- Maybe use for admins later to re-enable outside of defaults.
local better_host_active_override = false
local better_host_ran = false
local members_to_go_names = ''

-- Processing schedule times
local ping_update = nil
local better_host_update = nil
local rejoin_request_update = nil

local better_host_is_host_update = nil
local better_host_is_host_counter = 8

-- local function random_members()
-- 		local i = 0
-- 		local t = os.time()
-- 		while i < 32 do
-- 			local refid = math.random(5000)
-- 			memberstore[ refid ] = {}
-- 			memberstore[ refid ].name = tostring("FAKE-" .. refid )
-- 			memberstore[ refid ].steamid = math.random(100000000)
-- 			memberstore[ refid ].is_admin = false
-- 			memberstore[ refid ].host = false
-- 			memberstore[ refid ].is_better_host = false
-- 			memberstore[ refid ].ping_count = math.random(100)
-- 			memberstore[ refid ].ping_min = math.random(100)
-- 			memberstore[ refid ].ping_max = math.random(100)
-- 			memberstore[ refid ].ping_avg = math.random(5000, 150000)
-- 			memberstore[ refid ].ping_sum = math.random(100000)
-- 			memberstore[ refid ].warnings = 0		
-- 			memberstore[ refid ].rejoin_exit_count = 0
-- 			memberstore[ refid ].jointime = t
-- 			t = t + 2000
-- 			i = i + 1
-- 			member_count = member_count + 1
-- 		end
-- end

-- local function update_fake_host_ping()
-- 	memberstore[ better_host ].ping_avg = math.random(5000,150000)
-- end

local function timestamp()
	local ts = ''
	ts = tostring("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [BHB]: ")
	return ts
end



local function rejoin_members_to_go_count()
	local count = 0
	if better_host_jointime ~= nil then
		for refid,jointime in pairs( memberstore ) do
			if memberstore[ refid ].jointime < better_host_jointime then
				count = count + 1
			end
		end
	end
	members_to_go_count = count
end

-- Check is more then 1 better host. 
local function better_host_count()
	local count = 0
	for refid,attr in pairs( memberstore ) do
		if memberstore[ refid ].is_better_host then
			count = count + 1
		end
	end
	return count
end

local function rejoin_members_to_go_names()
	local names = ''
	if better_host_jointime ~= nil then
		for refid,name in pairs( memberstore ) do
			if memberstore[ refid ] ~= nil and memberstore[ refid ].jointime < better_host_jointime then
				local name = memberstore[ refid ].name
				if names == nil then
					names = name
				else
					names = (names .. ", " .. name)
				end
			end
		end
	end
	members_to_go_names = names
end

local function is_admin( steamid )
	local rs = false
	a = tostring(config.ingame_admins_steamids)
	for steam_id in string.gmatch(a, '([^,]+)') do
		if steam_id == tostring(steamid) then
			rs = true
		end
	    if debug then print("Admins listed are: " .. steam_id) end
	end
	return rs
end

local function show_member_ping( refid )
	local refid = refid
	local now = GetServerUptimeMs()
	local tdiff = math.ceil((ping_update - now) / 1000)
	local name = memberstore[ refid ].name
	local min = memberstore[ refid ].ping_min
	local max = memberstore[ refid ].ping_max
	local avg = memberstore[ refid ].ping_avg / 1000
	local pw = memberstore[ refid ].warnings
	local rw = memberstore[ refid ].rejoin_exit_count
	if memberstore[ refid ].ping_count > 0 then
		SendChatToMember( refid , "[BHB]: " .. name .. ", your ping (ms) stats: avg=" .. string.format("%.1f",avg) .. ", min=" .. min .. ", max=" .. max .. ".")
	else
		SendChatToMember( refid , "[BHB]: " .. name .. ", your stats will be ready in " .. tdiff .. " seconds.")
	end

end

local function clear_better_host_variables()
	previous_better_host = 'None'
	previous_better_host_name = 'None'
	previous_better_ping = nil
	better_ping = nil
	better_host = nil
	if debug then print("Cleared Better Host and previous better host variables") end
end

local function show_better_host( refid, to_all )
	if better_host ~= nil then
		local refid = refid
		local now = GetServerUptimeMs()
		local tdiff = math.ceil((better_host_update - now) / 1000)
		local admin = memberstore[ refid ].is_admin
		local to_all = to_all or false
		local name = memberstore[ better_host ].name
		local min = memberstore[ better_host ].ping_min 
		local max = memberstore[ better_host ].ping_max 
		local avg = memberstore[ better_host ].ping_avg / 1000 
		local pw = memberstore[ better_host ].warnings		
		local rw = memberstore[ better_host ].rejoin_exit_count
		if not to_all then
			SendChatToMember( refid , "[BHB]: Better Host is " .. better_host_name .. ", Stats: avg=" .. string.format("%.1f",avg) .. ", min=" .. min .. ", max=" .. max .. ".")
		elseif admin then
			SendChatToAll("[BHB]: Better Host is " .. better_host_name .. ", Stats: avg=" .. string.format("%.1f",avg) .. ", min=" .. min .. ", max=" .. max .. ".")
		end
	else
		SendChatToMember( refid , "[BHB]: Better Host is still gathering info.")
	end
end

local function show_lobby_ping( refid )
	local refid = refid
	local members = 0
	local min = 0
	local max = 0
	local avg = 0
	local pcount = 0		
	local sum = 0
	for refId,attr in pairs(memberstore) do
		members = members + 1
		min = min + memberstore[ refId ].ping_min
		max = max + memberstore[ refId ].ping_max
		pcount = pcount + memberstore[ refId ].ping_count
		sum = sum + memberstore[ refId ].ping_sum
		avg = (sum / pcount)
	end 	
	if members > 0 then
		SendChatToMember( refid , "[BHB]: Lobby ping (ms) stats: avg=" .. string.format("%.1f",avg) .. ", min=" .. min .. ", max=" .. max .. ".")
	end

end

local function show_worst_ping( refid )
	local refid = refid
	local member_ping = 0
	local member_refid = 0
	local worst_ping = nil
	local worst_host = nil
	local member_ping_count = 0
	local name = nil
	local min = 0
	local max = 0
	local avg = 0
	for refId,name in pairs(memberstore) do	
		member_ping = memberstore[ refId ].ping_avg
		member_ping_count = memberstore[ refId ].ping_count
		member_refid = refId
		if member_ping_count < 1 then
			return
		end
		if worst_ping == nil and member_ping > 0 and member_ping_count > 0 then 
			worst_ping = member_ping
			worst_host = refId
		end
		if member_ping > worst_ping and member_ping_count > 0 then
			worst_ping = member_ping
			worst_host = refId
		end
	end 
	min = memberstore[ worst_host ].ping_min
	max = memberstore[ worst_host ].ping_max
	avg = memberstore[ worst_host ].ping_avg / 1000
	name = memberstore[ worst_host ].name
	SendChatToMember( refid , "[BHB]: " .. name .. " has worst ping stats: avg=" .. string.format("%.1f",avg) .. ", min=" .. min .. ", max=" .. max .. ".")
	

end


local function show_lobby_ping_order( refid )
	local sorted = {}
	local id = 1
	for k,_ in pairs(memberstore) do
	  sorted[id] = {}
	  if memberstore[k].is_better_host then
	  	sorted[id].name = ("*bh " .. memberstore[k].name)
	  else
	  	sorted[id].name = memberstore[k].name
	  end
	  sorted[id].ping_avg = memberstore[k].ping_avg / 1000
	  id = id + 1
	end
	table.sort(sorted, function(a,b) return a.ping_avg < b.ping_avg end)
	SendChatToMember( refid , "[BHB]: Lobby Ping List in order.")
	for i = 1, tonumber(member_count) do		
		SendChatToMember( refid , "#" .. i .. "   " .. sorted[i].name .. " with " .. string.format("%.1f",sorted[i].ping_avg) .. "ms avg ping.")
	  	-- print(i .. ": " .. sorted[i].name .. ": " .. sorted[i].ping_avg)
	end
end

local function enforce_rejoin( arefid )
	local now = GetServerUptimeMs()
	local tdiff = math.ceil((better_host_update - now) / 1000)	
	local bhc = better_host_count()
	if bhc > 0 then
		for refId,attr in pairs(memberstore) do	
			local member_jointime =  memberstore[ refId ].jointime
			if not memberstore[ refId ].is_better_host and member_jointime < better_host_jointime then
				if to_kick[ refId ] == nil then
					now = now + 1000
					to_kick[ refId ] = now					
					SendChatToMember( refId , "[BHB]: Enforcing Rejoin. You'll be kicked in a few seconds. please rejoin.")
					if debug then print( timestamp() .. "Added " .. refId .. " to autokick batch to rejoin." ) end
				end
			elseif memberstore[ refId ].is_better_host == memberstore[ refId ].host then 
				SendChatToMember( refid , "[BHB]: Better host is the host who is " .. better_host_name ..".")
			end
		end
	else
		SendChatToMember( refid , "[BHB]: Better host hasn't been decided yet. Please wait " .. tdiff .. " more seconds.")
	end
end


-- Start
function start()

	last_update_time = GetServerUptimeMs()	
	
end

local function autokick( refId )
	local now = GetServerUptimeMs() 	
	if to_kick[ refId ] == nil then
		to_kick[ refId ] = now + 2000
		if debug then print( timestamp() .. "Added " .. refId .. " to autokick batch." ) end
	end
	
end


-- Regular update tick.
local function bhtick()
	-- If we have members to kick for high ping, process them here.
	local now = GetServerUptimeMs() 
	for refId, time in pairs( to_kick ) do
		if now >= time then	
			if debug then print( timestamp() .. "Kicking " .. refId )	end
			KickMember( refId )
			to_kick[ refId ] = nil
			if fill_ai then memberstore[ refId ] = nil end
		end
	end
	-- No-op until started
	if not last_update_time then
		return
	end
	-- Check time elapsed, process only after 1s
	local now = GetServerUptimeMs()
	local delta_ms = now - last_update_time
	if delta_ms < TICK_UPDATE_DELTA_MS then
		return
	end
	local delta_secs = delta_ms / 1000
	last_update_time = now

	
end

local function output_to_data_file()
	-- addon_data.member_jointime = member_jointime
	addon_data.memberstore = memberstore
	SavePersistentData()
end

-- Update history member's ping.
local function update_member_ping( member )
	local refid = member.refid
		if member.attributes.Ping > 0 and memberstore[ refid ] ~= nil then
		memberstore[ refid ].host = member.host
		memberstore[ refid ].ping_count = memberstore[ refid ].ping_count + 1
		memberstore[ refid ].ping_sum = ( memberstore[ refid ].ping_sum + member.attributes.Ping )
		memberstore[ refid ].ping_avg = math.floor(( memberstore[ refid ].ping_sum / memberstore[ refid ].ping_count )	* 1000)
		memberstore[ refid ].ping_min = math.min( member.attributes.Ping,  memberstore[ refid ].ping_min)
		memberstore[ refid ].ping_max = math.max( member.attributes.Ping,  memberstore[ refid ].ping_max)
		-- This is for high ping kicker only
		if memberstore[ refid ].ping_avg >= config.ping_limit_ms * 1000 and config.hp_active then
			memberstore[ refid ].warnings = memberstore[ refid ].warnings + 1
			SendChatToMember( member.refid,  "[BHB]: Warning " .. memberstore[ refid ].warnings .. " of " .. warnings .. ", AVG Ping is " .. string.format("%.1x", memberstore[ refid ].ping_avg / 1000) ..'ms. Limit is ' ..  config.ping_limit_ms .. 'ms.' )
		end
		if memberstore[ refid ].warnings >= warnings then
			SendChatToMember( member.refid,  "[BHB] You're being kicked for high ping, avg " .. string.format("%.1x", memberstore[ refid ].ping_avg / 1000) ..'ms. Limit is ' ..  config.ping_limit_ms .. 'ms.')
			SendChatToMember( member.refid,  "[BHB] Please check running apps, background processes etc before joining again. Bye")
			SendChatToAll( "[BHB] " .. member.name .. " will be removed from server due to high ping.")
			autokick( member.refid )
			if debug then print( timestamp() .. "Adding " .. member.refid .. " to autokick..") end
		end
	end
end

local function find_better_host()
	-- Setup and update delay so that this doesn't get spammed every server tick
	local now = GetServerUptimeMs()
	member_ping = 0
	better_host_update = better_host_update or (now + 2000)
	if (better_host_update <= now and not better_host_active_override and member_count > 1) then
		if debug then print(timestamp() .. "Member Count is " .. member_count) end
		-- Schedule next update time		
		better_host_update = ( now + better_host_scan_ms )
		better_ping = nil
		better_host = nil
		-- Cycle through members to find best host but first, clear is_best_host and assign them previous better host
		-- clear_better_host()	
		for refid,name in pairs(memberstore) do
			if memberstore[ refid ].is_better_host then
				previous_better_host = refid
				previous_better_ping = memberstore[ refid ].ping_avg
				previous_better_host_name = memberstore[ refid ].name
			end
			memberstore[ refid ].is_better_host = false
		end		
		-- Now loop through and find best host
		for refid,name in pairs(memberstore) do
			if memberstore[ refid ].ping_count >= ping_counts_to_include then
				member_ping = memberstore[ refid ].ping_avg
				-- If the ping count is below threshold, lets exclude them as stats might be skewed to much 
				-- Better ping is nil, but the first member in the list will be initially the better host, 
				-- but if better ping is already assigned , check other members to find the lowest ping + threshold ms value.			
				if  better_ping == nil then 
					better_ping = member_ping
					better_host = refid
					local bhn = tostring(memberstore[ refid ].name)
					if debug then print(timestamp() .. "Initial Better Ping is " .. bhn .. " : " .. better_host .. " with " .. better_ping .. ".") end
				-- If this is lower than better ping, update to current members details.
				end
				if debug then print(timestamp().. refid .. " Member Ping : " .. member_ping .. " vs Better Ping : " .. better_ping .. ". diff : " .. ( better_ping - member_ping)) end
				if member_ping < ( better_ping - (bh_ms_range * 1000) ) then
					local pbp = better_ping - (bh_ms_range * 1000)
					if debug then print( timestamp() .. tostring(member_ping .. " is < " .. pbp .. ".")) end
					better_ping = member_ping
					better_host = refid
					if debug then print(timestamp() .. "Updated Better Ping is " .. better_host .. " with " .. ( better_ping - (bh_ms_range * 1000) ) .. ".") end
				end
			elseif memberstore[ refid ].ping_count < ping_counts_to_include then
				if debug then print(timestamp() .. "Skipped member [" .. refid .. "] as ping count is below threshold or member ping count is zero.") end
			end
		end
		-- Now we should have better host details, so lets update memberstore and set is_better_host
		if better_host ~= nil then
			memberstore[ better_host ].is_better_host = true 
			memberstore[ better_host ].rejoin_exit_count = 0
			better_host_name = memberstore[ better_host ].name 
			better_host_jointime = memberstore[ better_host ].jointime
			if previous_better_host ~= better_host and better_host_ran then
				if previous_better_host_name ~= 'None' then
					if debug then 
						print(timestamp() .. "Found better host. Was " .. previous_better_host_name .. "(" .. math.floor(previous_better_ping / 1000 ) .. ") but now is " .. better_host_name .. " (" .. math.floor(better_ping / 1000) ..").")
					end	
					if debugchat then 
						SendChatToAll("[BHB]: Found better host. Was " .. previous_better_host_name .. " " .. math.floor(previous_better_ping / 1000 ) .. "ms, but now is " .. better_host_name .. " " .. math.floor(better_ping / 1000) .. "ms.")
					end
				elseif better_host_ran then
					if debug then 
						print(timestamp() .. "Found better host. This is " .. better_host_name .. ".")
					end
					if debugchat then 
						SendChatToAll("[BHB]: Found better host. This is " .. better_host_name .. " " .. math.floor(better_ping / 1000) .. "ms.")
					end	
				end
			end
		better_host_ran = true
		end
		local bhc = better_host_count()
		if debug then print(timestamp() .. "There is " .. bhc .. " better host(s)" ) end
		-- This runs every cycle and outputs the data to a file in lua_config folder called "better_host_data.json"
		-- If session is destroyed, the memberstore is reset, so not persistent.
		output_to_data_file()
	end
end

-- Send migration/rejoin
local function send_rejoin_request( refid )
	local is_better_host = memberstore[ refid ].is_better_host or nil
	local jointime = memberstore[ refid ].jointime or nil
	local member_name = memberstore[ refid ].name
	if not better_host_active_override then
		rejoin_members_to_go_count()
		rejoin_members_to_go_names()		
		-- send_rejoin_request could run before the data is initialised, so if either of these are nil return / break out of if statement.
		if jointime == nil or better_host_jointime == nil or member_count <= 1 or not better_host_ran then
			if debug then
				print(timestamp() .. "Better Host not run yet or either Member/better host join times are nil and only " .. member_count .. " member exists.")
			end
			return
		elseif not is_better_host and (jointime < better_host_jointime) and better_host_ran then
			if debug then 
				print(timestamp() .. "Send Rejoin started..")
				print(timestamp()  .. members_to_go_count .. " member(s) need to rejoin.")
				print(timestamp() .. "These name are " .. tostring(members_to_go_names):sub(1,40) .. ".")
			end
			-- Now log that migration/rejoin request sent to user
			memberstore[ refid ].rejoin_exit_count = memberstore[ refid ].rejoin_exit_count + 1
			local w = memberstore[ refid ].rejoin_exit_count
			if debug then print(timestamp() .. member_name .. ", exit and rejoin so " .. better_host_name .. " can become host." .. tostring(w) .. "/" .. tostring(rejoin_warnings) .. ".") end			
			SendChatToMember( refid,  "[BHB]: ".. member_name .. ", exit and rejoin so " .. better_host_name .. " can become host." .. tostring(w) .. "/" .. tostring(rejoin_warnings) .. ".")
			if memberstore[ refid ].rejoin_exit_count >= rejoin_warnings then
				SendChatToMember( refid,  "[BHB]: You're being kicked to allow " .. better_host_name .. " to become host")				
				SendChatToAll("[BHB]: Kicking " .. member_name .. " to allow better host " .. better_host_name ..".")
				SendChatToAll("[BHB]: " .. members_to_go_count .. " member(s) need to rejoin.")	
				autokick( refid )
			end
		end
	end
end


-- Server state changes.
local function handle_server_state_change( old_state, new_state )
	server_state = new_state
	if new_state == "Starting" then
		start()
	end
end

-- Member attribute changes.
local function handle_member_attributes( refid, attribute_names )
	local member = session.members[ refid ]
	local now = GetServerUptimeMs() 
	ping_update = ping_update or now + 2000
	if ping_update <= now then
		update_member_ping( member )
		ping_update = now + better_host_scan_ms
	end

	rejoin_request_update = rejoin_request_update or now
	if rejoin_request_update <= now and better_host_ran then
		rejoin_request_update = now + rejoin_reminder_ms
		send_rejoin_request( refid )
	end
end

-- Immediate send to given refid
local function send_now( refid )
	local s = ''
	if practice_session_enabled then
		s = tostring("[BHB]: Better Host is running during Lobby and Practice sessions.")
	else
		s = tostring("[BHB]: Better Host is running in Lobby only")		
	end
	SendChatToMember( refid, s )
	local p = tostring("[BHB]: Type cmd in chat to see a list of commands.")
	SendChatToMember( refid, p )

end

-- The tick that processes all queued sends
local function tick()
	local now = GetServerUptimeMs()
	for refid,time in pairs( scheduled_sends ) do
		if now >= time then
			send_now( refid )
			scheduled_sends[ refid ] = nil
		end
	end
end

-- Request send to given refid, or all session members if refid is not specified.
local function send_motd_to( refid )
	local send_time = GetServerUptimeMs() + 2000
	if refid then
		scheduled_sends[ refid ] = send_time
	else
		for k,_ in pairs( session.members ) do
			scheduled_sends[ k ] = send_time
		end
	end
end
local mc = 0
-- Main addon callback
function addon_callback( callback, ... )
	-- Regular tick
	if callback == Callback.Tick then
		bhtick()
		tick()
		if (practice_session_enabled and session_stage == "Practice1") or session_state == 'Lobby' then			
			find_better_host()
		end
	end

	-- Member attribute changes.
	if callback == Callback.MemberAttributesChanged then
		local refid, attribute_names = ...
		handle_member_attributes( refid, attribute_names )
	end

	if callback == Callback.SessionAttributesChanged then
		session_stage = session.attributes.SessionStage or nil
		session_state = session.attributes.SessionState or nil
	end

	if callback == Callback.EventLogged then
		local event = ...
		if ( event.type == "Session" ) and ( event.name == "StateChanged" ) then
			session_previous_state = session_current_state
			session_current_state = event.attributes.NewState
			if ( event.attributes.PreviousState ~= "None" ) and ( event.attributes.NewState == "Lobby" ) then
				if config.bh_announce_when_joining then
					send_motd_to()
				end
			end
		end

		if ( event.type == "Session" ) and ( event.name == "SessionDestroyed" ) then
			session_previous_state = 'SessionDestroyed'
			session_current_state = 'SessionDestroyed'
				memberstore = {}
				member_count = 0
				clear_better_host_variables()
				output_to_data_file()
		end
		-- Send member ping stats via in game chat
		if event.type == "Player" and event.name == "PlayerChat"  then
			local refid = event.refid
			if event.attributes.Message == "ping" then show_member_ping( refid ) 
			elseif event.attributes.Message == 'lstats' then show_lobby_ping( refid )
			elseif event.attributes.Message == 'lping' and memberstore[ refid ].is_admin then show_lobby_ping_order( refid )  
			elseif event.attributes.Message == 'wh' then show_worst_ping( refid )
			elseif event.attributes.Message == "bh" then show_better_host( refid )
			elseif event.attributes.Message == "bha" then show_better_host( refid, true )
			elseif event.attributes.Message == "ebh" and memberstore[ refid ].is_admin then enforce_rejoin( refid )
			elseif event.attributes.Message == "cmd" then 
				SendChatToMember( refid, "[BHB]: ping - Shows you your ping stats" )
				SendChatToMember( refid, "lstats - Shows you aggregated lobby ping stats")
				SendChatToMember( refid, "wh - Shows you worst members ping stats")
				SendChatToMember( refid, "bh - Shows you who is better host" )
				SendChatToMember( refid, "bha - Shows everyone who is better host" )
				SendChatToMember( refid, "cmd - Shows you commands that can be used via in-game chat." )
				if memberstore[ refid ].is_admin then
					SendChatToMember( refid, "ebh - Admins Only: Enforces Better Host.")
					SendChatToMember( refid, "Kick members between current and better host based on join time.")
					SendChatToMember( refid, "lping - Admins Only: Shows All users avg ping in order.")
					SendChatToMember( refid, "bhstop - Admins Only: Stops Better Host.")
					SendChatToMember( refid, "bhstart - Admins Only: Starts Better Host.")
					-- SendChatToMember( refid, "bhmst - Admins Only: Changes the default ms threshold when finding better host between members ")
				end
				-- elseif fill_ai then 
				-- 	if event.attributes.Message == "ump" then update_fake_host_ping( refid )
				-- 	elseif event.attributes.Message == "fill" then random_members()
				-- 	end
				
			elseif event.attributes.Message == "bhstop" and memberstore[ refid ].is_admin then 
				better_host_active_override = true 
				SendChatToMember( refid , "[BHB]: Admin has stopped BHB.")
				print(timestamp() .. "Admin has stopped better host")
			elseif event.attributes.Message == "bhstart" and memberstore[ refid ].is_admin then 
				better_host_active_override = false 
				SendChatToMember( refid , "[BHB]: Admin has started BHB.")
				print(timestamp() .. "Admin has started better host")
			end 
		end
		-- Check if player is an admin or not
		if event.type == "Player" and event.name == "PlayerJoined" then
			local refid = event.refid
			member_count = member_count + 1 
			-- better_host_stopped = false
			if debug then print(timestamp() .. "Members: " .. member_count)	end					
			send_motd_to( refid )
			member_jointime[ refid ] = event.time
			if debug then print(timestamp() .. "Join Time: " .. member_jointime[ refid ]) end
			memberstore[ refid ] = {}
			memberstore[ refid ].name = event.attributes.Name
			memberstore[ refid ].steamid = event.attributes.SteamId
			memberstore[ refid ].is_admin = is_admin(event.attributes.SteamId)
			memberstore[ refid ].host = false
			memberstore[ refid ].is_better_host = false
			memberstore[ refid ].ping_count = 0
			memberstore[ refid ].ping_min = 999
			memberstore[ refid ].ping_max = 0
			memberstore[ refid ].ping_avg = 999
			memberstore[ refid ].ping_sum = 0
			memberstore[ refid ].warnings = 0		
			memberstore[ refid ].rejoin_exit_count = 0
			memberstore[ refid ].jointime = event.time
			-- dump(event)
			output_to_data_file()
			
		end
		if event.type == "Player" and event.name == "PlayerLeft" then
			member_count = member_count - 1
			local refid = event.refid
			memberstore[refid] = nil
			member_jointime[ refid ] = nil
			if previous_better_host == refid then
				previous_better_host_name = 'None'
				previous_better_host = 'None'
			end
			if better_host == refid then
				better_ping = nil
				better_host_jointime = nil
				better_host_name = nil
			end
			if member_count > 0 then			
				rejoin_members_to_go_count()
				rejoin_members_to_go_names()
			end
						
		end
		if callback == Callback.HostMigrated then
			local migration = ...
			if debug then
				print(timestamp() ..  "HostMigration: " ) 
				dump( migration, "  " )
			end
		end
	end
end
SavePersistentData()


RegisterCallback( addon_callback )
EnableCallback( Callback.Tick )
EnableCallback( Callback.MemberAttributesChanged )
EnableCallback( Callback.EventLogged )
EnableCallback( Callback.SessionAttributesChanged )
EnableCallback( Callback.HostMigrated )

-- EOF --
