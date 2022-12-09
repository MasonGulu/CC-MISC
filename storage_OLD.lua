
fs.makeDir(".cache")
local storageMan = require("modules.storageMan")
local rednetMan = require("modules.rednetMan")

local configFile = "config.txt"

local config = {}

local configTypes = {
  inventories = "table",
  modem = "string",
  hostname = "string",
}

local defaultConfig = {
  inventories = {"minecraft:chest_4", "minecraft:chest_5", "minecraft:chest_6"},
  modem = "left",
  hostname = "test",
}

local function saveConfig()
  require("common").saveTableToFile(configFile, config)
end

local function loadConfig()
  local loaded = require("common").loadTableFromFile(configFile) or {}
  for k,v in pairs(defaultConfig) do
    config[k] = v
  end
  for k,v in pairs(loaded) do
    config[k] = v
  end
  for k,v in pairs(config) do
    assert(configTypes[k], ("Unexpected key in config, %s"):format(k))
    if type(configTypes[k]) == "table" then
      local matches = false
      for _, expectedType in ipairs(configTypes[k]) do
        if type(v) == expectedType then
          matches = true
          break
        end
      end
      assert(matches, ("Config value [%s]=%s does not match the type filter"):format(k,v))
    else
      assert(type(v) == configTypes[k], ("Config value [%s]=%s should be type %s"):format(k,v,configTypes[k]))
    end
  end
end

loadConfig()

local function startBasalt()
  local basalt = require("basalt")

  local main = assert(basalt.createFrame())
  local transferThread = main:addThread():start(function() storageMan.start(config) end)
  local rednetThread = main:addThread():start(function() rednetMan.start(config) end)

  main:addProgram():setSize("parent.w-2", "parent.h-8"):setPosition(2,2):execute("shell")
  main:addProgram():setSize("parent.w-2", 5):setPosition(2, "parent.h-5"):execute("events")

  basalt.autoUpdate()
end
startBasalt()