-- traffic_light_ui_enhancement: whole-number input field with +1 / -1 buttons and mouse wheel, clamped to [min, max].
-- A recipe of its own so it can have its own mouse listener (the base Slider it replaces reacted to the wheel).
-- Used by phase_card.tl; the IntInput record there must match the one below.

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local react = ug_require "::/gui/main/react.lua" as React

local record IntInputParam
	value : integer
	min : integer
	max : integer
	enabled : boolean
	onChange : function(integer)
end

local IntInputRecipe = react.RegisterRecipe("TlueIntInput", function(param : IntInputParam) : TreeNodeId
	local value, min, max, enabled = param.value, param.min, param.max, param.enabled

	-- Wheel ticks are collected locally and committed once the wheel has been idle for WHEEL_IDLE_TICKS * WHEEL_TICK_SECONDS,
	-- because every commit rebuilds the traffic light config in the engine and a fast scroll made the game stutter.
	-- The ref holds the pending value right away (several wheel events can arrive within one frame), the state only re-renders.
	local WHEEL_TICK_SECONDS = 0.1
	local WHEEL_IDLE_TICKS = 5
	local pendingRef = react.useRef(nil) as ReactRefT<integer>
	local pendingState = react.useState(nil) as ReactStateT<integer>
	local idleTicksRef = react.useRef(0) as ReactRefT<integer>
	local onChangeRef = react.useRef(nil) as ReactRefT<function(integer)>
	onChangeRef:set(param.onChange)

	local shown = pendingState:old() or value

	local function clamp(v : integer) : integer
		if v < min then v = min end
		if v > max then v = max end
		return v
	end

	local function setPending(v : integer)
		pendingRef:set(v)
		pendingState:set(v)
	end

	-- immediate commit (typing, +1 / -1 buttons, wheel flush); drops any pending wheel value
	local function set(v : integer)
		v = clamp(v)
		setPending(nil)
		if v ~= value then
			onChangeRef:get()(v)
		end
	end

	-- onStepTimer callbacks run deferred with a restricted API (sendCommand throws "API is currently restricted"),
	-- so the timer only counts idle ticks and the commit happens in onStep (like the base game's construction param queue)
	react.onStepTimer(function()
		if pendingRef:get() ~= nil then
			idleTicksRef:set(idleTicksRef:get() + 1)
		end
	end, WHEEL_TICK_SECONDS)

	react.onStep(function()
		if pendingRef:get() ~= nil and idleTicksRef:get() >= WHEEL_IDLE_TICKS then
			set(pendingRef:get())
		end
	end)

	-- wheel up = +1, wheel down = -1; handled so the surrounding scroll area does not scroll as well
	react.onMouseEvent(function(evt : Gui.Mouse.Event) : boolean
		if enabled and not evt.handled and evt.type == api.gui.mouse.Event.Type.Wheel and evt.yrel ~= 0 then
			setPending(clamp((pendingRef:get() or value) + (evt.yrel > 0 and 1 or -1)))
			idleTicksRef:set(0)
			return true
		end
		return false
	end)

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.TextInputField{
				meta = {
					class = "font-scale-body, no-clear-button",
					enabled = enabled,
				},
				value = tostring(shown),
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
					enabled = enabled and shown < max,
					tooltip = _("tlue_plus_one_second"),
					class = "tlue-step",
				},
				content = builtin.ImageView{
					path = "::/gui/camera_tool/icons/up_thin.tga",
				},
				onClick = function()
					set(shown + 1)
				end
			},
			builtin.Button{
				meta = {
					enabled = enabled and shown > min,
					tooltip = _("tlue_minus_one_second"),
					class = "tlue-step",
				},
				content = builtin.ImageView{
					path = "::/gui/camera_tool/icons/down_thin.tga",
				},
				onClick = function()
					set(shown - 1)
				end
			},
		}
	}
end)

local record IntInput
	make : function(value : integer, min : integer, max : integer, enabled : boolean, onChange : function(integer)) : TreeNodeId
end

local int_input : IntInput = {
	make = function(value : integer, min : integer, max : integer, enabled : boolean, onChange : function(integer)) : TreeNodeId
		return IntInputRecipe({ value = value, min = min, max = max, enabled = enabled, onChange = onChange })
	end,
}

return int_input
