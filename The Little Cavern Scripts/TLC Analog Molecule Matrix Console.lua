-- @description TLC Analog Molecule Matrix Console
-- @version 1.1
-- @provides [main] . > TLC Analog Molecule Matrix Console.lua
-- @author Jordi Molas - The Little Cavern Studio
-- @about This external Lua script scans your session and automatically changes the topology of each track based on a smart configuration. You can define exactly where to apply each topology using keywords:
-- Master: If you use a track named, for instance, "Mixbus" instead of the default REAPER Master, you can specify it in the Settings.
-- Buses: You can identify group tracks using keywords like "Bus", "Grp", or "Stems".
-- Channels: Individual tracks are identified as "Channel" topology by default, but you can add exceptions for tracks like "Aux" or "Click" to be ignored.
-- Additionally, it offers a fast, global way to push an initial setup for the 3 main console emulation values (3D Flux, Thermal Bloom, and Analog Texture) to all your instances at once.


local plugin_name = "Analog Molecule"
local ext_section = "JORDAN_AM_MATRIX"

-- Parameter IDs
local p_id, p_topo, p_flux, p_therm, p_text, p_drive, p_link, p_flavor = 0, 1, 3, 4, 5, 6, 11, 12

-- State Matrix
local state = {
    [0] = { flavor=0, flux=20, therm=20, text=12 },
    [1] = { flavor=0, flux=20, therm=20, text=12 },
    [2] = { flavor=0, flux=20, therm=20, text=12 }
}

-- Hardcoded Presets
local flavor_presets = {
    [1] = {flux = 15.0, therm = 30.0, text = 20.0}, -- British A
    [2] = {flux = 10.0, therm = 20.0, text = 12.0}, -- Solid State E
    [3] = {flux = 5.0,  therm = 10.0, text = 8.0},  -- US Discr.
    [4] = {flux = 2.0,  therm = 5.0,  text = 2.0}   -- Modern
}

-- UI Variables
local bg_r, bg_g, bg_b = 237/255, 237/255, 237/255
local link_M_to_B, link_M_to_C, link_B_to_C = false, false, false
local mouse_down, active_slider = false, ""
local last_mouse_cap, last_click_time = 0, 0

-- Config Overlay
local show_config = false
local cfg_w, cfg_h = 660, 540
local cfg_x, cfg_y = 0, 0
local is_dragging_cfg = false
local drag_dx, drag_dy = 0, 0
local cfg_temp = {}
local active_input_key = nil

--------------------------------------------------------------------------------
-- 1. DATABASE ENGINE
--------------------------------------------------------------------------------
function GetThesaurus()
    local exc = reaper.GetExtState(ext_section, "exclusions")
    if exc == "0" then exc = "" end
    local bk = reaper.GetExtState(ext_section, "bus_keywords")
    if bk == "0" or bk == "" then bk = "BUS, GRP" end

    return {
        master_name = reaper.GetExtState(ext_section, "master_name") ~= "" and reaper.GetExtState(ext_section, "master_name") or "MIXBUS",
        use_reaper_master = reaper.GetExtState(ext_section, "use_reaper_master") ~= "0",
        bus_keywords = bk,
        bus_parents = reaper.GetExtState(ext_section, "bus_parents") ~= "0",
        exclusions = exc
    }
end

function SaveThesaurus(cfg)
    reaper.SetExtState(ext_section, "master_name", cfg.master_name.val:upper(), true)
    reaper.SetExtState(ext_section, "use_reaper_master", cfg.use_reaper_master and "1" or "0", true)
    reaper.SetExtState(ext_section, "bus_keywords", cfg.bus_keywords.val:upper(), true)
    reaper.SetExtState(ext_section, "bus_parents", cfg.bus_parents and "1" or "0", true)
    reaper.SetExtState(ext_section, "exclusions", cfg.exclusions.val:upper(), true)
end

function MatchCSV(text, csv)
    if not csv or csv == "" then return false end
    for word in csv:gmatch('([^,]+)') do
        local clean_word = word:gsub("^%s*(.-)%s*$", "%1"):upper()
        if text:upper():find(clean_word, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- 2. PROCESSING ENGINE (FIXED MASTER TRACK API LOOP)
--------------------------------------------------------------------------------
function ReadBackFromPlugins()
    if mouse_down then return end
    local found = { [0]=false, [1]=false, [2]=false }
    -- INICIO BUCLE: -1 (Master Track) hasta CountTracks
    for t = -1, reaper.CountTracks(0) - 1 do
        local track = (t == -1) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
        for i = 0, reaper.TrackFX_GetCount(track) - 1 do
            local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
            if fx_name:match(plugin_name) then
                local topo = math.floor(reaper.TrackFX_GetParam(track, i, p_topo) + 0.5)
                if topo >= 0 and topo <= 2 and not found[topo] then
                    state[topo].flavor = reaper.TrackFX_GetParam(track, i, p_flavor)
                    state[topo].flux   = reaper.TrackFX_GetParam(track, i, p_flux)
                    state[topo].therm  = reaper.TrackFX_GetParam(track, i, p_therm)
                    state[topo].text   = reaper.TrackFX_GetParam(track, i, p_text)
                    found[topo] = true
                end
            end
        end
    end
end

function UpdatePlugins(target_topo, param_idx, value)
    for t = -1, reaper.CountTracks(0) - 1 do
        local track = (t == -1) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
        for i = 0, reaper.TrackFX_GetCount(track) - 1 do
            local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
            if fx_name:match(plugin_name) then
                local current_topo = math.floor(reaper.TrackFX_GetParam(track, i, p_topo) + 0.5)
                if current_topo == target_topo then
                    reaper.TrackFX_SetParam(track, i, param_idx, value)
                end
            end
        end
    end
end

function PushChange(source_topo, param_idx, value, key_name)
    state[source_topo][key_name] = value
    UpdatePlugins(source_topo, param_idx, value)
    if source_topo == 2 then 
        if link_M_to_B then state[1][key_name] = value; UpdatePlugins(1, param_idx, value) end
        if link_M_to_C then state[0][key_name] = value; UpdatePlugins(0, param_idx, value) end
    elseif source_topo == 1 then 
        if link_B_to_C and not link_M_to_C then state[0][key_name] = value; UpdatePlugins(0, param_idx, value) end
    end
end

-- Función auxiliar para cuando manipulamos un slider de manera manual
local function CheckSliderChange(topo_idx, param, val, key)
    if val ~= state[topo_idx][key] then
        PushChange(topo_idx, param, val, key)
        -- Si alteramos un slider manualmente, la interfaz salta a Custom(0)
        if state[topo_idx].flavor ~= 0 then
            PushChange(topo_idx, p_flavor, 0, "flavor")
        end
    end
end

function AutoConfig()
    local cfg = GetThesaurus()
    reaper.Undo_BeginBlock()
    local current_id = 1
    
    for t = -1, reaper.CountTracks(0) - 1 do
        local track = (t == -1) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local is_folder = (t ~= -1) and (reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1) or false
        local is_native_master = (t == -1)
        
        local target_topo = 0
        local skip = false

        if (cfg.use_reaper_master and is_native_master) or (not cfg.use_reaper_master and track_name:upper() == cfg.master_name:upper()) then
            target_topo = 2
        elseif (cfg.bus_parents and is_folder) or MatchCSV(track_name, cfg.bus_keywords) then
            target_topo = 1
        elseif MatchCSV(track_name, cfg.exclusions) then
            skip = true
        end

        if not skip then
            for i = 0, reaper.TrackFX_GetCount(track) - 1 do
                local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
                if fx_name:match(plugin_name) then
                    reaper.TrackFX_SetParam(track, i, p_topo, target_topo)
                    reaper.TrackFX_SetParam(track, i, p_id, current_id)
                    reaper.TrackFX_SetParam(track, i, p_link, 1)
                    current_id = (current_id % 180) + 1
                end
            end
        end
    end
    reaper.Undo_EndBlock("AM Matrix: Scan", -1)
    ReadBackFromPlugins()
end

--------------------------------------------------------------------------------
-- 3. DRAWING & UI COMPONENTS
--------------------------------------------------------------------------------
function DrawCheckbox(x, y, label, checked, disabled)
    local alpha = disabled and 0.4 or 1.0
    gfx.set(0, 0, 0, alpha)
    gfx.rect(x, y, 16, 16, false)
    if checked then
        gfx.line(x+3, y+8, x+7, y+12); gfx.line(x+7, y+12, x+13, y+4)
        gfx.line(x+3, y+7, x+7, y+11); gfx.line(x+7, y+11, x+13, y+3)
    end
    gfx.setfont(1, "Arial", 15); gfx.x, gfx.y = x + 24, y; gfx.drawstr(label)
    
    if not disabled and gfx.mouse_cap & 1 == 1 and not mouse_down then
        if gfx.mouse_x >= x and gfx.mouse_x <= x + 300 and gfx.mouse_y >= y and gfx.mouse_y <= y + 16 then
            mouse_down = true; return not checked
        end
    end
    return checked
end

function DrawFlavorSelector(topo_idx, x, y, w)
    local flavors = {"Custom", "British A", "Solid State E", "US Discr.", "Modern"}
    local current = math.floor(state[topo_idx].flavor + 0.5)
    local btn_w, btn_h = w / 2 - 2, 30
    for i = 0, 4 do
        local bx = x + ((i % 2) * (btn_w + 4))
        local by = y + (math.floor(i / 2) * (btn_h + 4))
        
        local is_on = (current == i)
        gfx.set(is_on and 0.2 or 0.8, is_on and 0.5 or 0.8, is_on and 0.8 or 0.8, 1)
        gfx.rect(bx, by, btn_w, btn_h, true)
        
        gfx.set(is_on and 1 or 0, is_on and 1 or 0, is_on and 1 or 0, 1)
        gfx.setfont(1, "Arial", 15, 98)
        local tw, _ = gfx.measurestr(flavors[i+1])
        gfx.x, gfx.y = bx + (btn_w - tw)/2, by + 7; gfx.drawstr(flavors[i+1])
        
        if gfx.mouse_cap & 1 == 1 and not mouse_down then
            if gfx.mouse_x >= bx and gfx.mouse_x <= bx + btn_w and gfx.mouse_y >= by and gfx.mouse_y <= by + btn_h then
                mouse_down = true
                
                -- Lógica perfecta: Actualizamos el GUI al instante y SÓLO le mandamos el Flavor al Plugin.
                if flavor_presets[i] then
                    state[topo_idx].flux = flavor_presets[i].flux
                    state[topo_idx].therm = flavor_presets[i].therm
                    state[topo_idx].text = flavor_presets[i].text
                    
                    -- Sincronizamos enlaces visualmente
                    if topo_idx == 2 then 
                        if link_M_to_B then state[1].flux, state[1].therm, state[1].text = flavor_presets[i].flux, flavor_presets[i].therm, flavor_presets[i].text end
                        if link_M_to_C then state[0].flux, state[0].therm, state[0].text = flavor_presets[i].flux, flavor_presets[i].therm, flavor_presets[i].text end
                    elseif topo_idx == 1 then
                        if link_B_to_C and not link_M_to_C then state[0].flux, state[0].therm, state[0].text = flavor_presets[i].flux, flavor_presets[i].therm, flavor_presets[i].text end
                    end
                end
                
                -- Le decimos al plugin "Cambia el Flavor". El plugin se encargará de mover los sliders internamente.
                PushChange(topo_idx, p_flavor, i, "flavor")
            end
        end
    end
    return y + (3 * (btn_h + 4))
end

function DrawSlider(slider_id, x, y, w, h, val, min_val, max_val, title, unit, color_idx)
    gfx.set(1, 1, 1, 1); gfx.rect(x, y, w, h, true)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.rect(x, y, w, h, false)
    
    local percent = (val - min_val) / (max_val - min_val)
    if color_idx == 1 then gfx.set(0.3, 0.7, 0.9, 0.5)      -- Flux
    elseif color_idx == 2 then gfx.set(0.9, 0.4, 0.2, 0.5)  -- Thermal
    elseif color_idx == 3 then gfx.set(0.4, 0.8, 0.4, 0.5)  -- Texture
    end
    gfx.rect(x+1, y+1, (w-2) * percent, h-2, true)
    
    if gfx.mouse_cap & 1 == 1 then
        if not mouse_down and gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h then
            mouse_down = true; active_slider = slider_id
        end
        if mouse_down and active_slider == slider_id then
            local mouse_pos = math.max(0, math.min(w, gfx.mouse_x - x))
            val = min_val + ((mouse_pos / w) * (max_val - min_val))
            val = math.floor(val * 10 + 0.5) / 10
        end
    end
    
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 14)
    gfx.x, gfx.y = x + 8, y + 6; gfx.drawstr(title)
    local val_str = string.format("%.1f", val) .. unit
    local tw, _ = gfx.measurestr(val_str); gfx.x = x + w - tw - 8; gfx.drawstr(val_str)
    return val
end

function DrawButton(x, y, w, h, label, bg_color, text_color)
    local hover = gfx.mouse_x >= x and gfx.mouse_x <= x+w and gfx.mouse_y >= y and gfx.mouse_y <= y+h
    gfx.set(bg_color[1] * (hover and 0.9 or 1), bg_color[2] * (hover and 0.9 or 1), bg_color[3] * (hover and 0.9 or 1), 1)
    gfx.rect(x, y, w, h, true)
    
    gfx.set(text_color[1], text_color[2], text_color[3], 1)
    gfx.setfont(1, "Arial", 14, 98)
    local tw, th = gfx.measurestr(label)
    gfx.x, gfx.y = x + (w-tw)/2, y + (h-th)/2; gfx.drawstr(label)
    
    if hover and gfx.mouse_cap & 1 == 1 and not mouse_down then
        mouse_down = true; return true
    end
    return false
end

--------------------------------------------------------------------------------
-- 4. CONFIGURATION OVERLAY
--------------------------------------------------------------------------------
function OpenConfig()
    local raw = GetThesaurus()
    cfg_temp = {
        use_reaper_master = raw.use_reaper_master,
        bus_parents = raw.bus_parents,
        master_name = { val = raw.master_name, cursor = #raw.master_name, sel = false },
        bus_keywords = { val = raw.bus_keywords, cursor = #raw.bus_keywords, sel = false },
        exclusions = { val = raw.exclusions, cursor = #raw.exclusions, sel = false }
    }
    cfg_x, cfg_y = (gfx.w - cfg_w)/2, (gfx.h - cfg_h)/2
    show_config = true
    active_input_key = nil
end

function DrawTextInputAdvanced(key, inp_obj, x, y, w, h, disabled)
    local is_active = (active_input_key == key) and not disabled
    
    gfx.set(disabled and 0.95 or 1, disabled and 0.95 or 1, disabled and 0.95 or 1, 1)
    gfx.rect(x, y, w, h, true)
    
    gfx.set(is_active and 0.2 or 0.7, is_active and 0.5 or 0.7, is_active and 0.8 or 0.7, 1)
    gfx.rect(x, y, w, h, false)
    if is_active then gfx.rect(x-1, y-1, w+2, h+2, false) end
    
    if is_active and inp_obj.sel then
        gfx.set(0, 0.5, 1, 0.3)
        local tw = gfx.measurestr(inp_obj.val)
        gfx.rect(x + 5, y + 3, tw + 5, h - 6, true)
    end
    
    if not disabled and gfx.mouse_cap & 1 == 1 and last_mouse_cap & 1 == 0 then
        if gfx.mouse_x >= x and gfx.mouse_x <= x+w and gfx.mouse_y >= y and gfx.mouse_y <= y+h then
            if active_input_key ~= key then inp_obj.sel = false end
            active_input_key = key
            
            local now = reaper.time_precise()
            if now - last_click_time < 0.3 then
                inp_obj.sel = true; inp_obj.cursor = #inp_obj.val
            else
                inp_obj.sel = false; inp_obj.cursor = #inp_obj.val
            end
            last_click_time = now
        elseif is_active then
            active_input_key = nil
        end
    end
    
    gfx.setfont(1, "Arial", 15); gfx.set(0, 0, 0, disabled and 0.4 or 1)
    local display_text = inp_obj.val
    
    local tw, th = gfx.measurestr(display_text)
    while tw > w - 15 and #display_text > 0 do
        display_text = display_text:sub(2)
        tw, th = gfx.measurestr(display_text)
    end
    
    gfx.x, gfx.y = x + 8, y + (h - th)/2
    gfx.drawstr(display_text)
    
    if is_active and not inp_obj.sel then
        local sub_str = display_text:sub(1, inp_obj.cursor)
        local cur_x = x + 8 + gfx.measurestr(sub_str)
        if math.floor(reaper.time_precise() * 2) % 2 == 0 then
            gfx.line(cur_x, y + 4, cur_x, y + h - 4)
        end
    end
end

function DrawConfigOverlay()
    gfx.set(bg_r, bg_g, bg_b, 0.85); gfx.rect(0, 0, gfx.w, gfx.h, true)
    
    if gfx.mouse_cap & 1 == 1 then
        if not mouse_down and gfx.mouse_x >= cfg_x and gfx.mouse_x <= cfg_x + cfg_w and gfx.mouse_y >= cfg_y and gfx.mouse_y <= cfg_y + 45 then
            is_dragging_cfg = true
            drag_dx, drag_dy = gfx.mouse_x - cfg_x, gfx.mouse_y - cfg_y
            mouse_down = true
        end
    else
        is_dragging_cfg = false
    end

    if is_dragging_cfg then
        cfg_x = math.max(0, math.min(gfx.w - cfg_w, gfx.mouse_x - drag_dx))
        cfg_y = math.max(0, math.min(gfx.h - cfg_h, gfx.mouse_y - drag_dy))
    end

    gfx.set(1, 1, 1, 1); gfx.rect(cfg_x, cfg_y, cfg_w, cfg_h, true)
    gfx.set(0.6, 0.6, 0.6, 1); gfx.rect(cfg_x, cfg_y, cfg_w, cfg_h, false)
    
    gfx.set(0.92, 0.92, 0.92, 1); gfx.rect(cfg_x+1, cfg_y+1, cfg_w-2, 45, true)
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 18, 98)
    gfx.x, gfx.y = cfg_x + 35, cfg_y + 13; gfx.drawstr("MATRIX SETTINGS")
    gfx.set(0.8, 0.8, 0.8, 1); gfx.line(cfg_x, cfg_y + 46, cfg_x + cfg_w, cfg_y + 46)
    
    local cy = cfg_y + 70
    local px = cfg_x + 35
    local input_width = cfg_w - 70
    
    -- 1. MASTER
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 16, 98)
    gfx.x, gfx.y = px, cy; gfx.drawstr("1. MASTER TRACK IDENTIFICATION")
    
    cy = cy + 28
    cfg_temp.use_reaper_master = DrawCheckbox(px, cy, "Use REAPER Native Master Track", cfg_temp.use_reaper_master, false)
    
    cy = cy + 30
    gfx.set(0, 0, 0, cfg_temp.use_reaper_master and 0.4 or 1.0); gfx.setfont(1, "Arial", 15)
    gfx.x, gfx.y = px, cy; gfx.drawstr("Or use custom track named:")
    
    cy = cy + 22
    DrawTextInputAdvanced("master_name", cfg_temp.master_name, px, cy, input_width, 30, cfg_temp.use_reaper_master)
    if cfg_temp.use_reaper_master and active_input_key == "master_name" then active_input_key = nil end

    -- 2. BUS
    cy = cy + 55
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 16, 98)
    gfx.x, gfx.y = px, cy; gfx.drawstr("2. BUS & GROUP IDENTIFICATION")
    
    cy = cy + 28
    cfg_temp.bus_parents = DrawCheckbox(px, cy, "Identify Parent Folders as Buses", cfg_temp.bus_parents, false)
    
    cy = cy + 30
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 15)
    gfx.x, gfx.y = px, cy; gfx.drawstr("Also apply to (words separated by commas):")
    cy = cy + 22
    DrawTextInputAdvanced("bus_keywords", cfg_temp.bus_keywords, px, cy, input_width, 30, false)
    
    -- 3. CHANNELS
    cy = cy + 55
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 16, 98)
    gfx.x, gfx.y = px, cy; gfx.drawstr("3. TRACK IDENTIFICATION")
    
    cy = cy + 28
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 15)
    gfx.x, gfx.y = px, cy; gfx.drawstr("Apply this config to all tracks except these tracks with those words (words separated by commas):")
    cy = cy + 22
    DrawTextInputAdvanced("exclusions", cfg_temp.exclusions, px, cy, input_width, 30, false)
    
    -- Botones
    local bY = cfg_y + cfg_h - 55
    if DrawButton(px, bY, 130, 35, "CANCEL", {0.8, 0.8, 0.8}, {0,0,0}) then
        show_config = false; active_input_key = nil
    end
    
    if DrawButton(cfg_x + cfg_w - 185, bY, 150, 35, "SAVE SETTINGS", {0.2, 0.6, 0.8}, {1,1,1}) then
        SaveThesaurus(cfg_temp)
        AutoConfig()
        show_config = false; active_input_key = nil
    end
end

--------------------------------------------------------------------------------
-- 5. MAIN EVENT LOOP
--------------------------------------------------------------------------------
function HandleKeyboard()
    local char = gfx.getchar()
    if char == -1 then gfx.quit(); return end
    if char == 0 then return end
    
    if show_config and active_input_key then
        local inp = cfg_temp[active_input_key]
        
        if char == 27 or char == 13 then
            active_input_key = nil; inp.sel = false
        elseif char == 9 then
            inp.sel = false
            if active_input_key == "master_name" then active_input_key = "bus_keywords"
            elseif active_input_key == "bus_keywords" then active_input_key = "exclusions"
            else active_input_key = "master_name" end
        elseif char == 1818584692 then
            inp.sel = false; inp.cursor = math.max(0, inp.cursor - 1)
        elseif char == 1919379572 then
            inp.sel = false; inp.cursor = math.min(#inp.val, inp.cursor + 1)
        elseif char == 1752132965 then
            inp.sel = false; inp.cursor = 0
        elseif char == 6647396 then
            inp.sel = false; inp.cursor = #inp.val
        elseif char == 8 then
            if inp.sel then inp.val = ""; inp.cursor = 0; inp.sel = false
            elseif inp.cursor > 0 then
                inp.val = inp.val:sub(1, inp.cursor - 1) .. inp.val:sub(inp.cursor + 1)
                inp.cursor = inp.cursor - 1
            end
        elseif char == 6579564 then
            if inp.sel then inp.val = ""; inp.cursor = 0; inp.sel = false
            elseif inp.cursor < #inp.val then
                inp.val = inp.val:sub(1, inp.cursor) .. inp.val:sub(inp.cursor + 2)
            end
        elseif char >= 32 and char <= 126 then
            if inp.sel then inp.val = ""; inp.cursor = 0; inp.sel = false end
            inp.val = inp.val:sub(1, inp.cursor) .. string.char(char) .. inp.val:sub(inp.cursor + 1)
            inp.cursor = inp.cursor + 1
        end
    else
        if char == 27 then gfx.quit() end
    end
end

function Main()
    HandleKeyboard()

    gfx.set(bg_r, bg_g, bg_b, 1); gfx.rect(0, 0, gfx.w, gfx.h, true)
    
    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 20, 98)
    gfx.x, gfx.y = 25, 20; gfx.drawstr("ANALOG MOLECULE MATRIX")
    
    if not show_config then
        if DrawButton(gfx.w - 120, 15, 100, 30, "CONFIG", {0.2, 0.2, 0.2}, {1,1,1}) then
            OpenConfig()
        end
    end

    local col_w = (gfx.w - 80) / 3
    local pos_C, pos_B, pos_M = 25, 25 + col_w + 15, 25 + (col_w * 2) + 30

    gfx.set(0, 0, 0, 1); gfx.setfont(1, "Arial", 16, 98)
    gfx.x, gfx.y = pos_C+5, 65; gfx.drawstr("CHANNELS")
    gfx.x = pos_B+5; gfx.drawstr("BUSES")
    gfx.x = pos_M+5; gfx.drawstr("MASTER TRACK")
    
    gfx.set(0.8, 0.8, 0.8, 1)
    gfx.line(pos_C, 90, pos_C+col_w, 90); gfx.line(pos_B, 90, pos_B+col_w, 90); gfx.line(pos_M, 90, pos_M+col_w, 90)

    link_M_to_B = DrawCheckbox(pos_M, 100, "Link to BUSES", link_M_to_B, false)
    link_M_to_C = DrawCheckbox(pos_M, 125, "Link to CHANNELS", link_M_to_C, false)
    link_B_to_C = DrawCheckbox(pos_B, 100, "Link to CHANNELS", link_B_to_C, link_M_to_B)

    local fY = 160
    
    -- CHANNELS
    local nC = DrawFlavorSelector(0, pos_C, fY, col_w)
    local vC_fl = DrawSlider("c1", pos_C, nC, col_w, 26, state[0].flux, 0, 100, "3D Flux %", "%", 1)
    CheckSliderChange(0, p_flux, vC_fl, "flux")
    local vC_th = DrawSlider("c2", pos_C, nC+32, col_w, 26, state[0].therm, 0, 100, "Thermal Bloom %", "%", 2)
    CheckSliderChange(0, p_therm, vC_th, "therm")
    local vC_te = DrawSlider("c3", pos_C, nC+64, col_w, 26, state[0].text, 0, 100, "Analog Texture %", "%", 3)
    CheckSliderChange(0, p_text, vC_te, "text")

    -- BUSES
    local nB = DrawFlavorSelector(1, pos_B, fY, col_w)
    local vB_fl = DrawSlider("b1", pos_B, nB, col_w, 26, state[1].flux, 0, 100, "3D Flux %", "%", 1)
    CheckSliderChange(1, p_flux, vB_fl, "flux")
    local vB_th = DrawSlider("b2", pos_B, nB+32, col_w, 26, state[1].therm, 0, 100, "Thermal Bloom %", "%", 2)
    CheckSliderChange(1, p_therm, vB_th, "therm")
    local vB_te = DrawSlider("b3", pos_B, nB+64, col_w, 26, state[1].text, 0, 100, "Analog Texture %", "%", 3)
    CheckSliderChange(1, p_text, vB_te, "text")

    -- MASTER
    local nM = DrawFlavorSelector(2, pos_M, fY, col_w)
    local vM_fl = DrawSlider("m1", pos_M, nM, col_w, 26, state[2].flux, 0, 100, "3D Flux %", "%", 1)
    CheckSliderChange(2, p_flux, vM_fl, "flux")
    local vM_th = DrawSlider("m2", pos_M, nM+32, col_w, 26, state[2].therm, 0, 100, "Thermal Bloom %", "%", 2)
    CheckSliderChange(2, p_therm, vM_th, "therm")
    local vM_te = DrawSlider("m3", pos_M, nM+64, col_w, 26, state[2].text, 0, 100, "Analog Texture %", "%", 3)
    CheckSliderChange(2, p_text, vM_te, "text")

    if show_config then DrawConfigOverlay() end

    last_mouse_cap = gfx.mouse_cap
    if gfx.mouse_cap & 1 == 0 then mouse_down = false; active_slider = "" end
    
    reaper.defer(Main)
end

AutoConfig()
gfx.init("Analog Molecule Matrix Pro v6.0", 900, 560, 0, 150, 150)
Main()
