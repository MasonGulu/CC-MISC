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
  ---@class ItemInfo
  ---@field [1] string
  ---@field tag boolean|nil

  ---@alias ItemIndex integer

  ---@type ItemInfo[]
  -- lookup into an ordered list of item names
  local item_lookup = {}
  ---@type table<string,ItemIndex> lookup from name -> item_lookup index
  local item_name_lookup = {}

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

  ---@param str string
  ---@param tag boolean|nil
  ---@return ItemIndex
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
    for k,v in pairs(item_lookup) do
      item_name_lookup[v[1]] = k
    end
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
        local height = v.height
        local width = v.width
        write_uint8(f,width)
        write_uint8(f,height)
        assert(width*height == #v.recipe, "malformed recipe.")
      else
        write_uint8(f,#v.recipe)
      end
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
      local length
      if shape_indicator == "S" then
        recipe.shaped = true
        recipe.width = read_uint8(f)
        recipe.height = read_uint8(f)
      elseif shape_indicator == "U" then
        length = read_uint8(f)
      else
        error("Invalid shape_indicator")
      end
      for i = 1, (length or recipe.width*recipe.height) do
        local mode = f.read(1)
        if mode == "S" then
          recipe.recipe[i] = read_uint16(f)
        elseif mode == "A" then
          recipe.recipe[i] = read_uint16_t(f)
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
      recipe.width = json.pattern[1]:len()
      recipe.height = #json.pattern
      for row, row_string in ipairs(json.pattern) do
        for i = 1, row_string:len() do
          table.insert(recipe.recipe, keys[row_string:sub(i,i)])
        end
      end
    end
    cache_additional(recipe)
    grid_recipes[recipe_name] = recipe
  end

  load_item_lookup()
  load_grid_recipes()

  ---@alias taskID string uuid foriegn key

  ---@type CraftingNode[] tasks that have unmet dependencies
  local waiting_queue = {}
  ---@type CraftingNode[] tasks that have all dependencies met
  local ready_queue = {}
  ---@type CraftingNode[] tasks that are in progress
  local crafting_queue = {}

  ---@type table<string,CraftingNode> tasks that have been completed, but are still relavant
  local done_lookup = {}

  local attached_turtles = {}

  local update_node_state, change_node_state, delete_task
  local modem = assert(peripheral.wrap(config.crafting.modem.value), "Bad modem specified.")
  modem.open(config.crafting.port.value)

  local protocol_handlers = {
    KEEP_ALIVE = function (message)
      attached_turtles[message.source] = attached_turtles[message.source] or {
        name = message.source
      }
      local turtle = attached_turtles[message.source]
      turtle.state = message.state
    end,
    CRAFTING_DONE = function (message)
      for _,slot in pairs(message.item_slots) do
        loaded.inventory.interface.pullItems(true, message.source, slot)
      end
      local turtle = attached_turtles[message.source]
      change_node_state(turtle.task, "DONE")
      update_node_state(turtle.task)
      turtle.task = nil
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
    modem.transmit(config.crafting.port.value, config.crafting.port.value, message)
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
            modem.transmit(config.crafting.port.value, config.crafting.port.value, response)
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

  ---@alias NodeType string | "ITEM" | "CG" | "ROOT"
  --- ITEM - this node represents a quantity of items from the network
  --- CG - this node represents a grid crafting task
  --- ROOT - this node represents the root of a crafting task

  ---@alias NodeState string | "WAITING" | "READY" | "CRAFTING" | "DONE"

  ---@class CraftingNode
  ---@field children CraftingNode[]|nil
  ---@field parent CraftingNode|nil
  ---@field type NodeType
  ---@field name string
  ---@field count integer amount of this item to produce
  ---@field task_id string
  ---@field job_id string
  ---@field state NodeState
  ---@field priority integer
  ---@field to_craft integer|nil type=="CG"
  ---@field plan table|nil type=="CG"

  ---@type table<string,integer> item name -> count reserved
  local reserved_items = {}

  local function get_count(name)
    return loaded.inventory.interface.getCount(name) - (reserved_items[name] or 0)
  end

  ---@param name string
  ---@param amount integer
  local function allocate_items(name, amount)
    reserved_items[name] = (reserved_items[name] or 0) + amount
    return amount
  end

  local function deallocate_items(name, amount)
    reserved_items[name] = reserved_items[name] - amount
    assert(reserved_items[name] >= 0, "We have negative items reserved?")
    return amount
  end

  ---Convert a string LUT id into a specific item name, favoring items we have
  ---@param id any
  local function get_name(id)
    if type(id) == "number" then
      local str, tag = item_lookup[id][1], item_lookup[id].tag
      if tag then
        error("TODO")
      else
        return str
      end
    end
  end

  local cached_stack_sizes = {} -- TODO
  ---@param name string
  local function get_stack_size(name)
    return 64 -- TODO
  end

  local function id()
    return os.epoch("utc")..math.random(1,100000)..string.char(math.random(65,90))
  end

  ---Select the best item from a tag
  ---@param tag string
  ---@return string name
  local function select_best_from_tag(tag)
    error("Not yet implemented")
  end

  ---Select the best item from an index
  ---@param index integer
  ---@return string name
  local function select_best_from_index(index)
    local item_info = assert(item_lookup[index], "Invalid item index")
    if item_info.tag then
      return select_best_from_tag(item_info[1])
    end
    return item_info[1]
  end

  ---Select the best item from a list of ItemIndex
  ---@param list ItemIndex[]
  ---@return string name
  local function select_best_from_list(list)
    return item_lookup[list[1]][1]
  end

  ---Select the best item
  ---@param a any
  ---@return string name
  local function get_best_item(a)
    if type(a) == "table" then
      return select_best_from_list(a)
    elseif type(a) == "number" then
      return select_best_from_index(a)
    end
    error("hah not any")
  end

  local function merge_into(from, to)
    for k,v in pairs(from) do
      table.insert(to,v)
    end
  end

  

  ---@type table<string,CraftingNode>
  local task_lookup = {}

  ---@type table<string,CraftingNode[]>
  local job_lookup = {}

  local function shallow_clone(t)
    local nt = {}
    for k,v in pairs(t) do
      nt[k] = v
    end
    return nt
  end


  local _request_craft
  local _request_craft_types = {
    grid = function(node,name,job_id,remaining)
      -- attempt to craft this
      local recipe = grid_recipes[name]
      if not recipe then
        return false
      end
      node.type = "CG"
      -- find out how many times we need to craft this recipe
      local to_craft = math.ceil(remaining / recipe.produces)
      -- this is the minimum amount we'd need to craft to produce enough of the requested item
      -- now we need to find the smallest stack-size of the ingredients
      ---@type table<integer,{name: string, max: integer, count: integer}>
      local plan = {}
      for k,v in pairs(recipe.recipe) do
        if v ~= 0 then
          plan[k] = {name = get_best_item(v)}
          plan[k].max = get_stack_size(plan[k].name)
          to_craft = math.min(to_craft, plan[k].max)
          -- We can only craft as many items as the smallest stack size allows us to
        end
      end
      node.plan = plan
      node.to_craft = to_craft
      node.children = {}
      for k,v in pairs(plan) do
        v.count = to_craft
        print(k,v.name,"plan?")
        merge_into(_request_craft(v.name, v.count, job_id), node.children)
      end
      for k,v in pairs(node.children) do
        v.parent = node
      end
      node.count = to_craft * recipe.produces
      return true
    end
  }

  ---@param name string item name
  ---@param count integer
  ---@param job_id string
  ---@param force boolean|nil
  ---@return CraftingNode[] leaves ITEM|CG node
  function _request_craft(name, count, job_id, force)
    ---@type CraftingNode[]
    local nodes = {}
    local remaining = count
    while remaining > 0 do
      ---@type CraftingNode
      local node = {
        name = name,
        task_id = id(),
        job_id = job_id
      }
      task_lookup[node.task_id] = node
      table.insert(job_lookup[job_id], node)
      -- First check if we have any of this
      local available = get_count(name)
      if available > 0 and not force then
        -- we do, so allocate it
        print("allocating", available)
        local allocate_amount = allocate_items(name, math.min(available, remaining))
        node.type = "ITEM"
        node.count = allocate_amount
        remaining = remaining - allocate_amount
      else
        print("crafting?")
        local success = false
        for k,v in pairs(_request_craft_types) do
          print("iterating")
          success = v(node, name, job_id, remaining)
          print(success)
          if success then
            break
          end
        end
        if not success then
          error(("No recipe found for %s"):format(name))
        end
        remaining = remaining - node.count
      end
      table.insert(nodes, node)
    end
    return nodes
  end

  ---Run the given function an all nodes of the given tree
  ---@param root CraftingNode root
  ---@param func fun(node: CraftingNode)
  local function run_on_all(root, func)
    func(root)
    if root.children then
      for _,v in pairs(root.children) do
        run_on_all(v, func)
      end
    end
  end

  local function remove_from_array(arr, val)
    for i,v in ipairs(arr) do
      if v == val then
        table.remove(arr, i)
      end
    end
  end

  function delete_task(task)
    if task.type == "ITEM" then
      deallocate_items(task.name, task.count)
    end
    assert(task.state == "DONE", "Attempt to delete not done task.")
    done_lookup[task.task_id] = nil
    assert(task.children == nil, "Attempt to delete task with children.")
  end

  ---@param node CraftingNode
  ---@param new_state NodeState
  function change_node_state(node, new_state)
    if node.state == "WAITING" then
      remove_from_array(waiting_queue, node)
    elseif node.state == "READY" then
      remove_from_array(ready_queue, node)
    elseif node.state == "CRAFTING" then
      remove_from_array(crafting_queue, node)
    elseif node.state == "DONE" then
      done_lookup[node.task_id] = nil
    end
    node.state = new_state
    if node.state == "WAITING" then
      table.insert(waiting_queue, node)
    elseif node.state == "READY" then
      table.insert(ready_queue, node)
    elseif node.state == "CRAFTING" then
      table.insert(crafting_queue, node)
    elseif node.state == "DONE" then
      done_lookup[node.task_id] = node
    end
  end

  ---@type table<string,fun(node: CraftingNode)> Process an item in the READY state
  local ready_handlers = {
    CG = function(node)
      -- check if there is a turtle available to craft this recipe
      print("Ready handler called")
      local available_turtle
      for k,v in pairs(attached_turtles) do
        if v.state == "READY" then
          available_turtle = v
          break
        end
      end
      if available_turtle then
        change_node_state(node, "CRAFTING")
        send_message({task = node}, available_turtle.name, "CRAFT")
        available_turtle.task = node
        node.turtle = available_turtle
        print("Moving items")
        for slot,v in pairs(node.plan) do
          local x = (slot-1) % (node.width or 3) + 1
          local y = math.floor((slot-1) / (node.height or 3))
          local turtle_slot = y * 4 + x
          loaded.inventory.interface.pushItems(true, available_turtle.name, v.name, v.count, turtle_slot, nil, {optimal=false})
        end
      end
    end
  }

  ---@type table<string,fun(node: CraftingNode)> Process an item that is in the CRAFTING state
  local crafting_handlers = {
    CG = function(node)
      -- Do nothing.
    end
  }


  ---@param node CraftingNode
  function update_node_state(node)
    if not node.state then
      -- This is an uninitialized node
      -- leaf -> set state to READY
      -- otherwise -> set state to WAITING
      if node.children then
        change_node_state(node, "WAITING")
      else
        change_node_state(node, "DONE")
      end
      return
    end
    -- this is a node that has been updated before
    if node.state == "WAITING" then
      print("waiting")
      if node.children then
        -- this has children it depends upon
        local all_children_done = true
        for _,child in pairs(node.children) do
          all_children_done = child.state == "DONE"
          if not all_children_done then
            break
          end
        end
        if all_children_done then
          -- this is ready to be crafted
          for _,child in pairs(node.children) do
            delete_task(child)
          end
          node.children = nil
          remove_from_array(waiting_queue, node)
          if node.type == "ROOT" then
            -- This task is the root of a job
            -- TODO some notification that the whole job is done!
            node.state = "DONE"
            error("Job done!")
          end
          change_node_state(node, "READY")
        end
      else
        change_node_state(node, "READY")
      end
    elseif node.state == "READY" then
      print("ready")
      assert(ready_handlers[node.type], "No ready_handler for type "..node.type)
      ready_handlers[node.type](node)
    elseif node.state == "CRAFTING" then
      print("crafting")
      assert(crafting_handlers[node.type], "No crafting_handler for type "..node.type)
      crafting_handlers[node.type](node)
    elseif node.state == "DONE" and node.children then
      -- delete all the children
      for k,v in pairs(node.children) do
        delete_task(v)
      end
      node.children = {}
    end
  end

  local function save_task_lookup()
    local flat_task_lookup = {}
    for k,v in pairs(task_lookup) do
      flat_task_lookup[k] = shallow_clone(v)
      local flat_task = flat_task_lookup[k]
      if v.parent then
        flat_task.parent = v.parent.task_id
      end
      if v.children then
        flat_task.children = {}
        for i,ch in pairs(v.children) do
          flat_task.children[i] = ch.task_id
        end
      end
    end
    require "common".saveTableToFile("flat_task_lookup.txt", flat_task_lookup)
  end

  local function load_task_lookup()
    task_lookup = assert(require"common".loadTableFromFile("flat_task_lookup.txt"), "File does not exist")
    for k,v in pairs(task_lookup) do
      if v.parent then
        v.parent = task_lookup[v.parent]
      end
      if v.children then
        for i,ch in pairs(v.children) do
          v.children[i] = task_lookup[ch]
        end
      end
      if v.state then
        if v.state == "WAITING" then
          table.insert(waiting_queue, v)
        elseif v.state == "READY" then
          table.insert(ready_queue, v)
        elseif v.state == "CRAFTING" then
          table.insert(crafting_queue, v)
        elseif v.state == "DONE" then
          done_lookup[v.task_id] = v
        else
          error("Invalid state on load")
        end
      end
    end
  end

  local function update_whole_tree(tree)
    -- traverse to each node of the tree
    run_on_all(tree, update_node_state)
  end


  local function cancel_task(task_id)
    local task = task_lookup[task_id]
    if task.state then
      if task.state == "WAITING" then
        remove_from_array(waiting_queue, task)
      elseif task.state == "READY" then
        remove_from_array(ready_queue, task)
      end
      -- if it's not in these two states, then it's not cancellable
      return
    end
    task_lookup[task_id] = nil
  end

  local function cancel_job(job_id)
    for k,v in pairs(job_lookup[job_id]) do
      cancel_task(v.task_id)
    end
    job_lookup[job_id] = nil
  end

  local function tick_crafting()
    while true do
      print("crafting tick")
      for k,v in pairs(task_lookup) do
        print("Updating node")
        update_node_state(v)
        -- print("Finished updating node")
      end
      save_task_lookup()

      sleep(1)
    end
  end

  ---@param name string
  ---@param count integer
  ---@return CraftingNode root ROOT node
  local function request_craft(name, count)
    local job_id = id()
    job_lookup[job_id] = {}
    local ok, job = pcall(_request_craft, name, count, job_id)

    if not ok then
      error(job) -- TODO
    end

    ---@type CraftingNode
    local root = {
      job_id = job_id,
      children = job,
      type = "ROOT"
    }

    -- TEMPORARY TODO REMOVE
    update_whole_tree(root)
    return root
  end
  request_craft("minecraft:powered_rail", 10)

  return {
    start = function()
      parallel.waitForAll(modem_manager, keep_alive, tick_crafting)
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