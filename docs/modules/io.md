---
title: "`io.lua`"
parent: Modules
---

# `io.lua`

This module provides highly configurable i/o capabilities to your MISC system.

## Configuration

This module provides importing and exporting options.

To import items simply add an entry to the `io.import` value with the following fields.

- `inventory: string` The inventory to import from
- `slots: integer[] | {min:integer, max:integer}?` Either a list of slots, or a range of slots to import from. If not present import from the entire inventory (requires inventory peripheral for autodetection).
- `whitelist: string[]?` Optional whitelist, if not present import all items. (requires inventory peripheral)
- `blacklist: string[]?` Optional blacklist. (requires inventory peripheral)
- `min: integer?` Optional, minimum number of free slots the storage should have to import from here.

To export items simply add an entry to the `io.export` value with the following fields

- `inventory: string` The inventory to export to
- `name: string` The item name to export
- `nbt: string?` Optional item nbt
- `min: integer?` Optional, do not export unless there are at least `min` of this item in the storage.
- `slots: integer[] | {min:integer, max:integer}?` Either a list of slots, or a range of slots to import from. If not present export to the entire inventory (requires inventory peripheral for autodetection).
