--- gui module built with basalt
local basalt = require("basalt")
local common = require("common")
return {
id = "gui",
version = "INDEV",
config = {
  test1 = {type="string",default="???"},
  test2 = {type="string",default="???"},
  test3 = {type="string",default="???"}
},
init = function(loaded, config)
  local main = assert(basalt.createFrame())
  local conf = main:addFrame():setSize("parent.w", "parent.h-1"):setPosition(1,2):hide()
  local debg = main:addFrame():setSize("parent.w", "parent.h-1"):setPosition(1,2):hide()
  -- setup top navbar
  local tabs = {
    {name = "config", frame = conf},
    {name = "debug", frame = debg},
  }
  tabs[1].frame:show()
  local tabBar = main:addMenubar():setSize("parent.w", 1):setPosition(1,1)
  for k,v in pairs(tabs) do
    tabBar:addItem(v.name)
  end
  tabBar:onChange(function (self, event, button, x, y)
    for k,v in pairs(tabs) do
      v.frame:hide()
    end
    tabs[self:getItemIndex()].frame:show()
  end)
  local confList = conf:addList():setPosition(2,2):setSize("parent.w-2","parent.h/2-2")
  local confInfo = conf:addLabel():setPosition(2,"parent.h/2"):setSize("parent.w-2","parent.h/2-2"):setText("Hell?")
  -- populate config menu
  for k,v in pairs(config) do
    for name,option in pairs(v) do
      confList:addItem(("%s.%s=%s"):format(k,name,textutils.serialize(option.value,{compact=true})), nil, nil, option)
    end
  end
  --- TODO
  -- add change setting button
  -- update setting list entry when value changes
  -- add better handling for tables

  confList:onChange(function(self)
    local option = self:getItem(self:getItemIndex()).args[1]
    confInfo:setText(option.description)
  end)

  return {
  start = function()
    _G.loaded = loaded
    debg:addProgram():setSize("parent.w", "parent.h"):setPosition(1,1):execute("shell")
    basalt.autoUpdate()
  end
  }
end
}