--[[
 * ReaScript Name: Locate True Peaks (Math Engine)
 * Description: Advanced peak detection and localization engine
 * @version 10.1
 * @author Jordi Molas - The Little Cavern Studio
 * @about
 * High-precision Math Engine for True Peak localization.
 * Version 10.1 (English Only, Studio Name & Empty State CTA)
 * @license GPL v3
--]]

function main()
    local count_sel_items = reaper.CountSelectedMediaItems(0)
    
    if count_sel_items == 0 then
        reaper.ShowMessageBox("Por favor, selecciona al menos un item de audio.", "Error", 0)
        return
    end

    local retval, userInput = reaper.GetUserInputs("TP a MIDI (Math Engine)", 1, "Picos (TP) a marcar por item:", "5")
    if not retval then return end
    local numPicosTarget = tonumber(userInput) or 5

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local report_tracks = {}

    for i = 0, count_sel_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take and not reaper.TakeIsMIDI(take) then
            local orig_track = reaper.GetMediaItemTrack(item)
            local orig_track_idx = reaper.CSurf_TrackToID(orig_track, false) - 1
            
            local _, orig_track_name = reaper.GetSetMediaTrackInfo_String(orig_track, "P_NAME", "", false)
            if orig_track_name == "" then 
                orig_track_name = "Track " .. tostring(math.floor(reaper.GetMediaTrackInfo_Value(orig_track, "IP_TRACKNUMBER"))) 
            end

            -- 1. Crear pista de reporte oscura (High Contrast)
            if not report_tracks[orig_track] then
                reaper.InsertTrackAtIndex(orig_track_idx, false)
                local new_track = reaper.GetTrack(0, orig_track_idx)
                reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "TP REPORT: " .. orig_track_name, true)
                reaper.SetMediaTrackInfo_Value(new_track, "I_CUSTOMCOLOR", reaper.ColorToNative(40, 40, 40) | 0x1000000)
                report_tracks[orig_track] = new_track
            end
            
            local report_track = report_tracks[orig_track]
            local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            local midi_item = reaper.CreateNewMIDIItemInProj(report_track, itemPos, itemPos + itemLen, false)
            local midi_take = reaper.GetActiveTake(midi_item)
            reaper.GetSetMediaItemTakeInfo_String(midi_take, "P_NAME", "TP Markers", true)

            -- 2. Variables del motor matemático de volumen
            local item_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
            local take_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
            local base_multiplier = item_vol * take_vol
            
            -- Buscamos la envolvente de la toma (Take Envelope)
            local vol_env = reaper.GetTakeEnvelopeByName(take, "Volume")

            -- 3. Análisis de True Peaks (Interpolación Cúbica Multicanal)
            local source = reaper.GetMediaItemTake_Source(take)
            local samplerate = reaper.GetMediaSourceSampleRate(source)
            local numChannels = reaper.GetMediaSourceNumChannels(source) 
            
            local accessor = reaper.CreateTakeAudioAccessor(take)
            local bufferSize = 16384 
            local buffer = reaper.new_array(bufferSize * numChannels) 
            
            local picosData = {}
            local totalSamples = math.floor(itemLen * samplerate)
            local samplesRead = 0
            local osFactor = 4 

            while samplesRead < totalSamples do
                local samplesToRead = math.min(bufferSize, totalSamples - samplesRead)
                reaper.GetAudioAccessorSamples(accessor, samplerate, numChannels, samplesRead / samplerate, samplesToRead, buffer)
                
                for j = 3, samplesToRead - 3, 50 do 
                    local limit = math.min(j + 49, samplesToRead - 3)
                    local max_idx_frame = j
                    local max_val_raw = 0
                    local max_c = 0
                    
                    for m = j, limit do
                        for c = 0, numChannels - 1 do
                            local idx = (m - 1) * numChannels + c + 1
                            local v = math.abs(buffer[idx] or 0)
                            if v > max_val_raw then
                                max_val_raw = v
                                max_idx_frame = m
                                max_c = c 
                            end
                        end
                    end
                    
                    if max_val_raw > 0.0001 then
                        local tp_val_raw = max_val_raw
                        local offset = max_c + 1
                        
                        -- Interpolación Cúbica
                        local y0 = buffer[(max_idx_frame - 2) * numChannels + offset] or 0
                        local y1 = buffer[(max_idx_frame - 1) * numChannels + offset] or 0
                        local y2 = buffer[max_idx_frame * numChannels + offset] or 0
                        local y3 = buffer[(max_idx_frame + 1) * numChannels + offset] or 0
                        
                        local a0 = -0.5*y0 + 1.5*y1 - 1.5*y2 + 0.5*y3
                        local a1 = y0 - 2.5*y1 + 2.0*y2 - 0.5*y3
                        local a2 = -0.5*y0 + 0.5*y2
                        local a3 = y1
                        
                        for k = 1, osFactor - 1 do
                            local mu = k / osFactor
                            local mu2 = mu * mu
                            local interp = a0*mu*mu2 + a1*mu2 + a2*mu + a3
                            local vTP = math.abs(interp)
                            if vTP > tp_val_raw then tp_val_raw = vTP end
                        end
                        
                        local ym1 = buffer[(max_idx_frame - 3) * numChannels + offset] or 0
                        local b0 = -0.5*ym1 + 1.5*y0 - 1.5*y1 + 0.5*y2
                        local b1 = ym1 - 2.5*y0 + 2.0*y1 - 0.5*y2
                        local b2 = -0.5*ym1 + 0.5*y1
                        local b3 = y0
                        
                        for k = 1, osFactor - 1 do
                            local mu = k / osFactor
                            local mu2 = mu * mu
                            local interp = b0*mu*mu2 + b1*mu2 + b2*mu + b3
                            local vTP = math.abs(interp)
                            if vTP > tp_val_raw then tp_val_raw = vTP end
                        end

                        -- CORRECCIÓN APLICADA: Calculamos el volumen en el tiempo relativo
                        local pos_in_item = (samplesRead + max_idx_frame) / samplerate
                        local env_multiplier = 1.0
                        
                        if vol_env then
                            -- REAPER exige "Item Time" (pos_in_item) para evaluar Take Envelopes
                            local retval_env, val_env = reaper.Envelope_Evaluate(vol_env, pos_in_item, samplerate, 1)
                            if retval_env then env_multiplier = val_env end
                        end
                        
                        -- Aplicamos todos los multiplicadores al True Peak bruto
                        local final_tp_val = tp_val_raw * base_multiplier * env_multiplier

                        table.insert(picosData, {pos = pos_in_item, val = final_tp_val})
                    end
                end
                samplesRead = samplesRead + samplesToRead
            end
            
            reaper.DestroyAudioAccessor(accessor)

            -- 4. Filtrar y colocar marcadores
            if #picosData > 0 then
                table.sort(picosData, function(a, b) return a.val > b.val end)
                
                local marcasPuestas = 0
                local picosRegistrados = {}
                local minSeparacion = 0.5 

                for _, p in ipairs(picosData) do
                    if marcasPuestas >= numPicosTarget then break end
                    
                    local posAbsoluta = itemPos + p.pos
                    local demasiadoCerca = false
                    
                    for _, posGuardada in ipairs(picosRegistrados) do
                        if math.abs(posAbsoluta - posGuardada) < minSeparacion then
                            demasiadoCerca = true; break
                        end
                    end
                    
                    if not demasiadoCerca then
                        local dbTP = -150.0 
                        if p.val > 0.0000001 then
                            dbTP = 20 * math.log(p.val, 10)
                        end
                        
                        local color = 0 
                        if dbTP >= -0.01 then 
                            color = reaper.ColorToNative(255, 0, 0) | 0x1000000 
                        end 
                        
                        local nombre = string.format("TP #%d: %.1f dBTP", marcasPuestas + 1, dbTP)
                        reaper.SetTakeMarker(midi_take, -1, nombre, p.pos, color)
                        
                        table.insert(picosRegistrados, posAbsoluta)
                        marcasPuestas = marcasPuestas + 1
                    end
                end
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("TP a MIDI (Math Engine)", -1)
    reaper.UpdateArrange()
end

main()

