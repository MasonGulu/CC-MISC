---
title: Modules
has_children: true
nav_order: 2
---
# Modules
Modules are the main way to customize the storage system and add functionality. `storage.lua` is the entrypoint and loader for your configured modules.

There are 3 ways to load modules. 
* Running `storage.lua` without args will scan `/modules/` and load all `.lua` files in there as modules.
* Pass in a filename as the first arg to read a newline seperated list of modules to load from the file.
  * Supports paths with `/` or `.`, and supports including or excluding `.lua` (but you should exclude it anyways).
* Pass in a folder as the first arg to load all `.lua` files in that folder as modules.

Module load order is automatically determined.

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
dependencies = { -- this table is optional, but if you don't include something you're dependant on it may be loaded out of order.
  inventory = {
    min = "1.0", -- this is checked against the first two "numbers" of the module semver. By default the MINOR version is allowed to be anything greater than provided, and MAJOR must be same as provided.
    max = "1.5", -- If you set a maximum version you *can* allow higher MAJOR versions. But this isn't required.
    optional = true, -- you can choose to make this dependency optional, if it's optional this will only effect load order.
  }
}
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

Next the module load order is determined based off each modules' defined `dependencies`.

The third thing done is to load and validate the config.

Then each module's `init` function is called, and anything returned is placed into the `interface` key.

Then to conclude each module that provided a `start` function in the `interface` is called in parallel.