# `interface.lua`
This module is a generic function interface for general, generic interface formats and protocols. The only current module that uses this is `modem.lua`. This module does not do anything beyond provide the methods, any other desired functionality (i.e. user authentification, privilages, etc) should be handled by another module.

## Interface Information
To call an interface method, use `interface.interface.callMethod`.

The `genericInterface.list` method returns a table nicer for general use, it is an array of tables with the following contents.
* `name` Item ID of the name
* `nbt` NBT hash of the item (or `"NONE"`)
* `count` Total count of this item in the system
It will also contain any other information `getItemDetail` would for that item. For example `enchantments` or `displayName`. This list will only contain one entry for each item.

If your interface wishes to provide updates for `"inventoryUpdate"` events use `interface.addInventoryUpdateHandler`. This will pass the result of `genericInterface.list` into your function anytime the inventory contents change.

## Internal Information
Adding an interface method is very simple, just add the function to `genericInterface`.