# `modem.lua`
This module uses `interface.lua` to provide the generic methods over modem. `clients/modemLib.lua` is a simple wrapper for this interface.

## Interface Information
This does not provide any interface methods other than `start`.

## Internal Information
The interface is very simple, a table containing a `destination`, `protocol`, and `source` is sent from the client to the host, and the host sends one back containing the same `protocol`. 

Specifically the `"storage_system_protocol"` protocol expects a `method` and `args` sent to `"HOST"`. It will then send a message back on the given response channel with the same `method` and the return value packed in `response`.