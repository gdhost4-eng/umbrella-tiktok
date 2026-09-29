--[[
     ~ qLocalization
     ~ automatic localization wrapper for Lua menu interfaces

     ~ author: qfun (qfun_g9s)
]]

local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local localization = qLocalization.new({
	en = {
		tt_group_main = "Main",
		tt_group_window = "Window",
		tt_enable = "Enable",
		tt_enable_tip = "Shows the TikTok icon during the match",
		tt_key = "Open window",
		tt_key_tip = "Opens and closes the TikTok window",
		tt_bind_name = "TikTok",
		tt_icon = "Icon",
		tt_icon_tip = "Drag with the mouse, click to open",
		tt_gear_icon = "Icon",
		tt_icon_size = "Size",
		tt_icon_alpha = "Opacity",
		tt_hide_key = "Hide icon",
		tt_hide_key_tip = "Hides and shows the icon",
		tt_icon_reset = "Reset position",
		tt_width = "Width",
		tt_height = "Height",
		tt_win_alpha = "Opacity",
		tt_start_page = "Start page",
		tt_page_foryou = "For You",
		tt_page_following = "Following",
		tt_page_explore = "Explore",
		tt_auto_death = "Open on death",
		tt_auto_death_tip = "Opens the window when your hero dies",
		tt_gear_death = "On death",
		tt_death_delay = "Delay",
		tt_death_close = "Close on respawn",
		tt_death_close_tip = "Closes the window if it was opened on death",
		tt_win_reset = "Reset position",
		tt_title = "TikTok",
		tt_respawn = "Respawn in %d s",
	},
	ru = {
		tt_group_main = "Основное",
		tt_group_window = "Окно",
		tt_enable = "Включить",
		tt_enable_tip = "Показывает значок TikTok в матче",
		tt_key = "Открыть окно",
		tt_key_tip = "Открывает и закрывает окно TikTok",
		tt_bind_name = "TikTok",
		tt_icon = "Значок",
		tt_icon_tip = "Двигается мышью, по клику открывает окно",
		tt_gear_icon = "Значок",
		tt_icon_size = "Размер",
		tt_icon_alpha = "Прозрачность",
		tt_hide_key = "Скрыть значок",
		tt_hide_key_tip = "Прячет и возвращает значок",
		tt_icon_reset = "Сбросить позицию",
		tt_width = "Ширина",
		tt_height = "Высота",
		tt_win_alpha = "Прозрачность",
		tt_start_page = "Стартовая страница",
		tt_page_foryou = "Рекомендации",
		tt_page_following = "Подписки",
		tt_page_explore = "Интересное",
		tt_auto_death = "Открывать при смерти",
		tt_auto_death_tip = "Открывает окно, когда герой умер",
		tt_gear_death = "При смерти",
		tt_death_delay = "Задержка",
		tt_death_close = "Закрывать при возрождении",
		tt_death_close_tip = "Закрывает окно, если оно открылось само",
		tt_win_reset = "Сбросить позицию",
		tt_title = "TikTok",
		tt_respawn = "Возрождение через %d с",
	},
})

local UI = localization.WrapLibrary(Menu)
local L = localization.Get

local K = {
	VERSION = "1.0.1",
	CFG = "tiktok",
	PANEL_ID = "TikTokWebPanel",
	HIT_ID = "TikTokHit",
	URL_BASE = "https://www.tiktok.com/",
	URL_LOGIN = "https://www.tiktok.com/login/qrcode",
	URL_BLANK = "about:blank",
	PAGES = { "foryou", "following", "explore" },
	HUD_PARENTS = { "Hud", "DotaHud" },
	MENU_PARENTS = { "DotaDashboard", "Dashboard" },
	HEADER_H = 28,
	W_MIN = 300,
	W_MAX = 1400,
	H_MIN = 400,
	H_MAX = 1400,
	ZOOM_CVAR = "dota_camera_disable_zoom",
	GRIP = 16,
	DRAG_THRESHOLD = 4,
	DEATH_INTERVAL = 0.2,
	LOGO_PX = 128,
	TEXT = Color(235, 235, 240, 255),
	MUTED = Color(160, 160, 170, 255),
	HOVER = Color(255, 255, 255, 30),
}

K.LOGO_PATH = "M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"
K.LOGO_SVG = string.format([[<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1.5 -1.5 27 27">
<path transform="translate(-0.6,-0.6)" fill="#25F4EE" d="%s"/>
<path transform="translate(0.6,0.6)" fill="#FE2C55" d="%s"/>
<path fill="#FFFFFF" d="%s"/>
</svg>]], K.LOGO_PATH, K.LOGO_PATH, K.LOGO_PATH)
K.JS_WRAP = [[(function(){var PID='%s',ID='%s';var c=$.GetContextPanel();var r=c;while(r.GetParent())r=r.GetParent();var par=(c.id==PID)?c:((r.id==PID)?r:r.FindChildTraverse(PID));if(!par){$.Msg('[TikTok] parent not found');return;}var p=ID?par.FindChildTraverse(ID):null;%s})()]]
K.HIDDEN_STYLE = "x: -9999px; y: -9999px; width: 0px; height: 0px; visibility: collapse;"
K.JS_KILL = [[if(!p)return;if(p.SetURL)p.SetURL('about:blank');p.hittest=false;p.visible=false;p.DeleteAsync(0);]]
K.JS_CLEAN = [[var ch=par.Children();for(var i=0;i<ch.length;i++){var id=ch[i].id||'';if(id.indexOf('TikTokWebPanel')==0||id.indexOf('TikTokHit')==0){if(ch[i].SetURL)ch[i].SetURL('about:blank');ch[i].hittest=false;ch[i].visible=false;ch[i].DeleteAsync(0);}}]]
K.JS_FOCUS = [[if(!p)return;var r=[];['SetAcceptsInput','SetAcceptsFocus','SetTopOfInputContext','SetIgnoreCursor'].forEach(function(f){try{p[f](true);}catch(e){r.push(f+'!'+e);}});try{p.SetDisableFocusOnMouseDown(false);}catch(e){r.push('SetDisableFocusOnMouseDown!'+e);}p.SetFocus();r.push('key='+p.BHasKeyFocus());par.SetAttributeString('tt_focus',r.join(' '));]]
K.JS_BLUR = [[if(!p)return;try{p.SetTopOfInputContext(false);}catch(e){}$.DispatchEvent('DropInputFocus',p);]]
K.JS_CREATE =[[var B='%s',U='%s';var types=['HTML','DOTAHTMLPanel','DOTAWebBrowser'];var info=[];var ok=null;
for(var i=0;i<types.length&&!ok;i++){var t=types[i],id=B+'_'+i,q=null;
try{q=$.CreatePanel(t,par,id,{url:U,acceptsinput:'true',acceptsfocus:'true'});}catch(e){info.push(t+' props!'+e);try{q=$.CreatePanel(t,par,id);}catch(e2){info.push(t+'!'+e2);}}
if(!q){info.push(t+' null');continue;}
info.push(t+'>'+q.paneltype);
if(q.paneltype==t){ok=q;info.unshift('ok:'+id);}else{q.DeleteAsync(0);}}
if(ok){try{ok.SetIgnoreCursor(true);info.push('ignorecursor');}catch(e){info.push('SetIgnoreCursor!'+e);}
var tries=0,pending=false;var check=function(u,t){t=t||'';par.SetAttributeString('tt_load',(u||'')+' | '+t+' | retry='+tries);if(t.indexOf('Access Denied')<0&&t.indexOf('Error')!=0){if(u)tries=0;return;}if(pending||tries>=3)return;pending=true;tries++;$.Schedule(1+tries*2,function(){pending=false;if(ok.IsValid())ok.SetURL((tries&1)==1?'https://www.tiktok.com/':U);});};
try{$.RegisterEventHandler('HTMLFinishRequest',ok,function(p,u,t){check(u,t);});$.RegisterEventHandler('HTMLTitle',ok,function(p,t){check('',t);});info.push('loadwatch');}catch(e){info.push('loadwatch!'+e);}
try{if(ok.SetURL)ok.SetURL(U);}catch(e){info.push('SetURL!'+e);}}
par.SetAttributeString('tt_report',info.join(' | '));]]

local ui = {}
local act = {}

do
	local tab = UI.Create("Scripts", "Scripts", "TikTok")
	tab:Icon("\u{f001}")

	local page = tab:Create("Settings")
	local g_main = page:Create("tt_group_main", Enum.GroupSide.Left)
	local g_win = page:Create("tt_group_window", Enum.GroupSide.Right)

	ui.enable = g_main:Switch("tt_enable", false, "\u{f011}")
	ui.enable:ToolTip("tt_enable_tip")

	ui.key = g_main:Bind("tt_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.key:ToolTip("tt_key_tip")

	ui.icon = g_main:Switch("tt_icon", true, "\u{f03e}")
	ui.icon:ToolTip("tt_icon_tip")
	local g_icon = ui.icon:Gear("tt_gear_icon")
	ui.icon_size = g_icon:Slider("tt_icon_size", 24, 96, 44, "%d px")
	ui.icon_size:Icon("\u{f065}")
	ui.icon_alpha = g_icon:Slider("tt_icon_alpha", 10, 100, 100, "%d%%")
	ui.icon_alpha:Icon("\u{f042}")
	ui.hide_key = g_icon:Bind("tt_hide_key", Enum.ButtonCode.KEY_NONE, "\u{f070}")
	ui.hide_key:ToolTip("tt_hide_key_tip")
	ui.icon_reset = g_icon:Button("tt_icon_reset", function() act.reset_icon() end)


	ui.win_w = g_win:Slider("tt_width", K.W_MIN, K.W_MAX, 560, "%d px")
	ui.win_w:Icon("\u{f337}")
	ui.win_h = g_win:Slider("tt_height", K.H_MIN, K.H_MAX, 900, "%d px")
	ui.win_h:Icon("\u{f338}")
	ui.win_alpha = g_win:Slider("tt_win_alpha", 20, 100, 100, "%d%%")
	ui.win_alpha:Icon("\u{f042}")
	ui.start_page = g_win:Combo("tt_start_page", { "tt_page_foryou", "tt_page_following", "tt_page_explore" }, 0)
	ui.start_page:Icon("\u{f015}")

	ui.auto_death = g_win:Switch("tt_auto_death", true, "\u{f54c}")
	ui.auto_death:ToolTip("tt_auto_death_tip")
	local g_death = ui.auto_death:Gear("tt_gear_death")
	ui.death_delay = g_death:Slider("tt_death_delay", 0, 5, 1, "%d s")
	ui.death_delay:Icon("\u{f017}")
	ui.death_close = g_death:Switch("tt_death_close", true, "\u{f00d}")
	ui.death_close:ToolTip("tt_death_close_tip")

	ui.win_reset = g_win:Button("tt_win_reset", function() act.reset_window() end, true)
	ui.win_reset:Icon("\u{f0e2}")

	ui.key:Properties(L("tt_bind_name"))
end

local function refresh_disabled()
	local on = ui.enable:Get()
	for _, w in ipairs({ ui.key, ui.icon, ui.auto_death, ui.win_w, ui.win_h, ui.win_alpha, ui.start_page }) do
		w:Disabled(not on)
	end
end

ui.enable:SetCallback(refresh_disabled, true)

local state = {
	panel = nil,
	parent_in_game = nil,
	parent = nil,
	parent_id = nil,
	panel_id = nil,
	serial = 0,
	open = false,
	web_failed = false,
	style = "",
	icon = nil,
	win = nil,
	icon_hidden = false,
	press = nil,
	auto_opened = false,
	alive = nil,
	death_at = nil,
	next_check = 0,
	draw_error = nil,
	logo = nil,
	font = nil,
	glyph = nil,
	hits = {},
	parents = {},
	parent_missing = nil,
	mouse_down = false,
	zoom_on = false,
	zoom_prev = nil,
	zoom_missing = false,
	over_window = false,
	mouse3_blocked = false,
	wheel_logged = false,
	load_status = "",
	web_focus = false,
}

local function log(text)
	Log.Write("[TikTok] " .. text)
end

local function screen()
	return Render.ScreenSize()
end

local function clamp(v, lo, hi)
	if hi < lo then return lo end
	return math.max(lo, math.min(hi, v))
end

local function in_rect(mx, my, x, y, w, h)
	return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function save_positions()
	if state.icon then
		Config.WriteInt(K.CFG, "icon_x", math.floor(state.icon.x))
		Config.WriteInt(K.CFG, "icon_y", math.floor(state.icon.y))
	end
	if state.win then
		Config.WriteInt(K.CFG, "win_x", math.floor(state.win.x))
		Config.WriteInt(K.CFG, "win_y", math.floor(state.win.y))
	end
end

local function default_icon()
	local s = screen()
	return { x = s.x - ui.icon_size:Get() - 24, y = math.floor(s.y * 0.32) }
end

local function default_window()
	local s = screen()
	return { x = s.x - ui.win_w:Get() - ui.icon_size:Get() - 48, y = math.floor(s.y * 0.1) }
end

local function load_positions()
	local ix, iy = Config.ReadInt(K.CFG, "icon_x", -1), Config.ReadInt(K.CFG, "icon_y", -1)
	state.icon = (ix >= 0 and iy >= 0) and { x = ix, y = iy } or default_icon()
	local wx, wy = Config.ReadInt(K.CFG, "win_x", -1), Config.ReadInt(K.CFG, "win_y", -1)
	state.win = (wx >= 0 and wy >= 0) and { x = wx, y = wy } or default_window()
end

local function clamp_positions()
	local s = screen()
	local size = ui.icon_size:Get()
	state.icon.x = clamp(state.icon.x, 0, s.x - size)
	state.icon.y = clamp(state.icon.y, 0, s.y - size)
	state.win.x = clamp(state.win.x, 0, s.x - ui.win_w:Get())
	state.win.y = clamp(state.win.y, 0, s.y - ui.win_h:Get() - K.HEADER_H)
end

local function start_url()
	return K.URL_BASE .. (K.PAGES[ui.start_page:Get() + 1] or K.PAGES[1])
end

local function overlay_open(url)
	local ok = Engine.RunScript(string.format("$.DispatchEvent('ExternalBrowserGoToURL', '%s');", url))
	log("overlay " .. url .. " sent=" .. tostring(ok))
	return ok
end

local function panel_valid()
	return state.panel ~= nil and state.panel:IsValid()
end

local function js_in(parent, parent_id, id, body)
	if not (parent and parent:IsValid()) then return false end
	return Engine.RunScript(string.format(K.JS_WRAP, parent_id, id or "", body), parent)
end

local function find_parent(in_game)
	local cached = state.parents[in_game]
	if cached and cached.panel:IsValid() then return cached.panel, cached.id end
	for _, name in ipairs(in_game and K.HUD_PARENTS or K.MENU_PARENTS) do
		local p = Panorama.GetPanelByName(name, false)
		if p and p:IsValid() then
			log("parent " .. name)
			state.parents[in_game] = { panel = p, id = name }
			js_in(p, name, nil, K.JS_CLEAN)
			state.parent_missing = nil
			return p, name
		end
	end
	if state.parent_missing ~= in_game then
		state.parent_missing = in_game
		log("parent not found, in_game=" .. tostring(in_game))
	end
	return nil
end

local function parent_js(body)
	return js_in(state.parent, state.parent_id, state.panel_id, body)
end

local function disarm(panel)
	panel:SetStyle(K.HIDDEN_STYLE)
	panel:BSetProperty("hittest", "false")
	panel:SetVisible(false)
end

local function drop_hit(name)
	local hp = state.hits[name]
	if not hp then return end
	state.hits[name] = nil
	if hp.panel:IsValid() then
		disarm(hp.panel)
		js_in(hp.parent, hp.parent_id, hp.id, K.JS_KILL)
	end
end

local function sync_hit(name, parent, parent_id, rect)
	local hp = state.hits[name]
	if hp and not (hp.panel:IsValid() and hp.parent == parent) then
		drop_hit(name)
		hp = nil
	end
	if not rect or not parent then
		if hp and hp.visible then
			disarm(hp.panel)
			hp.style = K.HIDDEN_STYLE
			hp.visible = false
		end
		return
	end
	if not hp then
		state.serial = state.serial + 1
		local id = K.HIT_ID .. name .. state.serial
		local p = Panorama.CreatePanel("Panel", id, parent, nil, "")
		if not (p and p:IsValid()) then return end
		p:BSetProperty("hittest", "true")
		hp = { panel = p, parent = parent, parent_id = parent_id, id = id, style = "", visible = true }
		state.hits[name] = hp
		log("hit panel " .. id)
	end
	local k = 1080 / screen().y
	local x, y, w, h = table.unpack(rect)
	local style = string.format("x: %dpx; y: %dpx; width: %dpx; height: %dpx;",
		math.floor(x * k), math.floor(y * k), math.ceil(w * k), math.ceil(h * k))
	if style ~= hp.style then
		hp.style = style
		hp.panel:SetStyle(style)
	end
	if not hp.visible then
		hp.panel:BSetProperty("hittest", "true")
		hp.panel:SetVisible(true)
		hp.visible = true
	end
end

local function set_zoom_lock(on)
	if on == state.zoom_on then return end
	state.zoom_on = on
	local cv = ConVar.Find(K.ZOOM_CVAR)
	if not cv then
		if not state.zoom_missing then
			state.zoom_missing = true
			log("convar " .. K.ZOOM_CVAR .. " not found")
		end
		return
	end
	if on then
		state.zoom_prev = ConVar.GetInt(cv)
		ConVar.SetInt(cv, 1)
	else
		ConVar.SetInt(cv, state.zoom_prev or 0)
	end
end

local function read_report()
	if not (state.parent and state.parent:IsValid()) then return "" end
	return state.parent:GetAttribute("tt_report", "") or ""
end

local function focus_web(on)
	if not panel_valid() or (not on and not state.web_focus) then return end
	local changed = on ~= state.web_focus
	state.web_focus = on
	parent_js(on and K.JS_FOCUS or K.JS_BLUR)
	local report = on and (state.parent:GetAttribute("tt_focus", "") or "") or ""
	if changed or report ~= "key=true" then
		log("web focus " .. tostring(on) .. (report ~= "" and (" " .. report) or ""))
	end
end

local function set_url(url)
	if not panel_valid() then return end
	local sent = parent_js(string.format([[if(!p)return;var u='%s';if(p.SetURL){p.SetURL(u);}else{p.SetAttributeString('url',u);}]], url))
	local ok = state.panel:BSetProperty("url", url)
	log("set url " .. url .. " js=" .. tostring(sent) .. " prop=" .. tostring(ok))
end

local function window_style()
	local s = screen()
	local k = 1080 / s.y
	return string.format("x: %dpx; y: %dpx; width: %dpx; height: %dpx; opacity: %.2f; background-color: #000000;",
		math.floor(state.win.x * k), math.floor((state.win.y + K.HEADER_H) * k),
		math.floor(ui.win_w:Get() * k), math.floor(ui.win_h:Get() * k),
		ui.win_alpha:Get() / 100)
end

local function apply_style()
	if not panel_valid() then return end
	local style = window_style()
	if style ~= state.style then
		state.style = style
		state.panel:SetStyle(style)
	end
end

local function destroy_panel()
	if panel_valid() then
		disarm(state.panel)
		parent_js(K.JS_KILL)
	end
	state.panel = nil
	state.panel_id = nil
	state.style = ""
end

local function ensure_panel(url)
	local in_game = Engine.IsInGame()
	if panel_valid() and state.parent_in_game == in_game then return true end
	destroy_panel()
	local parent, parent_id = find_parent(in_game)
	if not parent then return false end
	state.parent, state.parent_id, state.parent_in_game = parent, parent_id, in_game
	state.serial = state.serial + 1
	local base = K.PANEL_ID .. state.serial
	parent:SetAttribute("tt_report", "")
	local sent = parent_js(string.format(K.JS_CREATE, base, url))
	local report = read_report()
	log("create sent=" .. tostring(sent) .. " report: " .. (report ~= "" and report or "<empty>"))
	local id = report:match("ok:(%S+)")
	if not id then
		log("no html panel type worked")
		return false
	end
	state.panel_id = id
	state.panel = parent:FindChildTraverse(id) or Panorama.GetPanelByName(id, false)
	if not panel_valid() then
		log("panel " .. id .. " not found from lua")
		return false
	end
	log("panel " .. id .. " type=" .. tostring(state.panel:GetPanelType()))
	state.style = ""
	apply_style()
	return true
end

function act.open(url)
	url = url or start_url()
	if not state.win then load_positions() end
	clamp_positions()
	if state.web_failed or not ensure_panel(url) then
		state.web_failed = true
		log("web panel unavailable, fallback to overlay")
		overlay_open(url)
		return
	end
	state.panel:SetVisible(true)
	set_url(url)
	drop_hit("header")
	drop_hit("grip")
	state.open = true
	log("window open " .. url)
end

function act.close()
	focus_web(false)
	destroy_panel()
	state.web_focus = false
	drop_hit("header")
	drop_hit("grip")
	set_zoom_lock(false)
	state.open = false
	state.auto_opened = false
	state.press = nil
	log("window closed")
end

function act.toggle()
	if state.open then act.close() else act.open() end
end

function act.reload()
	if panel_valid() then
		parent_js("if(!p)return;if(p.Reload){p.Reload();}else if(p.SetURL){p.SetURL(p.GetAttributeString('url',''));}")
		log("reload")
	end
end


function act.login()
	if panel_valid() then
		set_url(K.URL_LOGIN)
	else
		act.open(K.URL_LOGIN)
	end
end

function act.reset_icon()
	state.icon = default_icon()
	save_positions()
end

function act.reset_window()
	state.win = default_window()
	apply_style()
	save_positions()
end

local function header_rects()
	local w = ui.win_w:Get()
	local x, y, h = state.win.x, state.win.y, K.HEADER_H
	return {
		header = { x, y, w, h },
		close = { x + w - h, y, h, h },
		reload = { x + w - h * 2, y, h, h },
		login = { x + w - h * 3, y, h, h },
		grip = { x + w - K.GRIP, y + h + ui.win_h:Get() - K.GRIP, K.GRIP, K.GRIP },
	}
end

local function icon_visible()
	return ui.icon:Get() and not state.icon_hidden and Engine.IsInGame()
end

local function hit_test(mx, my)
	if Menu.Opened() then
		local mp, ms = Menu.Pos(), Menu.Size()
		if in_rect(mx, my, mp.x, mp.y, ms.x, ms.y) then return nil end
	end
	if state.open and state.win then
		local r = header_rects()
		if in_rect(mx, my, table.unpack(r.close)) then return "close" end
		if in_rect(mx, my, table.unpack(r.reload)) then return "reload" end
		if in_rect(mx, my, table.unpack(r.login)) then return "login" end
		if in_rect(mx, my, table.unpack(r.header)) then return "header" end
		if in_rect(mx, my, table.unpack(r.grip)) then return "grip" end
	end
	if icon_visible() and state.icon then
		local size = ui.icon_size:Get()
		if in_rect(mx, my, state.icon.x, state.icon.y, size, size) then return "icon" end
	end
	return nil
end

local function on_press(target, mx, my)
	state.press = {
		target = target,
		mx = mx,
		my = my,
		moved = false,
		ox = target == "icon" and state.icon.x or state.win.x,
		oy = target == "icon" and state.icon.y or state.win.y,
		ow = ui.win_w:Get(),
		oh = ui.win_h:Get(),
	}
end

local function on_release(mx, my)
	local p = state.press
	state.press = nil
	if not p then return end
	if p.target == "icon" and not p.moved then
		act.toggle()
	elseif p.target == "close" and hit_test(mx, my) == "close" then
		act.close()
	elseif p.target == "reload" and hit_test(mx, my) == "reload" then
		act.reload()
	elseif p.target == "login" and hit_test(mx, my) == "login" then
		act.login()
	end
	save_positions()
end

local function update_drag(mx, my)
	local p = state.press
	if not p then return end
	local dx, dy = mx - p.mx, my - p.my
	if not p.moved and math.abs(dx) + math.abs(dy) >= K.DRAG_THRESHOLD then p.moved = true end
	if not p.moved then return end
	if p.target == "icon" then
		state.icon.x, state.icon.y = p.ox + dx, p.oy + dy
		clamp_positions()
	elseif p.target == "header" then
		state.win.x, state.win.y = p.ox + dx, p.oy + dy
		clamp_positions()
		apply_style()
	elseif p.target == "grip" then
		ui.win_w:Set(clamp(math.floor(p.ow + dx), K.W_MIN, K.W_MAX))
		ui.win_h:Set(clamp(math.floor(p.oh + dy), K.H_MIN, K.H_MAX))
		apply_style()
	end
end

local function ensure_assets()
	if not state.logo then
		state.logo = Render.LoadSvgString(K.LOGO_SVG, Vec2(K.LOGO_PX, K.LOGO_PX), "tt_logo_v1")
		state.font = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.BOLD)
		state.glyph = Render.LoadFont("FontAwesomeEx", Enum.FontCreate.FONTFLAG_ANTIALIAS, 400)
	end
end

local function draw_glyph(glyph, rect, hovered)
	local x, y, w, h = table.unpack(rect)
	if hovered then
		Render.FilledRect(Vec2(x + 3, y + 3), Vec2(x + w - 3, y + h - 3), K.HOVER, 5)
	end
	local ts = Render.TextSize(state.glyph, 13, glyph)
	Render.Text(state.glyph, 13, glyph, Vec2(x + (w - ts.x) / 2, y + (h - ts.y) / 2), K.TEXT)
end

local function header_title()
	local hero = Engine.IsInGame() and Heroes.GetLocal() or nil
	if hero and not Entity.IsAlive(hero) then
		local left = Hero.GetRespawnTime(hero) - GameRules.GetGameTime()
		if left > 0 then return string.format(L("tt_respawn"), math.ceil(left)) end
	end
	return L("tt_title")
end

local function draw_window(mx, my)
	local r = header_rects()
	local x, y, w, h = table.unpack(r.header)
	local a = ui.win_alpha:Get() / 100
	local bg = Color(18, 18, 22, math.floor(235 * a))
	Render.FilledRect(Vec2(x, y), Vec2(x + w, y + h), bg, 8, Enum.DrawFlags.RoundCornersTop)
	Render.Image(state.logo, Vec2(x + 7, y + 5), Vec2(h - 10, h - 10), Color(255, 255, 255, math.floor(255 * a)))
	local title = header_title()
	local ts = Render.TextSize(state.font, 12, title)
	Render.PushClip(Vec2(x, y), Vec2(x + w - h * 3, y + h))
	Render.Text(state.font, 12, title, Vec2(x + h + 2, y + (h - ts.y) / 2), K.TEXT)
	Render.PopClip()
	draw_glyph("\u{f2f6}", r.login, in_rect(mx, my, table.unpack(r.login)))
	draw_glyph("\u{f2f9}", r.reload, in_rect(mx, my, table.unpack(r.reload)))
	draw_glyph("\u{f00d}", r.close, in_rect(mx, my, table.unpack(r.close)))
	local gx, gy, gs = table.unpack(r.grip)
	local gc = in_rect(mx, my, gx, gy, gs, gs) and K.TEXT or K.MUTED
	Render.Line(Vec2(gx + gs - 3, gy + 4), Vec2(gx + 4, gy + gs - 3), gc, 1.5)
	Render.Line(Vec2(gx + gs - 3, gy + 9), Vec2(gx + 9, gy + gs - 3), gc, 1.5)
end

local function draw_icon(mx, my)
	local size = ui.icon_size:Get()
	local x, y = state.icon.x, state.icon.y
	local a = ui.icon_alpha:Get() / 100
	local hovered = in_rect(mx, my, x, y, size, size) or (state.press and state.press.target == "icon")
	local bg_a = math.floor((hovered and 245 or 225) * a)
	Render.FilledRect(Vec2(x, y), Vec2(x + size, y + size), Color(12, 12, 14, bg_a), size * 0.26)
	local pad = size * 0.18
	Render.Image(state.logo, Vec2(x + pad, y + pad), Vec2(size - pad * 2, size - pad * 2), Color(255, 255, 255, math.floor(255 * a)))
end

local function draw()
	ensure_assets()
	if not state.icon then load_positions() end
	local mx, my = Input.GetCursorPos()
	local down = Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1)
	if down and not state.mouse_down then
		local target = hit_test(mx, my)
		if target then
			on_press(target, mx, my)
		elseif state.open and state.over_window then
			focus_web(true)
		else
			focus_web(false)
		end
	elseif not down and state.mouse_down then
		on_release(mx, my)
	end
	state.mouse_down = down
	update_drag(mx, my)
	if state.open and not panel_valid() then
		log("panel lost")
		act.close()
	end
	local r = state.open and header_rects() or nil
	sync_hit("header", state.parent, state.parent_id, r and r.header)
	sync_hit("grip", state.parent, state.parent_id, r and r.grip)
	local hud, hud_id = nil, nil
	if Engine.IsInGame() then hud, hud_id = find_parent(true) end
	local size = ui.icon_size:Get()
	sync_hit("icon", hud, hud_id, icon_visible() and { state.icon.x, state.icon.y, size, size } or nil)
	state.over_window = r ~= nil and in_rect(mx, my, state.win.x, state.win.y, ui.win_w:Get(), K.HEADER_H + ui.win_h:Get())
	set_zoom_lock(state.over_window)
	if r and state.parent and state.parent:IsValid() then
		local load = state.parent:GetAttribute("tt_load", "") or ""
		if load ~= state.load_status then
			state.load_status = load
			if load ~= "" then log("page " .. load) end
		end
	end
	if r then
		apply_style()
		draw_window(mx, my)
	end
	if icon_visible() then draw_icon(mx, my) end
end

local function update_death()
	if not ui.auto_death:Get() then
		state.alive, state.death_at = nil, nil
		return
	end
	local now = GameRules.GetGameTime()
	if now < state.next_check then return end
	state.next_check = now + K.DEATH_INTERVAL
	local hero = Heroes.GetLocal()
	if not hero then return end
	local alive = Entity.IsAlive(hero)
	if state.alive == true and not alive then
		state.death_at = now + ui.death_delay:Get()
		log("hero died, open at " .. string.format("%.1f", state.death_at))
	elseif state.alive == false and alive then
		state.death_at = nil
		log("hero respawned, auto_opened=" .. tostring(state.auto_opened))
		if state.auto_opened and state.open and ui.death_close:Get() then act.close() end
		state.auto_opened = false
	end
	state.alive = alive
	if state.death_at and now >= state.death_at then
		state.death_at = nil
		if not state.open then
			act.open()
			state.auto_opened = state.open
		end
	end
end

local script = {}

function script.OnFrame()
	if not ui.enable:Get() and not state.open then return end
	local ok, err = pcall(draw)
	if not ok and err ~= state.draw_error then
		state.draw_error = err
		Log.Write("[TikTok] draw: " .. tostring(err))
	end
end

function script.OnUpdateEx()
	if not ui.enable:Get() then
		if state.open then act.close() end
		return
	end
	if Input.IsInputCaptured() then return end
	if ui.key:IsPressed() then act.toggle() end
	if ui.hide_key:IsPressed() then
		state.icon_hidden = not state.icon_hidden
		log("icon hidden=" .. tostring(state.icon_hidden))
	end
end

function script.OnUpdate()
	if not ui.enable:Get() then return end
	update_death()
end

function script.OnKeyEvent(data)
	local wheel = data.key == Enum.ButtonCode.KEY_MWHEELUP or data.key == Enum.ButtonCode.KEY_MWHEELDOWN
		or data.event == Enum.EKeyEvent.EKeyEvent_SCROLL_UP or data.event == Enum.EKeyEvent.EKeyEvent_SCROLL_DOWN
	if wheel then
		if state.over_window and not state.wheel_logged then
			state.wheel_logged = true
			log("wheel over window blocked for game")
		end
		return not state.over_window
	end
	if data.key ~= Enum.ButtonCode.KEY_MOUSE3 then return true end
	if data.event == Enum.EKeyEvent.EKeyEvent_KEY_DOWN then
		state.mouse3_blocked = state.over_window == true
		if state.mouse3_blocked then log("middle click over window blocked") end
		return not state.mouse3_blocked
	elseif data.event == Enum.EKeyEvent.EKeyEvent_KEY_UP and state.mouse3_blocked then
		state.mouse3_blocked = false
		return false
	end
	return true
end

function script.OnGameEnd()
	act.close()
	drop_hit("icon")
	state.alive, state.death_at, state.parent_in_game = nil, nil, nil
end

function script.OnScriptsLoaded()
	load_positions()
	local s = screen()
	log(string.format("v%s loaded, enabled=%s, screen=%dx%d, in_game=%s",
		K.VERSION, tostring(ui.enable:Get()), math.floor(s.x), math.floor(s.y), tostring(Engine.IsInGame())))
end

return script
