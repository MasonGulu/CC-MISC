--- Furnace crafting recipe handler
---@class modules.furnace
return {
id = "furnace",
version = "0.0.0",
config = {
    fuels = {
        type="table",
        description = "List of fuels table<item: string,smelts: integer>",
        default = {["minecraft:coal"]=8,["minecraft:charcoal"]=8}
    },
    checkFrequency = {
        type="number",
        description="Time in seconds to wait between checking each furnace",
        default=5
    }
},
dependencies = {
    logger = {min="1.1",optional=true},
    crafting = {min="1.4"},
    inventory = {min="1.2"}
},
---@param loaded {crafting: modules.crafting, logger: modules.logger|nil, inventory: modules.inventory}
init = function (loaded,config)

    local crafting = loaded.crafting.interface.recipeInterface
    ---@type table<string,string> output->input
    local recipes = {}

    local bfile = require("bfile")
    local structFurnaceRecipe = bfile.newStruct("furnace_recipe"):add("string", "output"):add("uint16","input")

    local function updateCraftableList()
        local list = {}
        for k,v in pairs(recipes) do
            table.insert(list, k)
        end
        crafting.addCraftableList("furnace", list)
    end

    local function saveFurnaceRecipes()
        local f = assert(fs.open("recipes/furnace_recipes.bin", "wb"))
        f.write("FURNACE0") -- "versioned"
        for k,v in pairs(recipes) do
            structFurnaceRecipe:writeHandle(f,{
                input=crafting.getOrCacheString(v),
                output=k
            })
        end
        f.close()
        updateCraftableList()
    end

    local function loadFurnaceRecipes()
        local f = fs.open("recipes/furnace_recipes.bin", "rb")
        if not f then
            recipes = {}
            return
        end
        assert(f.read(8) == "FURNACE0", "Invalid furnace recipe file.")
        while f.read(1) do
            f.seek(nil, -1)
            local recipeInfo = structFurnaceRecipe:readHandle(f)
            _, recipes[recipeInfo.output] = crafting.getBestItem(recipeInfo.input)
        end
        f.close()
        updateCraftableList()
    end

    local function jsonTypeHandler(json)
        local input = json.ingredient.item
        local output = json.result
        recipes[output] = input
        saveFurnaceRecipes()
    end
    crafting.addJsonTypeHandler("minecraft:smelting", jsonTypeHandler)

    ---Get a fuel for an item, and how many items is optimal if toSmelt is provided
    ---@param toSmelt integer? ensure there's enough of this fuel to smelt this many items
    ---@return string fuel
    ---@return integer multiple
    ---@return integer optimal
    local function getFuel(toSmelt)
        local name, multiple = next(config.furnace.fuels.value) -- TODO add logic for this
        return name, multiple, (math.ceil((toSmelt or 0)/ multiple) * multiple)
    end

    ---@class FurnaceNode : CraftingNode
    ---@field type "furnace"
    ---@field done integer count smelted
    ---@field multiple integer fuel multiple
    ---@field fuel string
    ---@field ingredient string
    ---@field smelting table<string,integer> amount to smelt in each furnace


    local function getMaxFurnaces(items, furnaceCount)
        while items % furnaceCount ~= 0 do
            furnaceCount = furnaceCount - 1
        end
        return furnaceCount
    end

    ---@type string[]
    local attachedFurnaces = {}
    for _, v in ipairs(peripheral.getNames()) do
        if peripheral.hasType(v, "minecraft:furnace") then
            attachedFurnaces[#attachedFurnaces+1] = v
        end
    end

    ---@param node FurnaceNode
    ---@param name string
    ---@param count integer
    ---@param requestChain table Do not modify, just pass through to calls to craft
    ---@return boolean
    local function craftType(node,name,count,requestChain)
        local requires = recipes[name]
        if not requires then
            return false
        end
        local fuel, multiple, toCraft = getFuel(count) --[[@as integer]]
        node.type = "furnace"
        node.count = toCraft
        node.done = 0
        node.children = crafting.craft(requires, toCraft, node.jobId, nil, requestChain)
        node.ingredient = requires
        node.fuel = fuel --[[@as string]]
        node.multiple = multiple
        node.smelting = {}
        node.children = crafting.craft(fuel --[[@as string]], math.floor(toCraft / multiple), node.jobId, false, requestChain)
        return true
    end
    crafting.addCraftType("furnace", craftType)


    ---@type table<FurnaceNode,FurnaceNode>
    local smelting = {}

    ---@param node FurnaceNode
    local function readyHandler(node)
        if #attachedFurnaces > 0 then
            local countFurnaces = getMaxFurnaces(node.count, #attachedFurnaces)
            local toSmelt = math.floor(node.count / countFurnaces)
            local fuelNeeded = math.floor(toSmelt / node.multiple)
            for i = 1, countFurnaces do
                local furnace = table.remove(attachedFurnaces, 1)
                local absFurnace = require("abstractInvLib")({furnace})
                loaded.inventory.interface.pushItems(false, absFurnace, node.fuel, fuelNeeded, 2)
                local moved = loaded.inventory.interface.pushItems(false, absFurnace, node.ingredient, toSmelt, 1)
                node.smelting[furnace] = toSmelt - moved
            end
            crafting.changeNodeState(node, "CRAFTING")
            smelting[node] = node
        end
    end
    crafting.addReadyHandler("furnace", readyHandler)

    local function craftingHandler(node)
        
    end
    crafting.addCraftingHandler("furnace", craftingHandler)

    ---@param node FurnaceNode
    local function checkNodeFurnaces(node)
        for furnace, remaining in pairs(node.smelting) do
            local absFurnace = require("abstractInvLib")({furnace})
            local crafted = loaded.inventory.interface.pullItems(false, absFurnace, 3)
            node.done = node.done + crafted
            if remaining > 0 then
                local amount = loaded.inventory.interface.pushItems(false, absFurnace, node.ingredient, remaining, 1)
                remaining = remaining - amount
            end
        end
        if node.done == node.count then
            crafting.changeNodeState(node, "DONE")
        end
    end

    local function furnaceChecker()
        while true do
            sleep(config.furnace.checkFrequency.value)
            for node in pairs(smelting) do
                checkNodeFurnaces(node)
            end
        end
    end

    return {
        start = function()
            loadFurnaceRecipes()
            furnaceChecker()
        end
    }
end
}