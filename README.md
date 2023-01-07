# MISC - Modular Inventory Storage and Crafting

# Setup
A minimal MISC system consists of
* A single computer running MISC
* Any number of connected inventories
* (Optionally) A client access terminal

Functionality can be extended by attaching more devices to the network, and adding appropriate modules.
For example, grid crafting functionality can be added by adding the following modules.
* Crafting planner and executor `/modules/crafting.lua`
* Grid crafting provider `/modules/grid.lua`
You'll need some recipes, you can start with `/recipes/*`.

Then adding as many crafty turtles running `/clients/crafter.lua` as you'd like.

## MISC Server
To install the MISC server, you will need the following files.
* The main executable, `storage.lua`
* The modules you'd like in `/modules/`, (`/modules/inventory.lua` and `abstractInvLib.lua` are required)
  * TODO add detail about changing module load order
* The shared library, `common.lua`

## MISC Terminal Client
To install the MISC terminal, attach a turtle to your MISC network and install the following files. These can both be installed to the root of the drive.
* The terminal executable `clients/terminal.lua`
* The generic modem interface library `clients/modem_lib.lua`

You'll also require a few additional modules on the MISC server
* Generic interface handler `/modules/interface.lua`
* Modem interface protocol `/modules/modem.lua`

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

# Module Specific Documentation

## `modules/inventory.lua`
This module is the backbone of the *storage* system. It uses `abstractInvLib` to manage the main storage capacity of the network. This module also manages a queue of transfers, so they may be done asyncronously and in bulk.

This module provides all method provided by `abstractInvLib`. But `pushItems` and `pullItems` take an additional boolean argument before the normal args, signifying whether to do the transfer asyncronously. For most purposes you should not do transfers syncronously.

## `modules/logger.lua`
This module provides a logging object constructor at `loaded.logger.interface.logger`

## `modules/interface.lua`
This module provides a generic external interface api. Currently the only interface is `modules/modem.lua`

## `modules/crafting.lua`
This module handles crafting, including generating crafting trees automatically from a given item name.

It also provides an interface for custom crafting providers. The only current crafting provider is `modules/grid.lua` which provides grid crafting.