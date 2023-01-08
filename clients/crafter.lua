-- file to put on a turtle
local modem = peripheral.find("modem", function(name, modem)
  -- return not modem.isWireless()
  return true
end)
local modemName = peripheral.getName(modem)
rednet.open(modemName)
local networkName = modem.getNameLocal()
---@enum State
local STATES = {
  READY = "READY",
  ERROR = "ERROR",
  BUSY = "BUSY",
  CRAFTING = "CRAFTING",
  DONE = "DONE",
}
local state = STATES.READY
local connected = false
local port = 121
local keepAliveTimeout = 10
local w,h = term.getSize()
local banner = window.create(term.current(), 1, 1, w, 1)
local panel = window.create(term.current(),1,2,w,h-1)

local lastStateChange = os.epoch("utc")

local turtleInventory = {}
local function refreshTurtleInventory()
  local f = {}
  for i = 1, 16 do
    f[i] = function()
      turtleInventory[i] = turtle.getItemDetail(i, true)
    end
  end
  parallel.waitForAll(table.unpack(f))
  return turtleInventory
end
---@type CraftingNode 
local task
term.redirect(panel)

modem.open(port)
local function validateMessage(message)
  local valid = type(message) == "table" and message.protocol ~= nil
  valid = valid and (message.destination == networkName or message.destination == "*")
  valid = valid and message.source ~= nil
  return valid
end
local function getModemMessage(filter, timeout)
  local timer
  if timeout then
    timer = os.startTimer(timeout)
  end
  while true do
    ---@type string, string, integer, integer, any, integer
    local event, side, channel, reply, message, distance = os.pullEvent()
    if event == "modem_message" and (filter == nil or filter(message)) then
      if timeout then
        os.cancelTimer(timer)
      end
      return {
        side = side,
        channel = channel,
        reply = reply,
        message = message,
        distance = distance
      }
    elseif event == "timer" and timeout and side == timer then
      return
    end
  end
end
local lastChar = "|"
local charStateLookup = {
  ["|"] = "/",
  ["/"] = "-",
  ["-"] = "\\",
  ["\\"] = "|",
}
local lastCharUpdate = os.epoch("utc")
local function getActivityChar()
  if os.epoch("utc") - lastCharUpdate < 50 then
    return lastChar
  end
  lastCharUpdate = os.epoch("utc")
  lastChar = charStateLookup[lastChar]
  return lastChar
end
local function writeBanner()
  local x, y = term.getCursorPos()

  banner.setBackgroundColor(colors.gray)
  banner.setCursorPos(1,1)
  banner.clear()
  if connected then
    banner.setTextColor(colors.green)
    banner.write("CONNECTED")
  else
    banner.setTextColor(colors.red)
    banner.write("DISCONNECTED")
  end
  banner.setTextColor(colors.white)
  banner.setCursorPos(w-state:len(),1)
  banner.write(state)
  term.setCursorPos(x,y)

  local toDisplay = state
  if not connected then
    toDisplay = "!"..toDisplay
  end

  os.setComputerLabel(
    ("%s %s - %s"):format(getActivityChar(), networkName, toDisplay))
end
local function keepAlive()
  while true do
    local modemMessage = getModemMessage(function(message)
      return validateMessage(message) and message.protocol == "KEEP_ALIVE"
    end, keepAliveTimeout)
    connected = modemMessage ~= nil
    if modemMessage then
      modem.transmit(port, port, {
        protocol = "KEEP_ALIVE",
        state = state,
        source = networkName,
        destination = "HOST",
      })
    end
    writeBanner()
  end
end
local function colWrite(fg, text)
  local oldFg = term.getTextColor()
  term.setTextColor(fg)
  term.write(text)
  term.setTextColor(oldFg)
end

---@param newState State
local function changeState(newState)
  if state ~= newState then
    lastStateChange = os.epoch("utc")
  end
  state = newState
  local itemSlots = {}
  for i, _ in pairs(turtleInventory) do
    table.insert(itemSlots, i)
  end
  modem.transmit(port, port, {
    protocol = "KEEP_ALIVE",
    state = state,
    source = networkName,
    destination = "HOST",
    itemSlots = itemSlots,
  })
  writeBanner()
end

local function getItemSlots()
  refreshTurtleInventory()
  local itemSlots = {}
  for i, _ in pairs(turtleInventory) do
    table.insert(itemSlots, i)
  end
  return itemSlots

end

local function empty()
  local itemSlots = getItemSlots()
  repeat
    modem.transmit(port, port, {
      protocol = "EMPTY",
      destination = "HOST",
      source = networkName,
      itemSlots = itemSlots
    })
    itemSlots = getItemSlots()
    os.sleep(3)
    -- this delay needs to be high enough
    -- to allow the inventory system to
    -- actually perform the transfers
  until #itemSlots == 0
end

local function signalDone()
  local itemSlots = getItemSlots()
  changeState(STATES.DONE)
  modem.transmit(port, port, {
    protocol = "CRAFTING_DONE",
    destination = "HOST",
    source = networkName,
    itemSlots = itemSlots,
  })
end

local function tryToCraft()
  local readyToCraft = true
  for slot,v in pairs(task.plan) do
    local x = (slot-1) % (task.width or 3) + 1
    local y = math.floor((slot-1) / (task.height or 3))
    local turtleSlot = y * 4 + x
    readyToCraft = readyToCraft and turtleInventory[turtleSlot]
    if not readyToCraft then
      break
    else
      readyToCraft = readyToCraft and turtleInventory[turtleSlot].count == v.count
      local errorFree = turtleInventory[turtleSlot].name == v.name
      if not errorFree then
        state = STATES.ERROR
        return
      end
    end
  end
  if readyToCraft then
    turtle.craft()
    signalDone()
  end
end


local protocols = {
  CRAFT = function (message)
    task = message.task
    changeState(STATES.CRAFTING)
    tryToCraft()
  end
}

local interface
local function modemInterface()
  while true do
    local event = getModemMessage(validateMessage)
    assert(event, "Got no message?")
    if protocols[event.message.protocol] then
      protocols[event.message.protocol](event.message)
    end
  end
end

local function turtleInventoryEvent()
  while true do
    os.pullEvent("turtle_inventory")
    refreshTurtleInventory()
    if state == STATES.CRAFTING then
      tryToCraft()
    elseif state == STATES.DONE then
      -- check if the items have been removed from the inventory
      refreshTurtleInventory()
      local emptyInv = not next(turtleInventory)
      if emptyInv then
        changeState(STATES.READY)
      end
    end
  end
end

local slotToRecipeLookup = {
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [5] = 4,
  [6] = 5,
  [7] = 6,
  [9] = 7,
  [10] = 8,
  [11] = 9
}

local function addRecipe(shaped)
  refreshTurtleInventory()
  local recipe = {}
  if shaped then
    for turtleSlot, craftSlot in pairs(slotToRecipeLookup) do
      recipe[craftSlot] = (turtleInventory[turtleSlot] or {}).name
    end
  else
    for _, item in pairs(turtleInventory) do
      table.insert(recipe, item.name)
    end
  end
  turtle.craft()
  refreshTurtleInventory()
  local crafted, amount = "", 0
  for _, item in pairs(turtleInventory) do
    crafted = item.name
    amount = amount + item.count
  end
  modem.transmit(port, port, {
    protocol = "NEW_RECIPE",
    destination = "HOST",
    source = networkName,
    name = crafted,
    amount = amount,
    recipe = recipe,
    shaped = shaped
  })
end

local interfaceLUT
interfaceLUT = {
  help = function()
    local maxw = 0
    local commandList = {}
    for k,v in pairs(interfaceLUT) do
      maxw = math.max(maxw, k:len()+1)
      table.insert(commandList, k)
    end
    local elementW = math.floor(w / maxw)
    local formatStr = "%"..maxw.."s"
    for i,v in ipairs(commandList) do
      term.write(formatStr:format(v))
      if (i + 1) % elementW == 0 then
        print()
      end
    end
    print()
  end,
  clear = function()
    term.clear()
    term.setCursorPos(1,1)
  end,
  info = function()
    print(("Local network name: %s"):format(networkName))
  end,
  cinfo = function()
    if state == STATES.CRAFTING then
      print("Current recipe is:")
      print(textutils.serialise(task.plan))
    else
      print("Not crafting.")
    end
  end,
  reboot = function ()
    os.reboot()
  end,
  recipe = function ()
    if state ~= "READY" then
      print("Must be ready to use")
      return
    end
    changeState(STATES.BUSY)
    print("Too add a crafting recipe, place the recipe in the turtle's inventory.")
    print("Then enter 1 for shaped, 2 for unshaped, or anything else to cancel")
    local shapeSelection = read()
    if shapeSelection == "1" then
      addRecipe(true)
    elseif shapeSelection == "2" then
      addRecipe(false)
    else
      print("Cancelled")
    end
    changeState(STATES.READY)
  end
}
function interface()
  print("Crafting turtle indev")
  while true do
    colWrite(colors.cyan, "] ")
    local input = io.read()
    if interfaceLUT[input] then
      interfaceLUT[input]()
    else
      colWrite(colors.red, "Invalid command.")
      print()
    end
  end
end

local retries = 0
local function errorChecker()
  while true do
    if os.epoch("utc") - lastStateChange > 10000 then
      lastStateChange = os.epoch("utc")
      if state == STATES.DONE then
        signalDone()
        retries = retries + 1
        if retries > 2 then
          print("Done too long")
          changeState(STATES.ERROR)
        end
      elseif state == STATES.CRAFTING then
        retries = retries + 1
        if retries > 2 then
          print("Crafting too long")
          changeState(STATES.ERROR)
        end
      else
        retries = 0
      end
    end
    os.sleep(1)
    writeBanner()
  end
end

writeBanner()
local ok, err = pcall(parallel.waitForAny, interface, keepAlive, modemInterface, turtleInventoryEvent, errorChecker)

os.setComputerLabel(("X %s - %s"):format(networkName, "OFFLINE"))
error(err)