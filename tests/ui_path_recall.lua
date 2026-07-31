-- Reproduce / verify user-facing recall paths (UI mode, cues, selected_only, params rebuild)
local out = "/tmp/reaprofessor-test/ui-path-result.txt"
local lines = {}
local function add(k,v) lines[#lines+1]=k.."="..tostring(v) end
local function log(m) lines[#lines+1]="log="..tostring(m) end
local function write()
  local f=io.open(out,"w"); for _,l in ipairs(lines) do f:write(l.."\n") end; f:close()
end
local function clear()
  for i=reaper.CountTracks(0)-1,0,-1 do reaper.DeleteTrack(reaper.GetTrack(0,i)) end
end
local function wipe(tr)
  for i=reaper.TrackFX_GetCount(tr)-1,0,-1 do reaper.TrackFX_Delete(tr,i) end
end
local function names(tr)
  local t={}
  for i=0,reaper.TrackFX_GetCount(tr)-1 do
    local _,n=reaper.TrackFX_GetFXName(tr,i,"")
    t[#t+1]=n
  end
  return table.concat(t," | ")
end

local ok,err=pcall(function()
  package.path = reaper.GetResourcePath().."/Scripts/ReaProfessor/lib/?.lua;"..package.path
  local Data=require("data")
  local Commands=require("commands")
  local Config=require("config")
  Config.FINALIZED=true

  clear()
  reaper.InsertTrackAtIndex(0,true)
  local tr=reaper.GetTrack(0,0)
  reaper.GetSetMediaTrackInfo_String(tr,"P_NAME","UI01",true)
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:ReaProfessor_role","same_strip",true)

  local chain={"JS: Filters/resonantlowpass","JS: Delay/delay","JS: Utility/volume"}
  for _,n in ipairs(chain) do
    assert(reaper.TrackFX_AddByName(tr,n,false,-1)>=0, "add "..n)
  end
  reaper.TrackFX_SetParamNormalized(tr,0,0,0.25)
  reaper.TrackFX_SetEnabled(tr,1,false)
  local want_n=reaper.TrackFX_GetCount(tr)
  local want_p0=reaper.TrackFX_GetParamNormalized(tr,0,0)
  log("built "..names(tr))

  ------------------------------------------------------------------
  -- A: Snapshots UI used to pass mode=params over a full snap → broken.
  --    Now params+mismatched chain auto-upgrades to full rebuild.
  ------------------------------------------------------------------
  local snap_full=Data.capture_snapshot("FullA",{mode="full",selected_only=false})
  Data.save_snapshots({snap_full})
  wipe(tr)
  reaper.TrackFX_AddByName(tr,"ReaGate",false,-1)
  Data.recall_snapshot(snap_full,{mode="params",selected_only=false}) -- old buggy UI call
  add("A_params_override_rebuilds", reaper.TrackFX_GetCount(tr)==want_n)
  log("after A: count="..reaper.TrackFX_GetCount(tr).." "..names(tr))

  ------------------------------------------------------------------
  -- A2: Correct UI path — no mode override
  ------------------------------------------------------------------
  wipe(tr)
  reaper.TrackFX_AddByName(tr,"ReaGate",false,-1)
  Data.recall_snapshot(snap_full,{selected_only=false})
  add("A2_snap_mode_full", reaper.TrackFX_GetCount(tr)==want_n)

  ------------------------------------------------------------------
  -- B: + CUE now captures full; wipe + cue GO restores chain
  ------------------------------------------------------------------
  local meta=Data.load_meta()
  meta.snapshot_mode="full"
  Data.save_meta(meta)
  Data.recall_snapshot(snap_full)
  -- Mimic cue_list add_cue (always full)
  local cue_snap=Data.capture_snapshot("CueFull",{mode="full",selected_only=false})
  Data.save_snapshots({snap_full,cue_snap})
  Data.save_cues({{id="c1",name="CueFull",kind="snapshot",payload={snapshot="CueFull"},notes=""}})
  meta.cue_index=1
  Data.save_meta(meta)
  wipe(tr)
  reaper.TrackFX_AddByName(tr,"ReaEQ",false,-1)
  local cok,cmsg=Commands.cue_go()
  add("B_cue_full_after_wipe", cok and reaper.TrackFX_GetCount(tr)==want_n)
  log("cue_go ok="..tostring(cok).." msg="..tostring(cmsg).." count="..reaper.TrackFX_GetCount(tr).." "..names(tr))

  ------------------------------------------------------------------
  -- C: selected_only with nothing selected falls back to all eligible
  ------------------------------------------------------------------
  Data.recall_snapshot(snap_full)
  reaper.SetOnlyTrackSelected(tr)
  reaper.SetTrackSelected(tr,false)
  reaper.TrackFX_SetParamNormalized(tr,0,0,0.9)
  Data.recall_snapshot(snap_full,{mode="full",selected_only=true})
  local after_p=reaper.TrackFX_GetParamNormalized(tr,0,0)
  add("C_selected_fallback", math.abs(after_p-want_p0)<0.03)
  log("C p0="..tostring(after_p).." want="..tostring(want_p0))

  ------------------------------------------------------------------
  -- D: params capture now includes fxchain; wipe + params recall rebuilds
  ------------------------------------------------------------------
  Data.recall_snapshot(snap_full)
  local snap_p=Data.capture_snapshot("OnlyParams",{mode="params",selected_only=false})
  add("D_params_has_fxchain", type(snap_p.tracks[1].fxchain)=="string" and snap_p.tracks[1].fxchain:find("<FXCHAIN")~=nil)
  wipe(tr)
  Data.recall_snapshot(snap_p) -- snap.mode=params, but chain empty → auto full
  add("D_params_rebuilds", reaper.TrackFX_GetCount(tr)==want_n)
  add("D_params_bypass", reaper.TrackFX_GetEnabled(tr,1)==false)
  add("D_params_value", math.abs(reaper.TrackFX_GetParamNormalized(tr,0,0)-want_p0)<0.03)

  ------------------------------------------------------------------
  -- E: wrong-FX replace with ExtState roundtrip
  ------------------------------------------------------------------
  Data.save_snapshots({snap_full})
  local loaded=Data.load_snapshots()[1]
  wipe(tr)
  reaper.TrackFX_AddByName(tr,"ReaGate",false,-1)
  reaper.TrackFX_AddByName(tr,"ReaVerbate",false,-1)
  Data.recall_snapshot(loaded)
  add("E_replace_ok", reaper.TrackFX_GetCount(tr)==want_n)
  add("E_bypass_ok", reaper.TrackFX_GetEnabled(tr,1)==false)
  add("E_param_ok", math.abs(reaper.TrackFX_GetParamNormalized(tr,0,0)-want_p0)<0.03)
  log("final "..names(tr))

  local keys={"A_params_override_rebuilds","A2_snap_mode_full","B_cue_full_after_wipe",
    "C_selected_fallback","D_params_has_fxchain","D_params_rebuilds","D_params_bypass",
    "D_params_value","E_replace_ok","E_bypass_ok","E_param_ok"}
  local failed={}
  for _,k in ipairs(keys) do
    for _,l in ipairs(lines) do
      if l:sub(1,#k+1)==k.."=" and not l:match("=true$") then failed[#failed+1]=k end
    end
  end
  if #failed==0 then table.insert(lines,1,"OK") else table.insert(lines,1,"FAIL"); add("failed",table.concat(failed,",")) end
end)
if not ok then
  local f=io.open(out,"w"); f:write("FAIL\nerror="..tostring(err).."\n"); f:close()
else write() end
reaper.Main_OnCommand(40004,0)
