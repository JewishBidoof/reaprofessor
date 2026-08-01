-- Extensive timecode + cue-fire / OSC isolation tests.
-- Writes /tmp/reaprofessor-test/timecode-result.txt

local out_dir = os.getenv("REAPROFESSOR_TEST_DIR") or "/tmp/reaprofessor-test"
local out_path = out_dir .. "/timecode-result.txt"

local function write_result(lines)
  reaper.RecursiveCreateDirectory(out_dir, 0)
  local f = io.open(out_path, "w")
  if not f then return end
  for _, line in ipairs(lines) do f:write(line .. "\n") end
  f:close()
end

local lines = {}
local function add(k, v) lines[#lines + 1] = k .. "=" .. tostring(v) end
local function approx(a, b, eps)
  if a == nil or b == nil then return false end
  return math.abs(a - b) <= (eps or 1e-3)
end

local function clear_markers()
  local idx = 0
  local to_delete = {}
  while true do
    local rv, isrgn, _, _, name, markrgnidx = reaper.EnumProjectMarkers(idx)
    if rv == 0 then break end
    idx = idx + 1
    if not isrgn and type(name) == "string" and name:sub(1, 3) == "RP|" then
      to_delete[#to_delete + 1] = markrgnidx
    end
  end
  for _, id in ipairs(to_delete) do
    reaper.DeleteProjectMarker(0, id, false)
  end
end

local function count_rp_markers()
  local n, idx = 0, 0
  while true do
    local rv, isrgn, _, _, name = reaper.EnumProjectMarkers(idx)
    if rv == 0 then break end
    idx = idx + 1
    if not isrgn and type(name) == "string" and name:sub(1, 3) == "RP|" then
      n = n + 1
    end
  end
  return n
end

local function find_marker_pos(cue_id)
  local idx = 0
  while true do
    local rv, isrgn, pos, _, name = reaper.EnumProjectMarkers(idx)
    if rv == 0 then break end
    idx = idx + 1
    if not isrgn and type(name) == "string" then
      local id = name:match("^RP|([^|]+)")
      if id == tostring(cue_id) then return pos end
    end
  end
  return nil
end

local ok, err = pcall(function()
  local scripts = reaper.GetResourcePath() .. "/Scripts/ReaProfessor"
  package.path = scripts .. "/lib/?.lua;" .. package.path

  local Data = require("data")
  local TC = require("timecode")
  local OSC = require("osc")
  local Commands = require("commands")
  local Config = require("config")
  Config.FINALIZED = true

  for i = reaper.CountTracks(0) - 1, 0, -1 do
    reaper.DeleteTrack(reaper.GetTrack(0, i))
  end
  clear_markers()
  OSC.clear_inbound_queue()
  reaper.SetProjExtState(0, "ReaProfessor", "osc_out_queue", "")

  local fps = TC.fps()
  add("fps_positive", fps > 0)

  -- Format / parse matrix
  local samples = { 0, 0.5, 1, 10, 61.25, 3600, 3661.04, 7200.5 }
  local round_ok = true
  for _, sec in ipairs(samples) do
    local s = TC.format(sec)
    local back = TC.parse(s)
    if not back or math.abs(back - sec) > (1.0 / math.max(1, fps)) + 1e-6 then
      round_ok = false
      add("round_fail", string.format("%s -> %s -> %s", tostring(sec), tostring(s), tostring(back)))
      break
    end
  end
  add("roundtrip", round_ok)
  add("parse_blank", TC.parse("") == nil and TC.parse("   ") == nil and TC.parse("-") == nil)
  add("parse_nil", TC.parse(nil) == nil)
  add("parse_hhmmssff", approx(TC.parse("01:00:00:00"), 3600, 1.0 / math.max(1, fps)))
  add("format_zero", type(TC.format(0)) == "string" and TC.format(0) ~= "")

  -- Cue TC set / clear / normalize persistence
  local cue = Data.new_cue("TC A", { kind = "dummy" })
  TC.set_cue_tc(cue, "00:00:10:00")
  add("set_from_str", TC.cue_seconds(cue) ~= nil and cue.tc ~= "")
  local sec10 = TC.cue_seconds(cue)
  Data.save_cues({ cue })
  local loaded = Data.load_cues()[1]
  add("persist_tc", loaded and loaded.tc == cue.tc and approx(TC.cue_seconds(loaded), sec10, 1e-6))
  TC.clear_cue_tc(loaded)
  add("clear_tc", (loaded.tc or "") == "" and loaded.tc_sec == nil)
  TC.set_cue_tc(cue, 25.0)
  add("set_from_num", approx(TC.cue_seconds(cue), 25.0, 1e-9))
  TC.set_cue_tc(cue, "")
  add("set_blank_clears", (cue.tc or "") == "" and cue.tc_sec == nil)

  -- normalize preserves tc via data layer
  local raw = { id = "raw1", name = "Raw", kind = "dummy", tc = TC.format(42), tc_sec = 42 }
  local norm = Data.normalize_cue(raw)
  add("normalize_tc", approx(TC.cue_seconds(norm), 42, 1e-9))

  -- Meta defaults
  local meta = Data.load_meta()
  add("meta_tc_chase_default", meta.tc_chase == false or meta.tc_chase == true) -- field present
  meta.tc_chase = false
  meta.tc_markers = true
  Data.save_meta(meta)
  meta = Data.load_meta()
  add("meta_tc_chase_false", meta.tc_chase == false)
  add("meta_tc_markers", meta.tc_markers == true)

  -- Chase: ordered multi-cue fire (gaps < 2s so polls aren't treated as scrub)
  local c1 = Data.new_cue("C1", { kind = "dummy", id = "id_c1" })
  local c2 = Data.new_cue("C2", { kind = "dummy", id = "id_c2" })
  local c3 = Data.new_cue("C3", { kind = "dummy", id = "id_c3" })
  TC.set_cue_tc(c1, 5.0)
  TC.set_cue_tc(c2, 5.5)
  TC.set_cue_tc(c3, 6.0)
  add("ids_honored", c1.id == "id_c1" and c2.id == "id_c2" and c3.id == "id_c3")
  local list = { c1, c2, c3 }
  local st = TC.new_chase_state()

  add("disarmed", #TC.poll_chase(list, false, st, { running = true, pos = 5.2 }) == 0)
  st = TC.new_chase_state()
  add("not_running", #TC.poll_chase(list, true, st, { running = false, pos = 5.2 }) == 0)

  st = TC.new_chase_state()
  TC.poll_chase(list, true, st, { running = true, pos = 4.8 })
  local f1 = TC.poll_chase(list, true, st, { running = true, pos = 5.1 })
  add("cross_c1", #f1 == 1 and f1[1] == 1)
  local f2 = TC.poll_chase(list, true, st, { running = true, pos = 5.55 })
  add("cross_c2", #f2 == 1 and f2[1] == 2)
  local f3 = TC.poll_chase(list, true, st, { running = true, pos = 6.05 })
  add("cross_c3", #f3 == 1 and f3[1] == 3)
  add("no_refire", #TC.poll_chase(list, true, st, { running = true, pos = 6.2 }) == 0)

  -- Same tick can cross multiple cues
  st = TC.new_chase_state()
  TC.poll_chase(list, true, st, { running = true, pos = 4.9 })
  local multi = TC.poll_chase(list, true, st, { running = true, pos = 5.6 })
  add("multi_cross", #multi == 2 and multi[1] == 1 and multi[2] == 2)

  -- Scrub jump ignored (>2s forward)
  st = TC.new_chase_state()
  TC.poll_chase(list, true, st, { running = true, pos = 1.0 })
  local scrub = TC.poll_chase(list, true, st, { running = true, pos = 20.0 })
  add("scrub_ignored", #scrub == 0)

  -- Rewind re-arms
  st = TC.new_chase_state()
  TC.poll_chase(list, true, st, { running = true, pos = 5.4 })
  TC.poll_chase(list, true, st, { running = true, pos = 5.6 })
  TC.poll_chase(list, true, st, { running = true, pos = 3.0 }) -- rewind
  TC.poll_chase(list, true, st, { running = true, pos = 4.5 })
  local again = TC.poll_chase(list, true, st, { running = true, pos = 5.2 })
  add("rewind_rearms", #again == 1 and again[1] == 1)

  -- Cue without TC never fires
  local bare = Data.new_cue("Bare", { kind = "dummy", id = "bare" })
  st = TC.new_chase_state()
  TC.poll_chase({ bare }, true, st, { running = true, pos = 1 })
  add("no_tc_cue", #TC.poll_chase({ bare }, true, st, { running = true, pos = 2 }) == 0)

  -- Marker sync / upsert / remove
  clear_markers()
  local mc = Data.new_cue("Mark Me", { kind = "dummy", id = "mark_1" })
  TC.set_cue_tc(mc, 33.0)
  add("sync_create", TC.sync_marker(mc) == true and count_rp_markers() == 1)
  add("marker_pos", approx(find_marker_pos("mark_1"), 33.0, 1e-3))
  TC.set_cue_tc(mc, 44.0)
  TC.sync_marker(mc)
  add("sync_upsert", count_rp_markers() == 1 and approx(find_marker_pos("mark_1"), 44.0, 1e-3))
  TC.clear_cue_tc(mc)
  TC.sync_marker(mc)
  add("sync_clear_deletes", count_rp_markers() == 0)
  TC.set_cue_tc(mc, 12.0)
  TC.sync_marker(mc)
  add("remove_marker", TC.remove_marker(mc) == true and count_rp_markers() == 0)

  -- Dummy fire sends OSC outbound only (no inbound feedback)
  OSC.clear_inbound_queue()
  reaper.SetProjExtState(0, "ReaProfessor", "osc_out_queue", "")
  local dummy = Data.new_cue("Dummy Fire", { kind = "dummy" })
  dummy.osc = "/ReaProfessor/TestFire"
  Data.save_cues({ dummy })
  meta = Data.load_meta()
  meta.cue_index = 1
  meta.osc_parent = "/ReaProfessor"
  Data.save_meta(meta)
  local fok, fmsg = Commands.cue_goto(1)
  add("dummy_fire_ok", fok == true)
  add("dummy_fire_msg_osc", tostring(fmsg or ""):find("OSC", 1, true) ~= nil)
  local inbound = OSC.drain_queue()
  add("no_inbound_feedback", #inbound == 0)
  local out_raw = select(2, reaper.GetProjExtState(0, "ReaProfessor", "osc_out_queue"))
  local out_q = Data.decode(out_raw)
  local out_ok = type(out_q) == "table" and #out_q >= 1 and out_q[#out_q].path == "/ReaProfessor/TestFire"
  add("outbound_queued", out_ok)
  local last_out = reaper.GetExtState("ReaProfessor", "osc_out")
  add("outbound_extstate", last_out == "/ReaProfessor/TestFire")

  -- Snapshot cue + TC chase path: fire restores FX when crossed
  reaper.InsertTrackAtIndex(0, true)
  local tr = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "TC01", true)
  reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "same_strip", true)
  assert(reaper.TrackFX_AddByName(tr, "JS: Filters/resonantlowpass", false, -1) >= 0)
  reaper.TrackFX_SetParamNormalized(tr, 0, 0, 0.42)
  local snap = Data.capture_snapshot("TCSnap", { mode = "full", selected_only = false })
  Data.save_snapshots({ snap })
  local scue = Data.new_cue("Snap TC", { kind = "cue", snapshot_name = "TCSnap", id = "snap_tc" })
  TC.set_cue_tc(scue, 8.0)
  Data.save_cues({ scue })
  -- Mutate FX
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do reaper.TrackFX_Delete(tr, i) end
  reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
  st = TC.new_chase_state()
  TC.poll_chase({ scue }, true, st, { running = true, pos = 7.5 })
  local hit = TC.poll_chase({ scue }, true, st, { running = true, pos = 8.05 })
  add("snap_chase_hit", #hit == 1)
  if #hit == 1 then
    local sok = Commands.cue_goto(1)
    local count_ok = sok == true and reaper.TrackFX_GetCount(tr) == 1
    add("snap_chase_fire", count_ok)
    local _, nm = reaper.TrackFX_GetFXName(tr, 0, "")
    nm = tostring(nm):lower()
    add("snap_chase_fx", count_ok and (nm:find("lowpass", 1, true) ~= nil or nm:find("resonant", 1, true) ~= nil
      or nm:find("filter", 1, true) ~= nil))
    add("snap_chase_fx_name", nm)
  else
    add("snap_chase_fire", false)
    add("snap_chase_fx", false)
  end

  -- Live transport: play + seekplay simulates LTC chase advancing the playhead
  reaper.SetEditCurPos(0.0, false, false)
  reaper.OnPlayButton()
  do
    local t0 = reaper.time_precise()
    while reaper.time_precise() - t0 < 0.5 and not TC.is_running() do end
  end
  add("transport_running", TC.is_running() == true)
  if TC.is_running() then
    local p1 = TC.now_seconds()
    do
      local t0 = reaper.time_precise()
      while reaper.time_precise() - t0 < 0.35 do end
    end
    local p2 = TC.now_seconds()
    local natural = p2 > p1 + 0.05
    if not natural then
      -- Headless/JACK environments may not advance audio time; seek while playing.
      reaper.SetEditCurPos(p1 + 0.5, false, true)
      p2 = TC.now_seconds()
    end
    add("playhead_advances", p2 > p1 + 0.05)
    add("playhead_natural", natural)

    local target = math.max(TC.now_seconds() + 0.3, 1.0)
    local live = Data.new_cue("Live", { kind = "dummy", id = "live_tc" })
    TC.set_cue_tc(live, target)
    st = TC.new_chase_state()
    TC.poll_chase({ live }, true, st, { running = true, pos = target - 0.2 })
    -- Seek playhead across the cue TC (LTC-chase equivalent)
    reaper.SetEditCurPos(target + 0.05, false, true)
    local live_hit = false
    for _ = 1, 10 do
      local fired = TC.poll_chase({ live }, true, st)
      if #fired > 0 then live_hit = true break end
      local tw = reaper.time_precise()
      while reaper.time_precise() - tw < 0.02 do end
    end
    add("live_chase_fire", live_hit)
    reaper.OnStopButton()
  else
    add("playhead_advances", false)
    add("playhead_natural", false)
    add("live_chase_fire", false)
  end

  -- Default cue OSC path still works with parent
  meta = Data.load_meta()
  meta.osc_parent = "/Show"
  Data.save_meta(meta)
  local dpath = Data.cue_osc_path(Data.new_cue("X", { kind = "dummy" }), 3, meta)
  add("default_osc_path", dpath == "/Show/3")

  clear_markers()
  reaper.OnStopButton()
end)

if not ok then
  write_result({ "FAIL", "error=" .. tostring(err) })
else
  table.insert(lines, 1, "OK")
  write_result(lines)
end

reaper.Main_OnCommand(40004, 0) -- File: Close project
