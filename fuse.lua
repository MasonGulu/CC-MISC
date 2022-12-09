assert(not _G.fs.fuse, "Already loaded!")
_G.fs.fuse = true

local absInv = require("abstractInvLib")
local inventories = {}
function _G.fs.mountInventory(name, inv)
  inventories[name] = absInv(inv)
  inventories[name].refreshStorage()
end

local storage_dir = "storage"

-- https://stackoverflow.com/questions/1426954/split-string-in-lua
local function split (inputstr, sep)
  sep = sep or "%s"
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local function isInStorageDir(path)
  local splitPath = split(path, "/")
  return splitPath[1] == storage_dir
end

local function isStorage(path)
  local splitPath = split(path, "/")
  return isInStorageDir(path) and #splitPath > 1 and inventories[splitPath[2]]
end

local old_list = _G.fs.list
function _G.fs.list(path)
  path = fs.combine(path)
  if path == "" then
    local listing = old_list(path)
    table.insert(listing, storage_dir)
    return listing
  elseif path == storage_dir then
    local listing = {}
    for k,v in pairs(inventories) do
      table.insert(listing, k)
    end
    return listing
  elseif isStorage(path) then
    local listing = {}
    local splitPath = split(path, "/")
    if #splitPath > 2 then
      error("Not a directory")
    end
    for k,v in pairs(inventories[splitPath[2]].list()) do
      table.insert(listing, tostring(k))
    end
    return listing
  end
  return old_list(path)
end

local old_isDir = _G.fs.isDir
function _G.fs.isDir(path)
  path = fs.combine(path)
  if path == storage_dir then
    return true
  elseif isStorage(path) then
    local splitPath = split(path, "/")
    if #splitPath > 2 then
      return false
    end
    return true
  end
  return old_isDir(path)
end

local old_exists = _G.fs.exists
function _G.fs.exists(path)
  path = fs.combine(path)
  if path == storage_dir then
    return true
  elseif isStorage(path) then
    local splitPath = split(path, "/")
    if #splitPath > 2 then
      if #splitPath == 3 then
        local listed = fs.list(fs.combine(table.unpack(splitPath, 1, 2)))
        for k,v in pairs(listed) do
          if v == splitPath[3] then
            return true
          end
        end
      end
      return false
    end
    return true
  end
  return old_exists(path)
end

local old_delete = _G.fs.delete
function _G.fs.delete(path)
  path = fs.combine(path)
  assert(not isInStorageDir(path), "Cannot delete virtual files.")
  return old_delete(path)
end

local old_find = _G.fs.find
function _G.fs.find(path)
  path = fs.combine(path)
  if isInStorageDir(path) then
    if fs.exists(path) then
      return {path}
    end
    return nil
  end
  return old_find(path)
end

local old_move = _G.fs.move
function _G.fs.move(path, dest)
  path = fs.combine(path)
  if isInStorageDir(path) and isInStorageDir(dest) then
    local splitPath = split(path, "/")
    local splitDest = split(dest, "/")
    assert(#splitPath == 3, "No source file provided")
    return inventories[splitPath[2]].pushItems(inventories[splitDest[2]], tonumber(splitPath[3]) or splitPath[3], nil, tonumber(splitDest[3]))
  elseif isInStorageDir(path) or isInStorageDir(dest) then
    error("Attempt to move virtual file outside of virtual fs.")
  end
  return old_move(path, dest)
end

print("Item fuse initialized.")