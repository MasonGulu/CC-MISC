---@alias handle table file handle
---@param f handle
---@param i integer
local function write_uint16(f, i)
  f.write(string.pack(">I2", i))
end
---@param f handle
---@param i integer
local function write_uint8(f, i)
  f.write(string.pack("I1", i))
end
---@param f handle
---@param str string
local function write_string(f,str)
  write_uint16(f, str:len())
  f.write(str)
end

local function write_uint16_t(f,t)
  write_uint8(f,#t)
  for k,v in ipairs(t) do
    write_uint16(f,v)
  end
end

---@param f handle
---@return integer
local function read_uint16(f)
  return select(1,string.unpack(">I2",f.read(2)))
end
---@param f handle
---@return integer
local function read_uint8(f)
  return select(1,string.unpack("I1",f.read(1)))
end
---@param f handle
---@return string
local function read_string(f)
  local length = string.unpack(">I2", f.read(2))
  local str = f.read(length)
  return str
end

local function read_uint16_t(f)
  local length = read_uint8(f)
  local t = {}
  for i = 1, length do
    t[i] = read_uint16(f)
  end
  return t
end

local STATES = {
  READY = "READY",
  ERROR = "ERROR",
  BUSY = "BUSY",
  CRAFTING = "CRAFTING",
}

return {
id = "crafting",
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

init = function(loaded, config)
  -- lookup into an ordered list of item names
  local item_lookup = {}
  ---@type table<string,integer>
  local item_name_lookup = {}
  local grid_recipes = {}

  ---@param str string
  ---@param tag any
  ---@return integer
  local function get_or_cache_string(str, tag)
    if not str then
      error("",2)
    end
    if item_name_lookup[str] then
      return item_name_lookup[str]
    end
    local i = #item_lookup + 1
    if tag then
      item_lookup[i] = {str,tag=true}
    else
      item_lookup[i] = {str}
    end
    item_name_lookup[str] = i
    return i
  end
  local function cache_additional(recipe)
    recipe.requires = {}
    for k,v in ipairs(recipe) do
      if recipe.shaped then
        for row,i in ipairs(v) do
          local old = recipe.requires[item_name_lookup[i][1]]
          recipe.requires[item_name_lookup[i][1]] = (old or 0) + 1
        end
      else
        local i = recipe.requires[item_name_lookup[v][1]]
        recipe.requires[item_name_lookup[v][1]] = (i or 0) + 1
      end
    end
  end

  local function save_item_lookup()
    local f = assert(fs.open("recipes/item_lookup.bin", "wb"))
    f.write("ILUT")
    for _,v in ipairs(item_lookup) do
      local item_name = assert(v[1],#item_lookup)
      if v.tag then
        f.write("T")
      else
        f.write("I")
      end
      write_string(f, item_name)
    end
    f.close()
  end
  local function load_item_lookup()
    local f = fs.open("recipes/item_lookup.bin", "rb")
    if not f then
      item_lookup = {}
      return
    end
    assert(f.read(4) == "ILUT", "Invalid item_lookup file")
    local mode = f.read(1)
    while mode do
      local name = read_string(f)
      local item = {name}
      if mode == "I" then
      elseif mode == "T" then
        item.tag = true
      end
      table.insert(item_lookup, item)
      mode = f.read(1)
    end
    f.close()
  end
  local function save_grid_recipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "wb"))
    f.write("GRECIPES")
    for k,v in pairs(grid_recipes) do
      if v.shaped then
        f.write("S")
      else
        f.write("U")
      end
      write_uint8(f, v.produces)
      write_string(f, k)
      if v.shaped then
        local height = #v.recipe
        local width = #v.recipe[1]
        write_uint8(f,width)
        write_uint8(f,height)
        for _,row in ipairs(v.recipe) do
          for _, i in ipairs(row) do
            if type(i) == "number" then
              f.write("S")
              write_uint16(f, i)
            else
              f.write("A")
              write_uint16_t(f,i)
            end
          end
        end
      else
        write_uint8(f,#v.recipe)
        for _,i in ipairs(v.recipe) do
          if type(i) == "number" then
            f.write("S")
            write_uint16(f, i)
          else
            f.write("A")
            write_uint16_t(f,i)
          end
        end
      end
    end
    f.close()
  end
  local function load_grid_recipes()
    local f = assert(fs.open("recipes/grid_recipes.bin", "rb"))
    assert(f.read(8) == "GRECIPES", "Invalid grid recipe file.")
    local shape_indicator = f.read(1)
    while shape_indicator do
      local recipe = {}
      recipe.recipe = {}
      recipe.produces = read_uint8(f)
      local recipe_name = read_string(f)
      if shape_indicator == "S" then
        local width = read_uint8(f)
        local height = read_uint8(f)
        for row = 1, height do
          recipe.recipe[row] = {}
          for column = 1, width do
            local mode = f.read(1)
            if mode == "S" then
              recipe.recipe[row][column] = read_uint16(f)
            elseif mode == "A" then
              recipe.recipe[row][column] = read_uint16_t(f)
            else
              error("Invalid mode")
            end
          end
        end
      elseif shape_indicator == "U" then
        local length = read_uint8(f)
        for i = 1, length do
          local mode = f.read(1)
          if mode == "S" then
            recipe.recipe[i] = read_uint16(f)
          elseif mode == "A" then
            recipe.recipe[i] = read_uint16_t(f)
          else
            error("Invalid mode")
          end
        end
      else
        error("Invalid shape_indicator")
      end
      grid_recipes[recipe_name] = recipe
      cache_additional(recipe)
      shape_indicator = f.read(1)
    end
  end

  local function load_json(json)
    local recipe = {}
    local recipe_name
    if json.type == "minecraft:crafting_shapeless" then
    elseif json.type == "minecraft:crafting_shaped" then
      recipe.shaped = true
    else
      return -- not supported
    end
    recipe_name = json.result.item
    recipe.produces = json.result.count or 1
    if json.type == "minecraft:crafting_shapeless" then
      recipe.recipe = {}
      for k,v in pairs(json.ingredients) do
        local name = v.item or v.tag
        if not (name) then
          local array = {}
          for _, opt in pairs(v) do
            name = opt.item or opt.tag
            table.insert(array, get_or_cache_string(name,v.tag))
          end
          table.insert(recipe.recipe, array)
        else
          table.insert(recipe.recipe, get_or_cache_string(name,v.tag))
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
            table.insert(array, get_or_cache_string(name,v.tag))
          end
          keys[k] = array
        else
          keys[k] = get_or_cache_string(name, v.tag)
        end
      end
      recipe.recipe = {}
      for row, row_string in ipairs(json.pattern) do
        recipe.recipe[row] = {}
        for i = 1, row_string:len() do
          recipe.recipe[row][i] = keys[row_string:sub(i,i)]
        end
      end
    end
    cache_additional(recipe)
    grid_recipes[recipe_name] = recipe
  end

  load_item_lookup()
  load_grid_recipes()

  local crafting_queue = {}

  local attached_turtles = {}

  local modem = assert(peripheral.wrap(config.crafting.modem.value), "Bad modem specified.")
  modem.open(config.crafting.port.value)

  local protocol_handlers = {
    KEEP_ALIVE = function (message)
      attached_turtles[message.source] = attached_turtles[message.source] or {
        name = message.source
      }
      local turtle = attached_turtles[message.source]
      turtle.state = message.state
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
            modem.transmit(modem_message.reply, config.crafting.port.value, response)
          end
        end
      end
    end
  end

  local function keep_alive()
    while true do
      modem.transmit(config.crafting.port.value, config.crafting.port.value, {
        protocol = "KEEP_ALIVE",
        source = "HOST",
        destination = "*",
      })
      sleep(config.crafting.keep_alive.value)
    end
  end

  return {
    start = function()
      parallel.waitForAll(modem_manager, keep_alive)
    end,
    gui = function (frame)
      frame:addLabel():setText("Drag and drop shaped/unshaped recipe JSONs")
      frame:addButton():setText("Save"):onClick(function()
        save_grid_recipes()
        save_item_lookup()
      end):setPosition(2,2):setSize("parent.w-2",1)
      local list = frame:addList():setPosition(2,6):setSize("parent.w-2","parent.h-8")

      --- file upload thread
      frame:addThread():start(function()
        while true do
          local e, transfer = os.pullEvent("file_transfer")
          for _,file in ipairs(transfer.getFiles()) do
            local contents = file.readAll()
            local json = textutils.unserialiseJSON(contents)
            if json then
              load_json(json)
            end
            file.close()
          end
        end
      end)
    end
  }
end
}