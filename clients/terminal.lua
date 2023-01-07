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
          lib.pullItems(true, self_name, i, nil, nil, nil, {optimal=false})
        end
      end
    end
    lib.performTransfer()
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
  display.setCursorPos(math.floor(x),math.floor(y))
  display.write(t)
end

local list = lib.list()
local craftables = lib.listCraftables()

local filter = ""
local craft_filter = ""
local item_amount = ""
local sifted_list = {}
local sifted_craftables = {}
local selected_item = 1
local selected_craft = 1
local display_item -- prevent the selected item from drifting while directly accessing it
local requesting_craft = false -- set to true to make INFO enter request craft instead

local function sort_search()
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
sort_search()
local function filter_craftables()
  table.sort(craftables)
  if pcall(string.match,"",craft_filter) then
    sifted_craftables = {}
    for k,v in pairs(craftables) do
      if v:match(craft_filter) then
        table.insert(sifted_craftables, v)
      end
    end
  end
  selected_craft = math.min(selected_craft, #sifted_craftables)
end
filter_craftables()

local craft_info
local disable_drawing = false

local function change_mode(new_mode)
  if new_mode == "REQUEST" then
    local craft = sifted_craftables[selected_craft]
    if not craft then
      mode = "CRAFT"
      return
    end
    disable_drawing = true
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
        disable_drawing = false
        return
      end
      local num_input = tonumber(input)
      if num_input then
        if num_input > 0 then
          craft_info = lib.requestCraft(craft, tonumber(input))
          break
        end
      end
    end
    disable_drawing = false
  end
  mode = new_mode
end


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
    if item.enchantments then
      text(1,5,"Enchantments")
      for k,v in ipairs(item.enchantments) do
        text(1,5+k,v.displayName or v.name)
      end
    end
    text(1,h,("Withdraw: %s"):format(item_amount))
    display.setCursorBlink(true)
    display.setCursorPos(item_amount:len()+11,h)
  end,
  CRAFT = function ()
    text(1,2,craft_filter)
    text(1,3,"Name")
    local screen_scroll = math.max(math.min(math.max(1,selected_craft-5), #sifted_craftables-h+4), 1)
    for i=screen_scroll, math.min(screen_scroll+h, #sifted_craftables) do
      local name = sifted_craftables[i]
      local y = 4 + i - screen_scroll
      if y > 3 then
        if i == selected_craft then
          set_colors(colors.black,colors.white)
          display.setCursorPos(1,y)
          display.clearLine()
        end
        text(1,y,name)
        set_colors(colors.white,colors.black)
      end
    end
    display.setCursorBlink(true)
    display.setCursorPos(craft_filter:len()+1,2)
  end,
  REQUEST = function ()
    text(1,2,(craft_info.success and "Press y to craft, n to cancel") or "Press n to cancel the craft")
    text(1,3,("Requested %s"):format(sifted_craftables[selected_craft]))
    text(1,4,(craft_info.success and "Success") or "Failure")
    local line = 5
    if not craft_info.success then
      set_colors(colors.red,colors.black)
      text(1,line,"Missing:")
      line = line + 1
      for k,v in pairs(craft_info.missing) do
        text(1,line,("%ux%s"):format(v,k))
        line = line + 1
      end
      set_colors(colors.white,colors.black)
    end
    text(1,line,"To use:")
    line = line + 1
    for k,v in pairs(craft_info.to_use) do
      text(1,line,("%ux%s"):format(v,k))
      line = line + 1
    end
    text(1,line,"To craft:")
    line = line + 1
    for k,v in pairs(craft_info.to_craft) do
      text(1,line,("%ux%s"):format(v,k))
      line = line + 1
    end
  end
}

local function draw()
  if draw_modes[mode] and not disable_drawing then
    display.setVisible(false)
    display.setCursorBlink(false)
    display.clear()
    set_colors(colors.black, colors.white)
    display.setCursorPos(1,1)
    display.clearLine()
    display.write(mode)
    set_colors(colors.white,colors.black)
    draw_modes[mode]()
    display.setVisible(true)
  end
end

local function event_update()
  while true do
    _, list = os.pullEvent("update")
    sort_search()
    draw()
  end
end

local char_modes = {
  SEARCH = function (ch)
    filter = filter .. ch
    sort_search()
  end,
  INFO = function (ch)
    if ch >= '0' and ch <= '9' then
      item_amount = item_amount .. ch
    end
  end,
  CRAFT = function (ch)
    craft_filter = craft_filter .. ch
    filter_craftables()
  end,
  REQUEST = function (ch)
    if craft_info then
      if ch == 'y' and craft_info.success then
        lib.startCraft(craft_info.job_id)
        craft_info = nil
        change_mode("SEARCH")
      elseif ch == 'n' then
        lib.cancelCraft(craft_info.job_id)
        craft_info = nil
        change_mode("SEARCH")
      end
    end
  end
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
    change_mode("SEARCH")
    return
  end
  amount = math.min(amount, item.count)
  local stacks = math.min(math.ceil(amount / item.maxCount),16)
  local free_slots = {}
  for i = 1, 16 do
    free_slots[i] = true
  end
  for i,_ in pairs(turtle_inventory) do
    free_slots[i] = nil
  end
  for i = 1, stacks do
    local slot = next(free_slots)
    if not slot then break end -- not enough space in the turtle to fit all of the items
    busy_slots[slot] = true
    free_slots[slot] = nil
  end
  lib.pushItems(true,self_name,item.name,amount,nil,item.nbt)
  lib.performTransfer()
end

local key_modes = {
  SEARCH = function (key)
    if key == keys.backspace then
      filter = filter:sub(1, -2)
      sort_search()
    elseif key == keys.up then
      selected_item = math.max(selected_item - 1, 1)
    elseif key == keys.down then
      selected_item = math.min(selected_item + 1, #sifted_list)
    elseif key == keys.enter then
      if selected_item > 0 then
        change_mode("INFO")
        -- this can easily become outdated if the contents of the storage change
        display_item = sifted_list[selected_item]
        item_amount = tostring(math.min(display_item.maxCount, display_item.count))
      end
    elseif key == keys.tab then
      change_mode("CRAFT")
    end
  end,
  INFO = function (key)
    if key == keys.backspace then
      item_amount = item_amount:sub(1, -2)
    elseif key == keys.enter then
      request_item(display_item,tonumber(item_amount or 0))
      change_mode("SEARCH")
    end
  end,
  CRAFT = function (key)
    if key == keys.backspace then
      craft_filter = craft_filter:sub(1, -2)
      filter_craftables()
    elseif key == keys.up then
      selected_craft = math.max(selected_craft - 1, 1)
    elseif key == keys.down then
      selected_craft = math.min(selected_craft + 1, #sifted_craftables)
    elseif key == keys.enter then
      if selected_craft > 0 then
        display_item = {name=sifted_craftables[selected_craft], count = 10000} -- TODO
        requesting_craft = true
        change_mode("REQUEST")
        -- this can easily become outdated if the contents of the storage change
      end
    elseif key == keys.tab then
      change_mode("SEARCH")
    end
  end,
  REQUEST = function (key)
    
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

-- support your
local small
-- business casino

-- << Across the bridge <<