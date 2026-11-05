-- Fork of the base game's TrafficLightConfigWidget (::/gui/entity_window/double_slip_switch.tl, TF3 as of 2026-10)
-- with move up/down and insert-below buttons per phase and whole-number duration inputs. Changes are marked with "traffic_light_ui_enhancement:".
-- traffic_light_ui_enhancement: parts live in their own modules (records below must match them):
--   phase_card.tl (one card of the phase list, uses int_input.tl), lane_overlay.tl (red/green lane overlay),
--   phase_names_ui.tl (phase names in the savegame), phase_clipboard.tl (copy & paste).

local app_util = ug_require "::/scripts/app_util.tl" as AppUtil
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local react = ug_require "::/gui/main/react.lua" as React
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl" as GuiReactUtil
local view_manager_util = ug_require "::/gui/entity_window/view_manager_util.tl" as ViewManagerUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil

local selectionGres = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/selection_colors.gres")).data as SelectionGuiConfig

local record PhaseCardContext
	numPhases : integer
	numLockable : integer
	activeIndex : integer
	progress : number
	editMode : boolean
	selectedIndex : integer
	isGamepad : boolean
	getName : function(k : integer) : string
	select : function(k : integer)
	toggleEdit : function(k : integer)
	move : function(k : integer, to : integer)
	insertBelow : function(k : integer)
	setAllRed : function(k : integer)
	remove : function(k : integer)
	rename : function(k : integer, name : string)
	update : function(k : integer, fn : function(Engine.Component.TrafficLightState))
end
local record PhaseCard
	make : function(ctx : PhaseCardContext, k : integer, state : Engine.Component.TrafficLightState) : TreeNodeId
end
local phase_card = ug_require "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/phase_card.tl" as PhaseCard

local record LaneOverlay
	build : function(selectedState : Engine.Component.TrafficLightState, numLanes : integer, numCrosswalks : integer, hoveredLane : integer) : {NodeViewerData}
end
local lane_overlay = ug_require "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/lane_overlay.tl" as LaneOverlay

local record PhaseNamesUi
	use : function(node : Engine.Entity) : ReactStateT<{string}>
	send : function(node : Engine.Entity, names : {string}, n : integer)
end
local phase_names_ui = ug_require "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/phase_names_ui.tl" as PhaseNamesUi

local record PhaseClipboard
	phaseCount : function() : integer
	copy : function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}, states : {Engine.Component.TrafficLightState}, names : {string}) : string
	paste : function(node : Engine.Entity, lanes : {{number, number, number, number}}, crosswalks : {Engine.Entity}) : {Engine.Component.TrafficLightState}, {string}, string
end
local phase_clipboard = ug_require "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/phase_clipboard.tl" as PhaseClipboard

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
	local phaseNames = phase_names_ui.use(param.keyEntity)

	local function getPhaseName(k : integer) : string
		return phaseNames:old()[k] or ""
	end

	-- send the complete name list for this node; `n` = number of phases the list must cover
	local function setPhaseNames(names : {string}, n : integer)
		phase_names_ui.send(param.keyEntity, names, n)
	end

	local function currentPhaseNames() : {string}
		local names : {string} = {}
		for i = 1, #stateData:old().trafficLightConfig.states do
			names[i] = getPhaseName(i)
		end
		return names
	end

	local numLanes = #stateData:old().allLaneConnections
	local numCrosswalks = #stateData:old().crosswalks

	local selectedIndexForEdit = currentState:old()
		and (editMode:old() and (selectedIndex:old() >= 1 and selectedIndex:old() or 1) or (currentState:old()[1] + 1))
		or nil
	local selectedState = (selectedIndexForEdit and #stateData:old().trafficLightConfig.states > 0)
			and stateData:old().trafficLightConfig.states[selectedIndexForEdit]
			or nil

	local nodeConfigForEntity = lane_overlay.build(selectedState, numLanes, numCrosswalks, hoveredIndex:old())

	-- all lanes and crosswalks locked, 0-based
	local function allLanesLocked() : {integer}
		local lockedLanes = {}
		for i = 1, numCrosswalks + numLanes do
			table.insert(lockedLanes, i - 1)
		end
		return lockedLanes
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

	-- traffic_light_ui_enhancement: "Set All to Red" locks all lanes of phase `k` only. The base game wrote to the
	-- selected phase instead and replaced every other phase with a copy of phase `k`.
	local function setAllRed(k : integer)
		local newBaseNodeState = table_util.copy(stateData:old())

		local newStates = newBaseNodeState.trafficLightConfig.states
		newStates[k].lockedLanes = allLanesLocked()
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)
	end

	local function removePhase(k : integer)
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

	local function addPhase()
		local newBaseNodeState = table_util.copy(stateData:old())

		local newStates = newBaseNodeState.trafficLightConfig.states

		local tls = api.type.TrafficLightState.new()
		tls.lockedLanes = allLanesLocked()
		table.insert(newStates, tls)
		newBaseNodeState.trafficLightConfig.states = newStates

		commit(newBaseNodeState)

		if editMode:old() then
			selectedIndex:set(#newBaseNodeState.trafficLightConfig.states)
		end
	end

	local function resetToDefault()
		local newBaseNodeState = table_util.copy(stateData:old())

		newBaseNodeState.trafficLightConfig.states = {}

		commit(newBaseNodeState)

		-- traffic_light_ui_enhancement: default phases get default names
		setPhaseNames({}, 0)
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
		tls.lockedLanes = allLanesLocked()

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

	-- traffic_light_ui_enhancement: copy & paste of the phase setup (see phase_clipboard.tl)
	local pasteMessage = react.useState(nil) as ReactStateT<string>

	local function copySetup()
		pasteMessage:set(phase_clipboard.copy(param.keyEntity, stateData:old().allLaneConnections, stateData:old().crosswalks,
			stateData:old().trafficLightConfig.states, currentPhaseNames()))
	end

	local function pasteSetup()
		local states, names, message = phase_clipboard.paste(param.keyEntity, stateData:old().allLaneConnections, stateData:old().crosswalks)
		pasteMessage:set(message)
		if not states then return end

		local newBaseNodeState = table_util.copy(stateData:old())
		newBaseNodeState.trafficLightConfig.states = states
		commit(newBaseNodeState)

		setPhaseNames(names, #states)
		selectedIndex:set(1)
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
		local cardContext : PhaseCardContext = {
			numPhases = #stateData:old().trafficLightConfig.states,
			numLockable = numCrosswalks + numLanes,
			activeIndex = currentState:old()[1] + 1,
			progress = currentState:old()[3] or 0.0,
			editMode = editMode:old(),
			selectedIndex = selectedIndex:old(),
			isGamepad = isGamepadState:old(),
			getName = getPhaseName,
			select = function(k : integer)
				selectedIndex:set(k)
				editMode:set(true)
			end,
			toggleEdit = function(k : integer)
				selectedIndex:set(k)
				if selectedIndex:old() == k then
					editMode:set(not editMode:old())
				else
					editMode:set(true)
				end
			end,
			move = movePhase,
			insertBelow = insertPhaseBelow,
			setAllRed = setAllRed,
			remove = removePhase,
			rename = function(k : integer, name : string)
				local names = currentPhaseNames()
				names[k] = name
				setPhaseNames(names, #names)
			end,
			update = updatePhase,
		}
		for k, state in ipairs(stateData:old().trafficLightConfig.states) do
			table.insert(states, phase_card.make(cardContext, k, state))
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
						onClick = addPhase,
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
						onClick = resetToDefault,
						content = builtin.TextView{
							meta = {
								class = "font-scale-body",
							},
							text = _("Reset to Default"),
						}
					},
				},
			} or nil,
			-- traffic_light_ui_enhancement: copy & paste the phase setup to another intersection, in a row of their own
			-- so the row above keeps its width
			currentState:old() and builtin.BoxLayout {
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					builtin.Button{
						meta = {
							class = "secondary",
							tooltip = _("tlue_copy_tooltip"),
						},
						onClick = copySetup,
						content = builtin.TextView{
							meta = {
								class = "font-scale-body",
							},
							text = _("Copy"),
						}
					},
					builtin.Button{
						meta = {
							class = "secondary",
							enabled = phase_clipboard.phaseCount() > 0,
							tooltip = phase_clipboard.phaseCount() > 0
								and lang_util.format(_("tlue_paste_tooltip"), { count = tostring(phase_clipboard.phaseCount()) })
								or _("tlue_paste_tooltip_empty"),
						},
						onClick = pasteSetup,
						content = builtin.TextView{
							meta = {
								class = "font-scale-body",
							},
							text = _("Paste"),
						}
					},
					gui_react_util.makeHorizontalSpacer(),
				},
			} or nil,
			-- traffic_light_ui_enhancement: result of the last copy / paste
			(currentState:old() and pasteMessage:old()) and builtin.TextView{
				meta = {
					class = "font-scale-annotation, tlue-message",
				},
				text = pasteMessage:old(),
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
	-- CallOriginalRecipe yields a recipe node, not a layout, so it needs a layout wrapper
	return builtin.BoxLayout {
		orientation = builtin.type.Orientation.Vertical,
		children = {
			react.CallOriginalRecipe(DoubleSlipSwitchContent, param)
		},
	}
end)

local ui_enhancement = {}

-- referenced by ui_enhancement.res.lua
ui_enhancement.doReplace = function(replacementApi : ReactReplacementApi)
	replacementApi.ReplaceRecipe(DoubleSlipSwitchContent, UiEnhancementContent)
end

return ui_enhancement
