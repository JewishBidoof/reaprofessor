-- Extensive FX snapshot recall tests with real built-in JSFX chains.
-- Writes /tmp/reaprofessor-test/fx-recall-result.txt

local out_dir = os.getenv("REAPROFESSOR_TEST_DIR") or "/tmp/reaprofessor-test"
local out_path = out_dir .. "/fx-recall-result.txt"

local function write_result(lines)
  reaper.RecursiveCreateDirectory(out_dir, 0)
  local f = io.open(out_path, "w")
  if not f then return end
  for _, line in ipairs(lines) do f:write(line .. "\n") end
  f:close()
end

local lines = {}
local function add(k, v) lines[#lines + 1] = k .. "=" .. tostring(v) end
local function log(msg)
  lines[#lines + 1] = "log=" .. tostring(msg)
  reaper.ShowConsoleMsg("[fx-recall] " .. tostring(msg) .. "\n")
end

local function approx(a, b, eps)
  eps = eps or 1e-4
  if a == nil or b == nil then return false end
  return math.abs(a - b) <= eps
end

local function clear_tracks()
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    reaper.DeleteTrack(reaper.GetTrack(0, i))
  end
end

local function fx_name(tr, fi)
  local _, n = reaper.TrackFX_GetFXName(tr, fi, "")
  return n
end

local function dump_chain(tr, label)
  local n = reaper.TrackFX_GetCount(tr)
  log(string.format("%s: %d FX", label, n))
  for i = 0, n - 1 do
    local name = fx_name(tr, i)
    local en = reaper.TrackFX_GetEnabled(tr, i)
    local pc = reaper.TrackFX_GetNumParams(tr, i)
    local p0 = pc > 0 and reaper.TrackFX_GetParam(tr, i, 0) or -1
    local ident, typ = "", ""
    if reaper.TrackFX_GetNamedConfigParm then
      local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, i, "fx_ident")
      if ok then ident = v end
      ok, v = reaper.TrackFX_GetNamedConfigParm(tr, i, "fx_type")
      if ok then typ = v end
    end
    log(string.format("  [%d] %s en=%s params=%d p0=%.6f type=%s ident=%s",
      i, name, tostring(en), pc, p0, typ, ident))
  end
end

local function try_add(tr, name)
  local idx = reaper.TrackFX_AddByName(tr, name, false, -1)
  return idx
end

local ok, err = pcall(function()
  local path = reaper.GetResourcePath()
  package.path = path .. "/Scripts/ReaProfessor/lib/?.lua;" .. package.path
  local Data = require("data")
  local Routing = require("routing")
  local Config = require("config")
  Config.FINALIZED = true

  clear_tracks()

  -- Probe which JSFX add names work
  reaper.InsertTrackAtIndex(0, true)
  local probe = reaper.GetTrack(0, 0)
  local candidates = {
    "JS: Filters/resonantlowpass",
    "JS: Delay/delay",
    "JS: Utility/volume",
    "JS: volume",
    "JS: IIIEQ",
    "JS: EQ",
    "JS: Loser/3bandpeaklimiter",
    "JS: Dynamics/general_dynamics",
    "JS: Filters/dc_remove",
    "JS: Analysis/gfxanalyzer",
    "ReaEQ",
    "ReaDelay",
    "ReaComp",
    "JS: Liteon/vumeter",
  }
  local added = {}
  for _, name in ipairs(candidates) do
    local idx = try_add(probe, name)
    if idx >= 0 then
      added[#added + 1] = { req = name, got = fx_name(probe, idx), idx = idx }
      log("ADD_OK " .. name .. " -> " .. fx_name(probe, idx))
    else
      log("ADD_FAIL " .. name)
    end
  end
  add("probe_added", #added)
  dump_chain(probe, "probe")

  -- Build a real multi-FX same_strip channel for recall tests
  clear_tracks()
  local created = Routing.create_channels(1, {
    mode = "same_strip", start_input = 1, start_output = 1, arm = true, prefix = "FX",
  })
  add("channel_created", #created == 1)
  local tr = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "FX01", true)

  -- Prefer working JSFX from probe; fall back to Rea* plugins
  local chain_specs = {
    { try = { "JS: Filters/resonantlowpass", "JS: Filters/dc_remove", "ReaEQ" }, p = { [0] = 0.25, [1] = 0.4 } },
    { try = { "JS: Delay/delay", "ReaDelay" }, p = { [0] = 0.33 } },
    { try = { "JS: Dynamics/general_dynamics", "ReaComp" }, p = { [0] = 0.15, [2] = 0.6 } },
    { try = { "ReaEQ" }, p = { [0] = 0.5 } },
  }

  local built = {}
  for _, spec in ipairs(chain_specs) do
    local idx = -1
    local used = nil
    for _, name in ipairs(spec.try) do
      idx = try_add(tr, name)
      if idx >= 0 then used = name break end
    end
    if idx >= 0 then
      for pi, pv in pairs(spec.p) do
        if pi < reaper.TrackFX_GetNumParams(tr, idx) then
          reaper.TrackFX_SetParam(tr, idx, pi, pv)
        end
      end
      built[#built + 1] = { idx = idx, req = used, name = fx_name(tr, idx) }
    end
  end
  -- Bypass middle FX if we have >= 2
  if #built >= 2 then
    reaper.TrackFX_SetEnabled(tr, built[2].idx, false)
  end
  add("chain_len", #built)
  dump_chain(tr, "built")

  if #built < 2 then
    error("Could not build a multi-FX chain for testing")
  end

  -- Snapshot ground truth
  local truth = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local pc = reaper.TrackFX_GetNumParams(tr, i)
    local params = {}
    for pi = 0, pc - 1 do params[pi] = reaper.TrackFX_GetParam(tr, i, pi) end
    truth[i + 1] = {
      name = fx_name(tr, i),
      enabled = reaper.TrackFX_GetEnabled(tr, i),
      params = params,
      pc = pc,
    }
  end

  local function chain_matches(label, expect_count)
    local n = reaper.TrackFX_GetCount(tr)
    local ok_count = (expect_count == nil) or (n == expect_count)
    if not ok_count then
      log(label .. " count mismatch: got " .. n .. " want " .. tostring(expect_count))
      dump_chain(tr, label)
      return false
    end
    local all = true
    for i = 1, #truth do
      if i > n then all = false break end
      local t = truth[i]
      local name = fx_name(tr, i - 1)
      -- Names may differ slightly after rebuild; compare stripped
      local function strip(s)
        return tostring(s):gsub("^[^:]+:%s*", ""):lower()
      end
      if strip(name) ~= strip(t.name) and not name:find(strip(t.name), 1, true)
         and not t.name:find(strip(name), 1, true) then
        log(string.format("%s name[%d]: got '%s' want '%s'", label, i, name, t.name))
        all = false
      end
      if reaper.TrackFX_GetEnabled(tr, i - 1) ~= t.enabled then
        log(string.format("%s enable[%d]: got %s want %s", label, i, tostring(reaper.TrackFX_GetEnabled(tr, i - 1)), tostring(t.enabled)))
        all = false
      end
      -- Compare first few meaningful params (skip trailing trailing-gain/etc if count differs)
      local pc = math.min(t.pc, reaper.TrackFX_GetNumParams(tr, i - 1), 16)
      for pi = 0, pc - 1 do
        -- Skip last 2-3 params often used for UI/drywet that may reset; still check first 8
        if pi < 8 then
          local got = reaper.TrackFX_GetParam(tr, i - 1, pi)
          local want = t.params[pi]
          if not approx(got, want, 1e-3) then
            log(string.format("%s param[%d][%d]: got %.6f want %.6f", label, i, pi, got, want))
            all = false
            break
          end
        end
      end
    end
    return all
  end

  ------------------------------------------------------------------
  -- TEST: bypass mode
  ------------------------------------------------------------------
  local snap_bypass = Data.capture_snapshot("BypassJS", { mode = "bypass", selected_only = false })
  -- flip all enables
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    reaper.TrackFX_SetEnabled(tr, i, not truth[i + 1].enabled)
  end
  Data.recall_snapshot(snap_bypass, { mode = "bypass" })
  local bypass_ok = true
  for i = 1, #truth do
    if reaper.TrackFX_GetEnabled(tr, i - 1) ~= truth[i].enabled then
      bypass_ok = false
      log("bypass fail at " .. i)
    end
  end
  add("bypass_ok", bypass_ok)

  ------------------------------------------------------------------
  -- TEST: params mode (mutate params + bypass, keep same FX)
  ------------------------------------------------------------------
  -- restore enables first
  for i = 1, #truth do
    reaper.TrackFX_SetEnabled(tr, i - 1, truth[i].enabled)
  end
  local snap_params = Data.capture_snapshot("ParamsJS", { mode = "params", selected_only = false })
  -- mutate
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local pc = reaper.TrackFX_GetNumParams(tr, i)
    for pi = 0, math.min(pc, 8) - 1 do
      reaper.TrackFX_SetParam(tr, i, pi, 0.99)
    end
    reaper.TrackFX_SetEnabled(tr, i, true)
  end
  Data.recall_snapshot(snap_params, { mode = "params" })
  local params_ok = chain_matches("params", #truth)
  add("params_ok", params_ok)

  ------------------------------------------------------------------
  -- TEST: full mode — delete all FX then recall
  ------------------------------------------------------------------
  local snap_full = Data.capture_snapshot("FullJS", { mode = "full", selected_only = false })
  -- Persist + reload through JSON like the UI does (catches encode bugs)
  Data.save_snapshots({ snap_bypass, snap_params, snap_full })
  local loaded = Data.load_snapshots()
  local snap_full_loaded = nil
  for _, s in ipairs(loaded) do
    if s.name == "FullJS" then snap_full_loaded = s end
  end
  add("full_roundtrip", snap_full_loaded ~= nil)

  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
    reaper.TrackFX_Delete(tr, i)
  end
  add("cleared", reaper.TrackFX_GetCount(tr) == 0)
  Data.recall_snapshot(snap_full_loaded or snap_full, { mode = "full" })
  dump_chain(tr, "after_full_recall")
  local full_ok = chain_matches("full", #truth)
  add("full_ok", full_ok)

  ------------------------------------------------------------------
  -- TEST: full mode — wrong FX then recall (replace chain)
  ------------------------------------------------------------------
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do reaper.TrackFX_Delete(tr, i) end
  try_add(tr, "ReaGate")
  try_add(tr, "ReaVerbate")
  Data.recall_snapshot(snap_full_loaded or snap_full, { mode = "full" })
  local full_replace_ok = chain_matches("full_replace", #truth)
  add("full_replace_ok", full_replace_ok)

  ------------------------------------------------------------------
  -- TEST: params mode after FX removed (should not crash; limited match)
  ------------------------------------------------------------------
  -- restore good chain via full
  Data.recall_snapshot(snap_full_loaded or snap_full, { mode = "full" })
  if reaper.TrackFX_GetCount(tr) > 0 then
    reaper.TrackFX_Delete(tr, reaper.TrackFX_GetCount(tr) - 1)
  end
  local ok_call = pcall(Data.recall_snapshot, snap_params, { mode = "params" })
  add("params_partial_safe", ok_call)

  ------------------------------------------------------------------
  -- TEST: cue fires full snapshot with JSFX
  ------------------------------------------------------------------
  local Commands = require("commands")
  Data.recall_snapshot(snap_full_loaded or snap_full, { mode = "full" })
  -- mutate
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do reaper.TrackFX_Delete(tr, i) end
  Data.save_cues({
    { id = "c1", name = "FullJS", kind = "snapshot", payload = { snapshot = "FullJS" }, notes = "" },
  })
  local meta = Data.load_meta()
  meta.cue_index = 1
  Data.save_meta(meta)
  local cue_ok = Commands.cue_go()
  local cue_chain_ok = cue_ok and chain_matches("cue_full", #truth)
  add("cue_full_ok", cue_chain_ok)

  ------------------------------------------------------------------
  -- TEST: double_patch — snapshot must skip record strip, hit FX strip
  ------------------------------------------------------------------
  clear_tracks()
  Routing.create_channels(1, {
    mode = "double_patch", start_input = 1, start_output = 1, arm = true, prefix = "CH",
  })
  local rec_tr, fx_tr = nil, nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    local _, role = reaper.GetSetMediaTrackInfo_String(t, "P_EXT:ReaProfessor_role", "", false)
    if role == "record" then rec_tr = t end
    if role == "process" then fx_tr = t end
  end
  add("dbl_roles", rec_tr ~= nil and fx_tr ~= nil)
  if fx_tr then
    local idx = try_add(fx_tr, built[1] and built[1].req or "ReaEQ")
    if idx < 0 then idx = try_add(fx_tr, "ReaEQ") end
    reaper.TrackFX_SetParam(fx_tr, idx, 0, 0.22)
    if rec_tr then
      -- put an FX on record strip that must survive
      try_add(rec_tr, "ReaEQ")
    end
    local snap_dbl = Data.capture_snapshot("Dbl", { mode = "full", selected_only = false })
    Data.save_snapshots({ snap_dbl })
    -- wipe fx track
    for i = reaper.TrackFX_GetCount(fx_tr) - 1, 0, -1 do reaper.TrackFX_Delete(fx_tr, i) end
    local rec_before = rec_tr and reaper.TrackFX_GetCount(rec_tr) or 0
    Data.recall_snapshot(snap_dbl, { mode = "full" })
    local fx_after = reaper.TrackFX_GetCount(fx_tr)
    local rec_after = rec_tr and reaper.TrackFX_GetCount(rec_tr) or 0
    add("dbl_fx_restored", fx_after >= 1)
    add("dbl_rec_untouched", rec_after == rec_before)
  end

  -- Summarize failure
  local failed = {}
  for _, k in ipairs({
    "bypass_ok", "params_ok", "full_ok", "full_replace_ok", "cue_full_ok",
    "full_roundtrip", "dbl_fx_restored", "dbl_rec_untouched",
  }) do
    for _, line in ipairs(lines) do
      if line:match("^" .. k .. "=") and not line:match("=true$") then
        failed[#failed + 1] = k
      end
    end
  end
  if #failed == 0 then
    table.insert(lines, 1, "OK")
  else
    table.insert(lines, 1, "FAIL")
    add("failed", table.concat(failed, ","))
  end
end)

if not ok then
  write_result({ "FAIL", "error=" .. tostring(err) })
else
  write_result(lines)
end

reaper.Main_OnCommand(40004, 0)
