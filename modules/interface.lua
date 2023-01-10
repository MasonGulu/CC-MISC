local common = require "common"
---@class modules.interface
---@field interface modules.interface.interface
return {
id="interface",
version="1.1.0",
dependencies = {
  inventory = {min="1.1"},
  crafting = {optional=true, min="1.1"},
  grid = {optional=true, min="1.1"},
},
---@param loaded {inventory: modules.inventory, crafting: modules.crafting|nil, grid: modules.grid|nil}
init=function (loaded,config)
  loaded = loaded
  local genericInterface = {}
  ---Push items to an inventory
  ---@param async boolean
  ---@param targetInventory string
  ---@param name string|number
  ---@param amount nil|number
  ---@param toSlot nil|number
  ---@param nbt nil|string
  ---@param options nil|TransferOptions
  ---@return integer|string count
  function genericInterface.pushItems(async,targetInventory, name, amount, toSlot, nbt, options)
    return loaded.inventory.interface.pushItems(async,targetInventory,name,amount,toSlot,nbt,options)
  end

  ---Pull items from an inventory
  ---@param async boolean
  ---@param fromInventory string|AbstractInventory
  ---@param fromSlot string|number
  ---@param amount nil|number
  ---@param toSlot nil|number
  ---@param nbt nil|string
  ---@param options nil|TransferOptions
  ---@return integer|string count
  function genericInterface.pullItems(async,fromInventory, fromSlot, amount, toSlot, nbt, options)
    return loaded.inventory.interface.pullItems(async, fromInventory, fromSlot, amount, toSlot, nbt, options)
  end

  ---List the items in this storage
  ---@return {name:string, nbt:string, count:integer}
  function genericInterface.list()
    local list = {}
    local names = loaded.inventory.interface.listNames()
    for _,name in pairs(names) do
      local nbts = loaded.inventory.interface.listNBT(name)
      for _,nbt in pairs(nbts) do
        local item = loaded.inventory.interface.getItem(name,nbt)
        if item then
          local itemClone = {}
          for k,v in pairs(item.item) do
            itemClone[k] = v
          end
          itemClone.name = name
          itemClone.nbt = nbt
          itemClone.count = loaded.inventory.interface.getCount(name,nbt)
          table.insert(list,itemClone)
        end
      end
    end
    return list
  end

  ---Flush the transfer queue immediately
  function genericInterface.performTransfer()
    loaded.inventory.interface.performTransfer()
  end

  ---List the craftable items in the inventory
  ---@return string[]
  function genericInterface.listCraftables()
    if not loaded.crafting then
      return {}
    end
    return loaded.crafting.interface.listCraftables()
  end

  ---Request a craft
  ---@param name string
  ---@param count integer
  ---@return table
  function genericInterface.requestCraft(name, count)
    common.enforceType(name,1,"string")
    common.enforceType(count,2,"integer")
    if not loaded.crafting then
      return {} -- TODO define better behavior for when a module is not loaded
    end
    return loaded.crafting.interface.requestCraft(name,count)
  end

  ---Start a craft job
  ---@param jobID string
  ---@return boolean
  function genericInterface.startCraft(jobID)
    common.enforceType(jobID,1,"string")
    if not loaded.crafting then
      return false
    end
    return loaded.crafting.interface.startCraft(jobID)
  end

  ---Cancel a craft job
  ---@param jobID string
  function genericInterface.cancelCraft(jobID)
    common.enforceType(jobID,1,"string")
    if not loaded.crafting then
      return
    end
    return loaded.crafting.interface.cancelCraft(jobID)
  end

  ---Add a grid recipe manually
  ---@param name string
  ---@param produces integer
  ---@param recipe string[] table of ITEM NAMES, this does NOT support tags
  ---@param shaped boolean
  function genericInterface.addGridRecipe(name,produces,recipe,shaped)
    common.enforceType(name,1,"string")
    common.enforceType(produces,2,"integer")
    common.enforceType(recipe, 3, "string[]")
    common.enforceType(shaped,4,"boolean")
    if not loaded.grid then
      return false
    end
    return loaded.grid.interface.addGridRecipe(name,produces,recipe,shaped)
  end

  ---Remove a grid recipe
  ---@param name string
  ---@return boolean
  function genericInterface.removeGridRecipe(name)
    common.enforceType(name,1,"string")
    if not loaded.grid then
      return false
    end
    return loaded.grid.interface.removeGridRecipe(name)
  end

  ---Get the slot usage of this inventory
  ---@return {free: integer, used:integer, total:integer}
  function genericInterface.getUsage()
    return loaded.inventory.interface.getUsage()
  end

  local interface = {}
  local inventoryUpdateHandlers = {}
  ---Add a handler for the inventoryUpdate event
  ---@param handler fun(list: table)
  function interface.addInventoryUpdateHandler(handler)
    common.enforceType(handler,1,"function")
    table.insert(inventoryUpdateHandlers, handler)
  end
  ---Poll for inventoryUpdate events, and distribute to all inventoryUpdateHandlers
  local function inventoryUpdateHandler()
    while true do
      os.pullEvent("inventoryUpdate")
      local list = genericInterface.list()
      for _, f in pairs(inventoryUpdateHandlers) do
        f(list)
      end
    end
  end
  ---Call a genericInterface method by name
  ---@param method string
  ---@param args table
  ---@return ...
  function interface.callMethod(method, args)
    common.enforceType(method,1,"string")
    local desiredMethod = genericInterface[method]
    assert(desiredMethod, method.." is not a valid method")
    return desiredMethod(table.unpack(args, 1, args.n))
  end
  function interface.start()
    inventoryUpdateHandler()
  end
  ---@class modules.interface.interface
  return interface
end
}