local STATES = {
  READY = "READY",
  ERROR = "ERROR",
  BUSY = "BUSY",
  CRAFTING = "CRAFTING",
}

local common = require("common")
return {
id = "crafting",
version = "INDEV",
config = {
  tagLookup = {
    type="table",
    description="Force a given item to be used for a tag lookup. Map from tag->item.",
    default={}
  }
},
init = function(loaded, config)
  local log = loaded.logger
  ---@class ItemInfo
  ---@field [1] string
  ---@field tag boolean|nil

  ---@alias ItemIndex integer

  ---@type ItemInfo[]
  -- lookup into an ordered list of item names
  local item_lookup = {}
  ---@type table<string,ItemIndex> lookup from name -> item_lookup index
  local item_name_lookup = {}


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
      common.write_string(f, item_name)
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
      local name = common.read_string(f)
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

  ---@alias taskID string uuid foriegn key

  ---@type CraftingNode[] tasks that have unmet dependencies
  local waiting_queue = {}
  ---@type CraftingNode[] tasks that have all dependencies met
  local ready_queue = {}
  ---@type CraftingNode[] tasks that are in progress
  local crafting_queue = {}

  ---@type table<string,CraftingNode> tasks that have been completed, but are still relavant
  local done_lookup = {}

  ---@type table<string,CraftingNode>
  local transfer_id_task_lut = {}

  local update_node_state, change_node_state, delete_task

  --- ITEM - this node represents a quantity of items from the network
  --- ROOT - this node represents the root of a crafting task

  ---@alias NodeState string | "WAITING" | "READY" | "CRAFTING" | "DONE"

  ---@class CraftingNode
  ---@field children CraftingNode[]|nil
  ---@field parent CraftingNode|nil
  ---@field type "ITEM" | "ROOT"
  ---@field name string
  ---@field count integer amount of this item to produce
  ---@field task_id string
  ---@field job_id string
  ---@field state NodeState
  ---@field priority integer TODO

  ---@type table<string,integer> item name -> count reserved
  local reserved_items = {}

  ---Get count of item in system, excluding reserved
  ---@param name string
  ---@return integer
  local function get_count(name)
    return loaded.inventory.interface.getCount(name) - (reserved_items[name] or 0)
  end

  ---Reserve amount of item name
  ---@param name string
  ---@param amount integer
  ---@return integer
  local function allocate_items(name, amount)
    reserved_items[name] = (reserved_items[name] or 0) + amount
    return amount
  end

  ---Free amount of item name
  ---@param name string
  ---@param amount integer
  ---@return integer
  local function deallocate_items(name, amount)
    reserved_items[name] = reserved_items[name] - amount
    assert(reserved_items[name] >= 0, "We have negative items reserved?")
    if reserved_items[name] == 0 then
      reserved_items[name] = nil
    end
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
  ---Get the maximum stacksize of an item by name
  ---@param name string
  local function get_stack_size(name)
    return 64 -- TODO
  end

  ---Get a psuedorandom uuid
  ---@return string
  local function id()
    return os.epoch("utc")..math.random(1,100000)..string.char(math.random(65,90))
  end

  ---Select the best item from a tag
  ---@param tag string
  ---@return string name
  local function select_best_from_tag(tag)
    if config.crafting.tagLookup.value[tag] then
      return config.crafting.tagLookup.value[tag]
    end
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

  ---Merge from into the end of to
  ---@param from table
  ---@param to table
  local function merge_into(from, to)
    for k,v in pairs(from) do
      table.insert(to,v)
    end
  end

  ---Lookup from task_id to the corrosponding CraftingNode
  ---@type table<string,CraftingNode>
  local task_lookup = {}

  ---Lookup from job_id to the corrosponding CraftingNode
  ---@type table<string,CraftingNode[]>
  local job_lookup = {}

  ---Shallow clone a table
  ---@param t table
  ---@return table
  local function shallow_clone(t)
    local nt = {}
    for k,v in pairs(t) do
      nt[k] = v
    end
    return nt
  end

  local craft_logger = setmetatable({}, {__index=function () return function () end end})
  if log then
    craft_logger = log.interface.logger("crafting","request_craft")
  end
  local _request_craft
  ---@type table<string,fun(node:CraftingNode,name:string,job_id:string,count:integer,request_chain:table):boolean>
  local request_craft_types = {} -- TODO load this from grid.lua
  local function add_request_craft_type(type, func)
    request_craft_types[type] = func
  end

  ---@param name string item name
  ---@param count integer
  ---@param job_id string
  ---@param force boolean|nil
  ---@param request_chain table<string,boolean>|nil table of item names that have been requested
  ---@return CraftingNode[] leaves ITEM|CG node
  function _request_craft(name, count, job_id, force, request_chain)
    request_chain = shallow_clone(request_chain or {})
    if request_chain[name] then
      error("Recursive craft", 0)
    end
    request_chain[name] = true
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
        local allocate_amount = allocate_items(name, math.min(available, remaining))
        node.type = "ITEM"
        node.count = allocate_amount
        remaining = remaining - allocate_amount
        craft_logger:debug("Item. name:%s,count:%u,task_id:%s,job_id:%s", name, allocate_amount, node.task_id, job_id)
      else
        local success = false
        for k,v in pairs(request_craft_types) do
          success = v(node, name, job_id, remaining, request_chain)
          if success then
            craft_logger:debug("Recipe. provider:%s,name:%s,count:%u,task_id:%s,job_id:%s", k, name, node.count, node.task_id, job_id)
            craft_logger:info("Recipe for %s was provided by %s", name, k)
            break
          end
        end
        if not success then
          error(("No recipe found for %s"):format(name), 0)
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

  ---Remove an object from a table
  ---@generic T : any
  ---@param arr T[]
  ---@param val T
  local function remove_from_array(arr, val)
    for i,v in ipairs(arr) do
      if v == val then
        table.remove(arr, i)
      end
    end
  end

  ---Delete a given task, given the task is DONE and has no children
  ---@param task CraftingNode
  function delete_task(task)
    if task.type == "ITEM" then
      deallocate_items(task.name, task.count)
    end
    if task.parent then
      remove_from_array(task.parent.children, task)
    end
    assert(task.state == "DONE", "Attempt to delete not done task.")
    done_lookup[task.task_id] = nil
    assert(task.children == nil, "Attempt to delete task with children.")
  end


  local node_state_logger = setmetatable({}, {__index=function () return function () end end})
  if log then
    node_state_logger = log.interface.logger("crafting", "node_state")
  end
  ---Safely change a node to a new state
  ---Only modifies the node's state and related caches
  ---@param node CraftingNode
  ---@param new_state NodeState
  function change_node_state(node, new_state)
    if not node then
      error("No node?", 2)
    end
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

  ---Protected pushItems, errors if it cannot move
  ---enough items to a slot
  ---@param to string
  ---@param name string
  ---@param to_move integer
  ---@param slot integer
  local function push_items(to, name, to_move, slot)
    local fail_count = 0
    while to_move > 0 do
      local transfered = loaded.inventory.interface.pushItems(false, to, name, to_move, slot, nil, {optimal=false})
      to_move = to_move - transfered
      if transfered == 0 then
        fail_count = fail_count + 1
        if fail_count > 3 then
          error(("Unable to move %s"):format(name))
        end
      end
    end
  end

  ---@type table<string,fun(node: CraftingNode)> Process an item in the READY state
  local ready_handlers = {} -- TODO get this from grid.lua

  ---@param type string
  ---@param func fun(node: CraftingNode)>
  local function add_ready_handler(type, func)
    ready_handlers[type] = func
  end

  ---@type table<string,fun(node: CraftingNode)> Process an item that is in the CRAFTING state
  local crafting_handlers = {} -- TODO get this from grid.lua

  ---@param type string
  ---@param func fun(node: CraftingNode)>
  local function add_crafting_handler(type, func)
    crafting_handlers[type] = func
  end

  local function delete_node_children(node)
    if not node.children then
      return
    end
    for _,child in pairs(node.children) do
      delete_task(child)
    end
    node.children = nil

  end

  ---Update the state of the given node
  ---@param node CraftingNode
  function update_node_state(node)
    if not node.state then
      if node.type == "ROOT" then
        node.start_time = os.epoch("utc")
      end
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
          print("ready to be crafted", node.type, node.task_id)
          delete_node_children(node)
          remove_from_array(waiting_queue, node)
          if node.type == "ROOT" then
            -- This task is the root of a job
            -- TODO some notification that the whole job is done!
            node_state_logger:info("Finished job_id:%s in %.2fsec", node.job_id, (os.epoch("utc") - node.start_time) / 1000)
            node.state = "DONE"
            error("Job done!")
          end
          change_node_state(node, "READY")
        end
      else
        change_node_state(node, "READY")
      end
    elseif node.state == "READY" then
      assert(ready_handlers[node.type], "No ready_handler for type "..node.type)
      ready_handlers[node.type](node)
    elseif node.state == "CRAFTING" then
      assert(crafting_handlers[node.type], "No crafting_handler for type "..node.type)
      crafting_handlers[node.type](node)
    elseif node.state == "DONE" and node.children then
      delete_node_children(node)
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

  ---Update every node on the tree
  ---@param tree CraftingNode
  local function update_whole_tree(tree)
    -- traverse to each node of the tree
    run_on_all(tree, update_node_state)
  end

  ---Remove the parent of each child
  ---@param node CraftingNode
  local function remove_childrens_parent(node)
    for k,v in pairs(node) do
      v.parent = nil
    end
  end

  ---Safely cancel a task by ID
  ---@param task_id string
  local function cancel_task(task_id)
    craft_logger:debug("Cancelling task %s", task_id)
    local task = task_lookup[task_id]
    if task.state then
      if task.state == "WAITING" then
        remove_from_array(waiting_queue, task)
        remove_childrens_parent(task)
      elseif task.state == "READY" then
        remove_from_array(ready_queue, task)
        remove_childrens_parent(task)
      end
      -- if it's not in these two states, then it's not cancellable
      return
    end
    task_lookup[task_id] = nil
  end

  ---Cancel a job by given id
  ---@param job_id any
  local function cancel_job(job_id)
    craft_logger:info("Cancelling job %s", job_id)
    for k,v in pairs(job_lookup[job_id]) do
      cancel_task(v.task_id)
    end
    job_lookup[job_id] = nil
  end

  local function tick_crafting()
    while true do
      for k,v in pairs(task_lookup) do
        update_node_state(v)
      end
      save_task_lookup()

      os.sleep(1)
    end
  end

  local inventory_transfer_logger
  if log then
    inventory_transfer_logger = log.interface.logger("crafting","inventory_transfer_listener")
  end
  local function inventory_transfer_listener()
    while true do
      local _, transfer_id = os.pullEvent("inventoryFinished")
      ---@type CraftingNode
      local node = transfer_id_task_lut[transfer_id]
      if node then
        transfer_id_task_lut[transfer_id] = nil
        remove_from_array(node.transfers, transfer_id)
        if #node.transfers == 0 then
          if log then
            inventory_transfer_logger:debug("Node DONE, task_id:%s, job_id:%s", node.task_id, node.job_id)
          end
          -- all transfers finished
          change_node_state(node, "DONE")
          update_node_state(node)
        end
      end
    end
  end

  ---@param name string
  ---@param count integer
  ---@return CraftingNode root ROOT node
  local function request_craft(name, count)
    local job_id = id()
    job_lookup[job_id] = {}

    craft_logger:debug("New job. name:%s,count:%u,job_id:%s", name, count, job_id)
    craft_logger:info("Requested craft for %ux%s", count, name)
    local ok, job = pcall(_request_craft, name, count, job_id, true)

    if not ok then
      craft_logger:error("Creating job for %ux%s failed. %s. job_id:%s", count, name, job, job_id)
      cancel_job(job_id)
      error(job) -- TODO
    end

    ---@type CraftingNode
    local root = {
      job_id = job_id,
      children = job,
      type = "ROOT",
      task_id = id(),
    }

    table.insert(job_lookup[job_id], root)
    task_lookup[root.task_id] = root

    -- TEMPORARY TODO REMOVE
    update_whole_tree(root)
    return root
  end

  return {
    start = function()
      parallel.waitForAny(tick_crafting, inventory_transfer_listener)
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
    end,

    request_craft = request_craft,

    recipeInterface = {
      change_node_state = change_node_state,
      update_node_state = update_node_state,
      get_best_item = get_best_item,
      get_stack_size = get_stack_size,
      merge_into = merge_into,
      _request_craft = _request_craft,
      push_items = push_items,
      add_crafting_handler = add_crafting_handler,
      add_ready_handler = add_ready_handler,
      add_request_craft_type = add_request_craft_type,
      delete_node_children = delete_node_children,
      delete_task = delete_task
    }
  }
end
}