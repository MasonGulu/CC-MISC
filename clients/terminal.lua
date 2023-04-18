-- storage terminal turtle for the system
local turtleInventory = {}
local lib = require("modemLib")
local function refreshTurtleInventory()
    local f = {}
    for i = 1, 16 do
        f[i] = function()
            turtleInventory[i] = turtle.getItemDetail(i, true)
        end
    end
    parallel.waitForAll(table.unpack(f))
    return turtleInventory
end

local modem = peripheral.getName(peripheral.find("modem"))
lib.connect(modem)
local selfName = peripheral.call(modem, "getNameLocal")

local importDivide = 4

---@type "SEARCH"|"INFO"|"CRAFT"
local mode = "SEARCH"

local function eventTurtleInventory()
    while true do
        os.pullEvent("turtle_inventory")
        refreshTurtleInventory()
        for i = 1,importDivide do
            if turtleInventory[i] then
                lib.pullItems(true, selfName, i, nil, nil, nil, {optimal=false})
            end
        end
        lib.performTransfer()
    end
end

local display = window.create(term.current(),1,1,term.getSize())
local w,h = display.getSize()
local itemCountW = 5
local itemNameW = w-itemCountW
local function formatItem(name,count)
    return ("%-"..itemCountW.."s %-"..itemNameW.."s"):format(count,name)
end
local function setColors(fg,bg,device)
    device = device or display
    device.setTextColor(fg)
    device.setBackgroundColor(bg)
end

local function text(x,y,t,device)
    device = device or display
    device.setCursorPos(math.floor(x),math.floor(y))
    device.write(t)
end

---@param t any[]
---@param pattern string
---@param sort nil|fun(a: any, b: any): boolean
---@param match nil|fun(val: any, pattern: string): boolean
---@return any[]
local function filterList(t, pattern, sort, match)
    table.sort(t, sort)
    local sifted = {}
    if pcall(string.match,"",pattern) then
        for k,v in pairs(t) do
            local ok, matches
            if not match then
                ok, matches = pcall(string.match, v, pattern)
            else
                ok, matches = pcall(match, v, pattern)
            end
            if ok and matches then
                table.insert(sifted, v)
            end
        end
    end
    return sifted
end

local craftInfo

local function getFirstItemOnScreen(item, list)
    return math.max(math.min(math.max(1,item-5), #list-h+4), 1)
end

local function getLastItemOnScreen(item, list)
    local scroll = getFirstItemOnScreen(item,list)
    return math.min(scroll+h+1, #list)
end

local function getYWithScroll(scroll, item)
    return 4 - scroll + item
end

---@param filter string
---@param selected integer
---@param list any[] filtered list
---@param header string
---@param dataFormatter fun(item: any): string
local function drawSearch(filter, selected, list, header, dataFormatter)
    text(1,2,filter)
    text(1,3,header)
    local screenScroll = getFirstItemOnScreen(selected, list)
    for i=screenScroll, getLastItemOnScreen(screenScroll, list) do
        local item = list[i]
        local y = getYWithScroll(screenScroll, i)
        if y > 3 then
            if i == selected then
                setColors(colors.black,colors.white)
            end
            text(1,y,dataFormatter(item))
            setColors(colors.white,colors.black)
        end
    end
    display.setCursorBlink(true)
    display.setCursorPos(filter:len()+1,2)
end

---@param drawFunc function
local function draw(drawFunc, ...)
    display.setVisible(false)
    display.setCursorBlink(false)
    display.clear()
    setColors(colors.black, colors.white)
    display.setCursorPos(1,1)
    display.clearLine()
    display.write(mode)
    setColors(colors.white,colors.black)
    drawFunc(...)
    display.setVisible(true)
end

---Request an item
---@param requestingCraft boolean
---@param item string
---@param amount integer?
local function requestItem(requestingCraft,item,amount)
    amount = amount or 0
    if amount == 0 then
        return
    end
    if requestingCraft then
        lib.requestCraft(item.name,amount)
        return
    end
    amount = math.min(amount, item.count)
    local stacks = math.min(math.ceil(amount / item.maxCount),16)
    local freeSlots = {}
    for i = importDivide+1, 16 do
        freeSlots[i] = true
    end
    for i,_ in pairs(turtleInventory) do
        freeSlots[i] = nil
    end
    for i = 1, stacks do
        local slot = next(freeSlots)
        if not slot then break end -- not enough space in the turtle to fit all of the items
        freeSlots[slot] = nil
        lib.pushItems(true,selfName,item.name,amount,slot,item.nbt)
    end
    lib.performTransfer()
end

local function isEnter(key)
    return key == keys.enter or key == keys.numPadEnter
end

local SEARCH, CRAFT, INFO, REQUEST

---Handle creating and drawing a searchable menu
---@param drawer fun(filter: string, selected: integer, sifted: any[])
---@param listProvider fun(): any[]
---@param onSelect fun(selected: any)
---@param event nil|fun(e: any[])
---@param sort nil|fun(a: any, b: any): boolean
---@param match nil|fun(val: any, pattern: string): boolean
---@param tab function mode to switch to upon pushing tab
local function searchableMenu(drawer, listProvider, onSelect, event, sort, match, tab)
    local filter = ""
    local sifted = filterList(listProvider(), filter, sort, match)
    local selected = 1
    while true do
        draw(drawer, filter, selected, sifted)
        local e = {os.pullEvent()}
        if event then
            event(e)
        end
        if e[1] == "char" then
            filter = filter .. e[2]
            sifted = filterList(listProvider(), filter, sort, match)
        elseif e[1] == "key" then
            local key = e[2]
            if key == keys.backspace then
                filter = filter:sub(1, -2)
                sifted = filterList(listProvider(), filter, sort, match)
                selected = math.min(selected, #sifted)
            elseif key == keys.up then
                selected = math.max(selected - 1, 1)
            elseif key == keys.down then
                selected = math.min(selected + 1, #sifted)
            elseif isEnter(key) then
                if selected > 0 then
                    return onSelect(sifted[selected])
                end
            elseif key == keys.tab then
                return tab()
            end
        elseif e[1] == "mouse_click" and e[4] > 3 then
            selected = math.max(math.min(getFirstItemOnScreen(selected, sifted) + e[4] - 4, #sifted), 1)
            return onSelect(sifted[selected])
        elseif e[1] == "mouse_scroll" then
            selected = math.max(math.min(selected + e[2], #sifted), 1)
        end
    end
end


function SEARCH()
    local list = lib.list()

    local drawer = function (filter, selected, sifted)
        drawSearch(filter, selected, sifted, formatItem("Name","Count"), function (item)
            return formatItem(item.displayName, item.count)
        end)
    end

    local match = function (v, filter)
        return v.name:match(filter) or v.displayName:lower():match(filter) or v.displayName:match(filter)
    end

    local sort = function (a,b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.name < b.name
    end

    local onSelect = function (selected)
        return INFO(selected)
    end

    local event = function (e)
        if e[1] == "update" then
            list = e[2]
        end
    end

    return searchableMenu(drawer, function() return list end, onSelect, event, sort, match, CRAFT)
end

function CRAFT()
    local craftables = lib.listCraftables()

    local drawer = function (craftFilter, selectedCraft, siftedCraftables)
        drawSearch(craftFilter, selectedCraft, siftedCraftables, "Name", function (item)
            return item
        end)
    end

    local onSelect = function (selected)
        return REQUEST(selected)
    end

    return searchableMenu(drawer, function() return craftables end, onSelect, nil, nil, nil, SEARCH)
end

function INFO(item)
    local itemAmount = tostring(math.min(item.maxCount, item.count))
    while true do
        draw(function ()
            text(1,2,("%u x %s"):format(item.count,item.displayName))
            text(1,3,item.name)
            text(1,4,item.nbt)
            if item.enchantments then
                text(1,5,"Enchantments")
                for k,v in ipairs(item.enchantments) do
                    text(1,5+k,v.displayName or v.name)
                end
            end
            text(1,h,("Withdraw: %s"):format(itemAmount))
            display.setCursorBlink(true)
            display.setCursorPos(itemAmount:len()+11,h)
        end)
        local e = {os.pullEvent()}
        if e[1] == "char" then
            local ch = e[2]
            if ch >= '0' and ch <= '9' then
                itemAmount = itemAmount .. ch
            end
        elseif e[1] == "key" then
            local key = e[2]
            if key == keys.backspace then
                itemAmount = itemAmount:sub(1, -2)
            elseif isEnter(key) then
                requestItem(false,item,tonumber(itemAmount or 0))
                return SEARCH()
            end
        end
    end
end

function REQUEST(item)
    if not item then
        return CRAFT()
    end
    display.clear()
    text(1,1,"Requesting Item")
    text(1,2,item)
    while true do
        display.setCursorPos(1,3)
        display.clearLine()
        text(1,3,"Quantity? ")
        local input = read()
        if input == "" then
            return CRAFT()
        end
        local num_input = tonumber(input)
        if num_input and num_input > 0 then
            craftInfo = lib.requestCraft(item, tonumber(input))
            break
        end
    end

    local oldTerm = term.current()
    local viewTerm = window.create(oldTerm, 1, 5, term.getSize())
    local height = 5
    for _ in pairs(craftInfo.missing) do height = height + 1 end
    local hasUse = false
    for _ in pairs(craftInfo.toUse) do hasUse = true; height = height + 1 end
    for _ in pairs(craftInfo.toCraft) do height = height + 1 end
    local win = window.create(viewTerm, 1, 1, term.getSize(), height)
    local line = 1
    draw(function ()
        text(1,2,(craftInfo.success and "Press y to craft, n to cancel") or "Press n to cancel the craft")
        text(1,3,("Requested %s"):format(item))
        text(1,4,(craftInfo.success and "Success") or "Failure")
        if not craftInfo.success then
            setColors(colors.red,colors.black,win)
            text(1,line,"Missing:",win)
            line = line + 1
            for k,v in pairs(craftInfo.missing) do
                text(1,line,("%ux%s"):format(v,k),win)
                line = line + 1
            end
            setColors(colors.white,colors.black,win)
        end
        if hasUse then
            text(1,line,"To use:",win)
            line = line + 1
            for k,v in pairs(craftInfo.toUse) do
                text(1,line,("%ux%s"):format(v,k),win)
                line = line + 1
            end
        end
        text(1,line,"To craft:",win)
        line = line + 1
        for k,v in pairs(craftInfo.toCraft) do
            text(1,line,("%ux%s"):format(v,k),win)
            line = line + 1
        end
    end)
    local scrollPos = 1
    win.reposition(1,scrollPos)

    while true do
        local e = {os.pullEvent()}
        if e[1] == "char" then
            local ch = e[2]
            if craftInfo then
                if ch == 'y' and craftInfo.success then
                    lib.startCraft(craftInfo.jobId)
                    craftInfo = nil
                    return SEARCH()
                elseif ch == 'n' then
                    if craftInfo.success then
                        lib.cancelCraft(craftInfo.jobId)
                    end
                    craftInfo = nil
                    return SEARCH()
                end
            end
        elseif e[1] == "key" then
            local key = e[2]
            if key == keys.down then
                scrollPos = math.max(3-line, scrollPos - 1)
                viewTerm.clear()
                win.reposition(1, scrollPos)
            elseif key == keys.up then
                scrollPos = math.min(1, scrollPos + 1)
                viewTerm.clear()
                win.reposition(1, scrollPos)
            end
        elseif e[1] == "mouse_scroll" then
            scrollPos = math.min(1, math.max(3-line, scrollPos - e[2]))
            viewTerm.clear()
            win.reposition(1, scrollPos)
        end
    end
end

parallel.waitForAll(lib.subscribe, eventTurtleInventory, SEARCH)