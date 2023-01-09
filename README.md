# MISC - Modular Inventory Storage and Crafting
PRs are welcome to this project, I hope the documentation is clear enough, but if you have any questions feel free to ask.

This documentation is also available at misc.madefor.cc

The directory structure of this project is as follows
* `clients/` client programs and libraries
* `modules/` all ready to use modules
* `recipes/` all vanilla grid recipes stored in custom binary format
* `suspended/` modules which development has been suspended on
* `common.lua` common library file (that should be split up in the future)
* `abstractInvLib.lua` local copy of [`abstractInvLib.lua`](https://gist.github.com/MasonGulu/57ef0f52a93304a17a9eaea21f431de6) to ease development, will eventually be removed
* `storage.lua` entrypoint and module loader

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
* The modules you'd like in `/modules/`, (`/modules/inventory.lua` is required)
  * Currently module load order and setup is defined at the top of `storage.lua`. Simply add the modules you'd like to load to the `modules` table.
* The shared library, `common.lua`
* [`abstractInvLib.lua`](https://gist.github.com/MasonGulu/57ef0f52a93304a17a9eaea21f431de6) For ease of development there is currently a copy in this repository.

## MISC Terminal Client
To install the MISC terminal, attach a turtle to your MISC network and install the following files. These can both be installed to the root of the drive.
* The terminal executable `clients/terminal.lua`
* The generic modem interface library `clients/modem_lib.lua`

You'll also require a few additional modules on the MISC server
* Generic interface handler `/modules/interface.lua`
* Modem interface protocol `/modules/modem.lua`

# Module Specific Documentation
Look in `/docs/` for development and module specific documentation.