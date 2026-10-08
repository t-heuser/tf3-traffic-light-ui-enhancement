-- Copy of the TrafficLightConfigWidget rules from ::/gui/entity_window/entity_window.css.lua, retargeted to the
-- forked recipe (selectors match recipe names, so the base rules do not apply to TlueTrafficLightConfigWidget).
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data

	a("!input-controller R::TlueTrafficLightConfigWidget", {
		actionPromptList = {
			{ia = "IA_OPTION2", text = _("Toggle Lane")},
		}
	})

	a("R::TlueTrafficLightConfigWidget !horizontal-spacer", {
		gravity = {-1, 0},
	})

	a([[R::TlueTrafficLightConfigWidget > BoxLayout,
		R::TlueTrafficLightConfigWidget BoxLayout!state-boxes-layout]], {
		innerSpacing = { 0, 8 },
	})

	a("R::TlueTrafficLightConfigWidget !state-box", {
		borderImage = {
			fileName = "::/gui/entity_window/design/card_contour.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/card_surface.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
		borderColor = colorDefault.NeutralDark,
		gravity = {-1, 0},
	})

	-- traffic_light_ui_enhancement: base used "!state-box R::Component" / "!state-box BoxLayout" (any depth) for this.
	-- Those also reach the internals of TextInputField and clip its text, so only the card's own containers are hit.
	a([[R::TlueTrafficLightConfigWidget !tlue-card,
		R::TlueTrafficLightConfigWidget !tlue-card-layout,
		R::TlueTrafficLightConfigWidget !tlue-row]], {
		gravity = {-1, 0},
	})
	
	a("R::TlueTrafficLightConfigWidget !entry-icon", {
		size = {60, 37},
	})

	a("R::TlueTrafficLightConfigWidget !state-box > BoxLayout", {
		innerSpacing = { 4, 4 },
		outerSpacing = { 4, 4 },
	})

	a("R::TlueTrafficLightConfigWidget !active", {
		borderColor = color_util.withTransparencyRaw(colorDefault.NeutralDarkest, transparency.Medium),
		backgroundColor1 = color_util.withTransparencyRaw(colorDefault.AccentDark, transparency.Medium),
	})

	a("R::TlueTrafficLightConfigWidget !selected", {
		borderColor = color_util.withTransparencyRaw(colorDefault.NeutralDarkest, transparency.Medium),
		backgroundColor1 = color_util.withTransparencyRaw(colorDefault.AccentLight, transparency.Medium),
	})

	-- traffic_light_ui_enhancement: scoped to the widget's own scroll areas (phase list, light types). The base
	-- selector "R::TrafficLightConfigWidget ScrollArea" also hits the scroll area inside text input fields and
	-- shrinks it, which clips the typed text.
	a("R::TlueTrafficLightConfigWidget !traffic-light-widget-layout > ScrollArea", {
		gravity = {-1, 0},
		maxSize = {-1, 508},
	})

	a("R::TlueTrafficLightConfigWidget !duration", {
		padding = {4, 4, 4, 28},
		minSize = {200, -1},
	})

	a("R::TlueTrafficLightConfigWidget !sliderLabel", {
		minSize = {50, -1},
	})

	-- traffic_light_ui_enhancement: base rule was "R::TrafficLightConfigWidget TextView" (any depth); limited to the
	-- label classes the widget uses.
	a([[R::TlueTrafficLightConfigWidget TextView!font-scale-body,
		R::TlueTrafficLightConfigWidget TextView!font-scale-annotation]], {
		padding = {4, 4, 4, 4},
	})

	a("R::TlueTrafficLightConfigWidget Button ImageView", {
		size = {24, 24},
	})

	a("R::TlueTrafficLightConfigWidget ProgressBar", {
		size = {-1, 6},
		margin = { 0, 4, 0, 4 },
		backgroundColor1 = color_util.withTransparencyRaw(colorDefault.AccentLight, transparency.Medium),

		-- size goes below 10, hence we have to adapt the mask
		backgroundImage1 = {
			fileName = "::/gui/builtin/button/compact_surface.tga",
			horizontal = { 0, 3, 9, 12 },
			vertical = { 0, 3, 9, 12 },
		},
		mask = {
			fileName = "::/gui/builtin/button/compact_surface.tga",
			horizontal = { 0, 3, 9, 12 },
			vertical = { 0, 3, 9, 12 },
		},
	})

	-- traffic_light_ui_enhancement: the +1/-1 buttons next to the inputs stay small like builtin buttons instead of the
	-- 24px header icons. The base ToggleButton(Group) rules are dropped so "Allow Skipping" keeps the builtin look too.
	a("R::TlueTrafficLightConfigWidget Button!tlue-step ImageView", {
		size = {16, 16},
	})

	-- traffic_light_ui_enhancement: input widths only, everything else stays at the builtin defaults
	a("R::TlueTrafficLightConfigWidget TextInputField", {
		minSize = {60, -1},
	})

	a("R::TlueTrafficLightConfigWidget TextInputField!phase-name", {
		minSize = {200, -1},
		gravity = {-1, 0.5},
	})

	return result
end
