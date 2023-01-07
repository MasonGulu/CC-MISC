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


  ---Get the index of a string or tag, creating one if one doesn't exist already
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

  local json_logger = setmetatable({}, {__index=function () return function () end end})
  if log then
    json_logger = log.interface.logger("crafting","json_importing")
  end
  local json_type_handlers = {}
  ---Add a JSON type handler, this should load a recipe from the given JSON table
  ---@param json_type string
  ---@param handler fun(json: table)
  local function add_json_type_handler(json_type, handler)
    json_type_handlers[json_type] = handler
  end
  local function load_json(json)
    if json_type_handlers[json.type] then
      print("Handling", json.type)
      json_logger:info("Importing JSON of type %s", json.type)
      json_type_handlers[json.type](json)
    else
      json_logger:info("Skipping JSON of type %s, no handler available", json.type)
      print("Skipping", json.type)
    end
  end

  load_item_lookup()

  ---@alias taskID string uuid foriegn key
  ---@alias jobID string

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

  local tick_node, change_node_state, delete_task

  --- ITEM - this node represents a quantity of items from the network
  --- ROOT - this node represents the root of a crafting task

  ---@alias NodeState string | "WAITING" | "READY" | "CRAFTING" | "DONE"

  ---@class CraftingNode
  ---@field children CraftingNode[]|nil
  ---@field parent CraftingNode|nil
  ---@field type "ITEM" | "ROOT" | "MISSING"
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

  local cached_stack_sizes = {} -- TODO save this

  ---Get the maximum stacksize of an item by name
  ---@param name string
  local function get_stack_size(name)
    if cached_stack_sizes[name] then
      return cached_stack_sizes[name]
    end
    local item = loaded.inventory.interface.getItem(name)
    cached_stack_sizes[name] = (item and item.item and item.item.maxCount) or 64
    return cached_stack_sizes[name]
  end

  ---Get a psuedorandom uuid
  ---@return string
  local function id()
    return os.epoch("utc")..math.random(1,100000)..string.char(math.random(65,90))
  end

  ---@type table<string,string[]>
  local craftable_lists = {}
  ---Set the table of craftable items for a given id
  ---@param id string ID of crafting module/type
  ---@param list string[] table of craftable item names, assigned by reference
  local function add_craftable_list(id, list)
    craftable_lists[id] = list
  end

  local function list_craftables()
    local l = {}
    for k, v in pairs(craftable_lists) do
      for i, s in ipairs(v) do
        table.insert(l, s)
      end
    end
    return l
  end

  ---@type table<string,string[]> tag -> item names
  local cached_tag_lookup = {}
  -- TODO load this
  ---@type table<string,table<string,boolean>> tag -> item name -> is it in cached_tag_lookup
  local cached_tag_presence = {}
  for tag,names in pairs(cached_tag_lookup) do
    cached_tag_presence[tag] = {}
    for _, name in ipairs(names) do
      cached_tag_presence[tag][name] = true
    end
  end

  ---Select the best item from a tag
  ---@param tag string
  ---@return string item_name
  local function select_best_from_tag(tag)
    if config.crafting.tagLookup.value[tag] then
      return config.crafting.tagLookup.value[tag]
    end
    if not cached_tag_presence[tag] then
      cached_tag_presence[tag] = {}
      cached_tag_lookup[tag] = {}
    end
    -- first check if we have anything
    local items_with_tag = loaded.inventory.interface.getTag(tag)
    local items_with_tag_count = {}
    for k,v in ipairs(items_with_tag) do
      if not cached_tag_presence[tag][v] then
        cached_tag_presence[tag][v] = true
        table.insert(cached_tag_lookup[tag], v)
      end
      items_with_tag_count[k] = {name=v, count=loaded.inventory.interface.getCount(v)}
    end
    table.sort(items_with_tag_count, function(a,b) return a.count > b.count end)
    if items_with_tag_count[1] then
      return items_with_tag_count[1].name
    end
    -- then check if we can craft anything (todo)
    error("Not yet implemented")
  end

  ---Select the best item from an index
  ---@param index ItemIndex
  ---@return string item_name
  local function select_best_from_index(index)
    local item_info = assert(item_lookup[index], "Invalid item index")
    if item_info.tag then
      return select_best_from_tag(item_info[1])
    end
    return item_info[1]
  end

  ---Select the best item from a list of ItemIndex
  ---@param list ItemIndex[]
  ---@return string item_name
  local function select_best_from_list(list)
    return item_lookup[list[1]][1]
  end

  ---Select the best item
  ---@param item ItemIndex[]|ItemIndex
  ---@return string item_name
  local function get_best_item(item)
    if type(item) == "table" then
      return select_best_from_list(item)
    elseif type(item) == "number" then
      return select_best_from_index(item)
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
  local craft
  ---@type table<string,fun(node:CraftingNode,name:string,job_id:string,count:integer,request_chain:table):boolean>
  local request_craft_types = {}
  local function add_craft_type(type, func)
    request_craft_types[type] = func
  end

  ---@param name string item name
  ---@param count integer
  ---@param job_id string
  ---@param force boolean|nil
  ---@param request_chain table<string,boolean>|nil table of item names that have been requested
  ---@return CraftingNode[] leaves ITEM|CG node
  function craft(name, count, job_id, force, request_chain)
    request_chain = shallow_clone(request_chain or {})
    if request_chain[name] then
      return {{
        name = name,
        task_id = id(),
        job_id = job_id,
        type = "MISSING",
        count = count,
      }}
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
          craft_logger:debug("No recipe found for %s", name)
          node.count = remaining
          node.type = "MISSING"
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

  ---Delete a given task, asserting the task is DONE and has no children
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
    task_lookup[task.task_id] = nil
    remove_from_array(job_lookup[task.job_id], task)
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

  ---Deletes all the node's children, calling delete_task on each
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
  function tick_node(node)
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
            change_node_state(node, "DONE")
            delete_task(node)
            return
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
    run_on_all(tree, tick_node)
  end

  ---Remove the parent of each child
  ---@param node CraftingNode
  local function remove_childrens_parent(node)
    for k,v in pairs(node.children) do
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

  ---@type table<jobID,CraftingNode>
  local pending_jobs = {}

  ---Cancel a job by given id
  ---@param job_id any
  local function cancel_craft(job_id)
    craft_logger:info("Cancelling job %s", job_id)
    if pending_jobs[job_id] then
      pending_jobs[job_id] = nil
      return
    end
    for k,v in pairs(job_lookup[job_id]) do
      cancel_task(v.task_id)
    end
    job_lookup[job_id] = nil
  end

  local function tick_crafting()
    while true do
      for k,v in pairs(task_lookup) do
        tick_node(v)
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
          tick_node(node)
        end
      end
    end
  end


  ---@param name string
  ---@param count integer
  ---@return jobID pending_jobID
  local function create_craft_job(name, count)
    local job_id = id()

    craft_logger:debug("New job. name:%s,count:%u,job_id:%s", name, count, job_id)
    craft_logger:info("Requested craft for %ux%s", count, name)
    local job = craft(name, count, job_id, true)

    ---@type CraftingNode
    local root = {
      job_id = job_id,
      children = job,
      type = "ROOT",
      task_id = id(),
    }

    pending_jobs[job_id] = root

    return job_id
  end

  ---Add the values in table b to table a
  ---@param a table<string,integer>
  ---@param b table<string,integer>
  local function add_tables(a,b)
    for k,v in pairs(b) do
      a[k] = (a[k] or 0) + v
    end
  end

  ---@alias jobInfo {success: boolean, to_craft: table<string,integer>, to_use: table<string,integer>, missing: table<string,integer>|nil, job_id: jobID}

  ---Extract information from a job root
  ---@param root CraftingNode
  ---@return jobInfo
  local function get_job_info(root)
    local ret = {}
    ret.success = true
    ret.to_craft = {}
    ret.to_use = {}
    ret.missing = {}
    ret.job_id = root.job_id
    if root.type == "ITEM" then
      ret.to_use[root.name] = (ret.to_use[root.name] or 0) + root.count
      print("item", ret.to_use[root.name])
    elseif root.type == "MISSING" then
      ret.success = false
      ret.missing[root.name] = (ret.missing[root.name] or 0) + root.count
    elseif root.type ~= "ROOT" then
      ret.to_craft[root.name] = (ret.to_craft[root.name] or 0) + (root.count or 0)
    end
    if root.children then
      for _, child in pairs(root.children) do
        local child_info = get_job_info(child)
        add_tables(ret.to_craft, child_info.to_craft)
        add_tables(ret.to_use, child_info.to_use)
        add_tables(ret.missing, child_info.missing or {})
        ret.success = ret.success and child_info.success
      end
    end
    return ret
  end

  ---Request a craft job, returning info about it
  ---@param name string
  ---@param count integer
  ---@return jobInfo
  local function request_craft(name,count)
    local jobID = create_craft_job(name,count)
    return get_job_info(pending_jobs[jobID])
  end

  ---Start a given job, if it's pending
  ---@param jobID jobID
  ---@return boolean success
  local function start_craft(jobID)
    local job = pending_jobs[jobID]
    if not job then
      return false
    end
    local job_info = get_job_info(job)
    if not job_info.success then
      return false -- cannot start unsuccessful job
    end
    pending_jobs[jobID] = nil
    job_lookup[jobID] = {}
    run_on_all(job, function(node)
      task_lookup[node.task_id] = node
      table.insert(job_lookup[jobID], node)
    end)
    update_whole_tree(job)
    return true
  end

  local function json_file_import()
    print("JSON file importing ready..")
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
  end

  return {
    start = function()
      parallel.waitForAny(tick_crafting, inventory_transfer_listener, json_file_import)
    end,

    request_craft = request_craft,
    start_craft = start_craft,
    load_json = load_json,
    list_craftables = list_craftables,
    cancel_craft = cancel_craft,

    recipeInterface = {
      change_node_state = change_node_state,
      tick_node = tick_node,
      get_best_item = get_best_item,
      get_stack_size = get_stack_size,
      merge_into = merge_into,
      craft = craft,
      push_items = push_items,
      add_crafting_handler = add_crafting_handler,
      add_ready_handler = add_ready_handler,
      add_craft_type = add_craft_type,
      delete_node_children = delete_node_children,
      delete_task = delete_task,
      get_or_cache_string = get_or_cache_string,
      add_json_type_handler = add_json_type_handler,
      add_craftable_list = add_craftable_list
    }
  }
end
}