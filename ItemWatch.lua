local ADDON_NAME, ns = ...

-- Default saved-variable structure
local defaults = {
    items = {},      -- list of { id = itemID, point = "CENTER", x = 0, y = 0 }
    locked = false,
}

local frames = {}    -- itemID -> frame
local FRAME_SIZE = 36

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

    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
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
    f.count:SetText(count)
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

    local entry = { id = itemID, point = "CENTER", x = 0, y = 0 }
    table.insert(ItemWatchDB.items, entry)
    frames[itemID] = CreateItemFrame(entry)
    RefreshFrame(entry)
    print("|cff00ff00ItemWatch:|r now tracking item "..itemID..". Type /iw unlock to drag it into place.")
end

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
                print("  - "..name.." ("..entry.id..")")
            end
        end
    else
        print("|cff00ff00ItemWatch commands:|r")
        print("  /iw add <itemID>    - start tracking an item")
        print("  /iw remove <itemID> - stop tracking an item")
        print("  /iw list            - list tracked items")
        print("  /iw lock / unlock   - lock or unlock frame positions")
    end
end
