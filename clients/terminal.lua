-- storage terminal turtle for the system
local modem = "back"
local turtle_inventory = {}
local lib = require("rednet_lib")
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

rednet.open(modem)
lib.connect()
local self_name = peripheral.call(modem, "getNameLocal")

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
        -- an item was placed into this slot, empty the slot
        lib.pullItems(self_name, i, nil, nil, nil, {optimal=false})
      end
    end
  end
end

local w,h = term.getSize()
local item_count_w = 5
local item_name_w = w-item_count_w
local function format_item(name,count)
  return ("%-"..item_count_w.."s %-"..item_name_w.."s"):format(count,name)
end

local list = lib.list()

local function apply_sort()
  table.sort(list, function(a,b)
    return a.count > b.count
  end)
end
apply_sort()
local function draw()
  term.clear()
  term.setCursorPos(1,2)
  term.write(format_item("Name","Count"))
  for i,item in ipairs(list) do
    term.setCursorPos(1,3+i)
    term.write(format_item(item.displayName,item.count))
  end
end

local function event_update()
  while true do
    _, list = os.pullEvent("update")
    error("Update")
    apply_sort()
    draw()
  end
end

draw()
parallel.waitForAll(lib.subscribe, event_turtle_inventory, event_update)