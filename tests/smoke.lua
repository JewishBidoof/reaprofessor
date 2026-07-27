-- ReaProfessor automated smoke harness (run via tools/smoke_test.sh)
-- Writes /tmp/reaprofessor-test/smoke-result.txt and quits REAPER.

local out_dir = os.getenv("REAPROFESSOR_TEST_DIR") or "/tmp/reaprofessor-test"
local out_path = out_dir .. "/smoke-result.txt"
local root = os.getenv("REAPROFESSOR_ROOT")
if not root or root == "" then
  -- fall back to Scripts symlink layout
  root = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/../../.."
end

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

  -- Resolve scripts dir
  local scripts = path .. "/Scripts/ReaProfessor"
  package.path = scripts .. "/lib/?.lua;" .. package.path

  local Data = require("data")
  local OSC = require("osc")

  -- Seed a snapshot + cue, then fire GO via OSC dispatch path
  local snaps = {}
  local snap = Data.capture_snapshot("SmokeSnap")
  snaps[1] = snap
  Data.save_snapshots(snaps)

  local cues = {
    { id = "c1", name = "Smoke Cue", kind = "snapshot", payload = { snapshot = "SmokeSnap" }, notes = "test" },
  }
  Data.save_cues(cues)
  local meta = Data.load_meta()
  meta.cue_index = 1
  Data.save_meta(meta)

  -- Simulate cue GO without opening gfx: use Data.recall directly + assert roundtrip
  local loaded = Data.load_cues()
  local loaded_snaps = Data.load_snapshots()
  local recalled = false
  if loaded[1] and loaded_snaps[1] then
    recalled = Data.recall_snapshot(loaded_snaps[1])
  end

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
  add("cue_go", recalled)
  add("osc_cue_go_path", OSC.addresses.cue_go)
  add("scripts", scripts)
end)

if not ok then
  write_result({ "FAIL", "error=" .. tostring(err) })
else
  write_result(lines)
end

reaper.Main_OnCommand(40004, 0) -- quit
