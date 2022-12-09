local common = require("common")
local printf = common.printf

---@type table array of module filenames to load
local modules = {
  "modules.inventory",
  "modules.gui",
}

-- A module should return a table that contains at least the following fields
---@class module
---@field id string
---@field config table<string, configspec>|nil
---@field init fun(modules:table,config:table):table

---@class configspec
---@field default any
---@field type string

local function interface__index(id)
  return function(t,k)
    if k == "interface" then
      error(("Attempt to get interface of %s before it was initialized"):format(id, id), 2)
    end
  end
end

---@type table loaded config information
local config = {}
---@type table array of module IDs in init order
local moduleInitOrder = {}
---@type table [id] -> module return info
local loaded = setmetatable({}, {__index = function (t,k)
  error(("Attempt to access non-existant plugin %s"):format(k), 2)
end})
for _,v in ipairs(modules) do
  ---@type module
  local mod = require(v)
  loaded[mod.id] = setmetatable(mod, {__index=interface__index(mod.id)})
  config[mod.id] = mod.config
  table.insert(moduleInitOrder, mod.id)
  printf("Loaded %s v%s", mod.id, mod.version)
end

local function protectedIndex(t, ...)
  local curIndex = t
  for k,v in pairs({...}) do
    curIndex = curIndex[v]
    if curIndex == nil then
      return nil
    end
  end
  return curIndex
end

local loadedConfig = common.loadTableFromFile("config.txt") or {}
local badOptions = {}
for id, spec in pairs(config) do
  for name, info in pairs(spec) do
    config[id][name].value = protectedIndex(loadedConfig, id, name, "value") or config[id][name].default
    if type(config[id][name].value) ~= info.type then
      table.insert(badOptions, ("Config option %s.%s is not type %s"):format(id, name, info.type))
    end
  end
end

local function saveConfig()
  common.saveTableToFile("config.txt", config, false)
end
saveConfig()

setmetatable(config, {__call=saveConfig})

if #badOptions > 0 then
  for k,v in pairs(badOptions) do
    print(v)
  end
  return
end


---@type table array of functions to run all the modules
local moduleExecution = {}
for _,v in ipairs(moduleInitOrder) do
  local mod = loaded[v]
  if mod.init then
    local t0 = os.clock()
    -- The table returned by init will be placed into [id].interface
    loaded[mod.id].interface = mod.init(loaded, config)
    table.insert(moduleExecution, loaded[mod.id].interface.start)
    printf("Initialized %s in %.2f seconds", mod.id, os.clock() - t0)
  else
    printf("Failed to initialize %s, no init function", mod.id)
  end
end

print("Starting execution...")
parallel.waitForAny(table.unpack(moduleExecution))