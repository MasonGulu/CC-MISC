return {
  id = "rednet",
  version = "INDEV",
  config = {
    modem = {
      type = "string",
      description = "Modem to host rednet services over",
    },
    hostname = {
      type = "string",
      description = "Hostname to use for rednet services"
    },
    protocol = {
      type = "string",
      description = "Name of rednet protocol",
      default = "STORAGE",
    }
  },
init = function(loaded, config)
  local interface = {}
  local modem = assert(peripheral.wrap(config.rednet.modem.value), "Invalid modem provided.")
  rednet.open(config.rednet.modem.value)
  rednet.host("STORAGE", config.rednet.hostname.value)

  local messageLUT = {}
  messageLUT.list = function(id, message)
    -- TODO
  end
  ---Direct access to the inventory module
  messageLUT.pullItems = function(id, message)
    local response = {"pullItems", loaded.inventory.interface.pullItems(true, table.unpack(message, 1, 8))}
    rednet.send(id, response, "STORAGE")
  end

  interface.start = function()
    while true do
      local id, message = rednet.receive("STORAGE")
      print("recieved message")
      if messageLUT[message[1]] then
        print("???")
        messageLUT[message[1]](id, message)
      end
    end
  end
  return interface
end
}