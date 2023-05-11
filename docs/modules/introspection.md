---
title: "`introspection.lua`"
parent: Modules
---

# `introspection.lua`

This module uses `interface.lua` to provide the generic methods over a websocket connection hosted using https://github.com/SkyTheCodeMaster/cc-websocket-bridge. `clients/websocketLib.lua` is a simple wrapper for this interface.

To setup a websocket connection you will need some host. SkyCrafter0 has one such host at `wss://ccws.skystuff.cc/connect/<channel name>/[password]`. As the brackets suggest you will need to provide a channel name and optionally a password. If you are the first to connect to a channel you get to set the password, if you don't set one the channel will stay open.

## Interface Information

This does not provide any interface methods other than `start`.
