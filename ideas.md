Each module returns a table
```lua
{
  version="1.0",
  id="example",
  requires={exampleRequirement="1.0"}, -- nil-able
  init=function(modules, config), -- returns a function
  config=ConfigSetupTable, -- nil-able
  ..., -- other interaction functions
}
```

Plugins can provide some config info to the config plugin through a ConfigSetupTable
```lua
{
  name = {
    default = "a default value", -- nil-able
    type = "string|nil", -- required
  },
  ...
}
```

When the plugin's `init` function is called two tables are passed in, the first is a table containing all the loaded modules at `id`. 

The second table is the config values, indexed by module id, then by setting name. 

`init` returns a table, this table is accessible from other modules at `modules[id].interface`, the function at `start` will be called to start execution of the module.

### Requirements for main storage module
Some way to queue transfers, this transfer queue should be cached.