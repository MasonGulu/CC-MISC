---
title: Modules
has_children: true
nav_order: 2
---
# Modules
Modules are the main way to customize the storage system and add functionality. `storage.lua` is the entrypoint and loader for your configured modules.

Currently, to configure the modules you want to have selected edit the `modules` table at the top of `storage.lua`. I am planning on replacing this

# Development information
The entrypoint, `storage.lua` is nothing more than a module and config loader.
An example of a module this would load is as follows.
```lua
return {
id = "example",
version = "0.0.1",
config = {
  name = {
    type = "string", -- any serializable lua type is allowed here
    description = "A string configuration option.",
    default = "default",
    -- when this is loaded and passed into init the value of this option will be at ["value"]
  }
},
-- This function is optional. If present, this function will be called whenever a nil config option is encountered in this module's settings.
-- The moduleConfig passed in is the config settings for this specific module.
-- It is asserted that all settings are set to valid values when this function returns.
setup = function(moduleConfig) end,

-- This function is not required, but a warning will be printed if it is not present.
-- loaded is the module environment (more below)
-- config is the config environment (more below)
init = function(loaded, config)
  local interface = {}

  -- This function is optional, if present this will be executed in parallel with all other modules.
  function interface.start = function() end

  return interface
end
}
```

## Module environment
Modules are loaded using `require`, the table they return are placed into `modules[id]`.
Everything initially returned by the module should be stateless, all state is achieved by providing the `init` function.
To enable inter-module communication the value returned by the `init` function is placed into `modules[id].interface`.

There is one module that is artificially provided by `storage.lua`, there are various config functions located at `modules.config.interface`.

## Config environment
Whenever a module has `config` defined as a table, that table is placed into the config environment at `config[id]`. 
Then after all modules are loaded the config file is loaded, and all config options are verified before the initialization stage begins.
Each config options's value is then stored at `value`.

## Module load stages
There are multiple stages in module loading. Loading, config loading, initializing, and executing.

The first thing done is to load each module, all that happens here is each module is `require`'d and stuck into the `modules` table

The second thing done is to load and validate the config.

Then each module's `init` function is called, and anything returned is placed into the `interface` key.

Then to conclude each module that provided a `start` function in the `interface` is called in parallel.