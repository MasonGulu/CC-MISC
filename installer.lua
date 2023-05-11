local repositoryUrl = "https://raw.githubusercontent.com/MasonGulu/CC-MISC/master/"

if ({ ... })[1] == "dev" then
  repositoryUrl = "https://raw.githubusercontent.com/MasonGulu/CC-MISC/dev/"
end

local function fromURL(url)
  return { url = url }
end

local function fromRepository(url)
  return fromURL(repositoryUrl .. url)
end

local craftInstall = {
  name = "Install all crafting modules",
  files = {
    ["bfile.lua"] = fromRepository "bfile.lua",
    modules = {
      ["crafting.lua"] = fromRepository "modules/crafting.lua",
      ["furnace.lua"] = fromRepository "modules/furnace.lua",
      ["grid.lua"] = fromRepository "modules/grid.lua",
    },
    recipes = {
      ["grid_recipes.bin"] = fromRepository "recipes/grid_recipes.bin",
      ["item_lookup.bin"] = fromRepository "recipes/item_lookup.bin",
      ["furnace_recipes.bin"] = fromRepository "recipes/furnace_recipes.bin",
    }
  }
}

local logInstall = {
  name = "Install a logger",
  files = {
    modules = {
      ["logger.lua"] = fromRepository "modules/logger.lua"
    }
  }
}

local introspectionInstall = {
  name = "Install the modules necessary for use with the introspection module",
  files = {
    modules = {
      ["introspection.lua"] = fromRepository "modules/introspection.lua",
      ["interface.lua"] = fromRepository "modules/interface.lua"
    }
  }
}

local baseInstall = {
  name = "Install base MISC and basic modem modules.",
  files = {
    ["startup.lua"] = fromRepository "storage.lua",
    ["abstractInvLib.lua"] = fromURL "https://gist.githubusercontent.com/MasonGulu/57ef0f52a93304a17a9eaea21f431de6/raw/07c3322a5fa0d628e558e19017295728e4ee2e8d/abstractInvLib.lua", -- TODO change this
    ["common.lua"] = fromRepository "common.lua",
    modules = {
      ["inventory.lua"] = fromRepository "modules/inventory.lua",
      ["interface.lua"] = fromRepository "modules/interface.lua",
      ["modem.lua"] = fromRepository "modules/modem.lua",
    }
  }
}

local serverInstallOptions = {
  name = "Server installation options",
  b = baseInstall,
  c = craftInstall,
  i = introspectionInstall,
  l = logInstall
}

local terminalInstall = {
  name = "Install a basic item access terminal on a turtle",
  files = {
    ["startup.lua"] = fromRepository "clients/terminal.lua",
    ["modemLib.lua"] = fromRepository "clients/modemLib.lua"
  }
}

local crafterInstall = {
  name = "Install an autocrafting terminal on a crafty turtle",
  files = {
    ["startup.lua"] = fromRepository "clients/crafter.lua"
  }
}

local monitorInstall = {
  name = "Install a basic usage monitor",
  files = {
    ["startup.lua"] = fromRepository "clients/usageMonitor.lua",
    ["modemLib.lua"] = fromRepository "clients/modemLib.lua"
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
  term.setCursorPos(1, 1)
  term.setTextColor(colors.black)
  term.setBackgroundColor(colors.white)
  term.clearLine()
  print("MISC INSTALLER")
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
  for k, v in pairs(options) do
    if k ~= "name" then
      print(string.format("[%s] %s", k, v.name))
    end
  end
end

local alwaysOverwrite = false

local function downloadFile(path, url)
  print(string.format("Installing %s to %s", url, path))
  local response = assert(http.get(url, nil, true), "Failed to get " .. url)
  local writeFile = true
  if fs.exists(path) and not alwaysOverwrite then
    term.write("%s already exists, overwrite? Y/n/always? ")
    local i = io.read():sub(1, 1)
    alwaysOverwrite = i == "a"
    writeFile = alwaysOverwrite or i ~= "n"
  end
  if writeFile then
    local f = assert(fs.open(path, "wb"), "Cannot open file " .. path)
    f.write(response.readAll())
    f.close()
  end
  response.close()
end

local function downloadFiles(folder, files)
  for k, v in pairs(files) do
    local path = fs.combine(folder, k)
    if v.url then
      downloadFile(path, v.url)
    else
      fs.makeDir(path)
      downloadFiles(path, v)
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
