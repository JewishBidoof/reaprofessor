-- ReaProfessor automated smoke harness (run via tools/smoke_test.sh)

local out_dir = os.getenv("REAPROFESSOR_TEST_DIR") or "/tmp/reaprofessor-test"
local out_path = out_dir .. "/smoke-result.txt"

local function write_result(lines)
  reaper.RecursiveCreateDirectory(out_dir, 0)
  local f = io.open(out_path, "w")
  if not f then return end
  for _, line in ipairs(lines) do f:write(line .. "\n") end
  f:close()
end

local lines = {}
local function add(k, v) lines[#lines + 1] = k .. "=" .. tostring(v) end

local ok, err = pcall(function()
  local ver = reaper.GetAppVersion()
  local path = reaper.GetResourcePath()
  local has_sws = reaper.APIExists("CF_GetSWSVersion") or reaper.APIExists("SNM_GetIntConfigVar")
  local has_reapack = reaper.APIExists("ReaPack_About") or reaper.APIExists("ReaPack_BrowsePackages")

  local scripts = path .. "/Scripts/ReaProfessor"
  package.path = scripts .. "/lib/?.lua;" .. package.path

  local Data = require("data")
  local OSC = require("osc")
  local Routing = require("routing")
  local Commands = require("commands")
  local MIDI = require("midi")

  -- Wipe tracks for deterministic routing test
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    reaper.DeleteTrack(reaper.GetTrack(0, i))
  end

  local created = Routing.create_channels(4, {
    mode = "same_strip",
    start_input = 1,
    start_output = 1,
    arm = true,
  })
  local same_ok = #created == 4
  local tr0 = reaper.GetTrack(0, 0)
  local recin = tr0 and reaper.GetMediaTrackInfo_Value(tr0, "I_RECINPUT") or -1
  local _, chunk0 = reaper.GetTrackStateChunk(tr0, "", false)
  local hwout = chunk0 and chunk0:match("HWOUT (%d+)") or "?"
  local mon = tr0 and reaper.GetMediaTrackInfo_Value(tr0, "I_RECMON") or -1
  local mode = tr0 and reaper.GetMediaTrackInfo_Value(tr0, "I_RECMODE") or -1

  -- Double-patch pair
  local created2 = Routing.create_channels(2, {
    mode = "double_patch",
    start_input = 10,
    start_output = 10,
  })
  local dbl_ok = #created2 == 2
  local roles = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    roles[#roles + 1] = role
  end
  local has_rec_role, has_fx_role = false, false
  for _, r in ipairs(roles) do
    if r == "record" then has_rec_role = true end
    if r == "process" then has_fx_role = true end
  end

  -- Snapshot modes: add FX, capture bypass+full
  local fx_tr = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role == "same_strip" or role == "process" then fx_tr = tr break end
  end
  local fx_idx = reaper.TrackFX_AddByName(fx_tr, "ReaEQ", false, -1)
  reaper.TrackFX_SetEnabled(fx_tr, fx_idx, false)

  local snap_bypass = Data.capture_snapshot("BypassSnap", { mode = "bypass", selected_only = false })
  reaper.TrackFX_SetEnabled(fx_tr, fx_idx, true)
  Data.recall_snapshot(snap_bypass, { mode = "bypass" })
  local bypass_recalled = reaper.TrackFX_GetEnabled(fx_tr, fx_idx) == false

  reaper.TrackFX_SetEnabled(fx_tr, fx_idx, true)
  local p0 = reaper.TrackFX_GetParam(fx_tr, fx_idx, 0)
  reaper.TrackFX_SetParam(fx_tr, fx_idx, 0, 0.25)
  local snap_params = Data.capture_snapshot("ParamSnap", { mode = "params", selected_only = false })
  reaper.TrackFX_SetParam(fx_tr, fx_idx, 0, 0.75)
  Data.recall_snapshot(snap_params, { mode = "params" })
  local p1 = reaper.TrackFX_GetParam(fx_tr, fx_idx, 0)
  local params_ok = math.abs(p1 - 0.25) < 0.001

  local snap_full = Data.capture_snapshot("FullSnap", { mode = "full", selected_only = false })
  -- delete FX and full-reload
  for i = reaper.TrackFX_GetCount(fx_tr) - 1, 0, -1 do reaper.TrackFX_Delete(fx_tr, i) end
  Data.recall_snapshot(snap_full, { mode = "full" })
  local full_ok = reaper.TrackFX_GetCount(fx_tr) >= 1

  -- Record strip exclusion: find a record track, give it FX, ensure snapshot targets skip it
  local rec_tr = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role == "record" then rec_tr = tr break end
  end
  local rec_skip_ok = true
  if rec_tr then
    reaper.TrackFX_AddByName(rec_tr, "ReaEQ", false, -1)
    local before = reaper.TrackFX_GetCount(rec_tr)
    local targets = Routing.snapshot_target_tracks(false)
    for _, t in ipairs(targets) do
      if t.track == rec_tr then rec_skip_ok = false end
    end
    -- full recall should not strip REC track FX via targets list
    Data.recall_snapshot(snap_full, { mode = "full" })
    local after = reaper.TrackFX_GetCount(rec_tr)
    if after ~= before then rec_skip_ok = false end
  end

  -- OSC / commands
  Data.save_cues({
    { id = "c1", name = "Smoke Cue", kind = "snapshot", payload = { snapshot = "ParamSnap" }, notes = "" },
  })
  local meta = Data.load_meta()
  meta.cue_index = 1
  Data.save_meta(meta)
  local cue_ok = Commands.cue_go()

  OSC.enqueue(OSC.addresses.snap_mode, { "full" })
  local q = OSC.drain_queue()
  local queue_ok = #q == 1 and q[1].path == OSC.addresses.snap_mode

  reaper.SetExtState("ReaProfessor", "osc_cmd", OSC.addresses.cue_back, false)
  local one = OSC.poll_oneshot()
  local oneshot_ok = one and one.path == OSC.addresses.cue_back

  local midi_map = MIDI.default_map()
  local cmd = MIDI.match({ type = "note_on", channel = 1, note = 36, velocity = 100 }, midi_map)

  -- JSON roundtrip
  local enc = Data.encode({ a = 1, b = "x", c = { true, false } })
  local dec = Data.decode(enc)
  local json_ok = dec and dec.a == 1 and dec.b == "x" and dec.c[1] == true

  lines[1] = "OK"
  add("version", ver)
  add("resource_path", path)
  add("sws", has_sws)
  add("reapack", has_reapack)
  add("modules", true)
  add("json_roundtrip", json_ok)
  add("channels_same", same_ok)
  add("recinput0", recin)
  add("hwout0", hwout)
  add("recmode", mode)
  add("recmon", mon)
  add("channels_double", dbl_ok)
  add("double_roles", has_rec_role and has_fx_role)
  add("snap_bypass", bypass_recalled)
  add("snap_params", params_ok)
  add("snap_full", full_ok)
  add("rec_strip_skip", rec_skip_ok)
  add("cue_go", cue_ok)
  add("osc_queue", queue_ok)
  add("osc_oneshot", oneshot_ok)
  add("midi_match", cmd == "cue_go")
  add("osc_cue_go_path", OSC.addresses.cue_go)
  add("scripts", scripts)
end)

if not ok then
  write_result({ "FAIL", "error=" .. tostring(err) })
else
  write_result(lines)
end

reaper.Main_OnCommand(40004, 0)
