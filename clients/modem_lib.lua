local lib = {}

local modem
local name

local host_port = 50
local update_port = 51
local resp_port = 50
local timeout = 3000

local function validate_message(message)
  local valid = type(message) == "table" and message.protocol ~= nil
  valid = valid and (message.destination == name or message.destination == "*")
  valid = valid and message.source ~= nil
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
---Connect to the storage system
function lib.connect(modem_name)
  modem = assert(peripheral.wrap(modem_name), "Invalid modem.")
  modem.open(resp_port)
  name = modem.getNameLocal()
end
---Call a method remotely on the storage module
---@param method string
---@param ... any
local function storage(method, ...)
  local message = {
    method = method,
    args = table.pack(...),
    protocol = "storage_system_modem",
    source = name,
    destination = "HOST"
  }
  modem.transmit(host_port, resp_port, message)
  local wait_start = os.epoch("utc")
  while true do
    local event = get_modem_message(validate_message, 2)
    if event then
      message = event.message
      if message.protocol == "storage_system_modem" and message.method == method then
        return table.unpack(message.response)
      end
    end
    if wait_start + timeout < os.epoch("utc") then
      error("Response timed out.", 2)
    end
  end
end
---Pull items from an inventory
---@param fromInventory string|AbstractInventory
---@param fromSlot string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pullItems(fromInventory, fromSlot, amount, toSlot, nbt, options)
  return storage("pullItems",fromInventory, fromSlot, amount, toSlot, nbt, options)
end

---Push items to an inventory
---@param targetInventory string
---@param name string|number
---@param amount nil|number
---@param toSlot nil|number
---@param nbt nil|string
---@param options nil|TransferOptions
function lib.pushItems(targetInventory, name, amount, toSlot, nbt, options)
  return storage("pushItems",targetInventory, name, amount, toSlot, nbt, options)
end

---List inventory contents
function lib.list()
  return storage("list")
end

---Subscribe to transfers
function lib.subscribe()
  modem.open(update_port)
  while true do
    local event = get_modem_message(validate_message)
    assert(event, "Got no event")
    if event.message.protocol == "storage_system_update" then
      os.queueEvent("update", event.message.list)
    end
  end
end

return lib