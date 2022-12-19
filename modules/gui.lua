--- gui module built with basalt
local basalt = require("basalt")
-- this is dumb
basalt.setTheme({
  BasaltBG = colors.lightGray,
  BasaltText = colors.black,
  FrameBG = colors.lightGray,
  FrameText = colors.black,
  ButtonBG = colors.gray,
  ButtonText = colors.black,
  CheckboxBG = colors.gray,
  CheckboxText = colors.black,
  InputBG = colors.gray,
  InputText = colors.black,
  TextfieldBG = colors.gray,
  TextfieldText = colors.black,
  ListBG = colors.gray,
  ListText = colors.black,
  MenubarBG = colors.gray,
  MenubarText = colors.black,
  DropdownBG = colors.gray,
  DropdownText = colors.black,
  RadioBG = colors.gray,
  RadioText = colors.black,
  SelectionBG = colors.black,
  SelectionText = colors.lightGray,
  GraphicBG = colors.black,
  ImageBG = colors.black,
  PaneBG = colors.black,
  ProgramBG = colors.black,
  ProgressbarBG = colors.gray,
  ProgressbarText = colors.black,
  ProgressbarActiveBG = colors.black,
  ScrollbarBG = colors.lightGray,
  ScrollbarText = colors.gray,
  ScrollbarSymbolColor = colors.black,
  SliderBG = false,
  SliderText = colors.gray,
  SliderSymbolColor = colors.black,
  SwitchBG = colors.lightGray,
  SwitchText = colors.gray,
  SwitchBGSymbol = colors.black,
  SwitchInactive = colors.red,
  SwitchActive = colors.green,
  LabelBG = false,
  LabelText = colors.black,
  GraphBG = colors.gray,
  GraphText = colors.black
})
local function asText(v)
  if type(v) == "table" then
    return textutils.serialise(v,{compact=true})
  end
  return v
end
local common = require("common")
return {
id = "gui",
version = "INDEV",
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
  tabBar:onChange(function (self, event, button, x, y)
    for k,v in pairs(tabs) do
      v.frame:hide()
    end
    tabs[self:getItemIndex()].frame:show()
  end)
  local confList = conf:addList():setPosition(2,2):setSize("parent.w-2","parent.h/2-2")
  local confInfo = conf:addLabel():setPosition(2,"parent.h/2"):setSize("parent.w-2","parent.h/2-7")
  local confType = conf:addLabel():setPosition(2, "parent.h-6"):setSize("parent.w-2",1)
  local confInput = conf:addInput():setPosition(2,"parent.h-5"):setSize("parent.w-2",1)
  local confSetButton = conf:addButton():setPosition(2, "parent.h-3"):setSize("parent.w-2",1):setText("Set")
  local confResetButton = conf:addButton():setPosition(2, "parent.h-1"):setSize("parent.w-2",1)
  -- populate config menu
  for k,v in pairs(config) do
    for name,option in pairs(v) do
      confList:addItem(("%s.%s=%s"):format(k,name,asText(option.value)), nil, nil, option)
    end
  end

  confList:onChange(function(self)
    local option = self:getItem(self:getItemIndex()).args[1]
    confInfo:setText(option.description)
    local inputValue
    if type(option.value) == "table" then
      inputValue = textutils.serialize(option.value,{compact=true})
    else
      inputValue = option.value
    end
    confInput:setValue(inputValue)
    confResetButton:setText(("Reset (default=%s)"):format(asText(option.default)))
    confType:setText(("Type=%s"):format(option.type))
  end)

  confSetButton:onClick(function(self,x,y)
    local selectedItem = confList:getItem(confList:getItemIndex())
    if selectedItem then
      local selectedConfig = selectedItem.args[1]
      if loaded.config.interface.set(selectedConfig, confInput:getValue()) then
        confList:editItem(confList:getItemIndex(),
        ("%s.%s=%s"):format(selectedConfig.id,selectedConfig.name,textutils.serialize(selectedConfig.value,{compact=true})),
        nil, nil, selectedConfig)
        loaded.config.interface.save()
      end
    end
  end)

  confResetButton:onClick(function()
    local selectedItem = confList:getItem(confList:getItemIndex())
    if selectedItem then
      local selectedConfig = selectedItem.args[1]
      loaded.config.interface.set(selectedConfig, selectedConfig.default)
      confList:editItem(confList:getItemIndex(),
      ("%s.%s=%s"):format(selectedConfig.id,selectedConfig.name,textutils.serialize(selectedConfig.value,{compact=true})),
      nil, nil, selectedConfig)
      loaded.config.interface.save()
    end
  end)

  for k,v in pairs(loaded) do
    if v.interface and v.interface.gui then
      local frame = main:addFrame():setSize("parent.w", "parent.h-1"):setPosition(1,2):hide()
      table.insert(tabs, {frame = frame, name = k})
      v.interface.gui(frame)
    end
  end

  for k,v in pairs(tabs) do
    tabBar:addItem(v.name)
  end

  return {
  start = function()
    _G.loaded = loaded
    debg:addProgram():setSize("parent.w", "parent.h"):setPosition(1,1):execute("shell")
    basalt.autoUpdate()
  end
  }
end
}