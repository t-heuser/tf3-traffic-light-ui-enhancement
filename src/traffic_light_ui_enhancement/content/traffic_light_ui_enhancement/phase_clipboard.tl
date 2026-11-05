-- traffic_light_ui_enhancement: copy & paste of a traffic light phase setup between intersections.
-- Used by ui_enhancement.script.tl; the PhaseClipboard record there must match the one below.
--
-- lockedLanes are indices into the node's own lane connection list (+ crosswalks after them), so they cannot be copied
-- verbatim to another node. Each lane connection is described intersection-independently instead: the arms (road segments)
-- it connects, numbered by direction around the node, plus its rank among the lanes of the same arm pair.
-- Pasting aligns the arms of both nodes by the rotation that best matches their directions.

local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil

local record LaneKey
	armIn : integer
	armOut : integer
	rank : integer
end

local record NodeLayout
	armAngles : {number} -- pseudo angle in [0, 4) per arm, ascending
	laneKeys : {LaneKey} -- per lane connection (1-based)
	groups : {string : {integer}} -- "armIn:armOut" -> 0-based lane indices ordered by rank
	-- arm -> 0-based crosswalk lane indices. BaseNodeConfig.crosswalks is undocumented, but holds the crossed segments
	-- (seen in game, TF3 build 40425, 3- and 4-way crossings). nil if an entry is not one of the arm segments; pasting then
	-- falls back to matching crosswalks by index, kept in case other layouts (e.g. footpaths) behave differently.
	crosswalksByArm : {integer : {integer}}
end

local record ClipPhase
	lockedLanes : {integer}
	duration : number
	minDuration : number
	canSkip : boolean
end

local record Clipboard
	node : Engine.Entity
	phases : {ClipPhase}
	names : {string}
	numLanes : integer
	numCrosswalks : integer
	layout : NodeLayout -- nil if the geometry could not be read
end

-- lives as long as the GUI script (until the game is restarted), shared by all entity windows
local clipboard : Clipboard = nil

-- monotonic in the direction angle, range [0, 4); avoids atan2, whose Lua spelling depends on the Lua version
local function pseudoAngle(x : number, y : number) : number
	if x == 0 and y == 0 then return 0 end
	if y >= 0 then
		if x >= 0 then return y / (x + y) end
		return 1 - x / (-x + y)
	end
	if x < 0 then return 2 - y / (-x - y) end
	return 3 + x / (x - y)
end

-- wrap a pseudo angle difference to (-2, 2]
local function wrapAngle(d : number) : number
	d = d % 4
	if d > 2 then d = d - 4 end
	return d
end

-- throws if the engine data is not as expected; callers use pcall
local function computeLayout(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}) : NodeLayout
	local angleOf : {Engine.Entity : number} = {}
	local segs : {Engine.Entity} = {}

	local function addSeg(seg : Engine.Entity)
		if angleOf[seg] then return end
		local e = api.engine.getComponent(seg, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		assert(e, "segment " .. tostring(seg) .. " has no BASE_EDGE")
		-- direction pointing away from the node, as in view_manager_util
		if e.node0 == node then
			angleOf[seg] = pseudoAngle(e.tangent0.x, e.tangent0.y)
		elseif e.node1 == node then
			angleOf[seg] = pseudoAngle(-e.tangent1.x, -e.tangent1.y)
		else
			error("segment " .. tostring(seg) .. " does not end at node " .. tostring(node))
		end
		table.insert(segs, seg)
	end

	for __, l in ipairs(lanes) do
		addSeg(l[1] as Engine.Entity)
		addSeg(l[3] as Engine.Entity)
	end

	table.sort(segs, function(a : Engine.Entity, b : Engine.Entity) : boolean
		return angleOf[a] < angleOf[b]
	end)
	local armOf : {Engine.Entity : integer} = {}
	local armAngles : {number} = {}
	for i, seg in ipairs(segs) do
		armOf[seg] = i
		armAngles[i] = angleOf[seg]
	end

	-- lane0 / lane1 are already counted "from left to right when looking from the node to the segment" (LaneConnection docs),
	-- so they compare across nodes as they are
	local groups : {string : {integer}} = {}
	for i, l in ipairs(lanes) do
		local key = tostring(armOf[l[1] as Engine.Entity]) .. ":" .. tostring(armOf[l[3] as Engine.Entity])
		groups[key] = groups[key] or {}
		table.insert(groups[key], i - 1)
	end
	local laneKeys : {LaneKey} = {}
	for __, group in pairs(groups) do
		table.sort(group, function(a : integer, b : integer) : boolean
			local la, lb = lanes[a + 1], lanes[b + 1]
			if la[2] ~= lb[2] then return la[2] < lb[2] end
			return la[4] < lb[4]
		end)
		for rank, idx in ipairs(group) do
			local l = lanes[idx + 1]
			laneKeys[idx + 1] = { armIn = armOf[l[1] as Engine.Entity], armOut = armOf[l[3] as Engine.Entity], rank = rank }
		end
	end

	local crosswalksByArm : {integer : {integer}} = {}
	for c, cw in ipairs(crosswalks) do
		local arm = armOf[cw]
		if not arm then
			crosswalksByArm = nil
			break
		end
		crosswalksByArm[arm] = crosswalksByArm[arm] or {}
		table.insert(crosswalksByArm[arm], #lanes + c - 1)
	end

	return { armAngles = armAngles, laneKeys = laneKeys, groups = groups, crosswalksByArm = crosswalksByArm }
end

-- rotation r so that target arm i corresponds to source arm ((i - 1 + r) % n) + 1.
-- Picks the rotation whose per-arm angle differences are most uniform (same shape, possibly rotated);
-- ties (symmetric crossings) go to the smallest overall rotation.
local function findRotation(src : {number}, dst : {number}) : integer
	local n = #src
	local best, bestCost, bestOffset = 0, math.huge, math.huge
	for r = 0, n - 1 do
		local base = wrapAngle(dst[1] - src[(r % n) + 1])
		local diffs : {number} = {}
		local sum = 0.0
		for i = 1, n do
			diffs[i] = wrapAngle(dst[i] - src[((i - 1 + r) % n) + 1] - base)
			sum = sum + diffs[i]
		end
		local mean = sum / n
		local cost = 0.0
		for i = 1, n do
			cost = cost + math.abs(diffs[i] - mean)
		end
		local offset = math.abs(wrapAngle(base + mean))
		if cost < bestCost - 1e-3 or (cost < bestCost + 1e-3 and offset < bestOffset) then
			best, bestCost, bestOffset = r, cost, offset
		end
	end
	return best
end

local record PasteResult
	phases : {ClipPhase}
	unmatched : integer -- target lanes/crosswalks without a source counterpart (set to red)
end

-- map the clipboard's phases onto a target node; returns nil + reason if not possible
local function mapClipboard(clip : Clipboard, dstLayout : NodeLayout, numLanes : integer, numCrosswalks : integer) : PasteResult, string
	local srcLayout = clip.layout
	local useGeometry = srcLayout ~= nil and dstLayout ~= nil and #srcLayout.armAngles == #dstLayout.armAngles
	if not useGeometry and not (clip.numLanes == numLanes and clip.numCrosswalks == numCrosswalks) then
		return nil, _("tlue_paste_layout_differs")
	end

	local srcArmOf : {integer : integer} = {}
	if useGeometry then
		local n = #srcLayout.armAngles
		local r = findRotation(srcLayout.armAngles, dstLayout.armAngles)
		for i = 1, n do
			srcArmOf[i] = ((i - 1 + r) % n) + 1
		end
	end

	local unmatched = 0
	local srcIndexOf : {integer : integer} = {} -- 0-based target lane -> 0-based source lane (nil = no match)
	for j = 1, numLanes do
		if useGeometry then
			local key = dstLayout.laneKeys[j]
			local group = srcLayout.groups[tostring(srcArmOf[key.armIn]) .. ":" .. tostring(srcArmOf[key.armOut])]
			if group then
				srcIndexOf[j - 1] = group[math.min(key.rank, #group)]
			else
				unmatched = unmatched + 1
			end
		else
			srcIndexOf[j - 1] = j - 1
		end
	end

	if useGeometry and srcLayout.crosswalksByArm and dstLayout.crosswalksByArm then
		-- crosswalks by the arm they cross, several on one arm by order
		for arm, dstList in pairs(dstLayout.crosswalksByArm) do
			local srcList = srcLayout.crosswalksByArm[srcArmOf[arm]]
			for i, t in ipairs(dstList) do
				if srcList then
					srcIndexOf[t] = srcList[math.min(i, #srcList)]
				else
					unmatched = unmatched + 1
				end
			end
		end
	else
		-- fallback: by index when the counts agree
		for c = 1, numCrosswalks do
			if clip.numCrosswalks == numCrosswalks then
				srcIndexOf[numLanes + c - 1] = clip.numLanes + c - 1
			else
				unmatched = unmatched + 1
			end
		end
	end

	local phases : {ClipPhase} = {}
	for __, p in ipairs(clip.phases) do
		local srcLocked : {integer : boolean} = {}
		for __, l in ipairs(p.lockedLanes) do
			srcLocked[l] = true
		end
		local locked : {integer} = {}
		for t = 0, numLanes + numCrosswalks - 1 do
			local s = srcIndexOf[t]
			if s == nil or srcLocked[s] then
				table.insert(locked, t)
			end
		end
		table.insert(phases, { lockedLanes = locked, duration = p.duration, minDuration = p.minDuration, canSkip = p.canSkip })
	end
	return { phases = phases, unmatched = unmatched }
end

-- debug log, switched on by the mod parameter "debug_log" (mod.json); the parameters are fixed while a game runs
local MOD_ID = "traffic_light_ui_enhancement_1"
local LOG_PREFIX = "[traffic_light_ui_enhancement] "
local debugLogEnabled : boolean = nil

local function debugLog(message : string)
	if debugLogEnabled == nil then
		local ok, all = pcall(api.engine.config.getModParams)
		if not ok or not all then
			return -- not cached, try again next time
		end
		local params = all[MOD_ID] as {string : any}
		-- params come back as 1-based index into "values": 1 = Off, 2 = On
		debugLogEnabled = params ~= nil and params["debug_log"] == 2
	end
	if debugLogEnabled then
		print(LOG_PREFIX .. message)
	end
end

-- nil if the geometry cannot be read; pasting then falls back to matching by index
local function layoutOf(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}) : NodeLayout
	local ok, result = pcall(computeLayout, node, lanes, crosswalks)
	if not ok then
		debugLog("no lane geometry for node " .. tostring(node) .. ": " .. tostring(result))
		return nil
	end
	local layout = result as NodeLayout
	debugLog("node " .. tostring(node) .. ": " .. tostring(#layout.armAngles) .. " arms, "
		.. tostring(#lanes) .. " lanes, " .. tostring(#crosswalks) .. " crosswalks"
		.. (layout.crosswalksByArm and " (crosswalks matched by arm)" or " (crosswalks are not segments, matched by index)"))
	return layout
end

local record PhaseClipboard
	-- number of copied phases, 0 if nothing has been copied yet
	phaseCount : function() : integer
	-- copy a node's phases and names; returns a message for the UI
	copy : function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}, states : {Engine.Component.TrafficLightState}, names : {string}) : string
	-- phases and names for the given node, or nil if they do not fit; always returns a message for the UI
	paste : function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}) : {Engine.Component.TrafficLightState}, {string}, string
end

local phase_clipboard : PhaseClipboard = {
	phaseCount = function() : integer
		return clipboard and #clipboard.phases or 0
	end,

	copy = function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}, states : {Engine.Component.TrafficLightState}, names : {string}) : string
		local phases : {ClipPhase} = {}
		for __, state in ipairs(states) do
			local locked : {integer} = {}
			for __, l in ipairs(state.lockedLanes) do
				table.insert(locked, l)
			end
			table.insert(phases, { lockedLanes = locked, duration = state.duration, minDuration = state.minDuration, canSkip = state.canSkip })
		end
		clipboard = {
			node = node,
			phases = phases,
			names = names,
			numLanes = #lanes,
			numCrosswalks = #crosswalks,
			layout = layoutOf(node, lanes, crosswalks),
		}
		return lang_util.format(_("tlue_copied"), { count = tostring(#phases) })
	end,

	paste = function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}) : {Engine.Component.TrafficLightState}, {string}, string
		if not clipboard then
			return nil, nil, _("tlue_paste_tooltip_empty")
		end
		local result, err = mapClipboard(clipboard, layoutOf(node, lanes, crosswalks), #lanes, #crosswalks)
		if not result then
			return nil, nil, err
		end

		local states : {Engine.Component.TrafficLightState} = {}
		for __, p in ipairs(result.phases) do
			local tls = api.type.TrafficLightState.new()
			tls.lockedLanes = p.lockedLanes
			tls.duration = p.duration
			tls.minDuration = p.minDuration
			tls.canSkip = p.canSkip
			table.insert(states, tls)
		end

		local names : {string} = {}
		for i, n in ipairs(clipboard.names) do
			names[i] = n
		end

		local message = result.unmatched > 0
			and lang_util.format(_("tlue_pasted_unmatched"), {
				count = tostring(#states),
				unmatched = tostring(result.unmatched),
			})
			or lang_util.format(_("tlue_pasted"), { count = tostring(#states) })
		return states, names, message
	end,
}

return phase_clipboard
