local monitorSide = "top"


local lib = require("modemLib")
local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)