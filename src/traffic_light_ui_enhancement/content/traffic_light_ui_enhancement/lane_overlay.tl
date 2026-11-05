-- traffic_light_ui_enhancement: red/green lane overlay of the selected phase, moved unchanged out of the base
-- TrafficLightConfigWidget. Used by ui_enhancement.script.tl; the LaneOverlay record there must match the one below.

local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil

local defaultColors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as DefaultColors
local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as GResTransparency

local record LaneOverlay
	build : function(selectedState : Engine.Component.TrafficLightState, numLanes : integer, numCrosswalks : integer, hoveredLane : integer) : {NodeViewerData}
end

local lane_overlay : LaneOverlay = {
	-- NodeViewer config for the lanes (0-based: lane connections, then crosswalks); empty without a selected phase
	build = function(selectedState : Engine.Component.TrafficLightState, numLanes : integer, numCrosswalks : integer, hoveredLane : integer) : {NodeViewerData}
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

		local nodeConfigForEntity : {NodeViewerData} = {}
		if selectedState then
			for vehicleLane = 1, numLanes do
				local lane = vehicleLane - 1

				local locked = table_util.arrayFind(selectedState.lockedLanes, lane) > 0
				if hoveredLane == lane then
					hoverLane.edgeIdx = lane
					table.insert(nodeConfigForEntity, hoverLane:clone())
				else
					local config = locked and lockedLane or unlockedLane
					config.edgeIdx = lane
					table.insert(nodeConfigForEntity, config:clone())
				end
			end
			for crosswalk = 1, numCrosswalks do
				local lane = crosswalk - 1 + numLanes

				local locked = table_util.arrayFind(selectedState.lockedLanes, lane) > 0
				-- base game uses the vehicle hover style for crosswalks too (its hoverLanePed was unused)
				if hoveredLane == lane then
					hoverLane.edgeIdx = lane
					table.insert(nodeConfigForEntity, hoverLane:clone())
				else
					local config = locked and lockedLanePed or unlockedLanePed
					config.edgeIdx = lane
					table.insert(nodeConfigForEntity, config:clone())
				end
			end
		end
		return nodeConfigForEntity
	end,
}

return lane_overlay
