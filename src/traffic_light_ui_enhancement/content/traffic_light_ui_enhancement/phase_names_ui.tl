-- traffic_light_ui_enhancement: GUI side of the phase names stored by phase_names.script.tl in the savegame.
-- Used by ui_enhancement.script.tl; the PhaseNamesUi record there must match the one below.

local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil

-- must match phase_names.script.tl
local PHASE_NAMES_SCRIPT = "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/phase_names.gs"
local PHASE_NAMES_EVENT_ID = "TrafficLightUiEnhancement"
local PHASE_NAMES_EVENT_SET = "tlueSetNames"

local record PhaseNamesState
	nodes : {string : {string}}
end

local function namesEqual(a : {string}, b : {string}) : boolean
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local record PhaseNamesUi
	use : function(node : Engine.Entity) : ReactStateT<{string}>
	send : function(node : Engine.Entity, names : {string}, n : integer)
end

local phase_names_ui : PhaseNamesUi = {
	-- hook: the names of `node` by phase index ("" = unnamed), refreshed every step
	use = function(node : Engine.Entity) : ReactStateT<{string}>
		local names = engine_react_util.useStepState(function() : {string}
			local scriptEntity = api.engine.system.gameScriptSystem.getEntityForGameScript(PHASE_NAMES_SCRIPT)
			if not scriptEntity then
				return {}
			end
			local gameScript = api.engine.getComponent(scriptEntity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<PhaseNamesState>
			if not gameScript then
				return {}
			end
			-- read only this node's entry natively instead of copying the whole state (`.state`) every step;
			-- same pattern as the base game's town_cargo_util.getTownCargoState
			local stateNative = gameScript.state_native
			if stateNative then
				local namesNative = stateNative:findPath({"nodes", tostring(node)}) as NativeLuaTable
				return namesNative and namesNative:asTable() as {string} or {}
			end
			local s = gameScript.state
			local list = s and s.nodes and s.nodes[tostring(node)]
			return list and table_util.copy(list) or {}
		end, nil, namesEqual)
		return names
	end,

	-- send the complete name list for `node`; `n` = number of phases the list must cover
	send = function(node : Engine.Entity, names : {string}, n : integer)
		local list : {string} = {}
		for i = 1, n do
			list[i] = names[i] or ""
		end
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", PHASE_NAMES_EVENT_ID, PHASE_NAMES_EVENT_SET, {
			node = node,
			names = list,
		}))
	end,
}

return phase_names_ui
