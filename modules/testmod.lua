return {
  id = "TEST",
  version = "TEST",
  init = function(loaded, config)
    return {
      start = function()
        local inv = require("abstractInvLib")({"minecraft:chest_0"})
        inv.refreshStorage()
        local tmp = {}
        for i = 1, 9 do
          table.insert(tmp, function ()
            print(loaded.inventory.interface.pushItems(false, inv, "minecraft:stone"))
          end)
        end
        parallel.waitForAll(table.unpack(tmp))
      end
    }
  end
}