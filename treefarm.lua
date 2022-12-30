while true do
  assert(turtle.getFuelLevel() > 0, "No fuel")
  local block, info = turtle.inspect()
  if block and info.tags and info.tags["minecraft:logs"] then
    -- wood
    turtle.dig()
    turtle.digUp()
    turtle.up()
  elseif block and info.tags and info.tags["minecraft:sapling"] then
    -- do nothing
  else
    local under, uinfo = turtle.inspectDown()
    if under and uinfo.name == "minecraft:wall_torch" then
      turtle.select(1)
      turtle.place() -- attempt to place sapling
      for i = 2, 16 do
        turtle.select(i)
        turtle.dropDown()
      end
    elseif not under then
      turtle.down()
    end
  end
  sleep(1)
end
