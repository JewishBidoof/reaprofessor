-- @description ReaProfessor library (path.lua)
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex

-- Shared path bootstrap for ReaProfessor scripts (works with Actions + dofile).
local M = {}

function M.script_dir()
  local src = debug.getinfo(2, "S").source
  if src and src:sub(1, 1) == "@" then
    local path = src:sub(2)
    local dir = path:match("(.+[\\/])")
    if dir then return dir end
  end
  -- Fallback when loaded via Actions context
  local ctx = ({reaper.get_action_context()})[2]
  if ctx and ctx ~= "" then
    local dir = ctx:match("(.+[\\/])")
    if dir then return dir end
  end
  return reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
end

function M.setup_package_path()
  local dir = M.script_dir()
  -- debug.getinfo(2) from setup_package_path points at caller; use explicit dir
  local src = debug.getinfo(2, "S").source
  if src and src:sub(1, 1) == "@" then
    local path = src:sub(2)
    local d = path:match("(.+[\\/])")
    if d then dir = d end
  end
  package.path = dir .. "lib/?.lua;" .. dir .. "?.lua;" .. package.path
  -- Always also search the linked resource Scripts folder
  local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
  package.path = res .. "lib/?.lua;" .. res .. "?.lua;" .. package.path
  return dir
end

return M
