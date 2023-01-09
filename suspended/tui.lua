local version = "INDEV"
return {
id = "tui",
version = version,
init = function (loaded, config)
  ---@param options table<string,string>
  ---@return string
  local function get_char_selection(options)
    for k,v in pairs(options) do
      print(("[%s]%s"):format(k:upper(),v))
    end
    while true do
      local e = {os.pullEvent("char")}
      if options[e[2]] then
        return e[2]
      end
    end
  end
  local function get_string_selection(options)
    for k,v in pairs(options) do
      print(("[%s]%s"):format(k,v))
    end
    while true do
      local i = io.read()
      if options[i] then
        return i
      end
    end
  end
  local function get_int_selection(options)
    for k,v in ipairs(options) do
      print(("[%u]%s"):format(k,v))
    end
    while true do
      local i = tonumber(io.read())
      if options[i] then
        return i
      end
    end
  end
  local old_fg, old_bg
  local function set(fg,bg)
    old_fg, old_bg = old_fg or term.getTextColor(), old_bg or term.getBackgroundColor()
    if fg then
      term.setTextColor(fg)
    end
    if bg then
      term.setBackgroundColor(bg)
    end
  end
  local function revert()
    term.setTextColor(old_fg)
    term.setBackgroundColor(old_bg)
    old_bg, old_fg = nil, nil
  end
  local function printf(f,...)
    print(f:format(...))
  end
  return {
    start = function ()
      set(colors.yellow)
      printf("TUI v%s", version)
      while true do
        set(colors.yellow)
        print("Make your selection from the list below.")
        revert()
        local selection = get_char_selection({
          l = "Enter lua prompt and add loaded to _G",
          m = "Module settings"
        })
        if selection == "l" then
          local old_loaded = _G.loaded
          _G.loaded = loaded
          shell.run("lua")
          _G.loaded = old_loaded
        end
      end
    end
  }
end
}