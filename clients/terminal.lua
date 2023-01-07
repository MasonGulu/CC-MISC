-- storage terminal turtle for the system
local turtleInventory = {}
local lib = require("modemLib")
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

local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)
local selfName = peripheral.call(modem, "getNameLocal")

---@type "SEARCH"|"INFO"|"CRAFT"
local mode = "SEARCH"

local busySlots = {} -- slots not to auto-import

local function eventTurtleInventory()
  while true do
    os.pullEvent("turtle_inventory")
    local oldFilledSlots = {}
    for i,_ in pairs(turtleInventory) do
      oldFilledSlots[i] = true
    end
    refreshTurtleInventory()
    for i,_ in pairs(turtleInventory) do
      if not oldFilledSlots[i] then
        if busySlots[i] then
          busySlots[i] = nil
        else
          -- an item was placed into this slot, empty the slot
          lib.pullItems(true, selfName, i, nil, nil, nil, {optimal=false})
        end
      end
    end
    lib.performTransfer()
  end
end

local display = window.create(term.current(),1,1,term.getSize())
local w,h = display.getSize()
local itemCountW = 5
local itemNameW = w-itemCountW
local function formatItem(name,count)
  return ("%-"..itemCountW.."s %-"..itemNameW.."s"):format(count,name)
end
local function setColors(fg,bg)
  display.setTextColor(fg)
  display.setBackgroundColor(bg)
end

local function text(x,y,t)
  display.setCursorPos(math.floor(x),math.floor(y))
  display.write(t)
end

local list = lib.list()
local craftables = lib.listCraftables()

local filter = ""
local craftFilter = ""
local itemAmount = ""
local siftedList = {}
local siftedCraftables = {}
local selectedItem = 1
local selectedCraft = 1
local displayItem -- prevent the selected item from drifting while directly accessing it
local requestingCraft = false -- set to true to make INFO enter request craft instead

local function sortSearch()
  table.sort(list, function(a,b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)
  if pcall(string.match,"",filter) then
    siftedList = {}
    for k,v in pairs(list) do
      if v.name:match(filter) or v.displayName:lower():match(filter) or v.displayName:match(filter) then
        table.insert(siftedList, v)
      end
    end
  end
  selectedItem = math.min(selectedItem, #siftedList)
end
sortSearch()
local function filterCraftables()
  table.sort(craftables)
  if pcall(string.match,"",craftFilter) then
    siftedCraftables = {}
    for k,v in pairs(craftables) do
      if v:match(craftFilter) then
        table.insert(siftedCraftables, v)
      end
    end
  end
  selectedCraft = math.min(selectedCraft, #siftedCraftables)
end
filterCraftables()

local craftInfo
local disableDrawing = false

local function changeMode(new_mode)
  if new_mode == "REQUEST" then
    local craft = siftedCraftables[selectedCraft]
    if not craft then
      mode = "CRAFT"
      return
    end
    disableDrawing = true
    display.clear()
    text(1,1,"Requesting Item")
    text(1,2,craft)
    while true do
      display.setCursorPos(1,3)
      display.clearLine()
      text(1,3,"Quantity? ")
      local input = read()
      if input == "" then
        mode = "CRAFT"
        disableDrawing = false
        return
      end
      local num_input = tonumber(input)
      if num_input then
        if num_input > 0 then
          craftInfo = lib.requestCraft(craft, tonumber(input))
          break
        end
      end
    end
    disableDrawing = false
  elseif new_mode == "INFO" then
    displayItem = siftedList[selectedItem]
    itemAmount = tostring(math.min(displayItem.maxCount, displayItem.count))
  end
  mode = new_mode
end

local function getFirstItemOnScreen(item, list)
  return math.max(math.min(math.max(1,item-5), #list-h+4), 1)
end

local function getLastItemOnScreen(item, list)
  local scroll = getFirstItemOnScreen(item,list)
  return math.min(scroll+h+1, #list)
end

local function getYWithScroll(scroll, item)
  return 4 - scroll + item
end

local drawModes = {
  SEARCH = function ()
    text(1,2,filter)
    text(1,3,formatItem("Name","Count"))
    local screenScroll = getFirstItemOnScreen(selectedItem, siftedList)
    for i=screenScroll, getLastItemOnScreen(screenScroll, siftedList) do
      local item = siftedList[i]
      local y = getYWithScroll(screenScroll, i)
      if y > 3 then
        if i == selectedItem then
          setColors(colors.black,colors.white)
        end
        text(1,y,formatItem(item.displayName,item.count))
        setColors(colors.white,colors.black)
      end
    end
    display.setCursorBlink(true)
    display.setCursorPos(filter:len()+1,2)
  end,
  INFO = function ()
    local item = displayItem
    text(1,2,("%u x %s"):format(item.count,item.displayName))
    text(1,3,item.name)
    text(1,4,item.nbt)
    if item.enchantments then
      text(1,5,"Enchantments")
      for k,v in ipairs(item.enchantments) do
        text(1,5+k,v.displayName or v.name)
      end
    end
    text(1,h,("Withdraw: %s"):format(itemAmount))
    display.setCursorBlink(true)
    display.setCursorPos(itemAmount:len()+11,h)
  end,
  CRAFT = function ()
    text(1,2,craftFilter)
    text(1,3,"Name")
    local screenScroll = getFirstItemOnScreen(selectedCraft, siftedCraftables)
    for i=screenScroll, getLastItemOnScreen(screenScroll, siftedCraftables) do
      local name = siftedCraftables[i]
      local y = getYWithScroll(screenScroll, i)
      if y > 3 then
        if i == selectedCraft then
          setColors(colors.black,colors.white)
          display.setCursorPos(1,y)
          display.clearLine()
        end
        text(1,y,name)
        setColors(colors.white,colors.black)
      end
    end
    display.setCursorBlink(true)
    display.setCursorPos(craftFilter:len()+1,2)
  end,
  REQUEST = function ()
    text(1,2,(craftInfo.success and "Press y to craft, n to cancel") or "Press n to cancel the craft")
    text(1,3,("Requested %s"):format(siftedCraftables[selectedCraft]))
    text(1,4,(craftInfo.success and "Success") or "Failure")
    local line = 5
    if not craftInfo.success then
      setColors(colors.red,colors.black)
      text(1,line,"Missing:")
      line = line + 1
      for k,v in pairs(craftInfo.missing) do
        text(1,line,("%ux%s"):format(v,k))
        line = line + 1
      end
      setColors(colors.white,colors.black)
    end
    text(1,line,"To use:")
    line = line + 1
    for k,v in pairs(craftInfo.toUse) do
      text(1,line,("%ux%s"):format(v,k))
      line = line + 1
    end
    text(1,line,"To craft:")
    line = line + 1
    for k,v in pairs(craftInfo.toCraft) do
      text(1,line,("%ux%s"):format(v,k))
      line = line + 1
    end
  end
}

local function draw()
  if drawModes[mode] and not disableDrawing then
    display.setVisible(false)
    display.setCursorBlink(false)
    display.clear()
    setColors(colors.black, colors.white)
    display.setCursorPos(1,1)
    display.clearLine()
    display.write(mode)
    setColors(colors.white,colors.black)
    drawModes[mode]()
    display.setVisible(true)
  end
end

local function eventUpdate()
  while true do
    _, list = os.pullEvent("update")
    sortSearch()
    draw()
  end
end

local charModes = {
  SEARCH = function (ch)
    filter = filter .. ch
    sortSearch()
  end,
  INFO = function (ch)
    if ch >= '0' and ch <= '9' then
      itemAmount = itemAmount .. ch
    end
  end,
  CRAFT = function (ch)
    craftFilter = craftFilter .. ch
    filterCraftables()
  end,
  REQUEST = function (ch)
    if craftInfo then
      if ch == 'y' and craftInfo.success then
        lib.startCraft(craftInfo.jobId)
        craftInfo = nil
        changeMode("SEARCH")
      elseif ch == 'n' then
        lib.cancelCraft(craftInfo.jobId)
        craftInfo = nil
        changeMode("SEARCH")
      end
    end
  end
}
local function handleChar(ch)
  assert(charModes[mode], "Missing char_mode "..mode)(ch)
end

local function requestItem(item,amount)
  amount = amount or 0
  if amount == 0 then
    requestingCraft = false
    return
  end

  if requestingCraft then
    requestingCraft = false
    lib.requestCraft(item.name,amount)
    changeMode("SEARCH")
    return
  end
  amount = math.min(amount, item.count)
  local stacks = math.min(math.ceil(amount / item.maxCount),16)
  local freeSlots = {}
  for i = 1, 16 do
    freeSlots[i] = true
  end
  for i,_ in pairs(turtleInventory) do
    freeSlots[i] = nil
  end
  for i = 1, stacks do
    local slot = next(freeSlots)
    if not slot then break end -- not enough space in the turtle to fit all of the items
    busySlots[slot] = true
    freeSlots[slot] = nil
  end
  lib.pushItems(true,selfName,item.name,amount,nil,item.nbt)
  lib.performTransfer()
end

local keyModes = {
  SEARCH = function (key)
    if key == keys.backspace then
      filter = filter:sub(1, -2)
      sortSearch()
    elseif key == keys.up then
      selectedItem = math.max(selectedItem - 1, 1)
    elseif key == keys.down then
      selectedItem = math.min(selectedItem + 1, #siftedList)
    elseif key == keys.enter then
      if selectedItem > 0 then
        changeMode("INFO")
      end
    elseif key == keys.tab then
      changeMode("CRAFT")
    end
  end,
  INFO = function (key)
    if key == keys.backspace then
      itemAmount = itemAmount:sub(1, -2)
    elseif key == keys.enter then
      requestItem(displayItem,tonumber(itemAmount or 0))
      changeMode("SEARCH")
    end
  end,
  CRAFT = function (key)
    if key == keys.backspace then
      craftFilter = craftFilter:sub(1, -2)
      filterCraftables()
    elseif key == keys.up then
      selectedCraft = math.max(selectedCraft - 1, 1)
    elseif key == keys.down then
      selectedCraft = math.min(selectedCraft + 1, #siftedCraftables)
    elseif key == keys.enter then
      if selectedCraft > 0 then
        displayItem = {name=siftedCraftables[selectedCraft], count = 10000} -- TODO
        requestingCraft = true
        changeMode("REQUEST")
        -- this can easily become outdated if the contents of the storage change
      end
    elseif key == keys.tab then
      changeMode("SEARCH")
    end
  end,
  REQUEST = function (key)
    
  end
}
local function handleKey(key)
  assert(keyModes[mode], "Missing key_mode "..mode)(key)
end

local function inputHandler()
  while true do
    local e = {os.pullEvent()}
    if e[1] == "char" then
      handleChar(e[2])
    elseif e[1] == "key" then
      handleKey(e[2])
    elseif e[1] == "mouse_click" then
      if mode == "SEARCH" then
        selectedItem = getFirstItemOnScreen(selectedItem, siftedList) + e[4] - 4
        changeMode("INFO")
      elseif mode == "CRAFT" then
        selectedCraft = getFirstItemOnScreen(selectedCraft, siftedCraftables) + e[4] - 4
        changeMode("REQUEST")
      end
    elseif e[1] == "mouse_scroll" then
      if mode == "SEARCH" then
        selectedItem = math.max(math.min(selectedItem + e[2], #siftedList), 1)
      elseif mode == "CRAFT" then
        selectedCraft = math.max(math.min(selectedCraft + e[2], #siftedCraftables), 1)
      end
    end
    draw()
  end
end

draw()
parallel.waitForAll(lib.subscribe, eventTurtleInventory, eventUpdate, inputHandler)