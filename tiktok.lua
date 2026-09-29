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
		tt_enable_tip = "Shows the TikTok icon and window",
		tt_scope = "Works",
		tt_scope_tip = "In the main menu the window opens by key or icon",
		tt_scope_match = "Only in match",
		tt_scope_all = "In match and menu",
		tt_key = "Open window",
		tt_key_tip = "Opens and closes the TikTok window",
		tt_bind_name = "TikTok",
		tt_icon = "Icon",
		tt_icon_tip = "Drag with the mouse, click to open",
		tt_gear_icon = "Icon",
		tt_icon_size = "Size",
		tt_icon_alpha = "Opacity",
		tt_icon_reveal = "Reveal near cursor",
		tt_icon_reveal_tip = "The icon is hidden and fades in as the cursor gets closer",
		tt_icon_radius = "Reveal radius",
		tt_hide_key = "Hide icon",
		tt_hide_key_tip = "Hides and shows the icon",
		tt_icon_reset = "Reset position",
		tt_width = "Width",
		tt_height = "Height",
		tt_win_alpha = "Opacity",
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
		tt_enable_tip = "Показывает значок и окно TikTok",
		tt_scope = "Работает",
		tt_scope_tip = "В главном меню окно открывается клавишей или значком",
		tt_scope_match = "Только в матче",
		tt_scope_all = "В матче и в меню",
		tt_key = "Открыть окно",
		tt_key_tip = "Открывает и закрывает окно TikTok",
		tt_bind_name = "TikTok",
		tt_icon = "Значок",
		tt_icon_tip = "Двигается мышью, по клику открывает окно",
		tt_gear_icon = "Значок",
		tt_icon_size = "Размер",
		tt_icon_alpha = "Прозрачность",
		tt_icon_reveal = "Проявлять у курсора",
		tt_icon_reveal_tip = "Значок скрыт и проявляется, когда к нему подводишь курсор",
		tt_icon_radius = "Радиус проявления",
		tt_hide_key = "Скрыть значок",
		tt_hide_key_tip = "Прячет и возвращает значок",
		tt_icon_reset = "Сбросить позицию",
		tt_width = "Ширина",
		tt_height = "Высота",
		tt_win_alpha = "Прозрачность",
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
	VERSION = "1.2.4",
	CFG = "tiktok",
	PANEL_ID = "TikTokWebPanel",
	HIT_ID = "TikTokHit",
	URL_START = "https://www.tiktok.com/foryou",
	URL_LOGIN = "https://www.tiktok.com/login/qrcode",
	URL_BLANK = "about:blank",
	HUD_PARENTS = { "Hud", "DotaHud" },
	MENU_PARENTS = { "DotaDashboard", "Dashboard" },
	HEADER_H = 28,
	W_MIN = 300,
	W_MAX = 1400,
	H_MIN = 400,
	H_MAX = 1400,
	ZOOM_CVAR = "dota_camera_disable_zoom",
	CAM_PATH = { "Info Screen", "Main", "Camera", "Main", "Camera Settings", "Camera Distance" },
	WHEEL_PATH = { "Info Screen", "Main", "Camera", "Main", "Camera Settings", "Zoom using Wheel" },
	WHEEL_OFF = { "none", "off", "disable", "never", "нет", "выкл", "ctrl", "alt", "shift" },
	GRIP = 16,
	DRAG_THRESHOLD = 4,
	DEATH_INTERVAL = 0.2,
	FOCUS_INTERVAL = 0.2,
	PULL_INTERVAL = 0.05,
	REPEAT_DELAY = 0.45,
	REPEAT_RATE = 0.035,
	RELEASE_GRACE = 0.15,
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
K.JS_FOCUS = [[if(!p)return;var had=p.BHasKeyFocus();if(!had)p.SetFocus();par.SetAttributeString('tt_focus',(had?'kept':'set')+' key='+p.BHasKeyFocus());]]
K.JS_BLUR = [[if(!p)return;if(p.BHasKeyFocus())$.DispatchEvent('DropInputFocus',p);]]
K.JS_FOCUS_WEB = [[if(!p)return;var had=p.BHasKeyFocus();if(!had){var te=par.FindChildTraverse('%s');if(te){try{te.SetFocus();}catch(e){}}p.SetFocus();}par.SetAttributeString('tt_focus',(had?'kept':'set')+' web key='+p.BHasKeyFocus());]]
K.JS_SEND = [[if(!p)return;var te=par.FindChildTraverse('%s');var s=par.GetAttributeString('tt_pend','');if(te&&te.text){s+=te.text;te.text='';par.SetAttributeString('tt_lpull','1');}par.SetAttributeString('tt_pend','');var a='%s',m=%d;if(!s&&!a)return;var P=par.GetAttributeString('tt_page',''),IM=par.GetAttributeString('tt_im','url');var q=function(x){return JSON.stringify(x).replace(/[\u007f-￿]/g,function(c){return '\\u'+('000'+c.charCodeAt(0).toString(16)).slice(-4);});};var c=(s?P+'("text",'+q(s)+',0);':'')+(a?P+'("'+a+'","",'+m+');':'');if(IM!='url'&&p[IM])p[IM](c);else p.SetURL('javascript:'+encodeURIComponent(c+'void '+(Date.now()+Math.random())));]]
K.PAGE_JS = [==[(function(a,t,m){var r;try{r=(function(){
var d=document,e=d.activeElement;
try{while(e&&/^i?frame$/i.test(e.tagName)&&e.contentDocument){d=e.contentDocument;e=d.activeElement;}}catch(x){}
while(e&&e.shadowRoot&&e.shadowRoot.activeElement)e=e.shadowRoot.activeElement;
if(e==d.body||e==d.documentElement)e=null;
var W=d.defaultView||window,tn=e?e.tagName:'';
var tf=tn=='TEXTAREA'||(tn=='INPUT'&&/^(text|search|email|url|tel|password|number)?$/i.test(e.getAttribute('type')||''));
var ed=tf||(!!e&&e.isContentEditable);
var sh=(m&1)>0,ct=(m&2)>0,tg=e||d.body||d.documentElement;
function cmd(c,v){try{return d.execCommand(c,false,v);}catch(x){return false;}}
function ev(tp,k,c,cd){var o=new W.KeyboardEvent(tp,{key:k,code:cd,bubbles:true,cancelable:true,composed:true,shiftKey:sh,ctrlKey:ct,keyCode:c,which:c,charCode:tp=='keypress'?c:0});
try{Object.defineProperty(o,'keyCode',{get:function(){return c;}});Object.defineProperty(o,'which',{get:function(){return c;}});}catch(x){}
return tg.dispatchEvent(o);}
function key(k,c,cd,p){var r=ev('keydown',k,c,cd);if(r&&p)r=ev('keypress',k,c,cd);ev('keyup',k,c,cd);return r;}
function put(s,i,j){try{e.setRangeText(s,i,j,'end');e.dispatchEvent(new W.InputEvent('input',{bubbles:true,inputType:s?'insertText':'deleteContentBackward',data:s||null}));}catch(x){}}
function wl(v,i){var q=v.slice(0,i).search(/\S+\s*$/);return q<0?0:q;}
function wr(v,i){var r=v.slice(i).match(/^\s*\S+/);return r?i+r[0].length:v.length;}
if(a=='text'){
if(ed){if(e.focus)e.focus();if(cmd('insertText',t))return 'ins:'+tn;if(tf){put(t,e.selectionStart,e.selectionEnd);return 'rng:'+tn;}return 'fail:'+tn;}
for(var n=0;n<t.length;n++){var ch=t.charAt(n);key(ch,ch.toUpperCase().charCodeAt(0),ch==' '?'Space':'',true);}
return 'keys:'+(tn||'none');}
var KS={back:['Backspace',8],del:['Delete',46],enter:['Enter',13],left:['ArrowLeft',37],right:['ArrowRight',39],up:['ArrowUp',38],down:['ArrowDown',40],home:['Home',36],end:['End',35],pgup:['PageUp',33],pgdn:['PageDown',34],tab:['Tab',9],esc:['Escape',27],a:['a',65,'KeyA'],c:['c',67,'KeyC'],x:['x',88,'KeyX'],z:['z',90,'KeyZ'],y:['y',89,'KeyY']};
var k=KS[a];if(!k)return 'nokey';if(!key(k[0],k[1],k[2]||k[0],a=='enter'))return 'prevented:'+tn;
if(a=='c'){cmd('copy');return;}
if(!ed||a=='pgup'||a=='pgdn'||a=='tab'||a=='esc')return;
if(a=='x'){cmd('cut');return;}
if(a=='z'||a=='y'){cmd(a=='z'?'undo':'redo');return;}
if(a=='a'){if(tf)e.select();else cmd('selectAll');return;}
if(a=='enter'){if(tn=='INPUT'){if(e.form&&e.form.requestSubmit)e.form.requestSubmit();}else if(tf){if(!cmd('insertText','\n'))put('\n',e.selectionStart,e.selectionEnd);}else if(!cmd('insertParagraph'))cmd('insertLineBreak');return;}
var fw=a=='del'||a=='right'||a=='end'||a=='down';
if(a=='back'||a=='del'){
if(tf){var v=e.value,i=e.selectionStart,j=e.selectionEnd;if(i==null)return;
if(i==j&&ct){if(fw)j=wr(v,j);else i=wl(v,i);e.setSelectionRange(i,j);}
if(!cmd(fw?'forwardDelete':'delete')){if(i==j){if(fw)j++;else i--;}if(i<0)i=0;if(i!=j)put('',i,j);}
return;}
var g=W.getSelection();if(ct&&g&&g.isCollapsed&&g.modify)g.modify('extend',fw?'forward':'backward','word');
cmd(fw?'forwardDelete':'delete');return;}
if(tf){var v2=e.value,i2=e.selectionStart,j2=e.selectionEnd;if(i2==null)return;
var bk=e.selectionDirection=='backward',f=bk?i2:j2,an=bk?j2:i2,L=v2.length,p;
if(a=='left'||a=='right'){if(i2!=j2&&!sh&&!ct)p=fw?j2:i2;else if(ct)p=fw?wr(v2,f):wl(v2,f);else p=fw?Math.min(L,f+1):Math.max(0,f-1);}
else if(tn=='TEXTAREA'&&(a=='up'||a=='down'))return;
else if(tn=='TEXTAREA'&&!ct){if(fw){p=v2.indexOf('\n',f);if(p<0)p=L;}else p=f?v2.lastIndexOf('\n',f-1)+1:0;}
else p=fw?L:0;
if(sh)e.setSelectionRange(Math.min(an,p),Math.max(an,p),p<an?'backward':'forward');else e.setSelectionRange(p,p);
return;}
var s=W.getSelection();if(!s||!s.modify)return;
s.modify(sh?'extend':'move',fw?'forward':'backward',(a=='left'||a=='right')?(ct?'word':'character'):(a=='up'||a=='down')?'line':(ct?'documentboundary':'lineboundary'));
})();}catch(x){r='err:'+x;}
try{var w=window,dd=document,o=dd.title;w.__ttn=(w.__ttn||0)+1;if(w.__ttn<=6){if(o.indexOf('tt:')==0)o=w.__tto||'';else w.__tto=o;var mk='tt:'+a+':'+(r||'done');dd.title=mk;setTimeout(function(){if(dd.title==mk)dd.title=o;},600);}}catch(x){}})]==]
K.JS_CREATE =[[var B='%s',U='%s',PAGE=%s,MENU=%d;var types=['HTML','DOTAHTMLPanel','DOTAWebBrowser'];var info=[];var ok=null;
for(var i=0;i<types.length&&!ok;i++){var t=types[i],id=B+'_'+i,q=null;
try{q=$.CreatePanel(t,par,id,{url:U,acceptsinput:'true',acceptsfocus:'true'});}catch(e){info.push(t+' props!'+e);try{q=$.CreatePanel(t,par,id);}catch(e2){info.push(t+'!'+e2);}}
if(!q){info.push(t+' null');continue;}
info.push(t+'>'+q.paneltype);
if(q.paneltype==t){ok=q;info.unshift('ok:'+id);}else{q.DeleteAsync(0);}}
if(ok){if(!MENU){try{ok.SetIgnoreCursor(true);info.push('ignorecursor');}catch(e){info.push('SetIgnoreCursor!'+e);}}
par.SetAttributeString('tt_page',PAGE);
var names=function(o){var s={};try{for(var k in o)s[k]=1;}catch(e){}try{var pr=Object.getPrototypeOf(o);while(pr&&pr!==Object.prototype){Object.getOwnPropertyNames(pr).forEach(function(n){s[n]=1;});pr=Object.getPrototypeOf(pr);}}catch(e){}return Object.keys(s).sort().join(',');};
try{par.SetAttributeString('tt_methods',names(ok));}catch(e){par.SetAttributeString('tt_methods','!'+e);}
var cands=['RunJavascript','RunJavaScript','ExecuteJavascript','ExecuteJavaScript','EvaluateJavascript','EvaluateJavaScript','ExecuteScript','RunScript'].filter(function(n){try{return typeof ok[n]=='function';}catch(e){return false;}});cands.push('url');info.push('inject='+cands.join('/'));
var IM=cands[0],ci=0,tries2=0,bad=false,st='',real=U,nn=0;
var setst=function(s){st=s;par.SetAttributeString('tt_im',IM);par.SetAttributeString('tt_inject',s);};
var inj=function(c){if(!ok.IsValid())return;if(IM!='url')ok[IM](c);else ok.SetURL('javascript:'+encodeURIComponent(c+';void '+(++nn)));};
var PROBE="(function(){var d=document,o=d.title;d.title='tt:probe';setTimeout(function(){if(d.title=='tt:probe')d.title=o;},600);})()";
var probe=function(){if(st=='ok'||!ok.IsValid())return;if(ci>=cands.length){setst('fail');return;}IM=cands[ci];setst('probe:'+IM);try{inj(PROBE);}catch(e){par.SetAttributeString('tt_fb','probe!'+IM+' '+e);bad=true;}$.Schedule(2.5,function(){if(st=='ok')return;if(bad||++tries2>=2){tries2=0;ci++;bad=false;}probe();});};
var fb=function(t){par.SetAttributeString('tt_fb',t);if(st!='ok')setst('ok');};
var tries=0,pending=false;var check=function(u,t){u=u||'';t=t||'';
if(t.indexOf('tt:')==0){fb(t);return;}
if(u.indexOf('javascript:')==0)return;
if(u.indexOf('javascript')>=0||t.indexOf('javascript:')==0){if(st!='ok'){bad=true;par.SetAttributeString('tt_fb','broken:'+IM);ok.SetURL(real);}return;}
if(u.indexOf('http')==0){real=u;par.SetAttributeString('tt_url',u);}
par.SetAttributeString('tt_load',u+' | '+t+' | retry='+tries);
if(st==''&&t){setst('wait');$.Schedule(1,probe);}
if(t.indexOf('Access Denied')<0&&t.indexOf('Error')!=0){if(u)tries=0;return;}if(pending||tries>=3)return;pending=true;tries++;$.Schedule(1+tries*2,function(){pending=false;if(ok.IsValid())ok.SetURL((tries&1)==1?'https://www.tiktok.com/':U);});};
try{$.RegisterEventHandler('HTMLFinishRequest',ok,function(p,u,t){check(u,t);});$.RegisterEventHandler('HTMLTitle',ok,function(p,t){check('',t);});info.push('loadwatch');}catch(e){info.push('loadwatch!'+e);}
var te=null;try{te=$.CreatePanel('TextEntry',par,B+'_in');}catch(e){info.push('bridge!'+e);}
if(te){te.hittest=false;try{te.hittestchildren=false;}catch(e){}try{te.style.width='2px';te.style.height='2px';te.style.opacity='0.01';if(MENU){te.style.x='-600px';te.style.y='-600px';info.push('bridge_off');}}catch(e){info.push('te_style!'+e);}
try{te.SetMaxChars(4096);}catch(e){}try{te.RaiseChangeEvents(true);}catch(e){}
var got=0,how='',sched=false;
var take=function(src){if(!te.IsValid())return false;var s=te.text;if(s){te.text='';par.SetAttributeString('tt_pend',par.GetAttributeString('tt_pend','')+s);got+=s.length;if(how.indexOf(src)<0)how+=src;par.SetAttributeString('tt_typed',how+':'+got);}return true;};
var q=function(x){return JSON.stringify(x).replace(/[\u007f-￿]/g,function(c){return '\\u'+('000'+c.charCodeAt(0).toString(16)).slice(-4);});};
var flush=function(){sched=false;if(st!='ok'||!ok.IsValid())return;var s=par.GetAttributeString('tt_pend','');if(!s)return;par.SetAttributeString('tt_pend','');inj(PAGE+'("text",'+q(s)+',0)');};
try{$.RegisterEventHandler('TextEntryChanged',te,function(){take('E');if(!sched){sched=true;$.Schedule(0,flush);}});}catch(e){info.push('te_event!'+e);}
var loop=function(){if(!take('P'))return;flush();$.Schedule(0.03,loop);};$.Schedule(0.03,loop);
info.push('bridge:'+te.id);}
try{if(ok.SetURL)ok.SetURL(U);}catch(e){info.push('SetURL!'+e);}}
par.SetAttributeString('tt_report',info.join(' | '));]]

do
	local B = Enum.ButtonCode
	K.EDIT_KEYS = {
		[B.KEY_BACKSPACE] = "back",
		[B.KEY_DELETE] = "del",
		[B.KEY_ENTER] = "enter",
		[B.KEY_PAD_ENTER] = "enter",
		[B.KEY_LEFT] = "left",
		[B.KEY_RIGHT] = "right",
		[B.KEY_UP] = "up",
		[B.KEY_DOWN] = "down",
		[B.KEY_HOME] = "home",
		[B.KEY_END] = "end",
		[B.KEY_PAGEUP] = "pgup",
		[B.KEY_PAGEDOWN] = "pgdn",
		[B.KEY_TAB] = "tab",
		[B.KEY_ESCAPE] = "esc",
	}
	K.CTRL_KEYS = { [B.KEY_A] = "a", [B.KEY_C] = "c", [B.KEY_X] = "x", [B.KEY_Z] = "z", [B.KEY_Y] = "y" }
	K.REPEAT = { back = true, del = true, left = true, right = true, up = true, down = true }
	K.POLL_KEYS = {}
	for key in pairs(K.EDIT_KEYS) do K.POLL_KEYS[#K.POLL_KEYS + 1] = key end
	for key in pairs(K.CTRL_KEYS) do K.POLL_KEYS[#K.POLL_KEYS + 1] = key end
end

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

	ui.scope = g_main:Combo("tt_scope", { "tt_scope_match", "tt_scope_all" }, 0)
	ui.scope:Icon("\u{f0ac}")
	ui.scope:ToolTip("tt_scope_tip")

	ui.key = g_main:Bind("tt_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.key:ToolTip("tt_key_tip")

	ui.icon = g_main:Switch("tt_icon", true, "\u{f03e}")
	ui.icon:ToolTip("tt_icon_tip")
	local g_icon = ui.icon:Gear("tt_gear_icon")
	ui.icon_size = g_icon:Slider("tt_icon_size", 24, 96, 44, "%d px")
	ui.icon_size:Icon("\u{f065}")
	ui.icon_alpha = g_icon:Slider("tt_icon_alpha", 10, 100, 100, "%d%%")
	ui.icon_alpha:Icon("\u{f042}")
	ui.icon_reveal = g_icon:Switch("tt_icon_reveal", false, "\u{f245}")
	ui.icon_reveal:ToolTip("tt_icon_reveal_tip")
	ui.icon_radius = g_icon:Slider("tt_icon_radius", 40, 800, 220, "%d px")
	ui.icon_radius:Icon("\u{f192}")
	ui.hide_key = g_icon:Bind("tt_hide_key", Enum.ButtonCode.KEY_NONE, "\u{f070}")
	ui.hide_key:ToolTip("tt_hide_key_tip")
	ui.icon_reset = g_icon:Button("tt_icon_reset", function() act.reset_icon() end)


	ui.win_w = g_win:Slider("tt_width", K.W_MIN, K.W_MAX, 560, "%d px")
	ui.win_w:Icon("\u{f337}")
	ui.win_h = g_win:Slider("tt_height", K.H_MIN, K.H_MAX, 900, "%d px")
	ui.win_h:Icon("\u{f338}")
	ui.win_alpha = g_win:Slider("tt_win_alpha", 20, 100, 100, "%d%%")
	ui.win_alpha:Icon("\u{f042}")

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
	for _, w in ipairs({ ui.scope, ui.key, ui.icon, ui.auto_death, ui.win_w, ui.win_h, ui.win_alpha }) do
		w:Disabled(not on)
	end
end

ui.enable:SetCallback(refresh_disabled, true)
ui.icon_reveal:SetCallback(function(w) ui.icon_radius:Visible(w:Get()) end, true)

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
	found = {},
	wheel_prev = nil,
	wheel_list_logged = false,
	prev_over = false,
	cam_hold = nil,
	load_status = "",
	web_focus = false,
	fade = 0,
	fade_clock = nil,
	input = nil,
	input_id = nil,
	input_style = "",
	keys = {},
	poll_prev = {},
	edit_queue = {},
	edit_logged = {},
	key_events = false,
	focus_at = 0,
	focus_seen = {},
	pull_at = 0,
	typed = "",
	pulled = false,
	inject = "",
	feedback = "",
	methods_logged = false,
	bind_down = {},
	origin_x = 0,
	origin_y = 0,
}

local function log(text)
	Log.Write("[TikTok] " .. text)
end

local cfg = { mem = {}, logged = false }

function cfg.get(key, def)
	local C = type(Config) == "table" and Config or {}
	local reads = {
		function() return C.ReadInt(K.CFG, key, def) end,
		function() return C.ReadFloat(K.CFG, key, def) end,
		function() return tonumber(C.ReadString(K.CFG, key, tostring(def))) end,
	}
	for _, read in ipairs(reads) do
		local ok, v = pcall(read)
		if ok and type(v) == "number" then return math.floor(v) end
	end
	if not cfg.logged then
		cfg.logged = true
		Log.Write("[TikTok] Config read unavailable, positions kept in memory")
	end
	local v = cfg.mem[key]
	if v == nil then return def end
	return v
end

function cfg.set(key, value)
	value = math.floor(value)
	cfg.mem[key] = value
	local C = type(Config) == "table" and Config or {}
	if pcall(function() C.WriteInt(K.CFG, key, value) end) then return end
	if pcall(function() C.WriteFloat(K.CFG, key, value) end) then return end
	pcall(function() C.WriteString(K.CFG, key, tostring(value)) end)
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
		cfg.set("icon_x", math.floor(state.icon.x))
		cfg.set("icon_y", math.floor(state.icon.y))
	end
	if state.win then
		cfg.set("win_x", math.floor(state.win.x))
		cfg.set("win_y", math.floor(state.win.y))
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
	local ix, iy = cfg.get("icon_x", -1), cfg.get("icon_y", -1)
	state.icon = (ix >= 0 and iy >= 0) and { x = ix, y = iy } or default_icon()
	local wx, wy = cfg.get("win_x", -1), cfg.get("win_y", -1)
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

local function js_str(s)
	return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\r?\n", "\\n") .. "'"
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
		if p and p:IsValid() and not in_game then
			local root = p
			while true do
				local up = root:GetParent()
				if not (up and up:IsValid()) then break end
				root = up
			end
			local rid = root:GetID() or ""
			log("menu root " .. (rid ~= "" and rid or "<no id>") .. " from " .. name)
			if root ~= p and rid ~= "" then p, name = root, rid end
		end
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

local function input_js(body)
	if not state.input_id then return false end
	return js_in(state.parent, state.parent_id, state.input_id, body)
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

local function origin(parent)
	if Engine.IsInGame() or not (parent and parent:IsValid()) then return 0, 0 end
	local ok, pos = pcall(parent.GetPositionWithinWindow, parent)
	if not ok or not pos then return 0, 0 end
	local ox, oy = math.floor(pos.x), math.floor(pos.y)
	if ox ~= state.origin_x or oy ~= state.origin_y then
		state.origin_x, state.origin_y = ox, oy
		log(string.format("menu parent origin %d,%d", ox, oy))
	end
	return ox, oy
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
	local ox, oy = origin(parent)
	local x, y, w, h = table.unpack(rect)
	x, y = x - ox, y - oy
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

local function umbrella_widget(name, path)
	if state.found[name] == nil then
		local ok, widget = pcall(Menu.Find, table.unpack(path))
		state.found[name] = (ok and widget) or false
		log("umbrella " .. name .. " " .. (state.found[name] and "found" or "not found"))
	end
	return state.found[name] or nil
end

local function pick_wheel_off(list)
	for _, pattern in ipairs(K.WHEEL_OFF) do
		for i, item in ipairs(list) do
			if tostring(item):lower():find(pattern) then return i - 1 end
		end
	end
	return nil
end

local function set_wheel_zoom(on)
	local w = umbrella_widget("zoom_wheel", K.WHEEL_PATH)
	if not w then return end
	if on then
		local list = w:List() or {}
		local cur, pick = w:Get(), pick_wheel_off(list)
		if not state.wheel_list_logged then
			state.wheel_list_logged = true
			log("umbrella zoom wheel items: " .. table.concat(list, ", ") .. " current=" .. tostring(cur) .. " pick=" .. tostring(pick))
		end
		if pick and pick ~= cur then
			state.wheel_prev = cur
			cfg.set("wheel_prev", cur)
			w:Set(pick)
		end
	elseif state.wheel_prev then
		w:Set(state.wheel_prev)
		state.wheel_prev = nil
		cfg.set("wheel_prev", -1)
	end
end

local function restore_wheel_zoom()
	local prev = cfg.get("wheel_prev", -1)
	if prev < 0 then return end
	local w = umbrella_widget("zoom_wheel", K.WHEEL_PATH)
	if w then w:Set(prev) end
	cfg.set("wheel_prev", -1)
	log("umbrella zoom wheel restored to " .. prev)
end

local function hold_camera()
	local cam = state.cam_hold and umbrella_widget("camera_distance", K.CAM_PATH)
	if cam and cam:Get() ~= state.cam_hold then cam:Set(state.cam_hold) end
end

local function set_zoom_lock(on)
	if on == state.zoom_on then return end
	state.zoom_on = on
	set_wheel_zoom(on)
	local cam = umbrella_widget("camera_distance", K.CAM_PATH)
	state.cam_hold = (on and cam) and cam:Get() or nil
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
	if on == state.web_focus then return end
	state.web_focus = on
	state.focus_at = 0
	state.keys = {}
	state.edit_queue = {}
	if not on then
		input_js(K.JS_BLUR)
		parent_js(K.JS_BLUR)
	end
	log("web focus " .. tostring(on))
end

local function bridge_ready()
	return state.inject == "ok" and state.input_id ~= nil
end

local function keep_focus(now, mouse_down)
	if not (state.web_focus and panel_valid()) or mouse_down or now < state.focus_at then return end
	state.focus_at = now + K.FOCUS_INTERVAL
	if bridge_ready() then
		input_js(K.JS_FOCUS)
	else
		parent_js(string.format(K.JS_FOCUS_WEB, state.input_id or ""))
	end
	local report = state.parent:GetAttribute("tt_focus", "") or ""
	if report ~= "" and not state.focus_seen[report] then
		state.focus_seen[report] = true
		log("focus " .. report)
	end
end

local function pull_text(now)
	if not bridge_ready() or state.typed ~= "" or now < state.pull_at then return end
	state.pull_at = now + K.PULL_INTERVAL
	parent_js(string.format(K.JS_SEND, state.input_id, "", 0))
end

local function watch_bridge()
	local attr = function(name) return state.parent:GetAttribute(name, "") or "" end
	local inject = attr("tt_inject")
	if inject ~= state.inject then
		state.inject = inject
		state.focus_at = 0
		log("page script " .. inject .. " via " .. attr("tt_im"))
	end
	local feedback = attr("tt_fb")
	if feedback ~= state.feedback then
		state.feedback = feedback
		log("page feedback " .. feedback)
	end
	local typed = attr("tt_typed")
	local how = typed:match("^(%a+):") or ""
	if how ~= state.typed then
		state.typed = how
		log("text entry got " .. typed)
	end
	if not state.pulled and attr("tt_lpull") ~= "" then
		state.pulled = true
		log("text entry read by lua")
	end
end

local function key_held(a, b)
	return Input.IsKeyDown(a, true) or Input.IsKeyDown(b, true)
end

local function edit_action(key)
	local B = Enum.ButtonCode
	if key_held(B.KEY_LALT, B.KEY_RALT) then return nil end
	if K.EDIT_KEYS[key] then return K.EDIT_KEYS[key] end
	if key_held(B.KEY_LCONTROL, B.KEY_RCONTROL) then return K.CTRL_KEYS[key] end
	return nil
end

local function press_edit(key, action, src)
	local B = Enum.ButtonCode
	local mods = (key_held(B.KEY_LSHIFT, B.KEY_RSHIFT) and 1 or 0) + (key_held(B.KEY_LCONTROL, B.KEY_RCONTROL) and 2 or 0)
	local now = os.clock()
	state.keys[key] = { action = action, mods = mods, src = src, t = now, next = now + K.REPEAT_DELAY }
	state.edit_queue[#state.edit_queue + 1] = { action, mods }
	if not state.edit_logged[src] then
		state.edit_logged[src] = true
		log("edit key " .. action .. " via " .. src)
	end
end

local function poll_edit_keys(now)
	for _, key in ipairs(K.POLL_KEYS) do
		local down = Input.IsKeyDown(key, true)
		local rising = down and not state.poll_prev[key]
		state.poll_prev[key] = down
		local h = state.keys[key]
		if h then
			if not down then
				if h.src == "poll" or now - h.t > K.RELEASE_GRACE then state.keys[key] = nil end
			elseif K.REPEAT[h.action] and now >= h.next then
				h.next = now + K.REPEAT_RATE
				state.edit_queue[#state.edit_queue + 1] = { h.action, h.mods }
			end
		elseif rising and state.web_focus and bridge_ready() and not state.key_events then
			local action = edit_action(key)
			if action then press_edit(key, action, "poll") end
		end
	end
end

local function flush_edits()
	local queue = state.edit_queue
	if #queue == 0 then return end
	state.edit_queue = {}
	if not panel_valid() then return end
	for _, item in ipairs(queue) do
		parent_js(string.format(K.JS_SEND, state.input_id or "", item[1], item[2]))
	end
end

local function edit_key_event(data)
	local held = state.keys[data.key]
	if data.event == Enum.EKeyEvent.EKeyEvent_KEY_UP then
		if not held then return true end
		state.keys[data.key] = nil
		return false
	end
	if data.event ~= Enum.EKeyEvent.EKeyEvent_KEY_DOWN or not (state.open and state.web_focus and bridge_ready()) then return true end
	local action = held and held.action or edit_action(data.key)
	if not action then return true end
	state.key_events = true
	if not held then press_edit(data.key, action, "event") end
	return false
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
	local ox, oy = origin(state.parent)
	return string.format("x: %dpx; y: %dpx; width: %dpx; height: %dpx; opacity: %.2f; background-color: #000000;",
		math.floor((state.win.x - ox) * k), math.floor((state.win.y + K.HEADER_H - oy) * k),
		math.floor(ui.win_w:Get() * k), math.floor(ui.win_h:Get() * k),
		ui.win_alpha:Get() / 100)
end

local function input_style()
	local k = 1080 / screen().y
	local ox, oy = origin(state.parent)
	return string.format("x: %dpx; y: %dpx; width: 2px; height: 2px; opacity: 0.01;",
		math.floor((state.win.x - ox) * k), math.floor((state.win.y + K.HEADER_H - oy) * k))
end

local function apply_style()
	if not panel_valid() then return end
	local style = window_style()
	if style ~= state.style then
		state.style = style
		state.panel:SetStyle(style)
	end
	if state.input and state.input:IsValid() then
		local istyle = input_style()
		if istyle ~= state.input_style then
			state.input_style = istyle
			state.input:SetStyle(istyle)
		end
	end
end

local function destroy_panel()
	if state.input_id then
		input_js(K.JS_BLUR)
		if state.input and state.input:IsValid() then disarm(state.input) end
		input_js(K.JS_KILL)
	end
	if panel_valid() then
		disarm(state.panel)
		parent_js(K.JS_KILL)
	end
	state.panel = nil
	state.panel_id = nil
	state.style = ""
	state.input = nil
	state.input_id = nil
	state.input_style = ""
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
	for _, attr in ipairs({ "tt_report", "tt_typed", "tt_lpull", "tt_focus", "tt_inject", "tt_im", "tt_fb", "tt_methods", "tt_url", "tt_pend" }) do
		parent:SetAttribute(attr, "")
	end
	state.typed, state.pulled, state.inject, state.feedback = "", false, "", ""
	local sent = parent_js(string.format(K.JS_CREATE, base, url, js_str(K.PAGE_JS), in_game and 0 or 1))
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
	state.input_id = report:match("bridge:(%S+)")
	state.input = state.input_id and parent:FindChildTraverse(state.input_id) or nil
	log("text bridge " .. tostring(state.input_id) .. " lua=" .. tostring(state.input ~= nil))
	if not state.methods_logged then
		state.methods_logged = true
		log("html methods: " .. (parent:GetAttribute("tt_methods", "") or ""))
	end
	state.style = ""
	state.input_style = ""
	apply_style()
	return true
end

function act.open(url)
	url = url or K.URL_START
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
	local typed = state.parent and state.parent:IsValid() and state.parent:GetAttribute("tt_typed", "") or ""
	if typed ~= "" then log("typed total " .. typed) end
	destroy_panel()
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
		parent_js("if(!p)return;var u=par.GetAttributeString('tt_url','')||p.GetAttributeString('url','');if(p.Reload){p.Reload();}else if(p.SetURL&&u){p.SetURL(u);}")
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

local function allowed()
	return ui.scope:Get() == 1 or Engine.IsInGame()
end

local function icon_visible()
	return ui.icon:Get() and not state.icon_hidden and allowed()
end

local function reveal_target(mx, my)
	if not ui.icon_reveal:Get() or state.open or (state.press and state.press.target == "icon") then return 1 end
	local size = ui.icon_size:Get()
	local x, y = state.icon.x, state.icon.y
	local dx = math.max(x - mx, 0, mx - (x + size))
	local dy = math.max(y - my, 0, my - (y + size))
	local t = clamp(1 - math.sqrt(dx * dx + dy * dy) / ui.icon_radius:Get(), 0, 1)
	return t * t * (3 - 2 * t)
end

local function update_fade(mx, my)
	local now = os.clock()
	local dt = state.fade_clock and clamp(now - state.fade_clock, 0, 0.1) or 0
	state.fade_clock = now
	local target = icon_visible() and reveal_target(mx, my) or 0
	local step = dt * 6
	if math.abs(target - state.fade) <= step then
		state.fade = target
	else
		state.fade = state.fade + (target > state.fade and step or -step)
	end
end

local function over_menu(mx, my)
	if not Menu.Opened() then return false end
	local mp, ms = Menu.Pos(), Menu.Size()
	return in_rect(mx, my, mp.x, mp.y, ms.x, ms.y)
end

local function typing_key(key)
	local B = Enum.ButtonCode
	return (key >= B.KEY_0 and key <= B.KEY_EQUAL) or key == B.KEY_SPACE or K.EDIT_KEYS[key] ~= nil
end

local function bind_hit(name, bind)
	local none = Enum.ButtonCode.KEY_NONE
	local pressed = bind:IsPressed()
	local k1, k2 = bind:Buttons()
	k1, k2 = k1 or none, k2 or none
	local single = k1 ~= none and k2 == none
	local down = single and Input.IsKeyDown(k1, true) or false
	local rising = down and not state.bind_down[name]
	state.bind_down[name] = down
	if not (state.open and state.web_focus) then return pressed and not Input.IsInputCaptured() end
	if typing_key(k1) or typing_key(k2) then return false end
	if single then return rising end
	return pressed
end

local function hit_test(mx, my)
	if over_menu(mx, my) then return nil end
	if state.open and state.win then
		local r = header_rects()
		if in_rect(mx, my, table.unpack(r.close)) then return "close" end
		if in_rect(mx, my, table.unpack(r.reload)) then return "reload" end
		if in_rect(mx, my, table.unpack(r.login)) then return "login" end
		if in_rect(mx, my, table.unpack(r.header)) then return "header" end
		if in_rect(mx, my, table.unpack(r.grip)) then return "grip" end
	end
	if icon_visible() and state.icon and state.fade > 0.05 then
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
	local a = ui.icon_alpha:Get() / 100 * state.fade
	local hovered = in_rect(mx, my, x, y, size, size) or (state.press and state.press.target == "icon")
	local bg_a = math.floor((hovered and 245 or 225) * a)
	Render.FilledRect(Vec2(x, y), Vec2(x + size, y + size), Color(12, 12, 14, bg_a), size * 0.26)
	local pad = size * 0.18
	Render.Image(state.logo, Vec2(x + pad, y + pad), Vec2(size - pad * 2, size - pad * 2), Color(255, 255, 255, math.floor(255 * a)))
end

local function draw()
	ensure_assets()
	if not state.icon then load_positions() end
	local now = os.clock()
	local mx, my = Input.GetCursorPos()
	local down = Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1, true)
	if down and not state.mouse_down then
		local target = hit_test(mx, my)
		if target then
			on_press(target, mx, my)
		elseif not (state.open and state.over_window) then
			focus_web(false)
		end
	elseif not down and state.mouse_down then
		on_release(mx, my)
		state.focus_at = 0
	end
	state.mouse_down = down
	update_drag(mx, my)
	if state.open and not panel_valid() then
		log("panel lost")
		act.close()
	end
	if state.open and state.parent_in_game ~= Engine.IsInGame() then
		local url = state.parent and state.parent:IsValid() and state.parent:GetAttribute("tt_url", "") or ""
		log("move window to " .. (Engine.IsInGame() and "game" or "menu") .. " " .. url)
		act.open(url ~= "" and url or nil)
	end
	local r = state.open and header_rects() or nil
	sync_hit("header", state.parent, state.parent_id, r and r.header)
	sync_hit("grip", state.parent, state.parent_id, r and r.grip)
	update_fade(mx, my)
	local shown = icon_visible() and state.fade > 0.05
	local hud, hud_id = nil, nil
	if shown then hud, hud_id = find_parent(Engine.IsInGame()) end
	local size = ui.icon_size:Get()
	sync_hit("icon", hud, hud_id, shown and { state.icon.x, state.icon.y, size, size } or nil)
	state.over_window = r ~= nil and not over_menu(mx, my)
		and in_rect(mx, my, state.win.x, state.win.y, ui.win_w:Get(), K.HEADER_H + ui.win_h:Get())
	set_zoom_lock(state.over_window)
	hold_camera()
	if state.over_window ~= state.prev_over then
		state.prev_over = state.over_window
		focus_web(state.over_window)
	end
	if r and state.parent and state.parent:IsValid() then
		local load = state.parent:GetAttribute("tt_load", "") or ""
		if load ~= state.load_status then
			state.load_status = load
			if load ~= "" then log("page " .. load) end
		end
		poll_edit_keys(now)
		flush_edits()
		watch_bridge()
		keep_focus(now, down)
		pull_text(now)
	end
	if r then
		apply_style()
		draw_window(mx, my)
	end
	if shown then draw_icon(mx, my) end
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
	if not ui.enable:Get() or not allowed() then
		if state.open then act.close() end
		return
	end
	if bind_hit("key", ui.key) then act.toggle() end
	if bind_hit("hide", ui.hide_key) then
		state.icon_hidden = not state.icon_hidden
		log("icon hidden=" .. tostring(state.icon_hidden))
	end
end

function script.OnUpdate()
	if not ui.enable:Get() then return end
	update_death()
end

function script.OnKeyEvent(data)
	if data.key ~= Enum.ButtonCode.KEY_MOUSE3 then return edit_key_event(data) end
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
	if ui.scope:Get() ~= 1 then act.close() end
	drop_hit("icon")
	state.alive, state.death_at, state.parent_in_game = nil, nil, nil
end

function script.OnScriptsLoaded()
	load_positions()
	restore_wheel_zoom()
	local s = screen()
	log(string.format("v%s loaded, enabled=%s, scope=%d, reveal=%s, screen=%dx%d, in_game=%s",
		K.VERSION, tostring(ui.enable:Get()), ui.scope:Get(), tostring(ui.icon_reveal:Get()),
		math.floor(s.x), math.floor(s.y), tostring(Engine.IsInGame())))
end

return script
