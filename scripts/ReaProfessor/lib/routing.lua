-- @description ReaProfessor routing helpers (1:1 I/O, record-safe layouts)
-- @version 0.5.0
-- @author JewishBidoof
-- @noindex

local Routing = {}

local function ensure_hwout_mono(tr, hw_out_1based)
  -- Hardware outs are most reliably set via the HWOUT track-chunk line.
  -- Format: HWOUT <dst> <flags> <vol> <pan> <mute> <phase> <src> ...
  -- dst: 0-based hardware channel index; src|1024 = mono from channel 1.
  local dst = math.max(0, (hw_out_1based or 1) - 1)
  local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not chunk then return false end
  local line = string.format("HWOUT %d 0 1 0 0 0 1024 -1:U -1", dst)
  if chunk:find("HWOUT ") then
    chunk = chunk:gsub("HWOUT [^\n]+", line)
  else
    if chunk:find("MAINSEND ") then
      chunk = chunk:gsub("MAINSEND [^\n]+", "%0\n" .. line)
    else
      chunk = chunk:gsub(">", line .. "\n>")
    end
  end
  return reaper.SetTrackStateChunk(tr, chunk, false)
end

local function clear_hwouts(tr)
  local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not chunk or not chunk:find("HWOUT ") then return true end
  chunk = chunk:gsub("HWOUT [^\n]+\n", "")
  return reaper.SetTrackStateChunk(tr, chunk, false)
end

local function try_arm(tr, armed)
  -- Best-effort: API/UI arm can refuse when no valid record device exists.
  if reaper.SetTrackUIRecArm then
    reaper.SetTrackUIRecArm(tr, armed and 1 or 0, 0)
  end
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARMED", armed and 1 or 0)
  if reaper.CSurf_OnRecArmChange then
    reaper.CSurf_OnRecArmChange(tr, armed and 1 or 0)
  end
  -- Persist arm bit in chunk so projects reopen correctly on real interfaces.
  local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if chunk then
    local rec = chunk:match("REC ([^\n]+)")
    if rec then
      local fields = {}
      for token in rec:gmatch("%S+") do fields[#fields + 1] = token end
      if #fields >= 1 then
        fields[1] = armed and "1" or "0"
        local newrec = "REC " .. table.concat(fields, " ")
        chunk = chunk:gsub("REC [^\n]+", newrec, 1)
        reaper.SetTrackStateChunk(tr, chunk, false)
      end
    end
  end
end

--- Configure a track as mono input → mono hardware out (1-based channel numbers).
-- @param opts table
--   input (number) hardware input 1-based
--   output (number) hardware output 1-based (default = input)
--   name (string)
--   arm (bool) record-arm
--   monitor (bool) input monitoring
--   record_mode ("input"|"output") default "input" (dry record)
--   master_send (bool) default false
--   clear_fx (bool)
function Routing.configure_mono_io(tr, opts)
  opts = opts or {}
  local input = tonumber(opts.input) or 1
  local output = tonumber(opts.output) or input
  local name = opts.name
  if name then
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  end

  -- Mono hardware input (0-based index, no stereo/MIDI flags)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", input - 1)

  -- Record dry input by default so FX never hits the recorded file.
  local mode = 0
  if opts.record_mode == "output" then mode = 1 end
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMODE", mode)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", opts.monitor and 1 or 0)
  -- Always drive master send from opts (default off) to avoid feedback into master.
  local master_on = opts.master_send and true or false
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", master_on and 1 or 0)
  do
    local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if chunk then
      if chunk:find("MAINSEND ") then
        chunk = chunk:gsub("MAINSEND [^\n]+", master_on and "MAINSEND 1 0" or "MAINSEND 0 0", 1)
      else
        chunk = chunk:gsub(">", (master_on and "MAINSEND 1 0\n>" or "MAINSEND 0 0\n>"), 1)
      end
      reaper.SetTrackStateChunk(tr, chunk, false)
    end
  end

  if opts.arm ~= nil then
    try_arm(tr, opts.arm and true or false)
  end

  if opts.hw_out == false then
    clear_hwouts(tr)
  else
    ensure_hwout_mono(tr, output)
  end

  if opts.clear_fx then
    for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
      reaper.TrackFX_Delete(tr, i)
    end
  end

  return true
end

--- Create N mono channels with 1:1 input/output routing.
-- @param count number
-- @param opts table optional { start_input=1, start_output=1, prefix="CH", mode="same_strip"|"double_patch", arm=true }
-- @return table list of created track infos
function Routing.create_channels(count, opts)
  opts = opts or {}
  count = math.max(1, math.floor(tonumber(count) or 1))
  local start_in = tonumber(opts.start_input) or 1
  local start_out = tonumber(opts.start_output) or start_in
  local prefix = opts.prefix or "CH"
  local mode = opts.mode or "same_strip"
  local arm = opts.arm ~= false
  local created = {}

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)

  for i = 1, count do
    local hw_in = start_in + i - 1
    local hw_out = start_out + i - 1
    local label = string.format("%s%02d", prefix, i)

    if mode == "double_patch" then
      -- Record track: dry capture only, no monitor, no HW out
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      local rec_tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      Routing.configure_mono_io(rec_tr, {
        input = hw_in,
        output = hw_out,
        name = label .. " REC",
        arm = arm,
        monitor = false,
        record_mode = "input",
        master_send = false,
        hw_out = false,
        clear_fx = true,
      })
      reaper.GetSetMediaTrackInfo_String(rec_tr, "P_EXT:ReaProfessor_role", "record", true)
      reaper.GetSetMediaTrackInfo_String(rec_tr, "P_EXT:ReaProfessor_pair", tostring(i), true)
      reaper.GetSetMediaTrackInfo_String(rec_tr, "P_EXT:ReaProfessor_hw_in", tostring(hw_in), true)

      -- Process track: same input, monitor + FX + HW out, not recording
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      local fx_tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      Routing.configure_mono_io(fx_tr, {
        input = hw_in,
        output = hw_out,
        name = label .. " FX",
        arm = false,
        monitor = true,
        record_mode = "input",
        master_send = false,
        hw_out = true,
        clear_fx = true,
      })
      reaper.GetSetMediaTrackInfo_String(fx_tr, "P_EXT:ReaProfessor_role", "process", true)
      reaper.GetSetMediaTrackInfo_String(fx_tr, "P_EXT:ReaProfessor_pair", tostring(i), true)
      reaper.GetSetMediaTrackInfo_String(fx_tr, "P_EXT:ReaProfessor_hw_in", tostring(hw_in), true)

      created[#created + 1] = { index = i, input = hw_in, output = hw_out, rec = rec_tr, fx = fx_tr, mode = mode }
    else
      -- Same strip: record dry input, monitor through FX, HW out for live
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      Routing.configure_mono_io(tr, {
        input = hw_in,
        output = hw_out,
        name = label,
        arm = arm,
        monitor = true,
        record_mode = "input",
        master_send = false,
        hw_out = true,
        clear_fx = true,
      })
      reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "same_strip", true)
      reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_pair", tostring(i), true)
      reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_hw_in", tostring(hw_in), true)
      created[#created + 1] = { index = i, input = hw_in, output = hw_out, track = tr, mode = "same_strip" }
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, string.format("ReaProfessor: Create %d channels (%s)", count, mode), -1)
  return created
end

--- Apply record-safe monitoring policy to existing ReaProfessor channels.
function Routing.apply_record_safe(mode)
  mode = mode or "same_strip"
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role == "same_strip" or (mode == "same_strip" and role == "") then
      -- Dry record + wet monitor
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMODE", 0)
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
    elseif role == "record" then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMODE", 0)
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 0)
      reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
    elseif role == "process" then
      try_arm(tr, false)
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
      reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
    end
  end
end

function Routing.track_role(tr)
  local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
  return role or ""
end

--- Tracks that should receive snapshot FX changes (process / same_strip / selected).
function Routing.snapshot_target_tracks(selected_only)
  local targets = {}
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    if selected_only and not reaper.IsTrackSelected(tr) then goto continue end
    local role = Routing.track_role(tr)
    if role == "record" then goto continue end -- never touch record-only strips
    targets[#targets + 1] = { track = tr, index = i, role = role }
    ::continue::
  end
  return targets
end

return Routing
