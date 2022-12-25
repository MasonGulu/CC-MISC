--- Grid crafting recipe handler
local common = require("common")
return {
id = "grid",
version = "INDEV",
config = {
  modem = {
    type = "string",
    description = "Modem to host crafting turtles on. This needs to be the same one the turtles AND inventory are on.",
  },
  port = {
    type = "number",
    description = "Port to host crafting turtles on.",
    default = 121
  },
  keep_alive = {
    type = "number",
    description = "Keep alive ping frequency",
    default = 8,
  }
},
init = function(loaded,config)
  ---@alias RecipeEntry ItemIndex|ItemIndex[]

  ---@class GridRecipe
  ---@field produces integer
  ---@field recipe RecipeEntry[]
  ---@field width integer|nil
  ---@field height integer|nil
  ---@field shaped boolean|nil
  ---@field name string
  ---@field requires table<ItemIndex,integer> 

  ---@type table<string,GridRecipe>
  local grid_recipes = {}

  ---This node represents a grid crafting recipe
  ---@class GridNode : CraftingNode
  ---@field type "CG"
  ---@field to_craft integer
  ---@field plan table<integer,{max:integer,name:string,count:integer}>

  local crafting = loaded.crafting.interface.recipeInterface

  ---Cache information about a GridRecipe that can be inferred from stored data
  ---@param recipe GridRecipe
  local function cache_additional(recipe)
    recipe.requires = {}
    for k,v in ipairs(recipe) do
      if recipe.shaped then
        for row,i in ipairs(v) do
          local old = recipe.requires[i]
          recipe.requires[i] = (old or 0) + 1
        end
      else
        local i = recipe.requires[v]
        recipe.requires[v] = (i or 0) + 1
      end
    end
  end

  ---Save the grid recipes to a file
  local function save_grid_recipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "wb"))
    f.write("GRECIPES")
    for k,v in pairs(grid_recipes) do
      if v.shaped then
        f.write("S")
      else
        f.write("U")
      end
      common.write_uint8(f, v.produces)
      common.write_string(f, k)
      if v.shaped then
        local height = v.height
        local width = v.width
        assert(width and height, "Shaped recipe does not have width/height")
        common.write_uint8(f,width)
        common.write_uint8(f,height)
        assert(width*height == #v.recipe, "malformed recipe.")
      else
        common.write_uint8(f,#v.recipe)
      end
      for _,i in ipairs(v.recipe) do
        if type(i) == "number" then
          f.write("S")
          common.write_uint16(f, i)
        elseif type(i) == "table" then
          f.write("A")
          common.write_uint16_t(f,i)
        else
          error("Invalid recipe contents")
        end
      end
    end
    f.close()
  end

  ---Load the grid recipes from a file
  local function load_grid_recipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "rb"))
    assert(f.read(8) == "GRECIPES", "Invalid grid recipe file.")
    local shape_indicator = f.read(1)
    while shape_indicator do
      local recipe = {}
      recipe.recipe = {}
      recipe.produces = common.read_uint8(f)
      local recipe_name = common.read_string(f)
      local length
      if shape_indicator == "S" then
        recipe.shaped = true
        recipe.width = common.read_uint8(f)
        recipe.height = common.read_uint8(f)
      elseif shape_indicator == "U" then
        length = common.read_uint8(f)
      else
        error("Invalid shape_indicator")
      end
      for i = 1, (length or recipe.width*recipe.height) do
        local mode = f.read(1)
        if mode == "S" then
          recipe.recipe[i] = common.read_uint16(f)
        elseif mode == "A" then
          recipe.recipe[i] = common.read_uint16_t(f)
        else
          error("Invalid mode")
        end
      end
      grid_recipes[recipe_name] = recipe
      recipe.name = recipe_name
      cache_additional(recipe)
      shape_indicator = f.read(1)
    end
  end

  load_grid_recipes()

  ---@class Turtle
  ---@field name string
  ---@field task nil|GridNode
  ---@field state "READY" | "ERROR" | "BUSY" | "CRAFTING" | "DONE"


  local attached_turtles = {}
  local modem = assert(peripheral.wrap(config.grid.modem.value), "Bad modem specified.")
  modem.open(config.grid.port.value)

  local function empty_turtle(turtle)
    for _,slot in pairs(turtle.item_slots) do
      loaded.inventory.interface.pullItems(true, turtle.name, slot)
    end
  end

  local function turtle_crafting_done(turtle)
    if turtle.task then
      crafting.change_node_state(turtle.task, "DONE")
      crafting.update_node_state(turtle.task)
      turtle.task = nil
    end
    turtle.state = "BUSY"
  end

  local protocol_handlers = {
    KEEP_ALIVE = function (message)
      attached_turtles[message.source] = attached_turtles[message.source] or {
        name = message.source
      }
      local turtle = attached_turtles[message.source]
      turtle.state = message.state
      turtle.item_slots = message.item_slots
    end,
    CRAFTING_DONE = function (message)
      local turtle = attached_turtles[message.source]
      turtle.item_slots = message.item_slots
      empty_turtle(turtle)
      turtle_crafting_done(turtle)
    end,
    EMPTY = function (message)
      local turtle = attached_turtles[message.source]
      turtle.item_slots = message.item_slots
      empty_turtle(turtle)
    end
  }

  local function validate_message(message)
    local valid = type(message) == "table" and message.protocol ~= nil
    valid = valid and message.destination == "HOST" and message.source ~= nil
    return valid
  end

  local function get_modem_message(filter, timeout)
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

  local function send_message(message, destination, protocol)
    message.source = "HOST"
    message.destination = destination
    message.protocol = protocol
    modem.transmit(config.grid.port.value, config.grid.port.value, message)
  end

  local function modem_manager()
    while true do
      local modem_message = get_modem_message(validate_message)
      if modem_message then
        local message = modem_message.message
        if protocol_handlers[message.protocol] then
          local response = protocol_handlers[message.protocol](message)
          if response then
            response.destination = response.destination or message.source
            response.source = "HOST"
            modem.transmit(config.grid.port.value, config.grid.port.value, response)
          end
        end
      end
    end
  end

  local function keep_alive()
    while true do
      modem.transmit(config.grid.port.value, config.grid.port.value, {
        protocol = "KEEP_ALIVE",
        source = "HOST",
        destination = "*",
      })
      os.sleep(config.grid.keep_alive.value)
    end
  end

  ---comment
  ---@param node GridRecipe
  ---@param name string
  ---@param job_id string
  ---@param count integer
  ---@param request_chain table Do not modify, just pass through to calls to _request_craft
  ---@return boolean
  local function request_craft_type(node,name,job_id,count,request_chain)
    -- attempt to craft this
    local recipe = grid_recipes[name]
    if not recipe then
      return false
    end
    node.type = "CG"
    -- find out how many times we need to craft this recipe
    local to_craft = math.ceil(count / recipe.produces)
    -- this is the minimum amount we'd need to craft to produce enough of the requested item
    -- now we need to find the smallest stack-size of the ingredients
    ---@type table<integer,{name: string, max: integer, count: integer}>
    local plan = {}
    for k,v in pairs(recipe.recipe) do
      if v ~= 0 then
        plan[k] = {name = crafting.get_best_item(v)}
        plan[k].max = crafting.get_stack_size(plan[k].name)
        to_craft = math.min(to_craft, plan[k].max)
        -- We can only craft as many items as the smallest stack size allows us to
      end
    end
    node.plan = plan
    node.to_craft = to_craft
    node.children = {}
    for k,v in pairs(plan) do
      v.count = to_craft
      crafting.merge_into(crafting._request_craft(v.name, v.count, job_id, nil, request_chain), node.children)
    end
    for k,v in pairs(node.children) do
      v.parent = node
    end
    node.count = to_craft * recipe.produces
    return true
  end
  crafting.add_request_craft_type("GRID", request_craft_type)

  local function ready_handler(node)
      -- check if there is a turtle available to craft this recipe
      local available_turtle
      for k,v in pairs(attached_turtles) do
        if v.state == "READY" then
          available_turtle = v
          break
        end
      end
      if available_turtle then
        crafting.change_node_state(node, "CRAFTING")
        send_message({task = node}, available_turtle.name, "CRAFT")
        available_turtle.task = node
        node.turtle = available_turtle.name
        local transfers = {}
        for slot,v in pairs(node.plan) do
          local x = (slot-1) % (node.width or 3) + 1
          local y = math.floor((slot-1) / (node.height or 3))
          local turtle_slot = y * 4 + x
          table.insert(transfers, function() crafting.push_items(available_turtle.name, v.name, v.count, turtle_slot) end)
        end
        available_turtle.state = "BUSY"
        parallel.waitForAll(table.unpack(transfers))
      end
  end
  crafting.add_ready_handler("CG", ready_handler)

  local function crafting_handler(node)
    -- -- Check if the turtle's state is DONE
    -- local turtle = attached_turtles[node.turtle]
    -- if turtle.state == "DONE" then
    --   turtle_crafting_done(turtle)
    -- end
  end
  crafting.add_crafting_handler("CG", crafting_handler)
  return {
    start = function()
      loaded.crafting.interface.request_craft("minecraft:detector_rail", 128)
      parallel.waitForAny(modem_manager, keep_alive)
    end
  }
end
}