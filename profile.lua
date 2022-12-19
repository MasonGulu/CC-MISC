--- This program will time the execution of a program you pass in
-- It takes a variety of arguments
-- Use the -help flag to see them all, or since you're in here, peek below.
-- The times reported do NOT include the time waiting for events. It is removed from ALL calculations and numbers.
-- This INCLUDES all times reported in the saved files

-- Copyright 2022 Mason Gulu
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


local args = {...}

local allowed_args = {
  csv = {type="value",description="file to output csv to"}, -- time -csv=file.out
  lua = {type="value",description="file to output lua table to"},
  json = {type="value",description="file to output json to"},
  nano = {type="flag",description="use nanoseconds (craftos-pc)"},
  hide = {type="flag",description="hide the program's window"},
  help = {type="flag",description="show this help"},
  limit = {type="value",description="# of yields to resume"},
}

-- the arguments without - before them
local var_args = {}

-- the recognized arguments passed into the program
local given_args = {}
for i = 1, #args do
  local v = args[i]
  if string.sub(v,1,1) == "-" then
    local full_arg_str = string.sub(v,2)
    for arg_name, arg_info in pairs(allowed_args) do
      if string.sub(full_arg_str,1,arg_name:len()) == arg_name then
        -- this is an argument that is allowed
        if arg_info.type == "value" then
          local arg_arg_str = string.sub(full_arg_str,arg_name:len()+1)
          assert(arg_arg_str:sub(1,1)=="=" and arg_arg_str:len() > 1, "Expected =<value> on arg "..arg_name)
          given_args[arg_name] = arg_arg_str:sub(2)
        elseif arg_info.type == "flag" then
          given_args[arg_name] = true
          break
        end
      end
    end
  else
    table.insert(var_args, v)
  end
end
if given_args.help then
  print("profile [filename]")
  for k,v in pairs(allowed_args) do
    local arg_label = k
    if v.type == "value" then
      arg_label = arg_label.."=?"
    end
    print(("%-10s|%s"):format(arg_label, v.description))
  end
  return
end

local filename = assert(var_args[1], "No program filename provided")

local loaded_func, err = loadfile(filename, nil, _ENV)
assert(loaded_func, err)

---@type table[] table of information about each yield
local yield_info = {}
local yield_index = 1 -- index of current yield

local yield_limit = tonumber(given_args.limit) -- maximum amount of times to allow the program to yield

local time_func = function()
  return os.epoch((given_args.nano and "nano") or "utc")
end
local time_precision = (given_args.nano and "ns") or "ms"


local offset = 0 -- total time offset due to yielding for events
local function t()
  return time_func() - offset
end

local function get_event()
  local start_time = t()
  local e = {os.pullEventRaw()}
  local end_time = t()
  offset = offset + end_time - start_time
  return e
end


local prior_term = term.current()
local w, h = term.getSize()
local program_window = window.create(prior_term, 1, 1, w, h, not given_args.hide)
term.redirect(program_window)


local c = coroutine.create(loaded_func)
local program_start_time = t()
local last_event = {}
local last_filter
local errorfree = true

while coroutine.status(c) ~= "dead" do
  if not last_filter or last_filter == last_event[1] then
    yield_info[yield_index] = {}
    local yield = yield_info[yield_index]
    yield.start_time = t()
    errorfree, last_filter = coroutine.resume(c, table.unpack(last_event))
    yield.end_time = t()
    yield.delta_time = yield.end_time - yield.start_time
    yield.event_filter = last_filter
    if not errorfree then
      break
    end
    yield_index = yield_index + 1
  end
  if yield_limit and yield_index > yield_limit then
    break
  end
  last_event = get_event()
end
local program_finish_time = t()
term.redirect(prior_term)

local exit_reason
if not errorfree then
  exit_reason = "Erorred: "..(last_filter or "")
elseif yield_limit and yield_index > yield_limit then
  exit_reason = "Yield limit reached."
end


if given_args.lua then
  local f = assert(fs.open(given_args.lua, "w"))
  local tab = {table.unpack(yield_info)}
  tab.precision = time_precision
  tab.exit_reason = exit_reason
  f.write(textutils.serialise(tab))
  f.close()
end

if given_args.json then
  local f = assert(fs.open(given_args.json, "w"))
  local tab = {table.unpack(yield_info)}
  tab.precision = time_precision
  tab.exit_reason = exit_reason
  f.write(textutils.serialiseJSON(tab))
  f.close()
end

if given_args.csv then
  local f = assert(fs.open(given_args.csv, "w"))
  f.writeLine("delta_index,delta_time,start_time,end_time,event_filter")
  for k,v in pairs(yield_info) do
    f.writeLine(("%u,%f,%f,%s"):format(k,v.delta_time,v.start_time,v.end_time,v.event_filter or ""))
  end
  f.writeLine("Precision,"..time_precision..",Exit reason,"..exit_reason)
  f.close()
end

if yield_limit and yield_index > yield_limit then
  print("Reached iteration count limit")
end
if not errorfree then
  print("Program errored:", last_filter)
end
print(("Execution finished in %.2f%s"):format(program_finish_time - program_start_time, time_precision))