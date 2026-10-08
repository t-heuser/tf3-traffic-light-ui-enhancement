-- Stores user-defined traffic light phase names in the savegame.
-- The engine's TrafficLightState has no name field, so names live here, keyed by node entity and phase index.
-- The GUI (ui_enhancement.script.tl) sends the complete name list of a node after every rename/move/insert/remove.

local record PhaseNamesState
	nodes : {string : {string}} -- tostring(node entity) -> names by phase index ("" = unnamed)
end

local EVENT_ID = "TrafficLightUiEnhancement"
local EVENT_SET_NAMES = "tlueSetNames"

local record SetNamesParam
	node : integer
	names : {string}
end

local phaseNamesScript : GameScript<PhaseNamesState> = {
	update = function(_userParams : table, state : GameScriptState<PhaseNamesState>, _dt : number) : any
		if not state:hasEventSubscriptions() then
			state:subscribeToEvent(EVENT_SET_NAMES)
		end
	end,

	handleEvent = function(_userParams : table, state : GameScriptState<PhaseNamesState>, _src : string, id : string, name : string, param : SetNamesParam) : any
		if id ~= EVENT_ID or name ~= EVENT_SET_NAMES or param == nil or param.node == nil then
			return
		end

		local s = state:get() or {}
		s.nodes = s.nodes or {}

		local names : {string} = {}
		local any = false
		for i, n in ipairs(param.names or {}) do
			names[i] = n
			if n ~= "" then any = true end
		end
		s.nodes[tostring(param.node)] = any and names or nil

		state:set(s)
	end,
}

return phaseNamesScript
