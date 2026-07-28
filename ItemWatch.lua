local ADDON_NAME, ns = ...

-- Default saved-variable structure
local defaults = {
    items = {},      -- list of { id = itemID, point = "CENTER", x = 0, y = 0 }
    locked = false,
}

local frames = {}    -- itemID -> frame
local FRAME_SIZE = 36

-- Plays a short "goal reached" chime
local function PlayGoalSound()
    PlaySoundFile("Sound\\Interface\\LevelUp2.ogg", "Master")
end

-- Confirmation popup for clearing every tracked item at once
StaticPopupDialogs["ITEMWATCH_CONFIRM_CLEAR"] = {
    text = "Clear ALL ItemWatch tracked items on this character?",
    button1 = "Clear All",
    button2 = "Cancel",
    OnAccept = function()
        for _, f in pairs(frames) do
            f:Hide()
        end
        wipe(frames)
        wipe(ItemWatchDB.items)
        print("|cff00ff00ItemWatch:|r cleared all tracked items.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Fills in any missing keys in dst using values from src (used to init/upgrade the DB)
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Builds one draggable icon+count frame for a tracked item
local function CreateItemFrame(entry)
    local f = CreateFrame("Button", "ItemWatchFrame"..entry.id, UIParent, "BackdropTemplate")
    f:SetSize(FRAME_SIZE, FRAME_SIZE)
    f:SetPoint(entry.point or "CENTER", UIParent, entry.point or "CENTER", entry.x or 0, entry.y or 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the default icon border

    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

    f:SetScript("OnDragStart", function(self)
        if not ItemWatchDB.locked then
            self:StartMoving()
        end
    end)

    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        entry.point = point
        entry.x = x
        entry.y = y
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(entry.id)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- Refreshes icon texture + count text for one tracked item
local function RefreshFrame(entry)
    local f = frames[entry.id]
    if not f then return end

    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(entry.id)
    if icon then
        f.icon:SetTexture(icon)
    end

    local count = C_Item.GetItemCount(entry.id, false, false, true)

    if entry.goal then
        f.count:SetText(count.."/"..entry.goal)

        if count >= entry.goal then
            f.count:SetTextColor(0.2, 1, 0.2) -- green once goal is met
            if not entry.goalReached then
                entry.goalReached = true
                if entry.soundEnabled then
                    PlayGoalSound()
                end
                print("|cff00ff00ItemWatch:|r goal reached for "..(GetItemInfo(entry.id) or ("item #"..entry.id))..
                      " ("..count.."/"..entry.goal..")")
            end
        else
            f.count:SetTextColor(1, 1, 1) -- back to white if below goal again
            entry.goalReached = false
        end
    else
        f.count:SetText(count)
        f.count:SetTextColor(1, 1, 1)
    end
end

local function RefreshAll()
    for _, entry in ipairs(ItemWatchDB.items) do
        RefreshFrame(entry)
    end
end

local function AddItem(itemID)
    for _, entry in ipairs(ItemWatchDB.items) do
        if entry.id == itemID then
            print("|cffff8800ItemWatch:|r item "..itemID.." is already tracked.")
            return
        end
    end

    local entry = { id = itemID, point = "CENTER", x = 0, y = 0, goal = nil, soundEnabled = true, goalReached = false }
    table.insert(ItemWatchDB.items, entry)
    frames[itemID] = CreateItemFrame(entry)
    RefreshFrame(entry)
    print("|cff00ff00ItemWatch:|r now tracking item "..itemID..". Type /iw unlock to drag it into place.")
end

-- Ctrl+Shift+Click an item in your default bags to add it, instead of typing the item ID manually.
-- Only works with Blizzard's default bag UI, since bag-replacement addons build their own click handling.
hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
    if IsControlKeyDown() and IsShiftKeyDown() then
        local bagID = self:GetParent():GetID()
        local slotID = self:GetID()
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info and info.itemID then
            AddItem(info.itemID)
        end
    end
end)

local function RemoveItem(itemID)
    for i, entry in ipairs(ItemWatchDB.items) do
        if entry.id == itemID then
            if frames[itemID] then
                frames[itemID]:Hide()
                frames[itemID] = nil
            end
            table.remove(ItemWatchDB.items, i)
            print("|cff00ff00ItemWatch:|r stopped tracking item "..itemID)
            return
        end
    end
    print("|cffff8800ItemWatch:|r item "..itemID.." wasn't being tracked.")
end

local function FindEntry(itemID)
    for _, entry in ipairs(ItemWatchDB.items) do
        if entry.id == itemID then return entry end
    end
    return nil
end

local function SetGoal(itemID, amount)
    local entry = FindEntry(itemID)
    if not entry then
        print("|cffff8800ItemWatch:|r item "..itemID.." isn't tracked yet. Use /iw add "..itemID.." first.")
        return
    end
    entry.goal = amount
    entry.goalReached = false
    RefreshFrame(entry)
    print("|cff00ff00ItemWatch:|r goal for item "..itemID.." set to "..amount)
end

local function ClearGoal(itemID)
    local entry = FindEntry(itemID)
    if not entry then
        print("|cffff8800ItemWatch:|r item "..itemID.." isn't tracked.")
        return
    end
    entry.goal = nil
    entry.goalReached = false
    RefreshFrame(entry)
    print("|cff00ff00ItemWatch:|r goal cleared for item "..itemID)
end

local function ToggleSound(itemID, state)
    local entry = FindEntry(itemID)
    if not entry then
        print("|cffff8800ItemWatch:|r item "..itemID.." isn't tracked.")
        return
    end
    entry.soundEnabled = state
    print("|cff00ff00ItemWatch:|r sound "..(state and "enabled" or "disabled").." for item "..itemID)
end

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ItemWatchDB = CopyDefaults(defaults, ItemWatchDB or {})
        for _, entry in ipairs(ItemWatchDB.items) do
            frames[entry.id] = CreateItemFrame(entry)
        end
        RefreshAll()
    elseif event == "BAG_UPDATE_DELAYED" then
        RefreshAll()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- item data can arrive late from the server; refresh once it's in
        RefreshAll()
    end
end)

-- Slash commands
SLASH_ITEMWATCH1 = "/itemwatch"
SLASH_ITEMWATCH2 = "/iw"
SlashCmdList["ITEMWATCH"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "add" then
        local id = tonumber(rest)
        if id then AddItem(id) else print("Usage: /iw add <itemID>") end
    elseif cmd == "remove" or cmd == "del" then
        local id = tonumber(rest)
        if id then RemoveItem(id) else print("Usage: /iw remove <itemID>") end
    elseif cmd == "lock" then
        ItemWatchDB.locked = true
        print("|cff00ff00ItemWatch:|r frames locked.")
    elseif cmd == "unlock" then
        ItemWatchDB.locked = false
        print("|cff00ff00ItemWatch:|r frames unlocked - drag them to move.")
    elseif cmd == "list" then
        if #ItemWatchDB.items == 0 then
            print("|cffff8800ItemWatch:|r no items tracked.")
        else
            for _, entry in ipairs(ItemWatchDB.items) do
                local name = GetItemInfo(entry.id) or ("Item #"..entry.id)
                local goalText = entry.goal and (" - goal: "..entry.goal) or ""
                print("  - "..name.." ("..entry.id..")"..goalText)
            end
        end
    elseif cmd == "clear" or cmd == "clearall" then
        StaticPopup_Show("ITEMWATCH_CONFIRM_CLEAR")
    elseif cmd == "goal" then
        local id, amount = rest:match("^(%d+)%s+(%S+)$")
        id = tonumber(id)
        if not id then
            print("Usage: /iw goal <itemID> <amount>  OR  /iw goal <itemID> clear")
        elseif amount == "clear" then
            ClearGoal(id)
        else
            local amt = tonumber(amount)
            if amt then SetGoal(id, amt) else print("Usage: /iw goal <itemID> <amount>") end
        end
    elseif cmd == "sound" then
        local id, state = rest:match("^(%d+)%s+(%S+)$")
        id = tonumber(id)
        if not id or (state ~= "on" and state ~= "off") then
            print("Usage: /iw sound <itemID> on|off")
        else
            ToggleSound(id, state == "on")
        end
    else
        print("|cff00ff00ItemWatch commands:|r")
        print("  (Ctrl+Shift+Click an item in your bags to add it directly)")
        print("  /iw add <itemID>            - start tracking an item")
        print("  /iw remove <itemID>         - stop tracking an item")
        print("  /iw list                    - list tracked items")
        print("  /iw clear                   - remove ALL tracked items (asks to confirm)")
        print("  /iw lock / unlock           - lock or unlock frame positions")
        print("  /iw goal <itemID> <amount>  - set a target amount (shows count/goal, turns green when met)")
        print("  /iw goal <itemID> clear     - remove the goal")
        print("  /iw sound <itemID> on|off   - toggle the goal-reached sound for that item")
    end
end
