---
title: '`logger.lua`'
parent: Modules
---
# `logger.lua`
This module provides a simple interface to log information. It supports 4 levels of logs (DEBUG, INFO, WARN, ERROR), and the minimum log level can be specified.

## Interface Information
To add a logger to your module you can follow this pattern
```lua
local logger = setmetatable({}, {__index=function () return function () end end})
if loaded.logger then
  logger = loaded.logger.interface.logger(id,label)
end
```
This will make your requirement of `logger` optional. Then you may simply log information like so
```lua
logger:debug("Some debug info!")
logger:info("Some information!")
logger:warn("A warning!")
logger:error("An error, %s", "by the way these all format strings")
```

## Internal Information
Metatables. There's not much going on here other than creating logging objects using meta
