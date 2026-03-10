-- Session Builder (The Bridge - Advanced Input)
-- Version 2.3
-- Author: Jordi Molas - The Little Cavern Studio
-- About: This script allows you to configure your studio name, sessions, and templates through a visual interface, feeding the Dynamic Session Launcher database.


local db_path = reaper.GetResourcePath() .. "/Scripts/jmolas_scripts/Session_DB.txt"

-- Recuperar Nombre del Estudio de la memoria de REAPER
local saved_studio = reaper.GetExtState("SessionBuilder", "StudioName")

-- =====================================================================
--  DISEÑO Y VARIABLES
-- =====================================================================
local col_bg = {r=237, g=237, b=237}
local col_input = {r=255, g=255, b=255}
local col_txt = {r=20, g=20, b=20}
local col_accent = {r=100, g=150, b=100}

local w, h = 500, 560 
local input_idx = 1
local last_mouse_cap = 0
local last_click_time = 0

local inputs = {
    {label = "1. Studio Name:", value = saved_studio, cursor = #saved_studio, sel = false},
    {label = "2. Button Name (e.g., Mixing):", value = "", cursor = 0, sel = false},
    {label = "3. Template (.rpp file name - Optional):", value = "", cursor = 0, sel = false},
    {label = "4. Screenset ID (Optional):", value = "", cursor = 0, sel = false},
    {label = "5. Action ID (Optional):", value = "", cursor = 0, sel = false},
    {label = "6. RGB Button Color (e.g., 87,238,31):", value = "150,150,150", cursor = 11, sel = false}
}

function GetCenteredPosition(w, h)
    local main_hwnd = reaper.GetMainHwnd()
    local res, left, top, right, bottom = reaper.JS_Window_GetRect(main_hwnd)
    if res then return left + (right - left - w) / 2, top + (bottom - top - h) / 2 end
    return 100, 100
end

function AddSession()
    reaper.SetExtState("SessionBuilder", "StudioName", inputs[1].value, true)
    local f = io.open(db_path, "a")
    if f then
        f:write(string.format("%s|%s|%s|%s|%s\n", inputs[2].value, inputs[3].value, inputs[4].value, inputs[5].value, inputs[6].value))
        f:close()
        for i=2, 5 do 
            inputs[i].value = "" 
            inputs[i].cursor = 0
            inputs[i].sel = false
        end
        reaper.ShowMessageBox("Session added successfully.", "Session Builder", 0)
    end
end

function Main()
    gfx.set(col_bg.r/255, col_bg.g/255, col_bg.b/255, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)
    gfx.setfont(1, "Arial", 15, 98)
    for i, input in ipairs(inputs) do
        local y = 20 + (i-1) * 70 
        gfx.set(col_txt.r/255, col_txt.g/255, col_txt.b/255, 1)
        gfx.x, gfx.y = 25, y
        gfx.drawstr(input.label)
        gfx.set(col_input.r/255, col_input.g/255, col_input.b/255, 1)
        gfx.rect(25, y + 25, gfx.w - 50, 30, 1)
        if i == input_idx then gfx.set(0, 0.5, 1, 1) else gfx.set(0.8, 0.8, 0.8, 1) end
        gfx.rect(25, y + 25, gfx.w - 50, 30, 0)
        if input.sel and i == input_idx then
            gfx.set(0, 0.5, 1, 0.3)
            local tw, th = gfx.measurestr(input.value)
            gfx.rect(30, y + 28, tw + 5, 24, 1)
        end
        gfx.set(0, 0, 0, 1)
        gfx.x, gfx.y = 32, y + 32
        gfx.drawstr(input.value)
        if i == input_idx and not input.sel then
            local sub_str = input.value:sub(1, input.cursor)
            local cur_x = 32 + gfx.measurestr(sub_str)
            if math.floor(reaper.time_precise() * 2) % 2 == 0 then
                gfx.set(0, 0, 0, 1)
                gfx.rect(cur_x, y + 28, 1, 24, 1)
            end
        end
    end
    local y_btns = 460
    gfx.set(col_accent.r/255, col_accent.g/255, col_accent.b/255, 1)
    gfx.rect(25, y_btns, gfx.w - 50, 45, 1)
    gfx.set(1, 1, 1, 1)
    gfx.setfont(1, "Arial", 16, 98)
    local tw, th = gfx.measurestr("ADD SESSION")
    gfx.x, gfx.y = (gfx.w - tw)/2, y_btns + (45-th)/2
    gfx.drawstr("ADD SESSION")
    local mouse_cap = gfx.mouse_cap
    local char = gfx.getchar()
    if mouse_cap & 1 == 1 and last_mouse_cap & 1 == 0 then
        local clicked_in_input = false
        local now = reaper.time_precise()
        for i, input in ipairs(inputs) do
            local y = 20 + (i-1) * 70
            if gfx.mouse_x > 25 and gfx.mouse_x < gfx.w - 25 and gfx.mouse_y > y + 25 and gfx.mouse_y < y + 55 then
                clicked_in_input = true
                if i ~= input_idx then input.sel = false end
                input_idx = i
                if now - last_click_time < 0.3 then input.sel = true input.cursor = #input.value
                else input.sel = false input.cursor = #input.value end
                last_click_time = now
            end
        end
        if not clicked_in_input and gfx.mouse_x > 25 and gfx.mouse_x < gfx.w - 25 and gfx.mouse_y > y_btns and gfx.mouse_y < y_btns + 45 then
            AddSession()
        end
    end
    last_mouse_cap = mouse_cap
    if char > 0 then
        local inp = inputs[input_idx]
        if char == 13 then AddSession()
        elseif char == 9 then inp.sel = false input_idx = (input_idx % 6) + 1
        elseif char == 1818584692 then inp.sel = false inp.cursor = math.max(0, inp.cursor - 1)
        elseif char == 1919379572 then inp.sel = false inp.cursor = math.min(#inp.value, inp.cursor + 1)
        elseif char == 8 then
            if inp.sel then inp.value = "" inp.cursor = 0 inp.sel = false
            elseif inp.cursor > 0 then
                inp.value = inp.value:sub(1, inp.cursor - 1) .. inp.value:sub(inp.cursor + 1)
                inp.cursor = inp.cursor - 1
            end
        elseif char >= 32 and char <= 126 then
            if inp.sel then inp.value = "" inp.cursor = 0 inp.sel = false end
            inp.value = inp.value:sub(1, inp.cursor) .. string.char(char) .. inp.value:sub(inp.cursor + 1)
            inp.cursor = inp.cursor + 1
        end
    end
    if char >= 0 and char ~= 27 then reaper.defer(Main) end
end

local stX, stY = GetCenteredPosition(w, h)
gfx.init("SESSION BUILDER - SETTINGS", w, h, 0, stX, stY)
Main()