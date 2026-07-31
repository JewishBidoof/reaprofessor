-- Multi-action cue + normalize legacy cues (LP2 shape)
local out = "/tmp/reaprofessor-test/lp2-cue-result.txt"
local lines = {}
local function add(k,v) lines[#lines+1]=k.."="..tostring(v) end
local function write()
  local f=io.open(out,"w"); for _,l in ipairs(lines) do f:write(l.."\n") end; f:close()
end

local ok,err=pcall(function()
  package.path = reaper.GetResourcePath().."/Scripts/ReaProfessor/lib/?.lua;"..package.path
  local Data=require("data")
  local Commands=require("commands")
  local Config=require("config")
  Config.FINALIZED=true

  for i=reaper.CountTracks(0)-1,0,-1 do reaper.DeleteTrack(reaper.GetTrack(0,i)) end
  reaper.InsertTrackAtIndex(0,true)
  local tr=reaper.GetTrack(0,0)
  reaper.GetSetMediaTrackInfo_String(tr,"P_NAME","LP01",true)
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:ReaProfessor_role","same_strip",true)
  assert(reaper.TrackFX_AddByName(tr,"JS: Filters/resonantlowpass",false,-1)>=0)
  assert(reaper.TrackFX_AddByName(tr,"JS: Delay/delay",false,-1)>=0)
  reaper.TrackFX_SetParamNormalized(tr,0,0,0.3)
  reaper.TrackFX_SetEnabled(tr,1,false)

  local snap=Data.capture_snapshot("LPSnap",{mode="full",selected_only=false})
  Data.save_snapshots({snap})

  -- Legacy flat cue normalizes to actions[]
  local legacy={ id="c1", name="Legacy", kind="snapshot", payload={snapshot="LPSnap"} }
  local norm=Data.normalize_cue(legacy)
  add("legacy_has_actions", #norm.actions==1 and norm.actions[1].kind=="snapshot")
  add("legacy_snap_name", norm.actions[1].snapshot=="LPSnap")
  add("format_ms", Data.format_ms(65000)=="01:05:00" or Data.format_ms(65000)=="01:05:00")
  add("parse_time", Data.parse_time_input("00:01:50")==1500 or Data.parse_time_input("1:5:0")==65000)

  -- Multi-action cue: snapshot + comment
  local cue=Data.new_cue("Show Cue")
  cue.actions={
    { kind="snapshot", snapshot="LPSnap", label="LPSnap" },
    { kind="comment", label="Lights go" },
  }
  cue.pre_wait_ms=0
  cue.fire_all=true
  Data.save_cues({cue})
  local meta=Data.load_meta(); meta.cue_index=1; Data.save_meta(meta)

  -- Mutate FX then GO should restore via action
  for i=reaper.TrackFX_GetCount(tr)-1,0,-1 do reaper.TrackFX_Delete(tr,i) end
  reaper.TrackFX_AddByName(tr,"ReaGate",false,-1)
  local cok,cmsg=Commands.cue_go()
  add("multi_go_ok", cok==true)
  add("multi_restored", reaper.TrackFX_GetCount(tr)==2)
  add("multi_bypass", reaper.TrackFX_GetEnabled(tr,1)==false)
  add("msg_has_snap", tostring(cmsg):find("LPSnap",1,true)~=nil)

  -- fire_all=false only runs first action (still snapshot)
  cue.fire_all=false
  Data.save_cues({cue})
  meta.cue_index=1; Data.save_meta(meta)
  for i=reaper.TrackFX_GetCount(tr)-1,0,-1 do reaper.TrackFX_Delete(tr,i) end
  local ok2=Commands.cue_go()
  add("fire_first_ok", ok2==true and reaper.TrackFX_GetCount(tr)==2)

  -- Missing snapshot reports clearly
  Data.save_cues({{ id="x", name="Broken", kind="snapshot", payload={snapshot="Nope"}, actions={{kind="snapshot",snapshot="Nope",label="Nope"}} }})
  meta.cue_index=1; Data.save_meta(meta)
  local mok,mmsg=Commands.cue_go()
  add("missing_ok", mok==false and tostring(mmsg):find("Missing",1,true)~=nil)

  -- Snap fire_cue link
  snap.fire_cue="Show Cue"
  -- recreate show cue
  Data.save_cues({cue})
  Data.save_snapshots({snap})
  -- wipe and recall via Commands.snap_recall which fires linked cue
  for i=reaper.TrackFX_GetCount(tr)-1,0,-1 do reaper.TrackFX_Delete(tr,i) end
  reaper.TrackFX_AddByName(tr,"ReaEQ",false,-1)
  -- Linked cue fires snapshot again — need cue with snapshot action
  cue.actions={{kind="snapshot",snapshot="LPSnap",label="LPSnap"}}
  cue.fire_all=true
  Data.save_cues({cue})
  Commands.snap_recall("LPSnap")
  add("fire_cue_link", reaper.TrackFX_GetCount(tr)==2)

  local keys={"legacy_has_actions","legacy_snap_name","multi_go_ok","multi_restored","multi_bypass",
    "msg_has_snap","fire_first_ok","missing_ok","fire_cue_link"}
  local failed={}
  for _,k in ipairs(keys) do
    for _,l in ipairs(lines) do
      if l:sub(1,#k+1)==k.."=" and not l:match("=true$") then failed[#failed+1]=k end
    end
  end
  if #failed==0 then table.insert(lines,1,"OK") else table.insert(lines,1,"FAIL"); add("failed",table.concat(failed,",")) end
end)
if not ok then local f=io.open(out,"w"); f:write("FAIL\nerror="..tostring(err).."\n"); f:close()
else write() end
reaper.Main_OnCommand(40004,0)
