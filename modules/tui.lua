return {
id = "tui",
version = "INDEV",
init = function (loaded, config)
  return {
    start = function ()
      print("Entering lua prompt..")
      _G.loaded = loaded
      shell.run("lua")
    end
  }
end
}