-- @description TLC Dashboard
-- @version 1.0
-- @provides [main] . > The Little Cavern Scripts/TLC Dashboard.lua
-- @author Jordi Molas - The Little Cavern Studio

local db_path = reaper.GetResourcePath() .. "/Scripts/jmolas_scripts/Session_DB.txt"
local ini_path = reaper.GetResourcePath() .. "/reaper.ini"
local ruta_templates = reaper.GetResourcePath() .. "/ProjectTemplates/"

-- Leer el nombre del estudio configurado en el TLC Dashboard Setup.lua
local studio_name = reaper.GetExtState("SessionBuilder", "StudioName")
if studio_name == "" then studio_name = "LITTLE CAVERN" end

-- =====================================================================
--  VARIABLES DE DISEÑO
-- =====================================================================
local sessions = {}
local recent_projects = {}
local win_w, win_h = 800, 520 
local col_sesiones_w = 350
local col_recientes_w = 450
local margin = 20
local bg_r, bg_g, bg_b = 237/255, 237/255, 237/255

-- =====================================================================
--  FUNCIONES
-- =====================================================================
function GetCenteredPosition(w, h)
    local main_hwnd = reaper.GetMainHwnd()
    local res, left, top, right, bottom = reaper.JS_Window_GetRect(main_hwnd)
    if res then
        return left + (right - left - w) / 2, top + (bottom - top - h) / 2
    else
        local _, _, r, b = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, 1)
        return (r - w) / 2, (b - h) / 2
    end
end

function LeerProyectosRecientes()
    recent_projects = {}
    local temp_raw = {}
    local f = io.open(ini_path, "r")
    if not f then return end
    for line in f:lines() do
        local path = line:match("^recent%d*=(.+)")
        if path then
            local clean_path = path:gsub('"', '')
            if clean_path:lower():match("%.rpp$") then table.insert(temp_raw, clean_path) end
        end
    end
    f:close()
    for i = #temp_raw, 1, -1 do
        local p = temp_raw[i]
        local is_dup = false
        for _, already_in in ipairs(recent_projects) do if already_in.path == p then is_dup = true break end end
        if not is_dup and #recent_projects < 10 then
            local name = p:match("([^/\\]+)%.rpp$") or p:match("([^/\\]+)$")
            table.insert(recent_projects, {name = name, path = p})
        end
    end
end

function ParseColor(str)
    if not str then return {180, 180, 180} end
    str = str:gsub("%s+", "") 
    local r, g, b = str:match("(%d+),(%d+),(%d+)")
    return {tonumber(r) or 180, tonumber(g) or 180, tonumber(b) or 180}
end

function LeerBaseDatos()
    local f = io.open(db_path, "r")
    if not f then return end
    sessions = {}
    for line in f:lines() do
        if line:sub(1,1) ~= "#" and line ~= "" then
            local label, template, screenset, action, color_str = line:match("([^|]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
            if label then
                table.insert(sessions, {
                    label = label, template = template, screenset = tonumber(screenset) or 0,
                    action = action, color = ParseColor(color_str)
                })
            end
        end
    end
    f:close()
end

-- =====================================================================
--  DIBUJO
-- =====================================================================
function draw_session_button(y, label, color)
    local x = margin
    local w = col_sesiones_w - (margin * 1.5)
    local h = 55
    local mouse_over = gfx.mouse_x > x and gfx.mouse_x < x + w and gfx.mouse_y > y and gfx.mouse_y < y + h
    local r, g, b = color[1]/255, color[2]/255, color[3]/255
    gfx.set(mouse_over and math.min(r+0.1,1) or r, mouse_over and math.min(g+0.1,1) or g, mouse_over and math.min(b+0.1,1) or b, 1)
    gfx.rect(x, y, w, h, 1)
    local lum = (r * 0.299 + g * 0.587 + b * 0.114)
    gfx.set(lum > 0.6 and 0 or 1, lum > 0.6 and 0 or 1, lum > 0.6 and 0 or 1, 1)
    gfx.setfont(1, "Arial", 19)
    local tw, th = gfx.measurestr(label)
    gfx.x, gfx.y = x + (w - tw) / 2, y + (h - th) / 2
    gfx.drawstr(label)
    return mouse_over and gfx.mouse_cap & 1 == 1
end

function draw_recent_item(i, y, name, path)
    local x = col_sesiones_w + margin
    local w = col_recientes_w - (margin * 2)
    local h = 38
    local mouse_over = gfx.mouse_x > x and gfx.mouse_x < x + w and gfx.mouse_y > y and gfx.mouse_y < y + h
    if mouse_over then
        gfx.set(0, 0, 0, 0.05)
        gfx.rect(x, y, w, h, 1)
    end
    gfx.set(0, 0, 0, mouse_over and 1 or 0.8)
    gfx.setfont(1, "Arial", 16)
    gfx.x, gfx.y = x + 10, y + (h - 16) / 2
    gfx.drawstr(i .. ". " .. name)
    if mouse_over and gfx.mouse_cap & 1 == 1 then
        reaper.Main_openProject(path)
        gfx.quit()
    end
end

function main()
    gfx.set(bg_r, bg_g, bg_b, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)
    gfx.set(0, 0, 0, 1)
    gfx.setfont(1, "Arial", 16, 98) 
    gfx.x, gfx.y = margin, 18
    gfx.drawstr("NEW SESSION")
    local curr_y = 55
    if #sessions == 0 then
        if draw_session_button(curr_y, "Create your home screen now", {100, 150, 100}) then
            local builder_path = reaper.GetResourcePath() .. "/Scripts/jmolas_scripts/TLC Dashboard Setup.lua"
            local cmd_id = reaper.AddRemoveReaScript(true, 0, builder_path, true)
            if cmd_id ~= 0 then
                reaper.Main_OnCommand(cmd_id, 0)
            else
                reaper.ShowMessageBox("TLC Dashboard Setup.lua not found in /Scripts/jmolas_scripts/", "Error", 0)
            end
            gfx.quit()
        end
    else
        for i, s in ipairs(sessions) do
            if draw_session_button(curr_y, s.label, s.color) then
                if not s.template or s.template == "" then reaper.Main_OnCommand(40001, 0)
                else reaper.Main_openProject("template:" .. ruta_templates .. s.template) end
                local sc, ac = s.screenset, s.action
                reaper.defer(function()
                    local start = reaper.time_precise()
                    function wait()
                        if reaper.time_precise() - start < 1.0 then reaper.defer(wait)
                        else
                            if sc and sc ~= 0 then reaper.Main_OnCommand(sc, 0) end
                            if ac and ac ~= "" then 
                                local id = reaper.NamedCommandLookup(ac)
                                if id ~= 0 then reaper.Main_OnCommand(id, 0) end
                            end
                        end
                    end
                    wait()
                end)
                gfx.quit()
            end
            curr_y = curr_y + 68
        end
    end
    gfx.set(0, 0, 0, 0.1)
    gfx.rect(col_sesiones_w, 20, 1, gfx.h - 40, 1)
    gfx.set(0, 0, 0, 1)
    gfx.setfont(1, "Arial", 16, 98)
    gfx.x, gfx.y = col_sesiones_w + margin, 18
    gfx.drawstr("RECENT PROJECTS")
    for i, proj in ipairs(recent_projects) do
        draw_recent_item(i, 55 + (i-1)*42, proj.name, proj.path)
    end
    -- ENLACE AL EXPLORADOR
    gfx.set(0.2, 0.4, 0.8, 1)
    gfx.setfont(1, "Arial", 14, 117) 
    local txt_link = "[ OPEN PROJECT EXPLORER ]"
    local tw, th = gfx.measurestr(txt_link)
    gfx.x, gfx.y = gfx.w - tw - margin, gfx.h - th - 20
    local link_hover = gfx.mouse_x > gfx.x and gfx.mouse_x < gfx.x + tw and gfx.mouse_y > gfx.y and gfx.mouse_y < gfx.y + th
    if link_hover then 
        gfx.set(0, 0, 1, 1) 
        if gfx.mouse_cap & 1 == 1 then reaper.Main_OnCommand(40025, 0) end
    end
    gfx.drawstr(txt_link)
    if gfx.getchar() >= 0 then reaper.defer(main) end
end

-- INICIO
LeerBaseDatos()
LeerProyectosRecientes()
local stX, stY = GetCenteredPosition(win_w, win_h)
gfx.init(studio_name .. " - DASHBOARD", win_w, win_h, 0, stX, stY)
main()