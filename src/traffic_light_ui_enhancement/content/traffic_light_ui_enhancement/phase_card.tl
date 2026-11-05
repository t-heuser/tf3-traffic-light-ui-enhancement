-- traffic_light_ui_enhancement: one phase card of the phase list (header with buttons, edit rows, progress bar).
-- Moved out of the base TrafficLightConfigWidget; a plain function, not a recipe, so it has no state of its own and the
-- stylesheet rules for TlueTrafficLightConfigWidget apply as before. All changes go through the callbacks in `ctx`.
-- Used by ui_enhancement.script.tl; the PhaseCard and PhaseCardContext records there must match the ones below.

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil

local record IntInput
	make : function(value : integer, min : integer, max : integer, enabled : boolean, onChange : function(integer)) : TreeNodeId
end
local int_input = ug_require "traffic_light_ui_enhancement_1::/traffic_light_ui_enhancement/int_input.tl" as IntInput

local record PhaseCardContext
	numPhases : integer
	numLockable : integer -- lane connections + crosswalks
	activeIndex : integer -- 1-based index of the running phase
	progress : number -- of the running phase, 0..1
	editMode : boolean
	selectedIndex : integer
	isGamepad : boolean
	getName : function(k : integer) : string -- "" = unnamed
	select : function(k : integer) -- gamepad focus
	toggleEdit : function(k : integer) -- click on the card
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

local function defaultName(k : integer) : string
	return lang_util.format(_("Phase #{number}"), {
		number = tostring(k),
	})
end

local phase_card : PhaseCard = {
	make = function(ctx : PhaseCardContext, k : integer, state : Engine.Component.TrafficLightState) : TreeNodeId
		local isPausePhase = #state.lockedLanes == ctx.numLockable
		local thisIsEdited = ctx.editMode and k == ctx.selectedIndex
		local isActive = k == ctx.activeIndex
		local name = ctx.getName(k)

		return builtin.Button{
			meta = {
				class = "state-box, " .. (thisIsEdited and "selected" or isActive and "active" or "unselected"),
				onFocusChange = ctx.isGamepad and function(focused : boolean)
					if focused then
						ctx.select(k)
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
										class = isActive and "visible" or "hidden"
									},
								},
								builtin.TextView{
									-- traffic_light_ui_enhancement: show the custom name if set
									text = name ~= ""
										and lang_util.format(_("tlue_phase_title_named"), {
											number = tostring(k),
											name = name,
										})
										or defaultName(k),
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
										tooltip = _("tlue_move_phase_up"),
									},
									content = builtin.ImageView{
										path = "::/gui/camera_tool/icons/up_thin.tga",
									},
									onClick = function()
										ctx.move(k, k - 1)
									end
								},
								builtin.Button{
									meta = {
										enabled = k < ctx.numPhases,
										tooltip = _("tlue_move_phase_down"),
									},
									content = builtin.ImageView{
										path = "::/gui/camera_tool/icons/down_thin.tga",
									},
									onClick = function()
										ctx.move(k, k + 1)
									end
								},
								builtin.Button{
									meta = {
										tooltip = _("tlue_insert_phase_below"),
									},
									content = builtin.ImageView{
										path = "::/gui/line_vehicle_mgmt/icons/add.tga",
									},
									onClick = function()
										ctx.insertBelow(k)
									end
								},
								builtin.Button{
									meta = {
										enabled = not isPausePhase,
										tooltip = _("Set All to Red"),
									},
									content = builtin.ImageView{
										path = "::/gui/entity_window/icons/stop.tga",
									},
									onClick = function()
										ctx.setAllRed(k)
									end
								},
								builtin.Button{
									meta = {
										enabled = ctx.numPhases > 1,
										tooltip = _("Remove Phase")
									},
									content = builtin.ImageView{
										path = "::/gui/entity_window/icons/symbol_trash_bin.tga",
									},
									onClick = function()
										ctx.remove(k)
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
									text = _("tlue_phase_name_label")
								},
								builtin.TextInputField{
									meta = {
										class = "font-scale-body, phase-name",
									},
									value = name,
									placeholderText = defaultName(k),
									maxLength = 40,
									onValueChange = function(text : string)
										local trimmed = text:match("^%s*(.-)%s*$")
										if trimmed ~= ctx.getName(k) then
											ctx.rename(k, trimmed)
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
								int_input.make(math.floor(state.duration), 1, 999, true, function(value : integer)
									ctx.update(k, function(s : Engine.Component.TrafficLightState)
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
										ctx.update(k, function(s : Engine.Component.TrafficLightState)
											s.canSkip = val == 1
										end)
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
								int_input.make(math.floor(state.minDuration), 0, math.floor(state.duration), state.canSkip, function(value : integer)
									ctx.update(k, function(s : Engine.Component.TrafficLightState)
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
								class = (isActive and "visible" or "hidden") .. ", font-scale-annotation",
							},
							value = ctx.progress,
						},
					},
				}
			},
			onClick = not ctx.isGamepad and function()
				ctx.toggleEdit(k)
			end or nil,
		}
	end,
}

return phase_card
