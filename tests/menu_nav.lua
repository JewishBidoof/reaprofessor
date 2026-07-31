local out = "/tmp/reaprofessor-test/menu-nav-result.txt"
local lines = {}
local function add(k,v) lines[#lines+1]=k.."="..tostring(v) end
local function write()
  local f=io.open(out,"w"); for _,l in ipairs(lines) do f:write(l.."\n") end; f:close()
end
local ok,err=pcall(function()
  package.path = reaper.GetResourcePath().."/Scripts/ReaProfessor/lib/?.lua;"..package.path
  local Menu=require("menu")
  local Nav=require("nav")
  local UI=require("ui")
  local Config=require("config")
  Config.FINALIZED=true

  local hub = Menu.find_hub()
  add("hub", hub~=nil)
  local cmd, named = Menu.register_hub(hub)
  add("named", named~=nil and named:sub(1,3)=="_RS")

  -- Force incomplete layout first (old bug: ReaProfessor only)
  do
    local path = reaper.GetResourcePath().."/reaper-menu.ini"
    local f=io.open(path,"w")
    f:write("[Main extensions]\nitem_0="..named.." ReaProfessor\n")
    f:close()
  end
  local ok1, changed, msg = Menu.ensure_extensions_item(named, "ReaProfessor")
  add("ext_ok", ok1==true)
  add("repaired", changed==true)
  add("msg_has_reapack", tostring(msg):find("ReaPack",1,true)~=nil)

  local path = reaper.GetResourcePath().."/reaper-menu.ini"
  local f=io.open(path,"r"); local text=f and f:read("*a") or ""; if f then f:close() end
  add("has_section", text:find("%[Main extensions%]")~=nil)
  add("has_reapack", text:find("_REAPACK_BROWSE",1,true)~=nil)
  add("has_sws", text:find("_SWS_ABOUT",1,true)~=nil or text:find("_SWSSNAPSHOT_OPEN",1,true)~=nil)
  add("has_reapack_submenu", text:find("%-2 Rea",1,true)~=nil or text:find("-2 Rea",1,true)~=nil)

  local flat = false
  for line in text:gmatch("[^\n]+") do
    if line:find(named,1,true) and line:find("ReaProfessor",1,true) then
      local val = line:match("^item_%d+=(.*)$")
      if val and val:match("^_RS") then flat = true end
      if val and val:match("^%d+%s") then flat = false; add("looks_like_submenu", val) end
    end
  end
  add("flat_item", flat)

  -- Second ensure should be no-op
  local ok2, changed2 = Menu.ensure_extensions_item(named, "ReaProfessor")
  add("second_ok", ok2==true)
  add("second_noop", changed2==false)

  -- Nav stack
  Nav.clear()
  Nav.set_current(hub)
  add("can_back0", Nav.can_back()==false)
  local child = hub:gsub("ReaProfessor%.lua$", "cue_list.lua")
  Nav.go(child)
  add("pending1", Nav.take_pending()==child)
  Nav.set_current(hub)
  Nav.go(child)
  add("can_back1", Nav.can_back()==true)
  Nav.set_current(child)
  add("back_ok", Nav.back()==true)
  add("pending_hub", Nav.take_pending()==hub)

  -- DPI init
  UI.init("dpi-test", 200, 100, 0)
  add("scale_ge1", (UI.scale or 0) >= 1)
  add("ext_retina_set", gfx.ext_retina ~= nil)
  local w,h = UI.dims()
  add("dims_ok", w>0 and h>0)
  gfx.quit()

  local function get(k) for _,l in ipairs(lines) do local a,b=l:match("^([^=]+)=(.*)$"); if a==k then return b end end end
  local failed={}
  for _,k in ipairs({
    "ext_ok","repaired","has_reapack","has_sws","has_reapack_submenu","flat_item",
    "second_ok","second_noop","can_back0","can_back1","back_ok","scale_ge1","dims_ok",
    "pending1","pending_hub"
  }) do
    if get(k)~="true" then failed[#failed+1]=k end
  end
  if get("named")~="true" then failed[#failed+1]="named" end
  if #failed==0 then table.insert(lines,1,"OK") else table.insert(lines,1,"FAIL"); add("failed",table.concat(failed,",")) end
end)
if not ok then local f=io.open(out,"w"); f:write("FAIL\nerror="..tostring(err).."\n"); f:close() else write() end
reaper.Main_OnCommand(40004,0)
