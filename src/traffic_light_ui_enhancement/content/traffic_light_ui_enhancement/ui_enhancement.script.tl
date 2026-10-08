-- Fork of the base game's TrafficLightConfigWidget (::/gui/entity_window/double_slip_switch.tl, TF3 as of 2026-10)
-- with move up/down and insert-below buttons per phase and whole-number duration inputs. Changes are marked with "traffic_light_ui_enhancement:".

local app_util = ug_require "::/scripts/app_util.tl" as AppUtil
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local react = ug_require "::/gui/main/react.lua" as React
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl" as GuiReactUtil
local view_manager_util = ug_require "::/gui/entity_window/view_manager_util.tl" as ViewManagerUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil

local defaultColors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as DefaultColors
local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as GResTransparency
local selectionGres = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/selection_colors.gres")).data as SelectionGuiConfig

-- traffic_light_ui_enhancement: must match phase_names.script.tl
local PHASE_NAMES_SCRIPT = "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/phase_names.gs"
local PHASE_NAMES_EVENT_ID = "TrafficLightUiEnhancement"
local PHASE_NAMES_EVENT_SET = "tlueSetNames"

local record PhaseNamesState
	nodes : {string : {string}}
end

local TrafficLightConfigWidget = react.RegisterRecipe("TlueTrafficLightConfigWidget", function(param : IEntityWindowParam) : TreeNodeId
	local isGamepadState = engine_react_util.useStepState(app_util.isGamepadInputMode)
	local isValidHoveringState = react.useState(false) as ReactStateT<boolean>
	local editMode = react.useState(false) as ReactStateT<boolean>
	local selectedIndex = react.useState(1) as ReactStateT<integer>
	local hoveredIndex = react.useState(nil) as ReactStateT<integer>
	local currentState = engine_react_util.useStepState(function() : {integer, number, number}
		local baseNodeTrafficLight : Engine.Component.BaseNodeTrafficLight = api.engine.getComponent(param.keyEntity, api.type.ComponentType.BASE_NODE_TRAFFIC_LIGHT)
		if not baseNodeTrafficLight then
			return nil 
		end

		local baseNodeConfig : Engine.Component.BaseNodeConfig = api.engine.getComponent(param.keyEntity, api.type.ComponentType.BASE_NODE_CONFIG)
		local duration = baseNodeConfig.trafficLightConfig.states[baseNodeTrafficLight.state + 1].duration
		local progress = duration > 0 and baseNodeTrafficLight.time / duration or 0.0

		return {baseNodeTrafficLight.state, baseNodeTrafficLight.time, progress}
	end)

	local record BaseNodeState
		allLaneConnections : {{number, number, number, number}}
		crosswalks : {Engine.Entity}
		trafficLightConfig : Engine.Component.TrafficLightConfig
		trafficLightPreference : TrafficLightPreference
	end
	local makeData = function() : BaseNodeState
		local baseNodeConfig : Engine.Component.BaseNodeConfig = api.engine.getComponent(param.keyEntity, api.type.ComponentType.BASE_NODE_CONFIG)

		local allLanes = {}
		for __, v in ipairs(baseNodeConfig.laneConnections) do
			table.insert(allLanes, {v.segment0, v.lane0, v.segment1, v.lane1})
		end
		return {
			allLaneConnections = allLanes,
			crosswalks = baseNodeConfig.crosswalks,
			trafficLightConfig = baseNodeConfig.trafficLightConfig:clone(),
			trafficLightPreference = baseNodeConfig.trafficLightPreference
		}
	end

	local function makeCmd(baseNodeState : BaseNodeState) : Command<WorldBuildProposalCommandData>, nil
		local proposal = api.engine.util.proposal.createTrafficLightProposal(param.keyEntity, baseNodeState.trafficLightConfig, baseNodeState.trafficLightPreference)

		return api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true)
	end

	local stateData, commit = engine_react_util.useStepState(makeData, makeCmd)

	-- traffic_light_ui_enhancement: phase names, stored by phase_names.script.tl in the savegame
	local phaseNames = engine_react_util.useStepState(function() : {string}
		local scriptEntity = api.engine.system.gameScriptSystem.getEntityForGameScript(PHASE_NAMES_SCRIPT)
		if not scriptEntity then
			return {}
		end
		local gameScript = api.engine.getComponent(scriptEntity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<PhaseNamesState>
		local s = gameScript and gameScript.state
		local names = s and s.nodes and s.nodes[tostring(param.keyEntity)]
		return names and table_util.copy(names) or {}
	end, nil, function(a : {string}, b : {string}) : boolean
		if #a ~= #b then return false end
		for i = 1, #a do
			if a[i] ~= b[i] then return false end
		end
		return true
	end)

	local function getPhaseName(k : integer) : string
		return phaseNames:old()[k] or ""
	end

	-- send the complete name list for this node; `n` = number of phases the list must cover
	local function setPhaseNames(names : {string}, n : integer)
		local list : {string} = {}
		for i = 1, n do
			list[i] = names[i] or ""
		end
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", PHASE_NAMES_EVENT_ID, PHASE_NAMES_EVENT_SET, {
			node = param.keyEntity,
			names = list,
		}))
	end

	local function currentPhaseNames() : {string}
		local names : {string} = {}
		for i = 1, #stateData:old().trafficLightConfig.states do
			names[i] = getPhaseName(i)
		end
		return names
	end

	local selectedIndexForEdit = currentState:old()
		and (editMode:old() and (selectedIndex:old() >= 1 and selectedIndex:old() or 1) or (currentState:old()[1] + 1))
		or nil
	local selectedState = (selectedIndexForEdit and #stateData:old().trafficLightConfig.states > 0)
			and stateData:old().trafficLightConfig.states[selectedIndexForEdit]
			or nil

	local redPhaseColor = color_util.toVec4(defaultColors.Error)
	local greenPhaseColor = color_util.toVec4(defaultColors.Ok)
	local highlightColor = color_util.toVec4(defaultColors.NeutralLightest)

	local redPhaseColorFade = {
		redPhaseColor,
		color_util.withTransparency(defaultColors.Error, transparency.VeryHigh)
	}
	local greenPhaseColorFade = {
		greenPhaseColor,
		color_util.withTransparency(defaultColors.Ok, transparency.VeryHigh)
	}
	local highlightColorFade = {
		highlightColor,
		color_util.withTransparency(defaultColors.NeutralLightest, transparency.VeryHigh)
	}

	local lockedLane = api.type.NodeViewerData.new()
	lockedLane.colors = redPhaseColorFade
	lockedLane.order = 1
	lockedLane.width = 0.3
	local unlockedLane = api.type.NodeViewerData.new()
	unlockedLane.colors = greenPhaseColorFade
	unlockedLane.order = 0
	unlockedLane.width = 0.3
	local hoverLane = api.type.NodeViewerData.new()
	hoverLane.colors = highlightColorFade
	hoverLane.order = -1
	hoverLane.width = 0.6

	local lockedLanePed = api.type.NodeViewerData.new()
	lockedLanePed.colors = {redPhaseColor}
	lockedLanePed.order = 1
	lockedLanePed.width = 0.3
	local unlockedLanePed = api.type.NodeViewerData.new()
	unlockedLanePed.colors = {greenPhaseColor}
	unlockedLanePed.order = 0
	unlockedLanePed.width = 0.3
	local hoverLanePed = api.type.NodeViewerData.new()
	hoverLanePed.colors = {highlightColor}
	hoverLanePed.order = -1
	hoverLanePed.width = 0.6

	local nodeConfigForEntity : {NodeViewerData} = {}
	if selectedState then
		for vehicleLane, _ in ipairs(stateData:old().allLaneConnections) do
			local lane = vehicleLane - 1

			local locked = table_util.arrayFind(selectedState.lockedLanes, lane) > 0
			if hoveredIndex:old() == lane then
				hoverLane.edgeIdx = lane
				table.insert(nodeConfigForEntity, hoverLane:clone())
			else
				local config = locked and lockedLane or unlockedLane
				config.edgeIdx = lane
				table.insert(nodeConfigForEntity, config:clone())
			end
		end
		for crosswalk, _ in ipairs(stateData:old().crosswalks) do
			local lane = crosswalk - 1 + #stateData:old().allLaneConnections -- + #stateData:old().crosswalks * 3

			local locked = table_util.arrayFind(selectedState.lockedLanes, lane) > 0
			if hoveredIndex:old() == lane then
				hoverLane.edgeIdx = lane
				table.insert(nodeConfigForEntity, hoverLane:clone())
			else
				local config = locked and lockedLanePed or unlockedLanePed
				config.edgeIdx = lane
				table.insert(nodeConfigForEntity, config:clone())
			end
		end
	end

	local function toggleLane(lane : integer)
		local newBaseNodeState = table_util.copy(stateData:old())

		local newStates = {}
		for k2, state in ipairs(stateData:old().trafficLightConfig.states) do
			if k2 == selectedIndex:old() then
				local stateCopy = table_util.copy(state)
				local lockedLanes = table_util.copy(stateCopy.lockedLanes)
				local idx = table_util.arrayFind(stateCopy.lockedLanes, lane)
				if idx > 0 then
					lockedLanes = {}
					for __, l in ipairs(stateCopy.lockedLanes) do
						if l ~= lane then
							table.insert(lockedLanes, l)
						end
					end
				else
					table.insert(lockedLanes, lane)
				end

				stateCopy.lockedLanes = lockedLanes

				table.insert(newStates, stateCopy)
			else
				table.insert(newStates, table_util.copy(state))
			end
		end
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)
	end

	-- traffic_light_ui_enhancement: swap phase `k` with its neighbour `to`, keeping the edited phase selected
	local function movePhase(k : integer, to : integer)
		local newBaseNodeState = table_util.copy(stateData:old())

		local newStates = {}
		for __, state in ipairs(stateData:old().trafficLightConfig.states) do
			table.insert(newStates, table_util.copy(state))
		end
		newStates[k], newStates[to] = newStates[to], newStates[k]
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)

		local names = currentPhaseNames()
		if names[k] ~= names[to] then
			names[k], names[to] = names[to], names[k]
			setPhaseNames(names, #newStates)
		end

		if selectedIndex:old() == k then
			selectedIndex:set(to)
		elseif selectedIndex:old() == to then
			selectedIndex:set(k)
		end
	end

	-- traffic_light_ui_enhancement: insert a new all-red phase directly after phase `k` (same defaults as "Add Phase")
	local function insertPhaseBelow(k : integer)
		local newBaseNodeState = table_util.copy(stateData:old())

		local tls = api.type.TrafficLightState.new()
		local lockedLanes = {}
		for i = 1, #stateData:old().crosswalks + #stateData:old().allLaneConnections do
			table.insert(lockedLanes, i - 1)
		end
		tls.lockedLanes = lockedLanes

		local newStates = {}
		for k2, state in ipairs(stateData:old().trafficLightConfig.states) do
			table.insert(newStates, table_util.copy(state))
			if k2 == k then
				table.insert(newStates, tls)
			end
		end
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)

		local names = currentPhaseNames()
		table.insert(names, k + 1, "")
		setPhaseNames(names, #newStates)

		if editMode:old() then
			selectedIndex:set(k + 1)
		elseif selectedIndex:old() > k then
			selectedIndex:set(selectedIndex:old() + 1)
		end
	end

	-- traffic_light_ui_enhancement: change a single phase in place
	local function updatePhase(k : integer, fn : function(Engine.Component.TrafficLightState))
		local newBaseNodeState = table_util.copy(stateData:old())

		local newStates = newBaseNodeState.trafficLightConfig.states
		fn(newStates[k])
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)
	end

	-- traffic_light_ui_enhancement: whole-number input field with +1 / -1 buttons, clamped to [min, max]
	local function makeIntInput(value : integer, min : integer, max : integer, enabled : boolean, onChange : function(integer)) : TreeNodeId
		local function set(v : integer)
			if v < min then v = min end
			if v > max then v = max end
			if v ~= value then
				onChange(v)
			end
		end

		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.TextInputField{
					meta = {
						class = "font-scale-body, no-clear-button",
						enabled = enabled,
					},
					value = tostring(value),
					maxLength = 3,
					filter = function(text : string) : boolean
						return text:match("^%d*$") ~= nil
					end,
					onValueChange = function(text : string)
						local v = tonumber(text)
						if v then
							set(math.floor(v))
						end
					end,
					acceptOnFocusLoss = true,
				},
				builtin.Button{
					meta = {
						enabled = enabled and value < max,
						tooltip = _("+1 s"),
						class = "tlue-step",
					},
					content = builtin.ImageView{
						path = "::/gui/camera_tool/icons/up_thin.tga",
					},
					onClick = function()
						set(value + 1)
					end
				},
				builtin.Button{
					meta = {
						enabled = enabled and value > min,
						tooltip = _("-1 s"),
						class = "tlue-step",
					},
					content = builtin.ImageView{
						path = "::/gui/camera_tool/icons/down_thin.tga",
					},
					onClick = function()
						set(value - 1)
					end
				},
			}
		}
	end

	react.useInputAction("IA_OPTION2", react.iaHandler(function()
		if editMode:old() and hoveredIndex:old() ~= nil then
			toggleLane(hoveredIndex:old())
		end
	end, function() : boolean
		return isValidHoveringState:old()
	end))

	param.setActionFn(function() : TreeNodeId
		local children = {
			builtin.NodeViewer{
				nodeConfig = {
					[param.keyEntity] = nodeConfigForEntity
				},
			},
			builtin.Selector{
				onHover = function(entity : Engine.Entity, indices : {integer}, _details : Gui.SelectionDetails)
					if editMode:old() and entity == param.keyEntity then
						isValidHoveringState:set(true)
						hoveredIndex:set(indices[1])
					else
						isValidHoveringState:set(false)
						hoveredIndex:set(nil)
					end
				end,
				onSelect = function(entity : Engine.Entity, indices : {integer}, _details : Gui.SelectionDetails) : boolean
					if not editMode:old() then 
						return false
					end
					if entity == param.keyEntity then
						toggleLane(indices[1])
					end
					return true
				end,
				filter = function() : boolean
					return false
				end,
				selectionColor = color_util.toVec4(selectionGres.trafficLight.selectionColor),
				selectionOutlineColor = color_util.toVec4(selectionGres.trafficLight.selectionOutlineColor),
				selectionOutlineColor1 = color_util.toVec4(selectionGres.trafficLight.selectionOutlineColor),
			},
		}

		return builtin.ActionDescriptor{
			horizontalPromptList = true,
			children = children,
			terrainCirclePolicy = "Never",
			crosshair = true,
		}
	end, tostring(param.keyEntity))


	local states = {}
	if currentState:old() then
		for k, state in ipairs(stateData:old().trafficLightConfig.states) do
			local isPausePhase = #state.lockedLanes == #stateData:old().crosswalks + #stateData:old().allLaneConnections
			local thisIsEdited = editMode:old() and k == selectedIndex:old()
			table.insert(states, builtin.Button{
				meta = {
					class = "state-box, " .. (thisIsEdited and "selected" or k == (currentState:old()[1] + 1) and "active" or "unselected"),
					onFocusChange = isGamepadState:old() and function(focused : boolean)
						if focused then
							selectedIndex:set(k)
							editMode:set(true)
						end
					end or nil,
				},
				-- traffic_light_ui_enhancement: classes so the stylesheet can stretch the card rows without the descendant
				-- selectors ("!state-box BoxLayout") that also reach into the text input fields and clip their text
				content = builtin.Component{
					meta = { class = "tlue-card" },
					layout = builtin.BoxLayout{
						meta = { class = "tlue-card-layout" },
						orientation = builtin.type.Orientation.Vertical,
						children = {
							builtin.BoxLayout{
								meta = { class = "tlue-row" },
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.ImageView{
										path = "::/gui/music_player/icons/play.tga",
										meta = {
											class = k == (currentState:old()[1] + 1) and "visible" or "hidden"
										},
									},
									builtin.TextView{
										-- traffic_light_ui_enhancement: show the custom name if set
										text = getPhaseName(k) ~= ""
											and lang_util.format(_("#{number}: {name}"), {
												number = tostring(k),
												name = getPhaseName(k),
											})
											or lang_util.format(_("Phase #{number}"), {
												number = tostring(k),
											}),
										meta = {
											class = "font-scale-body",
										},
									},
									builtin.Component{
										meta = {
											class = "horizontal-spacer"
										}
									},
									-- traffic_light_ui_enhancement: move buttons
									builtin.Button{
										meta = {
											enabled = k > 1,
											tooltip = _("Move Phase Up"),
										},
										content = builtin.ImageView{
											path = "::/gui/camera_tool/icons/up_thin.tga",
										},
										onClick = function()
											movePhase(k, k - 1)
										end
									},
									builtin.Button{
										meta = {
											enabled = k < #stateData:old().trafficLightConfig.states,
											tooltip = _("Move Phase Down"),
										},
										content = builtin.ImageView{
											path = "::/gui/camera_tool/icons/down_thin.tga",
										},
										onClick = function()
											movePhase(k, k + 1)
										end
									},
									builtin.Button{
										meta = {
											tooltip = _("Insert Phase Below"),
										},
										content = builtin.ImageView{
											path = "::/gui/line_vehicle_mgmt/icons/add.tga",
										},
										onClick = function()
											insertPhaseBelow(k)
										end
									},
									-- builtin.Button{
									-- 	content = builtin.ImageView{
									-- 		path = "::/gui/entity_window/icons/symbol_wrench.tga",
									-- 		meta = {
									-- 			tooltip = _("Click to add or remove lanes from the phase"),
									-- 		},
									-- 	},
									-- 	onClick = function()
									-- 		selectedIndex:set(k)
									-- 		if selectedIndex:old() == k then
									-- 			editMode:set(not editMode:old())
									-- 		else
									-- 			editMode:set(true)
									-- 		end
									-- 	end
									-- },
									builtin.Button{
										meta = {
											enabled = not isPausePhase,
											tooltip = _("Set All to Red"),
										},
										content = builtin.ImageView{
											path = "::/gui/entity_window/icons/stop.tga",
										},
										onClick = function()
											local newBaseNodeState = table_util.copy(stateData:old())
								
											local newStates = {}
											for k2, _state in ipairs(stateData:old().trafficLightConfig.states) do
												if k2 == selectedIndex:old() then
													local stateCopy = table_util.copy(state)
													local lockedLanes = {}

													for vehicleLane, _ in ipairs(stateData:old().allLaneConnections) do
														local lane = vehicleLane - 1
														table.insert(lockedLanes, lane)
													end
													for crosswalk, _ in ipairs(stateData:old().crosswalks) do
														local lane = crosswalk - 1 + #stateData:old().allLaneConnections -- + #stateData:old().crosswalks * 3
														table.insert(lockedLanes, lane)
													end

													stateCopy.lockedLanes = lockedLanes

													table.insert(newStates, stateCopy)
												else
													table.insert(newStates, table_util.copy(state))
												end

											end
											newBaseNodeState.trafficLightConfig.states = newStates

											commit(newBaseNodeState)
										end
									},
									builtin.Button{
										meta = {
											enabled = #stateData:old().trafficLightConfig.states > 1,
											tooltip = _("Remove Phase")
										},
										content = builtin.ImageView{
											path = "::/gui/entity_window/icons/symbol_trash_bin.tga",
										},
										onClick = function()
											local newBaseNodeState = table_util.copy(stateData:old())
											
											local newStates = {}
											for k2, v2 in ipairs(stateData:old().trafficLightConfig.states) do
												if k2 ~= k then
													table.insert(newStates, table_util.copy(v2))
												end

											end
											newBaseNodeState.trafficLightConfig.states = newStates

											commit(newBaseNodeState)

											-- traffic_light_ui_enhancement: keep names aligned
											local names = currentPhaseNames()
											if names[k] ~= "" or #names > k then
												table.remove(names, k)
												setPhaseNames(names, #newStates)
											end
										end
									},
								}
							},
							-- traffic_light_ui_enhancement: rename the selected phase (empty = default name)
							thisIsEdited and builtin.BoxLayout{
								meta = { class = "tlue-row" },
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.TextView{
										meta = {
											class = "font-scale-body, duration",
										},
										text = _("Name:")
									},
									builtin.TextInputField{
										meta = {
											class = "font-scale-body, phase-name",
										},
										value = getPhaseName(k),
										placeholderText = lang_util.format(_("Phase #{number}"), {
											number = tostring(k),
										}),
										maxLength = 40,
										onValueChange = function(text : string)
											local trimmed = text:match("^%s*(.-)%s*$")
											if trimmed ~= getPhaseName(k) then
												local names = currentPhaseNames()
												names[k] = trimmed
												setPhaseNames(names, #names)
											end
										end,
										acceptOnFocusLoss = true,
									},
								}
							} or nil,
							thisIsEdited and builtin.BoxLayout{
								meta = { class = "tlue-row" },
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.TextView{
										meta = {
											class = "font-scale-body, duration",
										},
										text = _("Duration:")
									},
									-- traffic_light_ui_enhancement: whole-number input instead of slider
									makeIntInput(math.floor(state.duration), 1, 999, true, function(value : integer)
										updatePhase(k, function(s : Engine.Component.TrafficLightState)
											s.duration = value
										end)
									end),
									builtin.TextView{
										meta = {
											class = "sliderLabel, font-scale-annotation",
										},
										text = "s",
									}
								}
							} or nil,
							thisIsEdited and builtin.BoxLayout{
								meta = { class = "tlue-row" },
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.TextView{
										meta = {
											tooltip = _("Allows this phase to end early or be skipped entirely when these lanes are empty and traffic is waiting on another phase."),
											class = "font-scale-body, duration",
										},
										text = _("Allow Skipping"),
									},
									builtin.ToggleButtonGroup{
										buttons = {
											{
												content = builtin.TextView{
													text = _("Yes")
												},
											},
											{
												content = builtin.TextView{
													text = _("No")
												},
											}
										},
										onValueChange = function(val : integer)
											local newBaseNodeState = table_util.copy(stateData:old())
									
											local newStates = newBaseNodeState.trafficLightConfig.states
											newStates[k].canSkip = val == 1
											newBaseNodeState.trafficLightConfig.states = newStates

											commit(newBaseNodeState)
										end,
										selected = state.canSkip and 1 or 2,
									},
									-- traffic_light_ui_enhancement: spacer takes the free width so the toggle sits left, under the inputs
									builtin.Component{
										meta = {
											class = "horizontal-spacer"
										}
									},
								}
							} or nil,
							thisIsEdited and builtin.BoxLayout{
								meta = { class = "tlue-row" },
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.TextView{
										meta = {
											class = "font-scale-body, duration",
										},
										text = _("Min. Duration:")
									},
									-- traffic_light_ui_enhancement: whole-number input instead of slider, capped at the phase duration
									makeIntInput(math.floor(state.minDuration), 0, math.floor(state.duration), state.canSkip, function(value : integer)
										updatePhase(k, function(s : Engine.Component.TrafficLightState)
											s.minDuration = value
										end)
									end),
									builtin.TextView{
										meta = {
											class = "sliderLabel, font-scale-annotation",
										},
										text = "s",
									},
								}
							} or nil,
							builtin.ProgressBar{
								meta = {
									class = (k == (currentState:old()[1] + 1) and "visible" or "hidden") .. ", font-scale-annotation",
								},
								value = currentState:old() and currentState:old()[3] or 0.0,
							},
						},
					}
				},
				onClick = not isGamepadState:old() and function()
					selectedIndex:set(k)
					if selectedIndex:old() == k then
						editMode:set(not editMode:old())
					else
						editMode:set(true)
					end
				end or nil,
			})
		end
	end

	local trafficLightTypes = {}
	table.insert(trafficLightTypes, builtin.Button{
		content = builtin.ImageView{
			path = "::/infrastructure/traffic_light/traffic_light_non.tga",
			meta = { 
				class = "entry-icon",
				tooltip = pGetText("traffic-light-type", "None"),
			},
		},
		onClick = function()
			local newBaseNodeState = table_util.copy(stateData:old())
			
			newBaseNodeState.trafficLightPreference = api.type.enum.TrafficLightPreference.NO

			commit(newBaseNodeState)
		end
	})

	local yearState = engine_react_util.useStepState(function() : integer
		local gameTime : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
		local date = api.engine.util.getCalendarDate(gameTime.gameTime)
		return date.year
	end)

	for k, __ in pairs(api.res.trafficLightTypeRep.getAll()) do
		local tl = api.res.trafficLightTypeRep.get(k)
		local name = tl.description.name

		local yearFrom = tl.availability.yearFrom as integer
		local yearTo = tl.availability.yearTo as integer
		if (yearFrom == 0 or yearFrom <= yearState:old()) and (yearTo == 0 or yearState:old() < yearTo) then
			table.insert(trafficLightTypes, builtin.Button{
				content = builtin.ImageView{
					path = tl.description.icon,
					meta = { 
						class = "entry-icon",
						tooltip = name,
					},
				},
				onClick = function()
					local newBaseNodeState = table_util.copy(stateData:old())
					
					newBaseNodeState.trafficLightConfig.trafficLightType = k
					newBaseNodeState.trafficLightPreference = api.type.enum.TrafficLightPreference.YES

					commit(newBaseNodeState)
				end
			})
		end

	end
	
	local trafficLightTypeWidget = builtin.ScrollArea{
		content = builtin.Component{
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = trafficLightTypes
			}
		},
		meta = {
			-- class = "invisible"
		}
	}
	
	return builtin.BoxLayout {
		meta = {
			class = "traffic-light-widget-layout",
		},
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.ScrollArea{
				horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
				verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
				content = builtin.Component{
					layout = builtin.BoxLayout {
						meta = {
							class = "state-boxes-layout",
						},
						orientation = builtin.type.Orientation.Vertical,
						children = states,
					},
				},
			},
			currentState:old() and builtin.BoxLayout {
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					builtin.Button{
						meta = {
							class = "primary",
						},
						onClick = function() 
							local newBaseNodeState = table_util.copy(stateData:old())
							
							local newStates = newBaseNodeState.trafficLightConfig.states

							local tls = api.type.TrafficLightState.new()
							local lockedLanes = {}
							for i = 1, #stateData:old().crosswalks + #stateData:old().allLaneConnections do
								table.insert(lockedLanes, i - 1)
							end
							tls.lockedLanes = lockedLanes
							table.insert(newStates, tls)
							newBaseNodeState.trafficLightConfig.states = newStates

							commit(newBaseNodeState)

							if editMode:old() then
								selectedIndex:set(#newBaseNodeState.trafficLightConfig.states)
							end
						end,
						content = builtin.BoxLayout{
							orientation = builtin.type.Orientation.Horizontal,
							children = {
								content = builtin.ImageView{
									path = "::/gui/line_vehicle_mgmt/icons/add.tga",
								},
								builtin.TextView{
									meta = {
										class = "font-scale-body",
									},
									text = _("Add Phase"),
								}
							}
						},
					},
					gui_react_util.makeHorizontalSpacer(),
					builtin.Button{
						meta = {
							class = "secondary",
						},
						onClick = function() 
							local newBaseNodeState = table_util.copy(stateData:old())
							
							newBaseNodeState.trafficLightConfig.states = {}

							commit(newBaseNodeState)

							-- traffic_light_ui_enhancement: default phases get default names
							setPhaseNames({}, 0)
						end,
						content = builtin.TextView{
							meta = {
								class = "font-scale-body",
							},
							text = _("Reset to Default"),
						}
					},
				},
			} or nil,
			trafficLightTypeWidget,
		},
	}
end)

local DoubleSlipSwitchContent = ug_require "::/gui/entity_window/double_slip_switch.tl" as Recipe<IEntityWindowParam>

-- Same as the original DoubleSlipSwitchContent, but with the forked traffic light widget.
local UiEnhancementContent = react.RegisterRecipe("TlueDoubleSlipSwitchContent", function(param : IEntityWindowParam) : TreeNodeId
	if view_manager_util.baseNodeCanConfigTrafficLight(param.keyEntity) then
		return builtin.BoxLayout {
			orientation = builtin.type.Orientation.Vertical,
			children = {
				TrafficLightConfigWidget(param)
			},
		}
	end
	return react.CallOriginalRecipe(DoubleSlipSwitchContent, param)
end)

local ui_enhancement = {}

-- referenced by ui_enhancement.res.lua
ui_enhancement.doReplace = function(replacementApi : ReactReplacementApi)
	replacementApi.ReplaceRecipe(DoubleSlipSwitchContent, UiEnhancementContent)
end

return ui_enhancement
