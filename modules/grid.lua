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
  keepAlive = {
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
  local gridRecipes = {}

  ---This node represents a grid crafting recipe
  ---@class GridNode : CraftingNode
  ---@field type "CG"
  ---@field toCraft integer
  ---@field plan table<integer,{max:integer,name:string,count:integer}>

  local crafting = loaded.crafting.interface.recipeInterface

  ---Cache information about a GridRecipe that can be inferred from stored data
  ---@param recipe GridRecipe
  local function cacheAdditional(recipe)
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
  local function saveGridRecipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "wb"))
    f.write("GRECIPES")
    for k,v in pairs(gridRecipes) do
      if v.shaped then
        f.write("S")
      else
        f.write("U")
      end
      common.writeUInt8(f, v.produces)
      common.writeString(f, k)
      if v.shaped then
        local height = v.height
        local width = v.width
        assert(width and height, "Shaped recipe does not have width/height")
        common.writeUInt8(f,width)
        common.writeUInt8(f,height)
        assert(width*height == #v.recipe, "malformed recipe.")
      else
        common.writeUInt8(f,#v.recipe)
      end
      for _,i in ipairs(v.recipe) do
        if type(i) == "number" then
          f.write("S")
          common.writeUInt16(f, i)
        elseif type(i) == "table" then
          f.write("A")
          common.writeUInt16T(f,i)
        else
          error("Invalid recipe contents")
        end
      end
    end
    f.close()
  end

  local function updateCraftableList()
    local list = {}
    for k,v in pairs(gridRecipes) do
      table.insert(list, k)
    end
    crafting.addCraftableList("grid", list)
  end

  ---Add a grid recipe manually
  ---@param name string
  ---@param produces integer
  ---@param recipe string[] table of ITEM NAMES, this does NOT support tags. Shaped recipes are assumed 3x3. Nil is assumed empty space.
  ---@param shaped boolean
  local function addGridRecipe(name, produces, recipe, shaped)
    common.enforceType(name,1,"string")
    common.enforceType(produces,2,"integer")
    common.enforceType(recipe,3,"string[]")
    common.enforceType(shaped,4,"boolean")
    local gridRecipe = {}
    gridRecipe.shaped = shaped
    gridRecipe.produces = produces
    gridRecipe.recipe = {}
    if shaped then
      for i = 1, 9 do
        local itemName = recipe[i]
        gridRecipe.recipe[i] = (itemName and crafting.getOrCacheString(itemName)) or 0
      end
      gridRecipe.width = 3
      gridRecipe.height = 3
    else
      for k,v in ipairs(recipe) do
        table.insert(gridRecipe.recipe, crafting.getOrCacheString(v))
      end
    end
    gridRecipes[name] = gridRecipe
    cacheAdditional(gridRecipe)
    saveGridRecipes()
    updateCraftableList()
  end

  ---Load the grid recipes from a file
  local function loadGridRecipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "rb"))
    assert(f.read(8) == "GRECIPES", "Invalid grid recipe file.")
    local shapeIndicator = f.read(1)
    while shapeIndicator do
      local recipe = {}
      recipe.recipe = {}
      recipe.produces = common.readUInt8(f)
      local recipeName = common.readString(f)
      local length
      if shapeIndicator == "S" then
        recipe.shaped = true
        recipe.width = common.readUInt8(f)
        recipe.height = common.readUInt8(f)
      elseif shapeIndicator == "U" then
        length = common.readUInt8(f)
      else
        error("Invalid shape_indicator")
      end
      for i = 1, (length or recipe.width*recipe.height) do
        local mode = f.read(1)
        if mode == "S" then
          recipe.recipe[i] = common.readUInt16(f)
        elseif mode == "A" then
          recipe.recipe[i] = common.readUInt16T(f)
        else
          error("Invalid mode")
        end
      end
      gridRecipes[recipeName] = recipe
      recipe.name = recipeName
      cacheAdditional(recipe)
      shapeIndicator = f.read(1)
    end
    updateCraftableList()
  end

  loadGridRecipes()

  ---@class Turtle
  ---@field name string
  ---@field task nil|GridNode
  ---@field state "READY" | "ERROR" | "BUSY" | "CRAFTING" | "DONE"


  local attachedTurtles = {}
  local modem = assert(peripheral.wrap(config.grid.modem.value), "Bad modem specified.")
  modem.open(config.grid.port.value)

  local function emptyTurtle(turtle)
    for _,slot in pairs(turtle.itemSlots) do
      loaded.inventory.interface.pullItems(true, turtle.name, slot)
    end
  end

  local function turtleCraftingDone(turtle)
    if turtle.task then
      crafting.changeNodeState(turtle.task, "DONE")
      crafting.deleteNodeChildren(turtle.task)
      crafting.deleteTask(turtle.task)
      turtle.task = nil
    end
    turtle.state = "BUSY"
  end

  local protocolHandlers = {
    KEEP_ALIVE = function (message)
      attachedTurtles[message.source] = attachedTurtles[message.source] or {
        name = message.source
      }
      local turtle = attachedTurtles[message.source]
      turtle.state = message.state
      turtle.itemSlots = message.itemSlots
    end,
    CRAFTING_DONE = function (message)
      local turtle = attachedTurtles[message.source]
      turtle.itemSlots = message.itemSlots
      emptyTurtle(turtle)
      turtleCraftingDone(turtle)
    end,
    EMPTY = function (message)
      local turtle = attachedTurtles[message.source]
      turtle.itemSlots = message.itemSlots
      emptyTurtle(turtle)
    end,
    NEW_RECIPE = function (message)
      addGridRecipe(message.name,message.amount,message.recipe,message.shaped)
    end
  }

  local function validateMessage(message)
    local valid = type(message) == "table" and message.protocol ~= nil
    valid = valid and message.destination == "HOST" and message.source ~= nil
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

  local function sendMessage(message, destination, protocol)
    message.source = "HOST"
    message.destination = destination
    message.protocol = protocol
    modem.transmit(config.grid.port.value, config.grid.port.value, message)
  end

  local function modemMessageHandler()
    while true do
      local modemMessage = getModemMessage(validateMessage)
      if modemMessage then
        local message = modemMessage.message
        if protocolHandlers[message.protocol] then
          local response = protocolHandlers[message.protocol](message)
          if response then
            response.destination = response.destination or message.source
            response.source = "HOST"
            modem.transmit(config.grid.port.value, config.grid.port.value, response)
          end
        end
      end
    end
  end

  local function keepAlive()
    while true do
      modem.transmit(config.grid.port.value, config.grid.port.value, {
        protocol = "KEEP_ALIVE",
        source = "HOST",
        destination = "*",
      })
      os.sleep(config.grid.keepAlive.value)
    end
  end

  ---comment
  ---@param node GridRecipe
  ---@param name string
  ---@param count integer
  ---@param requestChain table Do not modify, just pass through to calls to craft
  ---@return boolean
  local function craftType(node,name,count,requestChain)
    -- attempt to craft this
    local recipe = gridRecipes[name]
    if not recipe then
      return false
    end
    node.type = "grid"
    -- find out how many times we need to craft this recipe
    local toCraft = math.ceil(count / recipe.produces)
    -- this is the minimum amount we'd need to craft to produce enough of the requested item
    -- now we need to find the smallest stack-size of the ingredients
    ---@type table<integer,{name: string, max: integer, count: integer}>
    local plan = {}
    for k,v in pairs(recipe.recipe) do
      if v ~= 0 then
        local success, itemName = crafting.getBestItem(v)
        plan[k] = {}
        if success then
          plan[k].name = itemName
          -- We can only craft as many items as the smallest stack size allows us to
          plan[k].max = crafting.getStackSize(plan[k].name)
          toCraft = math.min(toCraft, plan[k].max)
        else
          plan[k].tag = itemName
        end
      end
    end
    node.plan = plan
    node.toCraft = toCraft
    node.children = {}
    node.name = name
    for k,v in pairs(plan) do
      v.count = toCraft
      if v.tag then
        -- this is a tag we could not resolve, so make a placeholder node
        table.insert(node.children, crafting.createMissingNode(v.tag, v.count, node.jobId))
      else
        crafting.mergeInto(crafting.craft(v.name, v.count, node.jobId, nil, requestChain), node.children)
      end
    end
    for k,v in pairs(node.children) do
      v.parent = node
    end
    node.count = toCraft * recipe.produces
    return true
  end
  crafting.addCraftType("grid", craftType)

  local function readyHandler(node)
      -- check if there is a turtle available to craft this recipe
      local availableTurtle
      for k,v in pairs(attachedTurtles) do
        if v.state == "READY" then
          availableTurtle = v
          break
        end
      end
      if availableTurtle then
        crafting.changeNodeState(node, "CRAFTING")
        sendMessage({task = node}, availableTurtle.name, "CRAFT")
        availableTurtle.task = node
        node.turtle = availableTurtle.name
        local transfers = {}
        for slot,v in pairs(node.plan) do
          local x = (slot-1) % (node.width or 3) + 1
          local y = math.floor((slot-1) / (node.height or 3))
          local turtleSlot = y * 4 + x
          table.insert(transfers, function() crafting.pushItems(availableTurtle.name, v.name, v.count, turtleSlot) end)
        end
        availableTurtle.state = "BUSY"
        parallel.waitForAll(table.unpack(transfers))
      end
  end
  crafting.addReadyHandler("grid", readyHandler)

  local function jsonTypeHandler(json)
    local recipe = {}
    local recipeName
    recipe.shaped = json.type == "minecraft:crafting_shaped"
    recipeName = json.result.item
    recipe.produces = json.result.count or 1
    if json.type == "minecraft:crafting_shapeless" then
      recipe.recipe = {}
      for k,v in pairs(json.ingredients) do
        local name = v.item or v.tag
        if not (name) then
          local array = {}
          for _, opt in pairs(v) do
            name = opt.item or opt.tag
            table.insert(array, crafting.getOrCacheString(name,v.tag))
          end
          table.insert(recipe.recipe, array)
        else
          table.insert(recipe.recipe, crafting.getOrCacheString(name,v.tag))
        end
      end
    elseif json.type == "minecraft:crafting_shaped" then
      ---@type table<string,integer|integer[]>
      local keys = {[" "]=0}
      for k,v in pairs(json.key) do
        local name = v.item or v.tag
        if not (name) then
          local array = {}
          for _, opt in pairs(v) do
            name = opt.item or opt.tag
            table.insert(array, crafting.getOrCacheString(name,v.tag))
          end
          keys[k] = array
        else
          keys[k] = crafting.getOrCacheString(name, v.tag)
        end
      end
      recipe.recipe = {}
      recipe.width = json.pattern[1]:len()
      recipe.height = #json.pattern
      for row, rowString in ipairs(json.pattern) do
        for i = 1, rowString:len() do
          table.insert(recipe.recipe, keys[rowString:sub(i,i)])
        end
      end
    end
    cacheAdditional(recipe)
    gridRecipes[recipeName] = recipe
  end
  crafting.addJsonTypeHandler("minecraft:crafting_shaped", jsonTypeHandler)
  crafting.addJsonTypeHandler("minecraft:crafting_shapeless", jsonTypeHandler)

  local function craftingHandler(node)
    -- -- Check if the turtle's state is DONE
    -- local turtle = attached_turtles[node.turtle]
    -- if turtle.state == "DONE" then
    --   turtle_crafting_done(turtle)
    -- end
  end
  crafting.addCraftingHandler("grid", craftingHandler)
  return {
    start = function()
      -- loaded.crafting.interface.request_craft("minecraft:piston", 128)
      parallel.waitForAny(modemMessageHandler, keepAlive)
    end,
    addGridRecipe = addGridRecipe
  }
end
}