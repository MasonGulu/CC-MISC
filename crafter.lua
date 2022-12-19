-- file to put on a turtle
local modem = peripheral.find("modem", function(name, modem)
  -- return not modem.isWireless()
  return true
end)
rednet.open(peripheral.getName(modem))
local network_name = "turtle_0"--modem.getNameLocal()
local STATES = {
  READY = "READY",
  ERROR = "ERROR",
  BUSY = "BUSY",
  CRAFTING = "CRAFTING",
}
local state = STATES.READY
local connected = false
local host_port = 121
local local_port = host_port
local keep_alive_timeout = 10
local w,h = term.getSize()
local banner = window.create(term.current(), 1, 1, w, 1)
local panel = window.create(term.current(),1,2,w,h-1)
term.redirect(panel)

modem.open(local_port)
local function validate_message(message)
  local valid = type(message) == "table" and message.protocol ~= nil
  valid = valid and (message.destination == network_name or message.destination == "*")
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
local function keep_alive()
  while true do
    local modem_message = get_modem_message(function(message)
      return validate_message(message) and message.protocol == "KEEP_ALIVE"
    end, keep_alive_timeout)
    connected = modem_message ~= nil
    if modem_message then
      modem.transmit(host_port, local_port, {
        protocol = "KEEP_ALIVE",
        state = state,
        source = network_name,
        destination = "HOST",
      })
    end
    local x, y = term.getCursorPos()

    banner.setBackgroundColor(colors.gray)
    banner.setCursorPos(1,1)
    banner.clear()
    if connected then
      banner.setTextColor(colors.green)
      banner.write("CONNECTED")
    else
      banner.setTextColor(colors.red)
      banner.write("DISCONNECTED")
    end
    term.setCursorPos(x,y)
    sleep(3)
  end
end
local function col_write(fg, text)
  local old_fg = term.getTextColor()
  term.setTextColor(fg)
  term.write(text)
  term.setTextColor(old_fg)
end
local interface_lut
interface_lut = {
  help = function()
    local maxw = 0
    for k,v in pairs(interface_lut) do
      maxw = math.max(maxw, k:len())
    end
    local element_w = math.floor(w / maxw)
    local format_str = "%s"
  end,
  clear = function()
    term.clear()
    term.setCursorPos(1,1)
  end
}
local function interface()
  print("Crafting turtle indev")
  while true do
    col_write(colors.cyan, "crft] ")
    local input = io.read()
    if interface_lut[input] then
      interface_lut[input]()
    else
      col_write(colors.red, "Invalid command.")
      print()
    end
  end
end

parallel.waitForAny(interface, keep_alive)