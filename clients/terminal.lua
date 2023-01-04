-- storage terminal turtle for the system
local turtle_inventory = {}
local lib = require("modem_lib")
local function refresh_turtle_inventory()
  local f = {}
  for i = 1, 16 do
    f[i] = function()
      turtle_inventory[i] = turtle.getItemDetail(i, true)
    end
  end
  parallel.waitForAll(table.unpack(f))
  return turtle_inventory
end

local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)
local self_name = peripheral.call(modem, "getNameLocal")

---@type "SEARCH"|"INFO"|"CRAFT"
local mode = "SEARCH"

local busy_slots = {} -- slots not to auto-import

local function event_turtle_inventory()
  while true do
    os.pullEvent("turtle_inventory")
    local old_filled_slots = {}
    for i,_ in pairs(turtle_inventory) do
      old_filled_slots[i] = true
    end
    refresh_turtle_inventory()
    for i,_ in pairs(turtle_inventory) do
      if not old_filled_slots[i] then
        if busy_slots[i] then
          busy_slots[i] = nil
        else
          -- an item was placed into this slot, empty the slot
          lib.pullItems(self_name, i, nil, nil, nil, {optimal=false})
        end
      end
    end
  end
end

local display = window.create(term.current(),1,1,term.getSize())
local w,h = display.getSize()
local item_count_w = 5
local item_name_w = w-item_count_w
local function format_item(name,count)
  return ("%-"..item_count_w.."s %-"..item_name_w.."s"):format(count,name)
end
local function set_colors(fg,bg)
  display.setTextColor(fg)
  display.setBackgroundColor(bg)
end

local function text(x,y,t)
  display.setCursorPos(x,y)
  display.write(t)
end

local list = lib.list()


local filter = ""
local craft_name = ""
local item_amount = ""
local sifted_list = {}
local selected_item = 1
local display_item -- prevent the selected item from drifting while directly accessing it
local requesting_craft = false -- set to true to make INFO enter request craft instead

local function apply_sort()
  table.sort(list, function(a,b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)
  if pcall(string.match,"",filter) then
    sifted_list = {}
    for k,v in pairs(list) do
      if v.name:match(filter) or v.displayName:lower():match(filter) or v.displayName:match(filter) then
        table.insert(sifted_list, v)
      end
    end
  end
  selected_item = math.min(selected_item, #sifted_list)
end
apply_sort()
local draw_modes = {
  SEARCH = function ()
    text(1,2,filter)
    text(1,3,format_item("Name","Count"))
    local screen_scroll = math.max(math.min(math.max(1,selected_item-5), #sifted_list-h+4), 1)
    for i=screen_scroll, math.min(screen_scroll+h, #sifted_list) do
      local item = sifted_list[i]
      local y = 4 + i - screen_scroll
      if y > 3 then
        if i == selected_item then
          set_colors(colors.black,colors.white)
        end
        text(1,y,format_item(item.displayName,item.count))
        set_colors(colors.white,colors.black)
      end
    end
    display.setCursorBlink(true)
    display.setCursorPos(filter:len()+1,2)
  end,
  INFO = function ()
    local item = display_item
    text(1,2,("%u x %s"):format(item.count,item.displayName))
    text(1,3,item.name)
    text(1,4,item.nbt)
    text(1,h,("Withdraw: %s"):format(item_amount))
    display.setCursorBlink(true)
    display.setCursorPos(item_amount:len()+11,h)
  end,
  CRAFT = function ()
    text(1,2,craft_name)
    display.setCursorBlink(true)
    display.setCursorPos(craft_name:len()+1,2)
  end
}
local function draw()
  display.setVisible(false)
  display.setCursorBlink(false)
  display.clear()
  set_colors(colors.black, colors.white)
  display.setCursorPos(1,1)
  display.clearLine()
  display.write(mode)
  set_colors(colors.white,colors.black)
  assert(draw_modes[mode], "Missing draw_mode "..mode)()
  display.setVisible(true)
end

local function event_update()
  while true do
    _, list = os.pullEvent("update")
    apply_sort()
    draw()
  end
end

local char_modes = {
  SEARCH = function (ch)
    filter = filter .. ch
    apply_sort()
  end,
  INFO = function (ch)
    if ch >= '0' and ch <= '9' then
      item_amount = item_amount .. ch
    end
  end,
  CRAFT = function (ch)
    craft_name = craft_name .. ch
  end,
}
local function handle_char(ch)
  assert(char_modes[mode], "Missing char_mode "..mode)(ch)
end

local function request_item(item,amount)
  amount = amount or 0
  if amount == 0 then
    requesting_craft = false
    return
  end

  if requesting_craft then
    requesting_craft = false
    lib.requestCraft(item.name,amount)
    mode = "SEARCH"
    return
  end
  amount = math.min(amount, item.count)
  local stacks = math.min(math.ceil(amount / item.maxCount),16)
  local free_slots = {}
  for i = 1, 16 do
    free_slots[i] = true
  end
  refresh_turtle_inventory()
  for i,_ in pairs(turtle_inventory) do
    free_slots[i] = nil
  end
  for i = 1, stacks do
    local slot = next(free_slots)
    if not slot then break end -- not enough space in the turtle to fit all of the items
    busy_slots[slot] = true
    free_slots[slot] = nil
  end
  lib.pushItems(self_name,item.name,amount,nil,item.nbt)
end

local key_modes = {
  SEARCH = function (key)
    if key == keys.backspace then
      filter = filter:sub(1, -2)
      apply_sort()
    elseif key == keys.up then
      selected_item = math.max(selected_item - 1, 1)
    elseif key == keys.down then
      selected_item = math.min(selected_item + 1, #sifted_list)
    elseif key == keys.enter then
      if selected_item > 0 then
        mode = "INFO"
        -- this can easily become outdated if the contents of the storage change
        display_item = sifted_list[selected_item]
        item_amount = tostring(math.min(display_item.maxCount, display_item.count))
      end
    elseif key == keys.tab then
      mode = "CRAFT"
    end
  end,
  INFO = function (key)
    if key == keys.backspace then
      item_amount = item_amount:sub(1, -2)
    elseif key == keys.enter then
      request_item(display_item,tonumber(item_amount or 0))
      mode = "SEARCH"
    end
  end,
  CRAFT = function (key)
    if key == keys.backspace then
      craft_name = craft_name:sub(1, -2)
    elseif key == keys.enter then
      mode = "INFO"
      display_item = {name=craft_name, count = 10000} -- TODO
      requesting_craft = true
    elseif key == keys.tab then
      mode = "SEARCH"
    end
  end
}
local function handle_key(key)
  assert(key_modes[mode], "Missing key_mode "..mode)(key)
end

local function input_handler()
  while true do
    local e = {os.pullEvent()}
    if e[1] == "char" then
      handle_char(e[2])
    elseif e[1] == "key" then
      handle_key(e[2])
    end
    draw()
  end
end

draw()
parallel.waitForAll(lib.subscribe, event_turtle_inventory, event_update, input_handler)