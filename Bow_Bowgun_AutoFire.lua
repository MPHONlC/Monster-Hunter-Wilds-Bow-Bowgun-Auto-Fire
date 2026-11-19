local MOD_TAG = "[BowBowgunAutoFire]"
local CONFIG_PATH = "Bow_Bowgun_AutoFire.json"
local CONFIG_VERSION = 5

local WEAPON_NAMES = { [11] = "Bow", [12] = "Heavy Bowgun", [13] = "Light Bowgun" }
local WEAPON_KEYS = { [11] = "bow", [12] = "heavyBowgun", [13] = "lightBowgun" }

local PAD_BUTTONS = {
    { 2048, "R2" }, { 512, "L2" }, { 1024, "R1" },
    { 16, "Y" }, { 128, "B" }, { 32, "A" }, { 64, "X" },
}

local VK_NAMES = {
    [1] = "Left Mouse", [2] = "Right Mouse", [4] = "Middle Mouse", [5] = "Mouse 4", [6] = "Mouse 5",
    [8] = "Backspace", [9] = "Tab", [13] = "Enter", [16] = "Shift", [17] = "Ctrl", [18] = "Alt",
    [20] = "Caps Lock", [27] = "Esc", [32] = "Space", [33] = "Page Up", [34] = "Page Down",
    [35] = "End", [36] = "Home", [37] = "Left", [38] = "Up", [39] = "Right", [40] = "Down",
    [45] = "Insert", [46] = "Delete", [160] = "Left Shift", [161] = "Right Shift",
    [162] = "Left Ctrl", [163] = "Right Ctrl", [164] = "Left Alt", [165] = "Right Alt",
}

local OUTPUT_KINDS = { "vinput", "pad", "mousehook", "mousedev" }
local OUTPUT_LABELS = {
    "Game virtual input (works for mouse, keyboard and controller)",
    "Controller input",
    "Mouse button via input hooks",
    "Mouse button via device write",
}
local MOUSE_CHOICES = { "Left", "Right", "Middle" }
local CHANNEL_LABELS = { pad = "Controller input", mousehook = "Mouse input hooks", mousedev = "Mouse device write" }

local DEFAULTS = {
    enabled = true,
    triggerKind = "key",
    triggerCode = 1,
    outputKind = "vinput",
    vkeys = "",
    outputPad = 0,
    outputLearned = false,
    outputMouse = 1,
    outputVk = 0,
    delayMs = 300,
    holdMs = 120,
    stopOnFire = true,
    bow = true,
    heavyBowgun = true,
    lightBowgun = true,
    cursorGuard = true,
    cancelKeys = "27",
    comboKeys = "69,70,82,32",
    comboResumeMs = 600,
    debugLog = false,
    configVersion = CONFIG_VERSION,
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end

local function kindIndex(kind)
    for i, k in ipairs(OUTPUT_KINDS) do
        if k == kind then return i end
    end
    return 1
end

local migrated = false
local function loadConfig()
    local ok, f = pcall(json.load_file, CONFIG_PATH)
    if ok and type(f) == "table" then
        local oldVersion = tonumber(f.configVersion) or 0
        for k in pairs(DEFAULTS) do
            if f[k] ~= nil and type(f[k]) == type(DEFAULTS[k]) then cfg[k] = f[k] end
        end
        if oldVersion < CONFIG_VERSION then
            cfg.outputKind, cfg.outputPad, cfg.outputLearned, cfg.outputVk = "vinput", 0, false, 0
            cfg.vkeys = ""
            cfg.holdMs, cfg.delayMs = DEFAULTS.holdMs, DEFAULTS.delayMs
            cfg.configVersion = CONFIG_VERSION
            migrated = true
        end
    end
    local valid = false
    for _, k in ipairs(OUTPUT_KINDS) do
        if k == cfg.outputKind then valid = true end
    end
    if not valid then cfg.outputKind = "vinput" end
end
local function saveConfig() pcall(json.dump_file, CONFIG_PATH, cfg) end
loadConfig()
if migrated then saveConfig() end

local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function dbg(fmt, ...)
    if not cfg.debugLog then return end
    local ok, s = pcall(string.format, fmt, ...)
    if ok then log.info(MOD_TAG .. " " .. s) end
end

local CANCEL_SET = {}
local function rebuildCancelSet()
    CANCEL_SET = {}
    for n in tostring(cfg.cancelKeys or ""):gmatch("%d+") do
        CANCEL_SET[tonumber(n)] = true
    end
end
rebuildCancelSet()

local VKEYS = {}
local function rebuildVkeys()
    VKEYS = {}
    for n in tostring(cfg.vkeys or ""):gmatch("%d+") do VKEYS[#VKEYS + 1] = tonumber(n) end
end
rebuildVkeys()

local COMBO_LIST = {}
local function rebuildComboList()
    COMBO_LIST = {}
    for n in tostring(cfg.comboKeys or ""):gmatch("%d+") do COMBO_LIST[#COMBO_LIST + 1] = tonumber(n) end
end
rebuildComboList()

local MOUSE_BITS = { L = 1, R = 2, C = 4 }
safe(function()
    local td = sdk.find_type_definition("via.hid.MouseButton")
    if not td then return end
    for _, f in ipairs(td:get_fields()) do
        if f:is_static() then
            local n = f:get_name()
            local v = safe(function() return f:get_data(nil) end)
            if type(v) == "number" and v > 0 then
                if n == "L" or n == "Left" then MOUSE_BITS.L = v
                elseif n == "R" or n == "Right" then MOUSE_BITS.R = v
                elseif n == "C" or n == "Center" or n == "Middle" then MOUSE_BITS.C = v end
            end
        end
    end
end)

local function mouseBitFor(choice)
    if choice == 2 then return MOUSE_BITS.R end
    if choice == 3 then return MOUSE_BITS.C end
    return MOUSE_BITS.L
end

local function mouseChoiceIndex(bit)
    if bit == MOUSE_BITS.R then return 2 end
    if bit == MOUSE_BITS.C then return 3 end
    return 1
end

local function vkToMouseBit(vk)
    if vk == 1 then return MOUSE_BITS.L end
    if vk == 2 then return MOUSE_BITS.R end
    if vk == 4 then return MOUSE_BITS.C end
    return nil
end

local function vkName(vk)
    if VK_NAMES[vk] then return VK_NAMES[vk] end
    if vk >= 48 and vk <= 57 then return string.char(vk) end
    if vk >= 65 and vk <= 90 then return string.char(vk) end
    if vk >= 112 and vk <= 135 then return "F" .. tostring(vk - 111) end
    return string.format("VK %d", vk)
end

local function padName(mask)
    if mask == 0 then return "not set" end
    local parts = {}
    for _, b in ipairs(PAD_BUTTONS) do
        if mask & b[1] ~= 0 then parts[#parts + 1] = b[2] end
    end
    if #parts == 0 then return string.format("mask %d", mask) end
    return table.concat(parts, "+") .. string.format(" (mask %d)", mask)
end

local character = nil
local actionCtrl = nil
local weaponType, weaponDrawn, riding = -1, false, false
local curAction = nil

local function refreshPlayer()
    local char = safe(function()
        local pm = sdk.get_managed_singleton("app.PlayerManager")
        local mp = pm and pm:getMasterPlayer() or nil
        return mp and mp:get_Character() or nil
    end)
    if not char then
        character, actionCtrl, curAction = nil, nil, nil
        weaponType, weaponDrawn, riding = -1, false, false
        return
    end
    if char ~= character then actionCtrl = nil end
    character = char
    weaponType = tonumber(safe(function() return char:call("get_WeaponType") end)) or -1
    weaponDrawn = safe(function() return char:call("get_IsWeaponOn") end) == true
    riding = safe(function() return char:call("get_IsPorterRiding") end) == true

    if not actionCtrl then
        actionCtrl = safe(function() return char:call("get_BaseActionController") end)
    end
    curAction = nil
    local aid = actionCtrl and (safe(function() return actionCtrl:call("get_CurrentActionID") end)
        or safe(function() return actionCtrl:get_field("_CurrentActionID") end))
    if aid then
        local cat = tonumber(safe(function() return aid:get_field("_Category") end)) or -1
        local idx = tonumber(safe(function() return aid:get_field("_Index") end)) or -1
        curAction = cat * 100000 + idx
    end
end

local function actionText(key)
    if not key then return "n/a" end
    return string.format("Cat=%d Idx=%d", key // 100000, key % 100000)
end

local gpType = sdk.find_type_definition("via.hid.GamePad")
local gpSingleton = sdk.get_native_singleton("via.hid.GamePad")
local DEVICE_GETTERS = { "get_LastInputDevice", "get_MergedDevice", "get_Device" }

local function getPadDevices()
    local list, seen = {}, {}
    if not gpType or not gpSingleton then return list end
    for _, g in ipairs(DEVICE_GETTERS) do
        local d = safe(function() return sdk.call_native_func(gpSingleton, gpType, g) end)
        if d then
            local addr = safe(function() return d:get_address() end) or tostring(d)
            if not seen[addr] then
                seen[addr] = true
                table.insert(list, d)
            end
        end
    end
    return list
end

local PAD_NAMES = { held = "Button", down = "ButtonDown", up = "ButtonUp", getPrefix = "get_", setPrefix = "set_" }

local mouseType = sdk.find_type_definition("via.hid.Mouse")
local mouseSingleton = sdk.get_native_singleton("via.hid.Mouse")
local mouseBackend = { tried = false, getter = nil, names = nil }

local function callGetter(getter)
    if getter == "__self" then return mouseSingleton end
    return safe(function() return sdk.call_native_func(mouseSingleton, mouseType, getter) end)
end

local function findSetters(obj)
    local td = safe(function() return obj:get_type_definition() end)
    local methods = td and safe(function() return td:get_methods() end) or nil
    if not methods then return nil end
    local found = nil
    for _, m in ipairs(methods) do
        local n = safe(function() return m:get_name() end)
        local np = safe(function() return m:get_num_params() end)
        if n and np == 1 then
            local l = n:lower()
            local us = n:sub(4, 4) == "_" and "_" or ""
            if l == "set_button" or l == "setbutton" then
                found = { held = n:sub(4 + #us), getPrefix = "get" .. us, setPrefix = "set" .. us }
            end
        end
    end
    if not found then return nil end
    local hasDown, hasUp = false, false
    for _, m in ipairs(methods) do
        local n = safe(function() return m:get_name() end)
        if n == found.setPrefix .. found.held .. "Down" then hasDown = true end
        if n == found.setPrefix .. found.held .. "Up" then hasUp = true end
    end
    found.down = hasDown and (found.held .. "Down") or nil
    found.up = hasUp and (found.held .. "Up") or nil
    return found
end

local function discoverMouse()
    mouseBackend.tried = true
    mouseBackend.getter = nil
    mouseBackend.names = nil
    if not mouseType or not mouseSingleton then return end

    local candidates = { "get_Device", "get_MergedDevice", "get_LastInputDevice", "get_Mouse" }
    local methods = safe(function() return mouseType:get_methods() end) or {}
    for _, m in ipairs(methods) do
        local n = safe(function() return m:get_name() end)
        local np = safe(function() return m:get_num_params() end)
        if n and np == 0 and n:sub(1, 3):lower() == "get" then candidates[#candidates + 1] = n end
    end

    for _, g in ipairs(candidates) do
        local d = callGetter(g)
        local names = d and findSetters(d)
        if names then
            mouseBackend.getter, mouseBackend.names = g, names
            return
        end
    end
    local names = findSetters(mouseSingleton)
    if names then mouseBackend.getter, mouseBackend.names = "__self", names end
end

local function getMouseDevice()
    if not mouseBackend.tried then discoverMouse() end
    if not mouseBackend.getter then return nil end
    return callGetter(mouseBackend.getter), mouseBackend.names
end

local function cursorVisible()
    if not mouseType or not mouseSingleton then return nil end
    local v = safe(function() return sdk.call_native_func(mouseSingleton, mouseType, "get_ShowCursor") end)
    if type(v) == "boolean" then return v end
    return nil
end

local function getU32(dev, name)
    return (tonumber(safe(function() return dev:call(name) end)) or 0) & 0xFFFFFFFF
end

local function setU32(dev, name, v)
    pcall(function() dev:call(name, v) end)
end

local function applyVirtual(dev, names, mask, virt, virtWas)
    if not virt and not virtWas then return end
    names = names or PAD_NAMES
    local gp, sp = names.getPrefix, names.setPrefix
    local btn = getU32(dev, gp .. names.held)
    local down = names.down and getU32(dev, gp .. names.down) or 0
    local up = names.up and getU32(dev, gp .. names.up) or 0

    if virt then btn = btn | mask end
    if virt and not virtWas then down = down | mask end
    if virtWas and not virt then up = up | mask end

    setU32(dev, sp .. names.held, btn)
    if names.down then setU32(dev, sp .. names.down, down) end
    if names.up then setU32(dev, sp .. names.up, up) end
end

local virtState = { held = false, down = false, up = false }
local injectKind, injectMask = nil, 1
local hookInfo = {}
local hookOrder = {}
local hookErrors = 0

local function classify(name)
    local l = name:lower()
    if l:find("^set") or l:find("pos") or l:find("wheel") or l:find("delta") or l:find("cursor") then
        return nil
    end
    if not (l:find("button") or l:find("^isdown") or l:find("^isup") or l:find("^ison")
        or l:find("^ispress") or l:find("^isrelease") or l:find("^istrig")) then
        return nil
    end
    if l:find("down") or l:find("trig") then return "down" end
    if l:find("up") or l:find("release") then return "up" end
    return "held"
end

local function installMouseHooks()
    for _, typeName in ipairs({ "via.hid.Mouse", "via.hid.MouseDevice" }) do
        local td = sdk.find_type_definition(typeName)
        local methods = td and safe(function() return td:get_methods() end) or nil
        for _, m in ipairs(methods or {}) do
            local name = safe(function() return m:get_name() end)
            local kind = name and classify(name)
            if kind then
                local np = safe(function() return m:get_num_params() end) or 0
                local rt = safe(function() return m:get_return_type() end)
                local rtName = rt and safe(function() return rt:get_full_name() end) or ""
                local returnsBool = rtName == "System.Boolean"
                local key = typeName:gsub("^via%.hid%.", "") .. "." .. name .. "/" .. tostring(np)
                local info = { key = key, calls = 0, kind = kind, bool = returnsBool, applied = 0 }
                hookInfo[key] = info
                hookOrder[#hookOrder + 1] = key
                local argv = nil
                local ok = pcall(function()
                    sdk.hook(m, function(args)
                        info.calls = info.calls + 1
                        if np >= 1 then
                            argv = safe(function() return sdk.to_int64(args[3]) & 0xFFFFFFFF end)
                        end
                    end, function(retval)
                        if injectKind ~= "mousehook" then return retval end
                        local want = (kind == "held" and virtState.held)
                            or (kind == "down" and virtState.down)
                            or (kind == "up" and virtState.up)
                        if not want then return retval end
                        local mask = injectMask
                        local ok2, result = pcall(function()
                            if returnsBool then
                                if np >= 1 and argv and (argv & mask) == 0 then return retval end
                                info.applied = info.applied + 1
                                return sdk.to_ptr(1)
                            end
                            local v = sdk.to_int64(retval) & 0xFFFFFFFF
                            info.applied = info.applied + 1
                            return sdk.to_ptr(v | mask)
                        end)
                        if ok2 then return result end
                        hookErrors = hookErrors + 1
                        return retval
                    end)
                end)
                if not ok then
                    info.failed = true
                    hookErrors = hookErrors + 1
                end
            end
        end
    end
end
pcall(installMouseHooks)

local apiLines = {}
for _, typeName in ipairs({ "via.hid.Mouse", "via.hid.MouseDevice" }) do
    local td = sdk.find_type_definition(typeName)
    if not td then
        apiLines[#apiLines + 1] = typeName .. ": type not found"
    else
        for _, m in ipairs(safe(function() return td:get_methods() end) or {}) do
            local n = safe(function() return m:get_name() end)
            local np = safe(function() return m:get_num_params() end)
            apiLines[#apiLines + 1] = string.format("%s.%s (%s)", typeName:gsub("^via%.hid%.", ""), tostring(n), tostring(np))
        end
    end
end

local vin = { controller = nil, calls = 0, applied = 0, hooked = false, err = nil, size = 0 }

local function vField(o, name)
    if not o then return nil end
    local ok, v = pcall(function() return o:get_field(name) end)
    if ok then return v end
    return nil
end

local function vSize(a)
    if not a then return nil end
    local ok, n = pcall(function() return a:get_size() end)
    if ok and type(n) == "number" then return n end
    ok, n = pcall(function() return a:get_length() end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function vElement(a, i)
    if not a then return nil end
    local ok, v = pcall(function() return a:get_element(i) end)
    if ok then return v end
    return nil
end

local function vSetBool(o, name, value)
    if not o or type(vField(o, name)) ~= "boolean" then return false end
    return pcall(function() o:set_field(name, value) end)
end

local function mergedKeys(controller)
    local merged = vField(controller, "_MergedVirtualInput")
    local keys, lagged = vField(merged, "_Keys"), vField(merged, "_LaggedKeys")
    if not keys or not lagged or not vSize(keys) or not vSize(lagged) then return nil, nil end
    return keys, lagged
end

local function activeVirtualKeys()
    local active = {}
    local controller = vin.controller
    if not controller then return active end
    local keys = mergedKeys(controller)
    local n = vSize(keys)
    if not n then return active end
    vin.size = n
    for i = 0, math.min(n, 200) - 1 do
        local k = vElement(keys, i)
        if k and vField(k, "_On") == true then active[i] = true end
    end
    return active
end

local function applyVirtualKeys(controller)
    local keys, lagged = mergedKeys(controller)
    if not keys then return end
    for _, id in ipairs(VKEYS) do
        local a, b = vElement(keys, id), vElement(lagged, id)
        if a and b and vField(a, "_On") ~= true then
            vSetBool(a, "_On", true)
            vSetBool(a, "_RawOn", true)
            local prev = not virtState.down
            vSetBool(b, "_On", prev)
            vSetBool(b, "_RawOn", prev)
            vin.applied = vin.applied + 1
        end
    end
end

local function installVirtualInputHook()
    local td = sdk.find_type_definition("app.cPlayerCommandController")
    local m = td and safe(function() return td:get_method("updateCommand") end)
    if not m then
        vin.err = "app.cPlayerCommandController.updateCommand not found"
        return
    end
    local ok, err = pcall(function()
        sdk.hook(m, function(args)
            vin.calls = vin.calls + 1
            local ok2, obj = pcall(sdk.to_managed_object, args[2])
            if ok2 and obj then vin.controller = obj end
            if vin.controller and injectKind == "vinput" and virtState.held then
                local ok3, err3 = pcall(applyVirtualKeys, vin.controller)
                if not ok3 then vin.err = tostring(err3) end
            end
        end, function(retval) return retval end)
    end)
    vin.hooked = ok
    if not ok then vin.err = tostring(err) end
end
pcall(installVirtualInputHook)

local comboResumeAt = 0
local toggleOn = false
local virtPrev = false
local trigPrev = false
local firePrev = false
local nextShot = 0
local pulseEnd = 0
local lastOut = { kind = "pad", mask = 0 }
local shots = 0
local status = "starting"
local outputOk = true

local function setVirtState(virt)
    virtState.held = virt
    virtState.down = virt and not virtPrev
    virtState.up = virtPrev and not virt
end

local function releaseOutput()
    if virtPrev then
        if lastOut.kind == "pad" then
            for _, d in ipairs(getPadDevices()) do applyVirtual(d, nil, lastOut.mask, false, true) end
        elseif lastOut.kind == "mousedev" then
            local md, names = getMouseDevice()
            if md then applyVirtual(md, names, lastOut.mask, false, true) end
        end
    end
    virtPrev = false
    virtState.held, virtState.down, virtState.up = false, false, false
    injectKind = nil
end

local function driveOutput(kind, mask, virt, padDevices)
    if (lastOut.kind ~= kind or lastOut.mask ~= mask) and virtPrev then releaseOutput() end
    lastOut = { kind = kind, mask = mask }
    injectKind, injectMask = kind, mask
    setVirtState(virt)

    if kind == "pad" then
        for _, d in ipairs(padDevices) do applyVirtual(d, nil, mask, virt, virtPrev) end
        outputOk = #padDevices > 0
    elseif kind == "mousedev" then
        local md, names = getMouseDevice()
        if md then applyVirtual(md, names, mask, virt, virtPrev) end
        outputOk = md ~= nil
    elseif kind == "vinput" then
        outputOk = vin.controller ~= nil and #VKEYS > 0
    else
        outputOk = next(hookInfo) ~= nil
    end
    virtPrev = virt
end

local function stopToggle(reason)
    if toggleOn then dbg("stop: %s", reason) end
    toggleOn = false
    releaseOutput()
    status = reason
end

local function blockReason()
    if not cfg.enabled then return "disabled" end
    if not character then return "no player" end
    local key = WEAPON_KEYS[weaponType]
    if not key then return "weapon is not a bow or bowgun" end
    if not cfg[key] then return WEAPON_NAMES[weaponType] .. " disabled in settings" end
    if not weaponDrawn then return "weapon sheathed" end
    if riding then return "riding" end
    if safe(function() return reframework:is_drawing_ui() end) == true then return "REFramework menu open" end
    if cfg.cursorGuard and cursorVisible() == true then return "menu open (cursor visible)" end
    if cfg.outputKind == "pad" and cfg.outputPad == 0 then return "no fire output set (use Auto-detect)" end
    if cfg.outputKind == "vinput" and #VKEYS == 0 then return "no fire keys learned yet (use Auto-detect)" end
    return nil
end

local function keyDown(vk)
    local down = safe(function() return reframework:is_key_down(vk) end) == true
    if down then return true end
    local bit = vkToMouseBit(vk)
    if bit then
        local md, names = getMouseDevice()
        if md and names and (getU32(md, names.getPrefix .. names.held) & bit) ~= 0 then return true end
    end
    return false
end

local function padBits(padDevices)
    local bits = 0
    for _, d in ipairs(padDevices) do bits = bits | getU32(d, "get_Button") end
    return bits
end

local function triggerDown(padDevices)
    if cfg.triggerKind == "pad" then
        return (padBits(padDevices) & cfg.triggerCode) ~= 0
    end
    return keyDown(cfg.triggerCode)
end

local fireVkForCombo = nil

local function comboKeyDown()
    for _, vk in ipairs(COMBO_LIST) do
        if vk ~= fireVkForCombo and safe(function() return reframework:is_key_down(vk) end) == true then return true end
    end
    return false
end

local function cancelPressed()
    for vk in pairs(CANCEL_SET) do
        if safe(function() return reframework:is_key_down(vk) end) == true then return true end
    end
    return false
end

local function fireVk()
    if cfg.outputKind == "pad" then return cfg.outputVk end
    if cfg.outputMouse == MOUSE_BITS.R then return 2 end
    if cfg.outputMouse == MOUSE_BITS.C then return 4 end
    return 1
end

local function firePhysicalDown(padDevices)
    if cfg.outputKind == "pad" and cfg.outputPad ~= 0 and (padBits(padDevices) & cfg.outputPad) ~= 0 then
        return true
    end
    local vk = fireVk()
    return vk ~= nil and vk ~= 0 and keyDown(vk)
end

local function triggerIsOutput()
    if cfg.triggerKind == "key" then
        local vk = fireVk()
        return vk ~= nil and vk ~= 0 and vk == cfg.triggerCode
    end
    if cfg.triggerKind == "pad" and cfg.outputKind == "pad" then
        return cfg.triggerCode == cfg.outputPad
    end
    return false
end

local binding = nil
local bindMessage = ""

local function anyKeyDown()
    for vk = 1, 254 do
        if safe(function() return reframework:is_key_down(vk) end) == true then return vk end
    end
    return nil
end

local function pollBinding(padDevices)
    local now = os.clock()
    if now - binding.started > 12 then
        bindMessage = "Binding timed out"
        binding = nil
        return
    end

    local vk = anyKeyDown()
    local bits = padBits(padDevices)

    if not binding.armed then
        if not vk and bits == 0 then binding.armed = true end
        return
    end

    if binding.what == "combo" and vk then
        local present = false
        for _, existing in ipairs(COMBO_LIST) do
            if existing == vk then present = true end
        end
        if not present then
            cfg.comboKeys = (cfg.comboKeys ~= "" and (cfg.comboKeys .. ",") or "") .. tostring(vk)
            rebuildComboList()
        end
        bindMessage = "Combo key added: " .. vkName(vk)
        binding = nil
        saveConfig()
        return
    end

    if binding.what == "trigger" and vk then
        cfg.triggerKind, cfg.triggerCode = "key", vk
        bindMessage = "Trigger set to " .. vkName(vk)
        binding = nil
        saveConfig()
        return
    end

    if bits ~= 0 then
        local bit = bits & -bits
        if binding.what == "trigger" then
            cfg.triggerKind, cfg.triggerCode = "pad", bit
            bindMessage = "Trigger set to " .. padName(bit)
        else
            cfg.outputKind, cfg.outputPad, cfg.outputLearned, cfg.outputVk = "pad", bit, false, 0
            bindMessage = "Output set to " .. padName(bit)
        end
        binding = nil
        saveConfig()
    end
end

local detect = nil
local detectLog = {}
local learnedActions = {}
local learnedCount = 0

local function dlog(msg)
    detectLog[#detectLog + 1] = msg
    while #detectLog > 24 do table.remove(detectLog, 1) end
    log.info(MOD_TAG .. " " .. msg)
end

local function firstMouseDown()
    for _, vk in ipairs({ 1, 2, 4 }) do
        if keyDown(vk) then return vk end
    end
    return nil
end

local function detectWorldReady()
    local ui = safe(function() return reframework:is_drawing_ui() end) == true
    if ui then return false, "Close the REFramework menu (Insert)" end
    if not WEAPON_KEYS[weaponType] then return false, "Switch to a bow or bowgun" end
    if not weaponDrawn then return false, "Draw your weapon" end
    if riding then return false, "Get off your Seikret" end
    if curAction == nil then return false, "Player action not readable" end
    return true, nil
end

local function startDetect()
    detect = { phase = "learn", armed = false, pressed = false, started = os.clock(), msg = "Starting" }
    detectLog = {}
    learnedActions, learnedCount = {}, 0
    toggleOn = false
    releaseOutput()
    dlog("Auto-detect started. Close the menu, draw your weapon, stand still and fire once normally.")
end

local function buildChannels(learnVk, learnPad)
    local list = {}
    if #VKEYS > 0 and vin.hooked then
        list[#list + 1] = { kind = "vinput", mask = 0, label = "Game virtual input (keys " .. table.concat(VKEYS, ",") .. ")" }
    end
    if learnPad and learnPad ~= 0 then
        list[#list + 1] = { kind = "pad", mask = learnPad, label = "Controller input " .. padName(learnPad) }
    end
    if next(hookInfo) ~= nil then
        list[#list + 1] = { kind = "mousehook", mask = cfg.outputMouse, label = "Mouse input hooks" }
    end
    if getMouseDevice() then
        list[#list + 1] = { kind = "mousedev", mask = cfg.outputMouse, label = "Mouse device write" }
    end
    for _, b in ipairs({ { 2048, "R2" }, { 16, "Y" }, { 128, "B" }, { 1024, "R1" } }) do
        if b[1] ~= learnPad then
            list[#list + 1] = { kind = "pad", mask = b[1], label = "Controller " .. b[2] }
        end
    end
    return list
end

local function finishLearn()
    local learned, count = {}, 0
    for key in pairs(detect.seen) do
        if key ~= detect.baseline then
            learned[key] = true
            count = count + 1
        end
    end
    if count == 0 then
        dlog("No action change was seen after your click. Is the weapon drawn and the click a fire input?")
        detect = nil
        return
    end
    learnedActions, learnedCount = learned, count
    do
        local ids = {}
        for id, n in pairs(detect.vcount or {}) do
            if n >= 2 then ids[#ids + 1] = id end
        end
        table.sort(ids)
        if #ids > 0 then
            cfg.vkeys = table.concat(ids, ",")
            rebuildVkeys()
            saveConfig()
            dlog("Learned virtual fire keys: " .. cfg.vkeys)
        else
            dlog("No virtual input key changed during your click (hook calls: " .. tostring(vin.calls) .. ").")
        end
    end
    local keys = {}
    for key in pairs(learned) do keys[#keys + 1] = actionText(key) end
    table.sort(keys)
    dlog("Learned " .. tostring(count) .. " fire action(s): " .. table.concat(keys, ", "))

    if detect.vk then
        cfg.outputVk = detect.vk
        cfg.outputMouse = vkToMouseBit(detect.vk) or cfg.outputMouse
    end
    detect.channels = buildChannels(detect.vk, detect.pbits)
    detect.i = 1
    detect.phase = "test"
    detect.sub = "settle"
    detect.subStart = os.clock()
    detect.lastAction = curAction
    dlog("Testing " .. tostring(#detect.channels) .. " output channels. Keep standing still with the weapon drawn.")
end

local function finishTest(found)
    releaseOutput()
    if found then
        cfg.outputKind = found.kind
        if found.kind == "vinput" then
            cfg.outputLearned = detect.vk ~= nil
        elseif found.kind == "pad" then
            cfg.outputPad = found.mask
            cfg.outputLearned = detect.vk ~= nil
        else
            cfg.outputMouse = found.mask
        end
        saveConfig()
        dlog("WORKS: " .. found.label .. ". It is now selected as the fire output.")
    else
        dlog("None of the tested channels made your weapon fire. See the notes in the panel.")
    end
    detect = nil
end

local function pollDetect(padDevices)
    local now = os.clock()
    local ready, why = detectWorldReady()

    if detect.phase == "learn" then
        if not ready then
            detect.armed, detect.pressed = false, false
            detect.msg = why
            return
        end
        if not detect.armed then
            detect.armed = true
            detect.baseline = curAction
            detect.started = now
            detect.msg = "Fire once with your normal fire button"
            return
        end
        local vk = firstMouseDown()
        local pbits = padBits(padDevices)
        if not detect.pressed then
            detect.baseline = curAction
            detect.vbase = activeVirtualKeys()
            if vk or pbits ~= 0 then
                detect.pressed = true
                detect.pressStart = now
                detect.vk, detect.pbits = vk, pbits
                detect.seen = { [curAction] = true }
                detect.vcount = {}
                detect.msg = "Reading the fire action"
            elseif now - detect.started > 60 then
                dlog("Timed out waiting for a click.")
                detect = nil
            end
        else
            detect.seen[curAction] = true
            for id in pairs(activeVirtualKeys()) do
                if not (detect.vbase or {})[id] then detect.vcount[id] = (detect.vcount[id] or 0) + 1 end
            end
            if now - detect.pressStart > 1.6 then finishLearn() end
        end
        return
    end

    local ch = detect.channels[detect.i]
    if not ch then
        finishTest(nil)
        return
    end

    if not ready then
        releaseOutput()
        detect.msg = "Paused: " .. why
        detect.sub = "settle"
        detect.subStart = now
        detect.lastAction = curAction
        return
    end

    local inputHeld = firstMouseDown() ~= nil or padBits(padDevices) ~= 0
    detect.msg = string.format("Testing %d/%d: %s", detect.i, #detect.channels, ch.label)

    if detect.sub == "settle" then
        if learnedActions[curAction] or inputHeld or curAction ~= detect.lastAction then
            detect.subStart = now
        end
        detect.lastAction = curAction
        if now - detect.subStart >= 0.5 then
            detect.sub = "press"
            detect.subStart = now
            detect.hit = false
        end
    elseif detect.sub == "press" then
        driveOutput(ch.kind, ch.mask, true, padDevices)
        if learnedActions[curAction] then detect.hit = true end
        if now - detect.subStart >= 0.15 then
            driveOutput(ch.kind, ch.mask, false, padDevices)
            detect.sub = "watch"
            detect.subStart = now
        end
    elseif detect.sub == "watch" then
        driveOutput(ch.kind, ch.mask, false, padDevices)
        if learnedActions[curAction] then detect.hit = true end
        if detect.hit then
            dlog("Channel worked: " .. ch.label)
            finishTest(ch)
        elseif now - detect.subStart >= 1.0 then
            dlog("No reaction: " .. ch.label)
            detect.i = detect.i + 1
            detect.sub = "settle"
            detect.subStart = now
            detect.lastAction = curAction
        end
    end
end

re.on_application_entry("UpdateHID", function()
    refreshPlayer()
    local padDevices = getPadDevices()

    if detect then
        status = "auto-detecting"
        toggleOn = false
        pollDetect(padDevices)
        trigPrev = true
        return
    end

    if binding then
        stopToggle("binding")
        pollBinding(padDevices)
        trigPrev = true
        return
    end

    local trig = triggerDown(padDevices)
    local pressed = trig and not trigPrev
    trigPrev = trig

    local now = os.clock()
    fireVkForCombo = fireVk()
    local comboDown = comboKeyDown()
    if comboDown then comboResumeAt = now + math.max(cfg.comboResumeMs, 0) / 1000 end
    if comboDown then pressed = false end

    local fireDown = firePhysicalDown(padDevices)
    local firePressed = false
    if not virtPrev then
        firePressed = fireDown and not firePrev
        firePrev = fireDown
    end

    local reason = blockReason()
    if reason then
        stopToggle(reason)
        return
    end

    if cancelPressed() then
        stopToggle("menu key pressed")
        return
    end

    local delay = math.max(cfg.delayMs, 0) / 1000
    local hold = math.max(cfg.holdMs, 10) / 1000

    if toggleOn and (pressed or (cfg.stopOnFire and firePressed and not comboDown)) then
        stopToggle(pressed and "toggled off" or "stopped by your fire button")
        return
    end

    if pressed then
        toggleOn = true
        nextShot = now + delay + (triggerIsOutput() and hold or 0)
        pulseEnd = 0
        status = "auto-firing"
        dbg("toggle ON")
    end

    if not toggleOn then
        releaseOutput()
        return
    end

    local paused = comboDown or now < comboResumeAt
    local virt
    if paused then
        virt = false
        nextShot = math.max(nextShot, comboResumeAt)
        status = "paused for combo"
    elseif virtPrev then
        if now >= pulseEnd then
            virt = false
            nextShot = now + delay
        else
            virt = true
        end
    elseif now >= nextShot then
        virt = true
        pulseEnd = now + hold
        shots = shots + 1
    else
        virt = false
    end
    if toggleOn and not paused then status = "auto-firing" end

    local kind = cfg.outputKind
    local mask = (kind == "pad") and cfg.outputPad or cfg.outputMouse
    driveOutput(kind, mask, virt, padDevices)
end)

local function resetAll()
    stopToggle("reset")
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    rebuildCancelSet()
    rebuildVkeys()
    rebuildComboList()
    binding, detect = nil, nil
    bindMessage = ""
    detectLog = {}
    learnedActions, learnedCount = {}, 0
    shots = 0
    trigPrev, firePrev = false, false
    saveConfig()
    log.info(MOD_TAG .. " settings reset to defaults")
end

local function dumpType(name)
    local td = sdk.find_type_definition(name)
    if not td then
        log.info(MOD_TAG .. " type not found: " .. name)
        return
    end
    for _, m in ipairs(safe(function() return td:get_methods() end) or {}) do
        local n = safe(function() return m:get_name() end)
        local np = safe(function() return m:get_num_params() end)
        log.info(string.format("%s %s :: %s (%s params)", MOD_TAG, name, tostring(n), tostring(np)))
    end
end

local function probe()
    mouseBackend.tried = false
    discoverMouse()
    log.info(MOD_TAG .. " mouse backend getter: " .. tostring(mouseBackend.getter))
    for _, key in ipairs(hookOrder) do
        local i = hookInfo[key]
        log.info(string.format("%s hooked %s kind=%s bool=%s calls=%d applied=%d failed=%s",
            MOD_TAG, key, i.kind, tostring(i.bool), i.calls, i.applied, tostring(i.failed)))
    end
    dumpType("via.hid.Mouse")
    dumpType("via.hid.MouseDevice")
    dumpType("via.hid.GamePad")
    dumpType("via.hid.GamePadDevice")
end

re.on_draw_ui(function()
    if not imgui.tree_node("Bow / Bowgun Auto Fire") then return end
    local changed, c = false, false

    c, cfg.enabled = imgui.checkbox("Enabled", cfg.enabled); changed = changed or c
    if imgui.button("Reset everything to defaults") then resetAll() end

    imgui.separator()
    local trigLabel = cfg.triggerKind == "pad" and padName(cfg.triggerCode) or vkName(cfg.triggerCode)
    imgui.text("Toggle button: " .. trigLabel .. (cfg.triggerKind == "pad" and "  (controller)" or ""))
    imgui.same_line()
    if binding and binding.what == "trigger" then
        if imgui.button("Cancel##bindtrigger") then binding = nil end
        imgui.text("Release everything, then press the key, mouse button or controller button to use")
    elseif imgui.button("Rebind##trigger") then
        binding = { what = "trigger", started = os.clock(), armed = false }
        bindMessage = ""
    end

    imgui.separator()
    imgui.text("Fire output (what gets pressed repeatedly)")
    if detect then
        if imgui.button("Cancel auto-detect") then
            detect = nil
            releaseOutput()
        end
        imgui.text(detect.msg or "")
        imgui.text("Close this menu with Insert, draw your weapon and follow the steps. Open the menu again to see results.")
    else
        if imgui.button("Auto-detect fire output") then startDetect() end
    end
    for _, line in ipairs(detectLog) do imgui.text(line) end

    local kc, newKind = imgui.combo("Output type", kindIndex(cfg.outputKind), OUTPUT_LABELS)
    if kc then
        cfg.outputKind = OUTPUT_KINDS[newKind] or "vinput"
        changed = true
    end

    if cfg.outputKind == "vinput" then
        local vc
        vc, cfg.vkeys = imgui.input_text("Fire virtual key numbers (comma list, filled by Auto-detect)", cfg.vkeys)
        if vc then
            rebuildVkeys()
            changed = true
        end
        imgui.text(string.format("Virtual input hook: %s   controller found: %s   calls: %d   keys written: %d",
            vin.hooked and "installed" or "NOT installed", tostring(vin.controller ~= nil), vin.calls, vin.applied))
        if vin.err then imgui.text_colored("Virtual input: " .. vin.err, 0xFF4444FF) end
        if #VKEYS == 0 then
            imgui.text("No fire keys yet: press Auto-detect and fire once normally.")
        end
    elseif cfg.outputKind == "pad" then
        imgui.text("Controller fire input: " .. padName(cfg.outputPad))
        if binding and binding.what == "output" then
            if imgui.button("Cancel##bindoutput") then binding = nil end
            imgui.text("Release everything, then press the controller button to fire with")
        elseif imgui.button("Press a controller button##output") then
            binding = { what = "output", started = os.clock(), armed = false }
            bindMessage = ""
        end
    else
        local mc, newMouse = imgui.combo("Mouse button", mouseChoiceIndex(cfg.outputMouse), MOUSE_CHOICES)
        if mc then
            cfg.outputMouse = mouseBitFor(newMouse)
            changed = true
        end
    end
    if bindMessage ~= "" then imgui.text(bindMessage) end

    imgui.separator()
    c, cfg.holdMs = imgui.slider_int("Press length (ms, how long each shot is held)", cfg.holdMs, 10, 2000)
    changed = changed or c
    c, cfg.delayMs = imgui.slider_int("Delay between shots (ms)", cfg.delayMs, 0, 5000)
    changed = changed or c
    c, cfg.stopOnFire = imgui.checkbox("Stop auto fire when I press the fire button myself", cfg.stopOnFire)
    changed = changed or c

    imgui.separator()
    c, cfg.bow = imgui.checkbox("Bow", cfg.bow); changed = changed or c
    imgui.same_line()
    c, cfg.heavyBowgun = imgui.checkbox("Heavy Bowgun", cfg.heavyBowgun); changed = changed or c
    imgui.same_line()
    c, cfg.lightBowgun = imgui.checkbox("Light Bowgun", cfg.lightBowgun); changed = changed or c

    imgui.separator()
    c, cfg.cursorGuard = imgui.checkbox("Stop and ignore the toggle while the game cursor is visible (menus)", cfg.cursorGuard)
    changed = changed or c
    imgui.separator()
    imgui.text("Combos: while one of these keys is held, auto fire pauses and then resumes by itself")
    c, cfg.comboKeys = imgui.input_text("Combo keys (VK numbers, comma list)", cfg.comboKeys)
    if c then
        rebuildComboList()
        changed = true
    end
    local names = {}
    for _, vk in ipairs(COMBO_LIST) do names[#names + 1] = vkName(vk) end
    imgui.text("Current combo keys: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    if binding and binding.what == "combo" then
        if imgui.button("Cancel##bindcombo") then binding = nil end
        imgui.text("Release everything, then press the key to add")
    elseif imgui.button("Add a combo key (press it)") then
        binding = { what = "combo", started = os.clock(), armed = false }
        bindMessage = ""
    end
    c, cfg.comboResumeMs = imgui.slider_int("Wait after a combo key is released (ms)", cfg.comboResumeMs, 0, 3000)
    changed = changed or c
    imgui.separator()
    c, cfg.cancelKeys = imgui.input_text("Keys that stop auto fire (VK numbers, comma list)", cfg.cancelKeys)
    if c then
        rebuildCancelSet()
        changed = true
    end
    c, cfg.debugLog = imgui.checkbox("Debug log", cfg.debugLog); changed = changed or c
    if changed then saveConfig() end

    imgui.separator()
    imgui.text(string.format("Weapon %d%s  drawn=%s  riding=%s", weaponType,
        WEAPON_NAMES[weaponType] and (" (" .. WEAPON_NAMES[weaponType] .. ")") or "",
        tostring(weaponDrawn), tostring(riding)))
    imgui.text(string.format("Auto fire: %s   status: %s   shots sent: %d",
        toggleOn and "ON" or "off", status, shots))
    imgui.text("Player action: " .. actionText(curAction) .. "   learned fire actions: " .. tostring(learnedCount))
    imgui.text(string.format("Controller input now: %s", padName(padBits(getPadDevices()))))
    imgui.text("Mouse device write backend: " .. tostring(mouseBackend.getter or (mouseBackend.tried and "not found" or "not checked yet")))
    local nHooks, nCalled, nApplied = 0, 0, 0
    for _, key in ipairs(hookOrder) do
        local i = hookInfo[key]
        if not i.failed then nHooks = nHooks + 1 end
        if i.calls > 0 then nCalled = nCalled + 1 end
        nApplied = nApplied + i.applied
    end
    imgui.text(string.format("Mouse hooks: %d installed, %d read by the game so far, %d overrides applied", nHooks, nCalled, nApplied))
    local cv = cursorVisible()
    imgui.text("Game cursor visible: " .. (cv == nil and "n/a" or tostring(cv)))
    if not outputOk and toggleOn then
        imgui.text_colored("Output not available for this type. Try another output type or Auto-detect.", 0xFF4444FF)
    end

    if imgui.tree_node("Mouse hook activity") then
        for _, key in ipairs(hookOrder) do
            local i = hookInfo[key]
            imgui.text(string.format("%s  kind=%s  calls=%d  overrides=%d%s", key, i.kind, i.calls, i.applied,
                i.failed and "  HOOK FAILED" or ""))
        end
        imgui.tree_pop()
    end
    if imgui.tree_node("Mouse API methods found in the game") then
        for _, line in ipairs(apiLines) do imgui.text(line) end
        imgui.tree_pop()
    end

    if imgui.button("Probe input API (writes to REFramework log)") then probe() end
    imgui.tree_pop()
end)

log.info(MOD_TAG .. " loaded")
