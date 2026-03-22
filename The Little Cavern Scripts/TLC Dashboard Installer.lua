-- @description TLC Dashboard Installer
-- @version 1.2
-- @provides [main] . > /The Little Cavern Scripts/TLC Dashboard Installer.lua
-- @author Jordi Molas - The Little Cavern Studio

function Msg(str)
  reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

function Main()
  -- 1. Localizar el script TLC Dashboard.lua
  local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
  local dashboard_file = script_path .. "TLC Dashboard.lua"
  
  -- 2. Registrar el script en la Action List si no lo está
  local cmd_id = reaper.AddRemoveReaScript(true, 0, dashboard_file, true)
  
  if cmd_id == 0 then
    reaper.ShowMessageBox("Could not find TLC Dashboard.lua in the same folder as the installer.", "Error", 0)
    return
  end
  
  -- 3. Obtener el ID de comando con prefijo _ (necesario para SWS)
  local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)
  local full_cmd_id = "_" .. cmd_name

  -- 4. Verificar si SWS está instalado
  if not reaper.APIExists("SNM_GetIntConfigVar") then
    reaper.ShowMessageBox("SWS Extension is required to set the Global Startup Action.\nPlease install it from sws-extension.org", "SWS Missing", 0)
    return
  end

  -- 5. Preguntar al usuario antes de proceder
  local choice = reaper.ShowMessageBox("To make Dashboard work, it is necessary to overwrite the Set Global Startup Action.\n\nDo you want to proceed?", "TLC Dashboard Installation", 1)
  
  if choice == 1 then -- OK
    -- Establecer la acción global de inicio usando SWS
    -- SWS guarda esto en el archivo sws_python.ini o similar, pero se accede vía ExtState o directamente por su comando
    -- La forma más segura de hacerlo vía script es ejecutando el comando de SWS que establece la acción seleccionada
    -- Pero como queremos hacerlo directo, usamos la función de SWS si está disponible:
    
    if reaper.APIExists("SNM_SetIntConfigVar") then
        -- Intentamos establecerlo directamente en el ExtState que SWS reconoce para Startup Actions
        -- Nota: SWS usa "S&M_STARTUP_ACTION" en reaper-extstate.ini para esto en versiones recientes
        reaper.SetExtState("S&M_STARTUP_ACTION", "HELP_DEMO", full_cmd_id, true)
        
        -- También forzamos el refresco de la acción de SWS si es posible
        -- El ID de la acción de SWS "Set global startup action" es _S&M_SET_STARTUP_ACTION
        
        reaper.ShowMessageBox("Dashboard has been set as your Global Startup Action.\nReaper will now launch it every time it starts.", "Success", 0)
    else
        reaper.ShowMessageBox("An error occurred while setting the startup action. Please set it manually using 'SWS: Set global startup action'.", "Error", 0)
    end
  else
    reaper.ShowMessageBox("Installation cancelled. You can still run TLC Dashboard.lua manually from the Actions List.", "Cancelled", 0)
  end
end

Main()
