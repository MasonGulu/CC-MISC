periphemu.create("left", "minecraft:chest")
local c = peripheral.wrap("left")
c.setItem(1, {name="minecraft:stone", count=10})
periphemu.create("right", "minecraft:chest")
local c2 = peripheral.wrap("right")

-- fs.mountInventory("left", {"left"})
-- fs.mountInventory("right", {"right"})