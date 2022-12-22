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
        print("update")
        -- an item was placed into this slot, empty the slot
        lib.pullItems(self_name, i, nil, nil, nil, {optimal=false})
      end
    end
  end
end

event_turtle_inventory()