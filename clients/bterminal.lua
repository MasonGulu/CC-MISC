local basalt = require("basalt")

local main = basalt.createFrame():addLayout("clients/bterminal.xml")

local itemList = main:getDeepObject("itemList")
local search = main:getDeepObject("search")
local count = main:getDeepObject("count")
local mode = main:getDeepObject("mode")
mode:onClick(function(self,event,button,x,y)

end)

basalt.autoUpdate()