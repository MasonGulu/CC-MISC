local repositoryUrl = "https://raw.githubusercontent.com/MasonGulu/CC-MISC/master/"

if ({...})[1] == "dev" then
  repositoryUrl = "https://raw.githubusercontent.com/MasonGulu/CC-MISC/dev/"
end

local fullInstall = {
  name = "Install MISC and all modules",
  files = {
    ["startup.lua"] = "storage.lua",
    ["abstractInvLib.lua"] = "abstractInvLib.lua", -- TODO change this
    ["common.lua"] = "common.lua",
    ["bfile.lua"] = "bfile.lua",
    modules = {
      ["inventory.lua"] = "modules/inventory.lua",
      ["logger.lua"] = "modules/logger.lua",
      ["interface.lua"] = "modules/interface.lua",
      ["modem.lua"] = "modules/modem.lua",
      ["crafting.lua"] = "modules/crafting.lua",
      ["grid.lua"] = "modules/grid.lua",
    }
  }
}

local minInstall = {
  name = "Install MISC and the minimal interface modules",
  files = {
    ["startup.lua"] = "storage.lua",
    ["abstractInvLib.lua"] = "abstractInvLib.lua", -- TODO change this
    ["common.lua"] = "common.lua",
    ["bfile.lua"] = "bfile.lua",
    modules = {
      ["inventory.lua"] = "modules/inventory.lua",
      ["interface.lua"] = "modules/interface.lua",
      ["modem.lua"] = "modules/modem.lua",
    }
  }
}

local serverInstallOptions = {
  name = "Server installation options",
  f = fullInstall,
  m = minInstall
}

local terminalInstall = {
  name = "Install a basic item access terminal on a turtle",
  files = {
    ["startup.lua"] = "clients/terminal.lua",
    ["modemLib.lua"] = "clients/modemLib.lua"
  }
}

local crafterInstall = {
  name = "Install an autocrafting terminal on a crafty turtle",
  files = {
    ["startup.lua"] = "clients/crafter.lua"
  }
}

local monitorInstall = {
  name = "Install a basic usage monitor",
  files = {
    ["startup.lua"] = "clients/usageMonitor.lua",
    ["modemLib.lua"] = "clients/modemLib.lua"
  }
}

local clientInstallOptions = {
  name = "Client installation options",
  t = terminalInstall,
  c = crafterInstall,
  m = monitorInstall,
}

local installOptions = {
  s = serverInstallOptions,
  c = clientInstallOptions
}

---Pass in a key, value table to have the user select a value from
---@generic T
---@param options table<string,T>
---@return T
local function getOption(options)
  while true do
    local _, ch = os.pullEvent("char")
    if options[ch] then
      return options[ch]
    end
  end
end

local function displayOptions(options)
  term.clear()
  term.setCursorPos(1,1)
  term.setTextColor(colors.black)
  term.setBackgroundColor(colors.white)
  term.clearLine()
  print("MISC INSTALLER")
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
  for k,v in pairs(options) do
    if k ~= "name" then
      print(string.format("[%s] %s", k, v.name))
    end
  end
end

local alwaysOverwrite = false

local function downloadFile(path, url)
  print(string.format("Installing %s to %s", url, path))
  local response = assert(http.get(url, nil, true), "Failed to get "..url)
  local writeFile = true
  if fs.exists(path) and not alwaysOverwrite then
    term.write("%s already exists, overwrite? Y/n/always? ")
    local i = io.read():sub(1,1)
    alwaysOverwrite = i == "a"
    writeFile = alwaysOverwrite or i ~= "n"
  end
  if writeFile then
    local f = assert(fs.open(path, "w"), "Cannot open file "..path)
    f.write(response.readAll())
    f.close()
  end
  response.close()
end

local function downloadFiles(folder, files)
  for k,v in pairs(files) do
    local path = fs.combine(folder, k)
    if type(v) == "table" then
      fs.makeDir(path)
      downloadFiles(path,v)
    else
      downloadFile(path,repositoryUrl..v)
    end
  end
end

local function processOptions(options)
  displayOptions(options)
  local selection = getOption(options)
  if selection.files then
    downloadFiles("", selection.files)
  else
    processOptions(selection)
  end
end

processOptions(installOptions)
