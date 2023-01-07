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
  local itemLookup = {}
  ---@type table<string,ItemIndex> lookup from name -> item_lookup index
  local itemNameLookup = {}


  ---Get the index of a string or tag, creating one if one doesn't exist already
  ---@param str string
  ---@param tag boolean|nil
  ---@return ItemIndex
  local function getOrCacheString(str, tag)
    if not str then
      error("",2)
    end
    if itemNameLookup[str] then
      return itemNameLookup[str]
    end
    local i = #itemLookup + 1
    if tag then
      itemLookup[i] = {str,tag=true}
    else
      itemLookup[i] = {str}
    end
    itemNameLookup[str] = i
    return i
  end

  local function saveItemLookup()
    local f = assert(fs.open("recipes/item_lookup.bin", "wb"))
    f.write("ILUT")
    for _,v in ipairs(itemLookup) do
      local itemName = assert(v[1],#itemLookup)
      if v.tag then
        f.write("T")
      else
        f.write("I")
      end
      common.writeString(f, itemName)
    end
    f.close()
  end
  local function loadItemLookup()
    local f = fs.open("recipes/item_lookup.bin", "rb")
    if not f then
      itemLookup = {}
      return
    end
    assert(f.read(4) == "ILUT", "Invalid item_lookup file")
    local mode = f.read(1)
    while mode do
      local name = common.readString(f)
      local item = {name}
      if mode == "I" then
      elseif mode == "T" then
        item.tag = true
      end
      table.insert(itemLookup, item)
      mode = f.read(1)
    end
    f.close()
    for k,v in pairs(itemLookup) do
      itemNameLookup[v[1]] = k
    end
  end

  local jsonLogger = setmetatable({}, {__index=function () return function () end end})
  if log then
    jsonLogger = log.interface.logger("crafting","json_importing")
  end
  local jsonTypeHandlers = {}
  ---Add a JSON type handler, this should load a recipe from the given JSON table
  ---@param jsonType string
  ---@param handler fun(json: table)
  local function addJsonTypeHandler(jsonType, handler)
    jsonTypeHandlers[jsonType] = handler
  end
  local function loadJson(json)
    if jsonTypeHandlers[json.type] then
      print("Handling", json.type)
      jsonLogger:info("Importing JSON of type %s", json.type)
      jsonTypeHandlers[json.type](json)
    else
      jsonLogger:info("Skipping JSON of type %s, no handler available", json.type)
      print("Skipping", json.type)
    end
  end

  loadItemLookup()

  ---@alias taskID string uuid foriegn key
  ---@alias JobId string

  ---@type CraftingNode[] tasks that have unmet dependencies
  local waitingQueue = {}
  ---@type CraftingNode[] tasks that have all dependencies met
  local readyQueue = {}
  ---@type CraftingNode[] tasks that are in progress
  local craftingQueue = {}

  ---@type table<string,CraftingNode> tasks that have been completed, but are still relavant
  local doneLookup = {}

  ---@type table<string,CraftingNode>
  local transferIdTaskLUT = {}

  local tickNode, changeNodeState, deleteTask

  --- ITEM - this node represents a quantity of items from the network
  --- ROOT - this node represents the root of a crafting task

  ---@alias NodeState string | "WAITING" | "READY" | "CRAFTING" | "DONE"

  ---@class CraftingNode
  ---@field children CraftingNode[]|nil
  ---@field parent CraftingNode|nil
  ---@field type "ITEM" | "ROOT" | "MISSING"
  ---@field name string
  ---@field count integer amount of this item to produce
  ---@field taskId string
  ---@field jobId string
  ---@field state NodeState
  ---@field priority integer TODO

  ---@type table<string,integer> item name -> count reserved
  local reservedItems = {}

  ---Get count of item in system, excluding reserved
  ---@param name string
  ---@return integer
  local function getCount(name)
    return loaded.inventory.interface.getCount(name) - (reservedItems[name] or 0)
  end

  ---Reserve amount of item name
  ---@param name string
  ---@param amount integer
  ---@return integer
  local function allocateItems(name, amount)
    reservedItems[name] = (reservedItems[name] or 0) + amount
    return amount
  end

  ---Free amount of item name
  ---@param name string
  ---@param amount integer
  ---@return integer
  local function deallocateItems(name, amount)
    reservedItems[name] = reservedItems[name] - amount
    assert(reservedItems[name] >= 0, "We have negative items reserved?")
    if reservedItems[name] == 0 then
      reservedItems[name] = nil
    end
    return amount
  end

  local cachedStackSizes = {} -- TODO save this

  ---Get the maximum stacksize of an item by name
  ---@param name string
  local function getStackSize(name)
    if cachedStackSizes[name] then
      return cachedStackSizes[name]
    end
    local item = loaded.inventory.interface.getItem(name)
    cachedStackSizes[name] = (item and item.item and item.item.maxCount) or 64
    return cachedStackSizes[name]
  end

  ---Get a psuedorandom uuid
  ---@return string
  local function id()
    return os.epoch("utc")..math.random(1,100000)..string.char(math.random(65,90))
  end

  ---@type table<string,string[]>
  local craftableLists = {}
  ---Set the table of craftable items for a given id
  ---@param id string ID of crafting module/type
  ---@param list string[] table of craftable item names, assigned by reference
  local function addCraftableList(id, list)
    craftableLists[id] = list
  end

  local function listCraftables()
    local l = {}
    for k, v in pairs(craftableLists) do
      for i, s in ipairs(v) do
        table.insert(l, s)
      end
    end
    return l
  end

  ---@type table<string,string[]> tag -> item names
  local cachedTagLookup = {}
  -- TODO load this
  ---@type table<string,table<string,boolean>> tag -> item name -> is it in cached_tag_lookup
  local cachedTagPresence = {}
  for tag,names in pairs(cachedTagLookup) do
    cachedTagPresence[tag] = {}
    for _, name in ipairs(names) do
      cachedTagPresence[tag][name] = true
    end
  end

  ---Select the best item from a tag
  ---@param tag string
  ---@return string itemName
  local function selectBestFromTag(tag)
    if config.crafting.tagLookup.value[tag] then
      return config.crafting.tagLookup.value[tag]
    end
    if not cachedTagPresence[tag] then
      cachedTagPresence[tag] = {}
      cachedTagLookup[tag] = {}
    end
    -- first check if we have anything
    local itemsWithTag = loaded.inventory.interface.getTag(tag)
    local itemsWithTagsCount = {}
    for k,v in ipairs(itemsWithTag) do
      if not cachedTagPresence[tag][v] then
        cachedTagPresence[tag][v] = true
        table.insert(cachedTagLookup[tag], v)
      end
      itemsWithTagsCount[k] = {name=v, count=loaded.inventory.interface.getCount(v)}
    end
    table.sort(itemsWithTagsCount, function(a,b) return a.count > b.count end)
    if itemsWithTagsCount[1] then
      return itemsWithTagsCount[1].name
    end
    -- then check if we can craft anything (todo)
    error("Not yet implemented")
  end

  ---Select the best item from an index
  ---@param index ItemIndex
  ---@return string itemName
  local function selectBestFromIndex(index)
    local itemInfo = assert(itemLookup[index], "Invalid item index")
    if itemInfo.tag then
      return selectBestFromTag(itemInfo[1])
    end
    return itemInfo[1]
  end

  ---Select the best item from a list of ItemIndex
  ---@param list ItemIndex[]
  ---@return string itemName
  local function selectBestFromList(list)
    return itemLookup[list[1]][1]
  end

  ---Select the best item
  ---@param item ItemIndex[]|ItemIndex
  ---@return string itemName
  local function getBestItem(item)
    if type(item) == "table" then
      return selectBestFromList(item)
    elseif type(item) == "number" then
      return selectBestFromIndex(item)
    end
    error("hah not any")
  end

  ---Merge from into the end of to
  ---@param from table
  ---@param to table
  local function mergeInto(from, to)
    for k,v in pairs(from) do
      table.insert(to,v)
    end
  end

  ---Lookup from taskId to the corrosponding CraftingNode
  ---@type table<string,CraftingNode>
  local taskLookup = {}

  ---Lookup from jobId to the corrosponding CraftingNode
  ---@type table<string,CraftingNode[]>
  local jobLookup = {}

  ---Shallow clone a table
  ---@param t table
  ---@return table
  local function shallowClone(t)
    local nt = {}
    for k,v in pairs(t) do
      nt[k] = v
    end
    return nt
  end

  local craftLogger = setmetatable({}, {__index=function () return function () end end})
  if log then
    craftLogger = log.interface.logger("crafting","request_craft")
  end
  local craft
  ---@type table<string,fun(node:CraftingNode,name:string,jobId:string,count:integer,request_chain:table):boolean>
  local requestCraftTypes = {}
  local function addCraftType(type, func)
    requestCraftTypes[type] = func
  end

  ---@param name string item name
  ---@param count integer
  ---@param jobId string
  ---@param force boolean|nil
  ---@param requestChain table<string,boolean>|nil table of item names that have been requested
  ---@return CraftingNode[] leaves ITEM|CG node
  function craft(name, count, jobId, force, requestChain)
    requestChain = shallowClone(requestChain or {})
    if requestChain[name] then
      return {{
        name = name,
        taskId = id(),
        jobId = jobId,
        type = "MISSING",
        count = count,
      }}
    end
    requestChain[name] = true
    ---@type CraftingNode[]
    local nodes = {}
    local remaining = count
    craftLogger:debug("Remaining craft count for %s is %u", name, remaining)
    while remaining > 0 do
      ---@type CraftingNode
      local node = {
        name = name,
        taskId = id(),
        jobId = jobId
      }
      -- First check if we have any of this
      local available = getCount(name)
      if available > 0 and not force then
        -- we do, so allocate it
        local allocateAmount = allocateItems(name, math.min(available, remaining))
        node.type = "ITEM"
        node.count = allocateAmount
        remaining = remaining - allocateAmount
        craftLogger:debug("Item. name:%s,count:%u,taskId:%s,jobId:%s", name, allocateAmount, node.taskId, jobId)
      else
        local success = false
        for k,v in pairs(requestCraftTypes) do
          success = v(node, name, jobId, remaining, requestChain)
          if success then
            craftLogger:debug("Recipe. provider:%s,name:%s,count:%u,taskId:%s,jobId:%s", k, name, node.count, node.taskId, jobId)
            craftLogger:info("Recipe for %s was provided by %s", name, k)
            break
          end
        end
        if not success then
          craftLogger:debug("No recipe found for %s", name)
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
  local function runOnAll(root, func)
    func(root)
    if root.children then
      for _,v in pairs(root.children) do
        runOnAll(v, func)
      end
    end
  end

  ---Remove an object from a table
  ---@generic T : any
  ---@param arr T[]
  ---@param val T
  local function removeFromArray(arr, val)
    for i,v in ipairs(arr) do
      if v == val then
        table.remove(arr, i)
      end
    end
  end

  ---Delete a given task, asserting the task is DONE and has no children
  ---@param task CraftingNode
  function deleteTask(task)
    if task.type == "ITEM" then
      deallocateItems(task.name, task.count)
    end
    if task.parent then
      removeFromArray(task.parent.children, task)
    end
    assert(task.state == "DONE", "Attempt to delete not done task.")
    doneLookup[task.taskId] = nil
    assert(task.children == nil, "Attempt to delete task with children.")
    taskLookup[task.taskId] = nil
    removeFromArray(jobLookup[task.jobId], task)
  end


  local nodeStateLogger = setmetatable({}, {__index=function () return function () end end})
  if log then
    nodeStateLogger = log.interface.logger("crafting", "node_state")
  end
  ---Safely change a node to a new state
  ---Only modifies the node's state and related caches
  ---@param node CraftingNode
  ---@param newState NodeState
  function changeNodeState(node, newState)
    if not node then
      error("No node?", 2)
    end
    if node.state == "WAITING" then
      removeFromArray(waitingQueue, node)
    elseif node.state == "READY" then
      removeFromArray(readyQueue, node)
    elseif node.state == "CRAFTING" then
      removeFromArray(craftingQueue, node)
    elseif node.state == "DONE" then
      doneLookup[node.taskId] = nil
    end
    node.state = newState
    if node.state == "WAITING" then
      table.insert(waitingQueue, node)
    elseif node.state == "READY" then
      table.insert(readyQueue, node)
    elseif node.state == "CRAFTING" then
      table.insert(craftingQueue, node)
    elseif node.state == "DONE" then
      doneLookup[node.taskId] = node
    end
  end

  ---Protected pushItems, errors if it cannot move
  ---enough items to a slot
  ---@param to string
  ---@param name string
  ---@param toMove integer
  ---@param slot integer
  local function pushItems(to, name, toMove, slot)
    local failCount = 0
    while toMove > 0 do
      local transfered = loaded.inventory.interface.pushItems(false, to, name, toMove, slot, nil, {optimal=false})
      toMove = toMove - transfered
      if transfered == 0 then
        failCount = failCount + 1
        if failCount > 3 then
          error(("Unable to move %s"):format(name))
        end
      end
    end
  end

  ---@type table<string,fun(node: CraftingNode)> Process an item in the READY state
  local readyHandlers = {} -- TODO get this from grid.lua

  ---@param type string
  ---@param func fun(node: CraftingNode)>
  local function addReadyHandler(type, func)
    readyHandlers[type] = func
  end

  ---@type table<string,fun(node: CraftingNode)> Process an item that is in the CRAFTING state
  local craftingHandlers = {} -- TODO get this from grid.lua

  ---@param type string
  ---@param func fun(node: CraftingNode)>
  local function addCraftingHandler(type, func)
    craftingHandlers[type] = func
  end

  ---Deletes all the node's children, calling delete_task on each
  local function deleteNodeChildren(node)
    if not node.children then
      return
    end
    for _,child in pairs(node.children) do
      deleteTask(child)
    end
    node.children = nil

  end

  ---Update the state of the given node
  ---@param node CraftingNode
  function tickNode(node)
    if not node.state then
      if node.type == "ROOT" then
        node.startTime = os.epoch("utc")
      end
      -- This is an uninitialized node
      -- leaf -> set state to READY
      -- otherwise -> set state to WAITING
      if node.children then
        changeNodeState(node, "WAITING")
      else
        changeNodeState(node, "DONE")
      end
      return
    end
    -- this is a node that has been updated before
    if node.state == "WAITING" then
      if node.children then
        -- this has children it depends upon
        local allChildrenDone = true
        for _,child in pairs(node.children) do
          allChildrenDone = child.state == "DONE"
          if not allChildrenDone then
            break
          end
        end
        if allChildrenDone then
          -- this is ready to be crafted
          print("ready to be crafted", node.type, node.taskId)
          deleteNodeChildren(node)
          removeFromArray(waitingQueue, node)
          if node.type == "ROOT" then
            -- This task is the root of a job
            -- TODO some notification that the whole job is done!
            nodeStateLogger:info("Finished jobId:%s in %.2fsec", node.jobId, (os.epoch("utc") - node.startTime) / 1000)
            changeNodeState(node, "DONE")
            deleteTask(node)
            return
          end
          changeNodeState(node, "READY")
        end
      else
        changeNodeState(node, "READY")
      end
    elseif node.state == "READY" then
      assert(readyHandlers[node.type], "No readyHandler for type "..node.type)
      readyHandlers[node.type](node)
    elseif node.state == "CRAFTING" then
      assert(craftingHandlers[node.type], "No craftingHandler for type "..node.type)
      craftingHandlers[node.type](node)
    elseif node.state == "DONE" and node.children then
      deleteNodeChildren(node)
    end
  end

  local function saveTaskLookup()
    local flatTaskLookup = {}
    for k,v in pairs(taskLookup) do
      flatTaskLookup[k] = shallowClone(v)
      local flatTask = flatTaskLookup[k]
      if v.parent then
        flatTask.parent = v.parent.taskId
      end
      if v.children then
        flatTask.children = {}
        for i,ch in pairs(v.children) do
          flatTask.children[i] = ch.taskId
        end
      end
    end
    require "common".saveTableToFile("flatTaskLookup.txt", flatTaskLookup)
  end

  local function loadTaskLookup()
    taskLookup = assert(require"common".loadTableFromFile("flatTaskLookup.txt"), "File does not exist")
    for k,v in pairs(taskLookup) do
      if v.parent then
        v.parent = taskLookup[v.parent]
      end
      if v.children then
        for i,ch in pairs(v.children) do
          v.children[i] = taskLookup[ch]
        end
      end
      if v.state then
        if v.state == "WAITING" then
          table.insert(waitingQueue, v)
        elseif v.state == "READY" then
          table.insert(readyQueue, v)
        elseif v.state == "CRAFTING" then
          table.insert(craftingQueue, v)
        elseif v.state == "DONE" then
          doneLookup[v.taskId] = v
        else
          error("Invalid state on load")
        end
      end
    end
  end

  ---Update every node on the tree
  ---@param tree CraftingNode
  local function updateWholeTree(tree)
    -- traverse to each node of the tree
    runOnAll(tree, tickNode)
  end

  ---Remove the parent of each child
  ---@param node CraftingNode
  local function removeChildrensParents(node)
    for k,v in pairs(node.children) do
      v.parent = nil
    end
  end

  ---Safely cancel a task by ID
  ---@param taskId string
  local function cancelTask(taskId)
    craftLogger:debug("Cancelling task %s", taskId)
    local task = taskLookup[taskId]
    if task.state then
      if task.state == "WAITING" then
        removeFromArray(waitingQueue, task)
        removeChildrensParents(task)
      elseif task.state == "READY" then
        removeFromArray(readyQueue, task)
        removeChildrensParents(task)
      end
      -- if it's not in these two states, then it's not cancellable
      return
    end
    taskLookup[taskId] = nil
  end

  ---@type table<JobId,CraftingNode>
  local pendingJobs = {}

  ---Cancel a job by given id
  ---@param jobId any
  local function cancelCraft(jobId)
    craftLogger:info("Cancelling job %s", jobId)
    if pendingJobs[jobId] then
      pendingJobs[jobId] = nil
      return
    end
    for k,v in pairs(jobLookup[jobId]) do
      cancelTask(v.taskId)
    end
    jobLookup[jobId] = nil
  end

  local function tickCrafting()
    while true do
      for k,v in pairs(taskLookup) do
        tickNode(v)
      end
      saveTaskLookup()

      os.sleep(1)
    end
  end

  local inventoryTransferLogger
  if log then
    inventoryTransferLogger = log.interface.logger("crafting","inventory_transfer_listener")
  end
  local function inventoryTransferListener()
    while true do
      local _, transferId = os.pullEvent("inventoryFinished")
      ---@type CraftingNode
      local node = transferIdTaskLUT[transferId]
      if node then
        transferIdTaskLUT[transferId] = nil
        removeFromArray(node.transfers, transferId)
        if #node.transfers == 0 then
          if log then
            inventoryTransferLogger:debug("Node DONE, taskId:%s, jobId:%s", node.taskId, node.jobId)
          end
          -- all transfers finished
          changeNodeState(node, "DONE")
          tickNode(node)
        end
      end
    end
  end


  ---@param name string
  ---@param count integer
  ---@return JobId pendingJobId
  local function createCraftJob(name, count)
    local jobId = id()

    craftLogger:debug("New job. name:%s,count:%u,jobId:%s", name, count, jobId)
    craftLogger:info("Requested craft for %ux%s", count, name)
    local job = craft(name, count, jobId, true)

    ---@type CraftingNode
    local root = {
      jobId = jobId,
      children = job,
      type = "ROOT",
      taskId = id(),
    }

    pendingJobs[jobId] = root

    return jobId
  end

  ---Add the values in table b to table a
  ---@param a table<string,integer>
  ---@param b table<string,integer>
  local function addTables(a,b)
    for k,v in pairs(b) do
      a[k] = (a[k] or 0) + v
    end
  end

  ---@alias jobInfo {success: boolean, toCraft: table<string,integer>, toUse: table<string,integer>, missing: table<string,integer>|nil, jobId: JobId}

  ---Extract information from a job root
  ---@param root CraftingNode
  ---@return jobInfo
  local function getJobInfo(root)
    local ret = {}
    ret.success = true
    ret.toCraft = {}
    ret.toUse = {}
    ret.missing = {}
    ret.jobId = root.jobId
    runOnAll(root, function()
      if root.type == "ITEM" then
        ret.toUse[root.name] = (ret.toUse[root.name] or 0) + root.count
        print("item", ret.toUse[root.name])
      elseif root.type == "MISSING" then
        ret.success = false
        ret.missing[root.name] = (ret.missing[root.name] or 0) + root.count
      elseif root.type ~= "ROOT" then
        ret.toCraft[root.name] = (ret.toCraft[root.name] or 0) + (root.count or 0)
      end
    end)
    return ret
  end

  ---Request a craft job, returning info about it
  ---@param name string
  ---@param count integer
  ---@return jobInfo
  local function requestCraft(name,count)
    local jobID = createCraftJob(name,count)
    craftLogger:debug("Request craft called for %u %s(s), returning job ID %u", count, name, jobID)
    return getJobInfo(pendingJobs[jobID])
  end

  ---Start a given job, if it's pending
  ---@param jobId JobId
  ---@return boolean success
  local function startCraft(jobId)
    craftLogger:debug("Start craft called for job ID %u", jobId)
    local job = pendingJobs[jobId]
    if not job then
      return false
    end
    local jobInfo = getJobInfo(job)
    if not jobInfo.success then
      return false -- cannot start unsuccessful job
    end
    pendingJobs[jobId] = nil
    jobLookup[jobId] = {}
    runOnAll(job, function(node)
      taskLookup[node.taskId] = node
      table.insert(jobLookup[jobId], node)
    end)
    updateWholeTree(job)
    return true
  end

  local function jsonFileImport()
    print("JSON file importing ready..")
    while true do
    local e, transfer = os.pullEvent("file_transfer")
      for _,file in ipairs(transfer.getFiles()) do
        local contents = file.readAll()
        local json = textutils.unserialiseJSON(contents)
        if json then
          loadJson(json)
        end
        file.close()
      end
    end
  end

  return {
    start = function()
      parallel.waitForAny(tickCrafting, inventoryTransferListener, jsonFileImport)
    end,

    requestCraft = requestCraft,
    startCraft = startCraft,
    loadJson = loadJson,
    listCraftables = listCraftables,
    cancelCraft = cancelCraft,

    recipeInterface = {
      changeNodeState = changeNodeState,
      tickNode = tickNode,
      getBestItem = getBestItem,
      getStackSize = getStackSize,
      mergeInto = mergeInto,
      craft = craft,
      pushItems = pushItems,
      addCraftingHandler = addCraftingHandler,
      addReadyHandler = addReadyHandler,
      addCraftType = addCraftType,
      deleteNodeChildren = deleteNodeChildren,
      deleteTask = deleteTask,
      getOrCacheString = getOrCacheString,
      addJsonTypeHandler = addJsonTypeHandler,
      addCraftableList = addCraftableList
    }
  }
end
}