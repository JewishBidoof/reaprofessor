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
  local ok1, changed, msg = Menu.ensure_extensions_item(named, "ReaProfessor")
  add("ext_ok", ok1==true)
  -- Read menu.ini and ensure flat item (command starts with _RS, not numeric submenu)
  local path = reaper.GetResourcePath().."/reaper-menu.ini"
  local f=io.open(path,"r"); local text=f and f:read("*a") or ""; if f then f:close() end
  add("has_section", text:find("%[Main extensions%]")~=nil)
  local flat = false
  for line in text:gmatch("[^\n]+") do
    if line:find(named,1,true) and line:find("ReaProfessor",1,true) then
      -- item_N=_RSxxx ReaProfessor  — after = should start with _
      local val = line:match("^item_%d+=(.*)$")
      if val and val:match("^_RS") then flat = true end
      if val and val:match("^%d+%s") then flat = false; add("looks_like_submenu", val) end
    end
  end
  add("flat_item", flat)

  -- Nav stack
  Nav.clear()
  Nav.set_current(hub)
  add("can_back0", Nav.can_back()==false)
  local child = hub:gsub("ReaProfessor%.lua$", "cue_list.lua")
  Nav.go(child)
  add("pending1", Nav.take_pending()==child)
  -- go again properly
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

  local failed={}
  for _,k in ipairs({"hub","named","ext_ok","flat_item","can_back0","pending1","can_back1","back_ok","pending_hub","scale_ge1","dims_ok"}) do
    for _,l in ipairs(lines) do
      if l:sub(1,#k+1)==k.."=" and l~=(k.."=true") and not (k=="hub" or k=="named") then
        if not l:match("=true$") and k~="hub" and k~="named" then failed[#failed+1]=k end
      end
    end
  end
  -- recheck simply
  failed={}
  local function get(k) for _,l in ipairs(lines) do local a,b=l:match("^([^=]+)=(.*)$"); if a==k then return b end end end
  for _,k in ipairs({"ext_ok","flat_item","can_back0","can_back1","back_ok","scale_ge1","dims_ok"}) do
    if get(k)~="true" then failed[#failed+1]=k end
  end
  if get("named")~="true" then failed[#failed+1]="named" end
  if get("pending1")~="true" then failed[#failed+1]="pending1" end
  if get("pending_hub")~="true" then failed[#failed+1]="pending_hub" end
  if #failed==0 then table.insert(lines,1,"OK") else table.insert(lines,1,"FAIL"); add("failed",table.concat(failed,",")) end
end)
if not ok then local f=io.open(out,"w"); f:write("FAIL\nerror="..tostring(err).."\n"); f:close() else write() end
reaper.Main_OnCommand(40004,0)
