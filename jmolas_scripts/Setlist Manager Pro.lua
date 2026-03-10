-- @description Setlist Manager
-- @version 1.1.4
-- @author Jordi Molas - The Little Cavern Studio
-- @about Load as many projects at the same time as you define in the setlist

local reaper = reaper
local imgui = reaper.ImGui_CreateContext('Setlist_Manager_Pro')

local script_path = debug.getinfo(1,'S').source:match([[^@?(.*[\/])]])
local config_file = script_path .. "setlist_manager_data.lua"

-- =================================================================
-- NATIVE LUA SERIALIZATION ENGINE
-- =================================================================
local function serialize_table(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local tmp = string.rep(" ", depth)
    if name then
        if type(name) == "number" then tmp = tmp .. "[" .. name .. "] = "
        else tmp = tmp .. "[\"" .. tostring(name) .. "\"] = " end
    end
    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")
        for k, v in pairs(val) do
            tmp = tmp .. serialize_table(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end
        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then tmp = tmp .. tostring(val)
    elseif type(val) == "string" then tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then tmp = tmp .. (val and "true" or "false")
    else tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\"" end
    return tmp
end

-- =================================================================
-- DATA ENGINE & STATE
-- =================================================================
local data = { selected_group = 1, groups = {} }
local editing_group_idx = nil
local rename_buf = ""

-- Async Deploy Engine Variables
local deploy_state = 0
local deploy_group = nil
local deploy_frame_wait = 0
local deploy_last_count = -1
local deploy_state2_attempted = false

function SaveConfig()
    local file = io.open(config_file, "w")
    if file then
        file:write("return " .. serialize_table(data))
        file:close()
    end
end

function LoadConfig()
    local chunk = loadfile(config_file)
    if chunk then
        data = chunk()
        if type(data) ~= "table" or not data.groups then
             data = { selected_group = 1, groups = { { name = "Default Band", songs = {} } } }
        end
    else
        data = { selected_group = 1, groups = { { name = "Default Band", songs = {} } } }
        SaveConfig()
    end
end

-- =================================================================
-- ASYNCHRONOUS DEPLOY ENGINE
-- =================================================================
function HandleAsyncDeploy()
    if deploy_state == 0 then return end

    if deploy_frame_wait > 0 then
        deploy_frame_wait = deploy_frame_wait - 1
        return
    end

    local count = 0
    while reaper.EnumProjects(count, "") do count = count + 1 end

    if deploy_state == 1 then
        if count > 1 then
            if deploy_last_count ~= -1 and count == deploy_last_count then
                deploy_state = 0 
                return
            end
            deploy_last_count = count
            reaper.Main_OnCommand(40860, 0) -- Close current project
            deploy_frame_wait = 3 
            return
        else
            deploy_state = 2
            deploy_state2_attempted = false
            return
        end
        
    elseif deploy_state == 2 then
        local proj, path = reaper.EnumProjects(0, "")
        local dirty = reaper.IsProjectDirty(proj)
        
        if path ~= "" or dirty ~= 0 then
            if deploy_state2_attempted then
                deploy_state = 0 
                deploy_state2_attempted = false
                return
            end
            deploy_state2_attempted = true
            reaper.Main_OnCommand(40860, 0) 
            deploy_frame_wait = 3
            return
        else
            deploy_state = 3
            deploy_state2_attempted = false
            return
        end
        
    elseif deploy_state == 3 then
        for i, song in ipairs(deploy_group.songs) do
            if reaper.file_exists(song.path) then
                if i == 1 then
                    reaper.Main_openProject(song.path)
                else
                    reaper.Main_OnCommand(40859, 0) 
                    reaper.Main_openProject(song.path)
                end
            end
        end
        reaper.Main_OnCommand(41929, 0) 
        deploy_state = 0 
    end
end

-- =================================================================
-- GUI COMPATIBILITY LAYER
-- =================================================================
local function GetBorderFlag()
    if reaper.ImGui_ChildFlags_Borders then return reaper.ImGui_ChildFlags_Borders()
    elseif reaper.ImGui_ChildFlags_Border then return reaper.ImGui_ChildFlags_Border() end
    return 1 
end
local CHILD_BORDER = GetBorderFlag()

-- =================================================================
-- GUI (REAIMGUI)
-- =================================================================
function DrawGUI()
    HandleAsyncDeploy()

    reaper.ImGui_SetNextWindowSize(imgui, 650, 400, reaper.ImGui_Cond_FirstUseEver())
    
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_WindowBg(), 0xEDEDEDFF)
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Text(), 0x141414FF)
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ChildBg(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_PopupBg(), 0xEDEDEDFF)
    
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_TitleBg(), 0xCCCCCCFF)
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_TitleBgActive(), 0xDDDDDDFF)
    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_TitleBgCollapsed(), 0xCCCCCCFF)

    local visible, open = reaper.ImGui_Begin(imgui, 'SETLIST MANAGER PRO', true)
    
    if visible then
        -- BANDS (LEFT COLUMN)
        if reaper.ImGui_BeginChild(imgui, "left", 180, 0, CHILD_BORDER) then
            reaper.ImGui_Text(imgui, "BANDS")
            reaper.ImGui_Separator(imgui)
            
            for i, group in ipairs(data.groups) do
                if editing_group_idx == i then
                    reaper.ImGui_SetKeyboardFocusHere(imgui)
                    local rv, new_text = reaper.ImGui_InputText(imgui, "##rename"..i, rename_buf, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                    if rv then rename_buf = new_text end
                    
                    if rv or reaper.ImGui_IsItemDeactivated(imgui) then
                        if rename_buf ~= "" then data.groups[i].name = rename_buf end
                        editing_group_idx = nil
                        SaveConfig()
                    end
                else
                    if reaper.ImGui_Selectable(imgui, group.name .. "##" .. i, data.selected_group == i) then
                        data.selected_group = i
                    end
                    
                    if reaper.ImGui_BeginPopupContextItem(imgui) then
                        if reaper.ImGui_MenuItem(imgui, "Rename Band") then
                            editing_group_idx = i
                            rename_buf = group.name
                        end
                        if reaper.ImGui_MenuItem(imgui, "Delete Band") then
                            table.remove(data.groups, i)
                            if data.selected_group > #data.groups then data.selected_group = #data.groups end
                            if data.selected_group < 1 and #data.groups > 0 then data.selected_group = 1 end
                            SaveConfig()
                        end
                        reaper.ImGui_EndPopup(imgui)
                    end
                end
            end
            
            reaper.ImGui_Spacing(imgui)
            if reaper.ImGui_Button(imgui, "+ Add Band", -1) then
                table.insert(data.groups, {name = "New Band", songs = {}})
                SaveConfig()
            end
            reaper.ImGui_EndChild(imgui)
        end
        
        reaper.ImGui_SameLine(imgui)
        
        -- SONGS (RIGHT COLUMN)
        reaper.ImGui_BeginGroup(imgui)
            local current = data.groups[data.selected_group]
            reaper.ImGui_Text(imgui, "SETLIST: " .. (current and current.name:upper() or ""))
            reaper.ImGui_Separator(imgui)
            
            if reaper.ImGui_BeginChild(imgui, "list", 0, -45, CHILD_BORDER) then
                if current then
                    for j, song in ipairs(current.songs) do
                        reaper.ImGui_Selectable(imgui, j .. ". " .. song.title .. "##" .. j)
                        
                        if reaper.ImGui_BeginDragDropSource(imgui) then
                            reaper.ImGui_SetDragDropPayload(imgui, "REORDER", tostring(j))
                            reaper.ImGui_Text(imgui, "Moving: " .. song.title)
                            reaper.ImGui_EndDragDropSource(imgui)
                        end
                        if reaper.ImGui_BeginDragDropTarget(imgui) then
                            local rv, payload = reaper.ImGui_AcceptDragDropPayload(imgui, "REORDER")
                            if rv then
                                local moved = table.remove(current.songs, tonumber(payload))
                                table.insert(current.songs, j, moved)
                                SaveConfig()
                            end
                            reaper.ImGui_EndDragDropTarget(imgui)
                        end
                        
                        if reaper.ImGui_BeginPopupContextItem(imgui) then
                            if reaper.ImGui_MenuItem(imgui, "Delete Song") then
                                table.remove(current.songs, j)
                                SaveConfig()
                            end
                            reaper.ImGui_EndPopup(imgui)
                        end
                    end
                    
                    reaper.ImGui_Spacing(imgui)
                    reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Button(), 0xE0E0E0FF)
                    reaper.ImGui_Button(imgui, "--- DROP .RPP FILES HERE ---", -1, 40)
                    reaper.ImGui_PopStyleColor(imgui)
                    
                    if reaper.ImGui_BeginDragDropTarget(imgui) then
                        local rv, count = reaper.ImGui_AcceptDragDropPayloadFiles(imgui)
                        if rv then
                            for f = 0, count - 1 do
                                local ok, filepath = reaper.ImGui_GetDragDropPayloadFile(imgui, f)
                                if ok then
                                    local name = filepath:match("([^/\\]+)%.[rR][pP][pP]$")
                                    if name then
                                        table.insert(current.songs, {title = name, path = filepath})
                                    end
                                end
                            end
                            SaveConfig()
                        end
                        reaper.ImGui_EndDragDropTarget(imgui)
                    end
                end
                reaper.ImGui_EndChild(imgui)
            end
            
            if deploy_state > 0 then
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Button(), 0x999999FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ButtonHovered(), 0x999999FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ButtonActive(), 0x999999FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Text(), 0xFFFFFFFF) 
                
                reaper.ImGui_Button(imgui, "DEPLOYING... PLEASE WAIT", -1, 35)
                
                reaper.ImGui_PopStyleColor(imgui, 4)
            else
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Button(), 0x649664FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ButtonHovered(), 0x78B478FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ButtonActive(), 0x507850FF) 
                reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Text(), 0xFFFFFFFF) 
                
                if reaper.ImGui_Button(imgui, "DEPLOY SETLIST", -1, 35) then
                    deploy_group = data.groups[data.selected_group]
                    if deploy_group and #deploy_group.songs > 0 then
                        deploy_state = 1
                        deploy_last_count = -1
                        deploy_frame_wait = 0
                    end
                end
                
                reaper.ImGui_PopStyleColor(imgui, 4)
            end

        reaper.ImGui_EndGroup(imgui)
        reaper.ImGui_End(imgui)
    end
    
    reaper.ImGui_PopStyleColor(imgui, 7) 
    
    if open then reaper.defer(DrawGUI) end
end

LoadConfig()
DrawGUI()
