local PROTOCOL = "STORAGE"
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
  }
},
init = function(loaded, config)
  local interface = {}
  assert(loaded.interface, "rednet requires interface to be loaded")
  local modem = assert(peripheral.wrap(config.rednet.modem.value), "Invalid modem provided.")
  rednet.open(config.rednet.modem.value)
  rednet.host(PROTOCOL, config.rednet.hostname.value)

  local subscribed = {}
  local function handleUpdate(list)
    for id, _ in pairs(subscribed) do
      print("updating",id)
      rednet.send(id, {method="update",value=list}, PROTOCOL)
    end
  end
  loaded.interface.interface.addInventoryUpdateHandler(handleUpdate)

  interface.start = function()
    while true do
      local from, msg, protocol = rednet.receive(PROTOCOL)
      if type(msg) == "table" and msg.method then
        if msg.method == "subscribe" then
          subscribed[from] = true
          rednet.send(from, {method=msg.method,success=true}, PROTOCOL)
        elseif msg.method == "unsubscribe" then
          subscribed[from] = nil
          rednet.send(from, {method=msg.method,success=true}, PROTOCOL)
        else
          local val = loaded.interface.interface.callMethod(msg.method,msg.args)
          rednet.send(from, {method=msg.method,success=true,value=val}, PROTOCOL)
        end
      else
        rednet.send(from,{success=false},PROTOCOL)
      end
    end
  end
  return interface
end
}