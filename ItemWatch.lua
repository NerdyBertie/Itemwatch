local ADDON_NAME, ns = ...

-- Default saved-variable structure
local defaults = {
    items = {},      -- list of { id = itemID, point = "CENTER", x = 0, y = 0 }
    locked = false,
    selectedSound = { type = "file", id = 558132, name = "Peon - Work Complete!" },
    box = { point = "CENTER", x = 0, y = 150, width = 220, height = 180 },
    hideInCombat = false,
    hideInPetBattles = false,
    minimapIcon = { hide = false },
}

local MIN_BOX_WIDTH, MIN_BOX_HEIGHT = 160, 100

local frames = {}    -- itemID -> frame
local FRAME_SIZE = 36

-- Plays the "goal reached" sound for a specific tracked item - its own
-- custom sound if it has one set, otherwise the global default sound.
local function PlayGoalSound(entry)
    local sel = (entry and entry.sound) or (ItemWatchDB and ItemWatchDB.selectedSound)
    if not sel then return end
    if sel.type == "kit" and SOUNDKIT and SOUNDKIT[sel.id] then
        PlaySound(SOUNDKIT[sel.id], "Master")
    elseif sel.type == "file" and sel.id then
        PlaySoundFile(sel.id, "Master")
    end
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

local itemBox = nil
local inCombat = false
local inPetBattle = false

-- Hides or shows the box based on current combat/pet-battle state and
-- whatever the player's chosen in settings. Tracking still runs in the
-- background while hidden - counts stay accurate, nothing gets lost,
-- the box just doesn't visually interrupt combat or a pet battle.
local function UpdateBoxVisibility()
    if not itemBox then return end
    local shouldHide = (inCombat and ItemWatchDB.hideInCombat) or
                        (inPetBattle and ItemWatchDB.hideInPetBattles)
    if shouldHide then
        itemBox:Hide()
    else
        itemBox:Show()
    end
end
local LayoutBox -- forward declaration; defined after item frames are set up below
local HandleItemDroppedOnBox -- forward declaration; defined after AddItem below
local RemoveItem -- forward declaration; defined further below, but CreateItemFrame needs it for right-click
local OpenQuickAddPopup -- forward declaration; defined after AddItem/SetGoal/ToggleSound below
local OpenItemEditPopup -- forward declaration; defined after SetGoal/ToggleSound/SetItemSound below

-- Builds the empty Item Box container frame - movable, resizable, with a
-- title bar. Item icons get placed inside this in a later step; for now
-- it's just the shell so we can confirm it shows up and behaves correctly.
local function CreateItemBox()
    local box = CreateFrame("Frame", "ItemWatchBox", UIParent, "BackdropTemplate")
    box:SetSize(ItemWatchDB.box.width, ItemWatchDB.box.height)
    box:SetPoint(ItemWatchDB.box.point, UIParent, ItemWatchDB.box.point, ItemWatchDB.box.x, ItemWatchDB.box.y)
    box:SetMovable(true)
    box:SetResizable(true)
    box:SetClampedToScreen(true)

    if box.SetResizeBounds then
        box:SetResizeBounds(MIN_BOX_WIDTH, MIN_BOX_HEIGHT)
    else
        box:SetMinResize(MIN_BOX_WIDTH, MIN_BOX_HEIGHT) -- older API, kept for compatibility
    end

    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Title bar doubles as the drag handle
    local titleBar = CreateFrame("Frame", nil, box)
    titleBar:SetHeight(20)
    titleBar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("ItemWatch")

    -- Small "+" button to open the quick-add popup (for items you don't
    -- have in your bags yet, so there's nothing to drag)
    local addBtn = CreateFrame("Button", nil, titleBar)
    addBtn:SetSize(22, 22)
    addBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    local addBtnFS = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    addBtnFS:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
    addBtnFS:SetText("+")
    addBtnFS:SetTextColor(0.4, 1, 0.4)
    addBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    addBtn:SetScript("OnClick", function()
        if OpenQuickAddPopup then OpenQuickAddPopup() end
    end)
    addBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Track a new item")
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    titleBar:SetScript("OnDragStart", function()
        if not ItemWatchDB.locked then
            box:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        box:StopMovingOrSizing()
        local point, _, _, x, y = box:GetPoint()
        ItemWatchDB.box.point = point
        ItemWatchDB.box.x = x
        ItemWatchDB.box.y = y
    end)

    -- Resize handle, bottom-right corner
    local resizeHandle = CreateFrame("Button", nil, box)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeHandle:SetScript("OnMouseDown", function()
        if not ItemWatchDB.locked then
            box:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        box:StopMovingOrSizing()
        ItemWatchDB.box.width = box:GetWidth()
        ItemWatchDB.box.height = box:GetHeight()
        if LayoutBox then LayoutBox() end
    end)

    box:SetClipsChildren(true)

    -- Content area sits below the title bar - icons get positioned within this
    local content = CreateFrame("Frame", nil, box)
    content:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -24)
    content:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    box.content = content

    content:EnableMouse(true)
    content:SetScript("OnReceiveDrag", function()
        if HandleItemDroppedOnBox then HandleItemDroppedOnBox() end
    end)
    content:SetScript("OnMouseUp", function(self, button)
        if CursorHasItem() and HandleItemDroppedOnBox then
            HandleItemDroppedOnBox()
        elseif button == "RightButton" and OpenQuickAddPopup then
            OpenQuickAddPopup()
        end
    end)

    return box
end

-- Builds one icon+count button for a tracked item, living inside the box grid.
-- Right-click removes it from tracking. Individual items no longer drag
-- independently - the box itself is what you move; items just occupy a grid slot.
local function CreateItemFrame(entry)
    local f = CreateFrame("Button", "ItemWatchFrame"..entry.id, itemBox.content, "BackdropTemplate")
    f:SetSize(FRAME_SIZE, FRAME_SIZE)
    f:RegisterForClicks("RightButtonUp", "LeftButtonUp")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the default icon border

    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            RemoveItem(entry.id)
        elseif button == "LeftButton" then
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                local _, itemLink = GetItemInfo(entry.id)
                if itemLink and HandleModifiedItemClick then
                    HandleModifiedItemClick(itemLink)
                end
            elseif IsModifierKeyDown and IsModifierKeyDown() then
                -- Covers other modified-click types (dressup, AH search, etc.)
                -- the same way Blizzard's own item buttons handle them
                local _, itemLink = GetItemInfo(entry.id)
                if itemLink and HandleModifiedItemClick then
                    HandleModifiedItemClick(itemLink)
                end
            else
                if OpenItemEditPopup then OpenItemEditPopup(entry.id) end
            end
        end
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(entry.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: edit goal/sound", 0.6, 0.8, 1)
        GameTooltip:AddLine("Shift-click: link in chat", 0.6, 0.8, 1)
        GameTooltip:AddLine("Right-click: stop tracking", 1, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- Arranges every tracked item's frame into a grid inside the box, reflowing
-- automatically to fit however many columns the current box width allows.
function LayoutBox()
    if not itemBox then return end
    local gap = 4
    local availableWidth = itemBox.content:GetWidth()
    local columns = math.max(1, math.floor((availableWidth + gap) / (FRAME_SIZE + gap)))

    local col, row = 0, 0
    for _, entry in ipairs(ItemWatchDB.items) do
        local f = frames[entry.id]
        if f then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", itemBox.content, "TOPLEFT",
                col * (FRAME_SIZE + gap), -row * (FRAME_SIZE + gap))
            f:Show()
            col = col + 1
            if col >= columns then
                col = 0
                row = row + 1
            end
        end
    end
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
                    PlayGoalSound(entry)
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

    local entry = { id = itemID, goal = nil, soundEnabled = true, goalReached = false }
    table.insert(ItemWatchDB.items, entry)
    frames[itemID] = CreateItemFrame(entry)
    RefreshFrame(entry)
    if LayoutBox then LayoutBox() end
    print("|cff00ff00ItemWatch:|r now tracking item "..itemID..".")
end

-- Called when something is dropped onto the box's content area. Reads
-- whatever's on the cursor (from a bag slot, or elsewhere), and if it's
-- an item, starts tracking it the same way /iw add would.
function HandleItemDroppedOnBox()
    local cursorType, _, itemLink = GetCursorInfo()
    if cursorType == "item" then
        local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
        ClearCursor()
        if itemID then
            AddItem(itemID)
        end
    else
        ClearCursor()
    end
end

-- Ctrl+Shift+Click an item in your default bags to add it, instead of typing the item ID manually.
-- Only works with Blizzard's default bag UI, since bag-replacement addons build their own click handling.
-- Wrapped in an existence check so a future Blizzard API rename disables just this feature, not the whole addon.
if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnClick then
    hooksecurefunc(ContainerFrameItemButtonMixin, "OnClick", function(self, button)
        if IsControlKeyDown() and IsShiftKeyDown() then
            local bagID = (self.GetBagID and self:GetBagID()) or self:GetParent():GetID()
            local slotID = self:GetID()
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                AddItem(info.itemID)
            end
        end
    end)
end

function RemoveItem(itemID)
    for i, entry in ipairs(ItemWatchDB.items) do
        if entry.id == itemID then
            if frames[itemID] then
                frames[itemID]:Hide()
                frames[itemID] = nil
            end
            table.remove(ItemWatchDB.items, i)
            print("|cff00ff00ItemWatch:|r stopped tracking item "..itemID)
            if LayoutBox then LayoutBox() end
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

-- Sets a specific sound for one tracked item, overriding the global default.
-- Pass choice = nil to clear the override and go back to using the default.
local function SetItemSound(itemID, choice)
    local entry = FindEntry(itemID)
    if not entry then
        print("|cffff8800ItemWatch:|r item "..itemID.." isn't tracked.")
        return
    end
    entry.sound = choice
    print("|cff00ff00ItemWatch:|r sound for item "..itemID.." set to "..(choice and choice.name or "default"))
end

-- Available preset sounds. Confirmed working during testing: Peon, Ready Check, Achievement
-- chime, Coin sound. type="file" uses PlaySoundFile with a FileDataID; type="kit" uses
-- PlaySound with a SOUNDKIT name.
local SOUND_PRESETS = {
    { type = "file", id = 558132, name = "Peon - Work Complete!" },
    { type = "kit", id = "READY_CHECK", name = "Ready Check (loud!)" },
    { type = "kit", id = "ACHIEVEMENT_MENU_OPEN", name = "Achievement Chime (quiet)" },
    { type = "kit", id = "MONEY_FRAME_OPEN", name = "Coin Sound (quiet)" },
}

-- Sentinel table representing "explicitly no sound for this item" - distinct
-- from nil, which instead means "follow whatever the global default is"
local MUTED_SOUND = { muted = true, name = "No sound (silent)" }

-- Compares two sound choices for equality, handling nil (default), the
-- muted sentinel (compared by reference), and preset tables (by name)
local function SoundChoicesMatch(a, b)
    if a == b then return true end
    if a and b and a.name and b.name then return a.name == b.name end
    return false
end

local optionButtons = {}

-- Creates a radio-style checkbutton with our own label, rather than relying on
-- whatever the template's built-in text region happens to be named (this varies).
local function CreateOptionRadio(parent, labelText)
    local btn = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    local label = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    label:SetText(labelText)
    btn.label = label
    return btn
end

local function SelectSound(choice)
    ItemWatchDB.selectedSound = choice
    for _, btn in ipairs(optionButtons) do
        btn:SetChecked(btn.choice and btn.choice.name == choice.name)
    end
end

local optionsCategory = nil

local function OpenItemWatchOptions()
    if Settings and Settings.OpenToCategory and optionsCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("ItemWatch")
    else
        print("|cffff8800ItemWatch:|r couldn't open settings automatically - check Options > AddOns > ItemWatch manually.")
    end
end

-- Creates the minimap button via LibDataBroker + LibDBIcon (standard shared
-- libraries most WoW addons use for this). Left-click toggles the Item Box,
-- right-click opens settings. Because it's a proper LibDBIcon object, it
-- automatically gets picked up by any minimap-button "tray" addon someone
-- already has installed (ElvUI, Dominos, Bartender4, MBB, SexyMap, etc.) -
-- no extra work needed for that compatibility, it comes from following the
-- shared convention.
local function CreateMinimapButton()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not DBIcon then
        print("|cffff8800ItemWatch:|r minimap button libraries didn't load - the box and /iw commands still work fine.")
        return
    end

    local dataObject = LDB:NewDataObject("ItemWatch", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Sigil_UlduarAll",
        OnClick = function(self, button)
            if button == "LeftButton" then
                if itemBox then
                    if itemBox:IsShown() then
                        itemBox:Hide()
                    else
                        itemBox:Show()
                    end
                end
            elseif button == "RightButton" then
                OpenItemWatchOptions()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("ItemWatch")
            tooltip:AddLine("Left-click: show/hide the box", 0.8, 0.8, 0.8)
            tooltip:AddLine("Right-click: open settings", 0.8, 0.8, 0.8)
        end,
    })

    DBIcon:Register("ItemWatch", dataObject, ItemWatchDB.minimapIcon)
end

local quickAddFrame = nil

-- Pulls a plain item ID out of either a raw number, a Wowhead URL/link, or
-- an itemString like "item:12345:...". Returns nil if nothing usable is found.
local function ParseItemIDInput(text)
    if not text or text == "" then return nil end
    text = text:match("^%s*(.-)%s*$") -- trim whitespace

    -- Plain number, e.g. "12345"
    local plain = tonumber(text)
    if plain then return plain end

    -- Wowhead URL, e.g. "https://www.wowhead.com/item=12345/strange-goop"
    local fromUrl = text:match("item=(%d+)")
    if fromUrl then return tonumber(fromUrl) end

    -- Item link/string, e.g. "item:12345:0:0:..."
    local fromLink = text:match("item:(%d+)")
    if fromLink then return tonumber(fromLink) end

    return nil
end

-- Builds the quick-add popup: one panel to set item ID (or a pasted Wowhead
-- link), an optional goal amount, and whether to play a sound on completion -
-- instead of needing three separate /iw commands. This is also the only way
-- to start tracking an item you don't have yet, since drag-and-drop requires
-- the item to already be in your bags.
local function CreateQuickAddPopup()
    local panel = CreateFrame("Frame", "ItemWatchQuickAdd", UIParent, "BackdropTemplate")
    panel:SetSize(340, 230)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("Track a New Item")

    -- Item ID / Wowhead link field
    local idLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -44)
    idLabel:SetWidth(300)
    idLabel:SetJustifyH("LEFT")
    idLabel:SetWordWrap(true)
    idLabel:SetText("Item ID, Wowhead link, or shift-click item:")

    local idBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    idBox:SetSize(290, 20)
    idBox:SetAutoFocus(true)
    idBox:SetPoint("TOPLEFT", idLabel, "BOTTOMLEFT", 6, -6)
    idBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); panel:Hide() end)
    panel.idBox = idBox

    -- Goal amount field (optional)
    local goalLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goalLabel:SetPoint("TOPLEFT", idBox, "BOTTOMLEFT", -6, -14)
    goalLabel:SetText("Goal amount (optional):")

    local goalBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    goalBox:SetSize(80, 20)
    goalBox:SetAutoFocus(false)
    goalBox:SetNumeric(true)
    goalBox:SetPoint("TOPLEFT", goalLabel, "BOTTOMLEFT", 6, -6)
    goalBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); panel:Hide() end)
    panel.goalBox = goalBox

    -- Sound checkbox
    local soundCheck = CreateFrame("CheckButton", "ItemWatchQuickAddSoundCheck", panel, "UICheckButtonTemplate")
    soundCheck:SetSize(24, 24)
    soundCheck:SetPoint("LEFT", goalBox, "RIGHT", 20, 0)
    soundCheck:SetChecked(true)
    if soundCheck.Text then soundCheck.Text:SetText("") end
    panel.soundCheck = soundCheck

    local soundLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundLabel:SetPoint("LEFT", soundCheck, "RIGHT", 0, 0)
    soundLabel:SetText("Play sound on goal")

    -- Quick reminder - the sound only fires once a goal is set AND reached,
    -- easy to miss since the checkbox alone doesn't do anything on its own
    local hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintText:SetPoint("TOPLEFT", goalBox, "BOTTOMLEFT", -6, -8)
    hintText:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    hintText:SetJustifyH("LEFT")
    hintText:SetTextColor(0.4, 1, 0.4)
    hintText:SetText("Tip: set a goal amount above if you want the sound to play.")

    -- Error/status text
    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", panel, "BOTTOM", 0, 42)
    statusText:SetTextColor(1, 0.4, 0.4)
    panel.statusText = statusText

    -- Track button
    local trackBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    trackBtn:SetSize(90, 22)
    trackBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 16)
    trackBtn:SetText("Track")
    trackBtn:SetScript("OnClick", function()
        local rawText = idBox:GetText()
        local itemID = ParseItemIDInput(rawText)
        if not itemID then
            statusText:SetText("Enter a valid item ID or Wowhead link.")
            print("|cffff8800ItemWatch debug:|r raw field text was: ["..tostring(rawText).."] (length "..#(rawText or "")..")")
            return
        end

        AddItem(itemID)

        local goalText = goalBox:GetText()
        if goalText and goalText ~= "" then
            local amount = tonumber(goalText)
            if amount and amount > 0 then
                SetGoal(itemID, amount)
            end
        end

        ToggleSound(itemID, soundCheck:GetChecked() and true or false)

        panel:Hide()
    end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Registering with UISpecialFrames means Blizzard's own Escape-key
    -- handling will close this automatically, same as any other WoW panel
    tinsert(UISpecialFrames, "ItemWatchQuickAdd")

    return panel
end

function OpenQuickAddPopup()
    if not quickAddFrame then return end
    quickAddFrame.idBox:SetText("")
    quickAddFrame.goalBox:SetText("")
    quickAddFrame.soundCheck:SetChecked(true)
    quickAddFrame.statusText:SetText("")
    quickAddFrame:Show()
    quickAddFrame.idBox:SetFocus()
end

-- Shift-clicking an item calls the global HandleModifiedItemClick with the
-- item's link, regardless of whether any chat box is even open. We use a
-- secure post-hook (hooksecurefunc, not an override) so we're only ever
-- observing after Blizzard's own handling runs - this can't taint anything,
-- unlike replacing the function outright. If our quick-add popup's item ID
-- field is focused when a shift-click happens, we drop the link in there.
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(itemLink)
        if itemLink and quickAddFrame and quickAddFrame:IsShown() and quickAddFrame.idBox:HasFocus() then
            quickAddFrame.idBox:SetText(itemLink)
            quickAddFrame.idBox:HighlightText(0, 0)
            quickAddFrame.idBox:SetCursorPosition(#itemLink)
        end
    end)
end

local itemEditFrame = nil
local itemEditButtons = {}

-- Builds the per-item edit popup - lets you change an already-tracked
-- item's goal amount and pick its own custom "goal reached" sound
-- (or leave it on "Use default" to follow the global default sound).
-- Opened by left-clicking a tracked item's icon inside the box.
local function CreateItemEditPopup()
    local panel = CreateFrame("Frame", "ItemWatchItemEdit", UIParent, "BackdropTemplate")
    panel:SetSize(280, 370)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", panel, "TOP", 0, -16)
    panel.icon = icon

    local nameText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOP", icon, "BOTTOM", 0, -6)
    panel.nameText = nameText

    local goalLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goalLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -80)
    goalLabel:SetText("Goal amount (blank = none):")

    local goalBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    goalBox:SetSize(80, 20)
    goalBox:SetAutoFocus(false)
    goalBox:SetNumeric(true)
    goalBox:SetPoint("TOPLEFT", goalLabel, "BOTTOMLEFT", 6, -6)
    goalBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); panel:Hide() end)
    panel.goalBox = goalBox

    local soundLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundLabel:SetPoint("TOPLEFT", goalBox, "BOTTOMLEFT", -6, -18)
    soundLabel:SetText("Goal-reached sound for this item:")

    wipe(itemEditButtons)
    local lastBtn = nil

    local defaultBtn = CreateOptionRadio(panel, "Use default sound")
    defaultBtn:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 6, -12)
    defaultBtn.choice = nil
    table.insert(itemEditButtons, defaultBtn)
    lastBtn = defaultBtn

    for _, choice in ipairs(SOUND_PRESETS) do
        local btn = CreateOptionRadio(panel, choice.name)
        btn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -10)
        btn.choice = choice
        table.insert(itemEditButtons, btn)
        lastBtn = btn
    end

    local muteBtn = CreateOptionRadio(panel, MUTED_SOUND.name)
    muteBtn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -10)
    muteBtn.choice = MUTED_SOUND
    table.insert(itemEditButtons, muteBtn)

    local function SelectEditSound(choice)
        panel.selectedSound = choice
        for _, btn in ipairs(itemEditButtons) do
            btn:SetChecked(SoundChoicesMatch(btn.choice, choice))
        end
    end
    panel.SelectEditSound = SelectEditSound

    for _, btn in ipairs(itemEditButtons) do
        btn:SetScript("OnClick", function() SelectEditSound(btn.choice) end)
    end

    local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 16)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local itemID = panel.itemID
        if not itemID then panel:Hide() return end

        local goalText = goalBox:GetText()
        if goalText and goalText ~= "" then
            local amount = tonumber(goalText)
            if amount and amount > 0 then
                SetGoal(itemID, amount)
            end
        else
            ClearGoal(itemID)
        end

        if panel.selectedSound == MUTED_SOUND then
            ToggleSound(itemID, false)
            SetItemSound(itemID, nil)
        else
            ToggleSound(itemID, true)
            SetItemSound(itemID, panel.selectedSound)
        end

        panel:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)

    tinsert(UISpecialFrames, "ItemWatchItemEdit")

    return panel
end

function OpenItemEditPopup(itemID)
    if not itemEditFrame then return end
    local entry = FindEntry(itemID)
    if not entry then return end

    itemEditFrame.itemID = itemID
    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    itemEditFrame.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    itemEditFrame.nameText:SetText(name or ("Item #"..itemID))
    itemEditFrame.goalBox:SetText(entry.goal and tostring(entry.goal) or "")

    if entry.soundEnabled == false then
        itemEditFrame:SelectEditSound(MUTED_SOUND)
    else
        itemEditFrame:SelectEditSound(entry.sound)
    end

    itemEditFrame:Show()
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "ItemWatch"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ItemWatch")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Choose the sound played when a tracked item's goal is reached.")

    local lastButton = nil
    for _, choice in ipairs(SOUND_PRESETS) do
        local btn = CreateOptionRadio(panel, choice.name)
        btn.choice = choice
        if lastButton then
            btn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -12)
        else
            btn:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
        end
        btn:SetScript("OnClick", function() SelectSound(choice) end)
        table.insert(optionButtons, btn)
        lastButton = btn
    end

    -- Custom sound ID option
    local customBtn = CreateOptionRadio(panel, "Custom FileDataID:")
    customBtn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -12)
    table.insert(optionButtons, customBtn)

    local customBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    customBox:SetSize(100, 20)
    customBox:SetAutoFocus(false)
    customBox:SetPoint("LEFT", customBtn.label, "RIGHT", 12, 0)
    customBox:SetNumeric(true)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", customBtn, "BOTTOMLEFT", 4, -6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Find sound IDs at wago.tools/files, or browse wowhead.com/sounds for something easier to search.")

    customBtn.choice = nil -- filled in dynamically below
    customBtn:SetScript("OnClick", function()
        local id = tonumber(customBox:GetText())
        if id then
            local choice = { type = "file", id = id, name = "Custom FileDataID: "..id }
            customBtn.choice = choice
            SelectSound(choice)
        else
            print("|cffff8800ItemWatch:|r enter a numeric FileDataID first. Find one by browsing wago.tools/files, or search wowhead.com/sounds for something easier to look through.")
            customBtn:SetChecked(false)
        end
    end)

    -- Test button
    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -12)
    testBtn:SetText("Test Sound")
    testBtn:SetScript("OnClick", function() PlayGoalSound() end)

    -- Visibility section
    local visTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    visTitle:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 4, -28)
    visTitle:SetText("Visibility")

    local visSubtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    visSubtitle:SetPoint("TOPLEFT", visTitle, "BOTTOMLEFT", 0, -8)
    visSubtitle:SetText("Tracking keeps running in the background even while hidden - nothing is lost.")

    local combatCheck = CreateFrame("CheckButton", "ItemWatchHideCombatCheck", panel, "UICheckButtonTemplate")
    combatCheck:SetPoint("TOPLEFT", visSubtitle, "BOTTOMLEFT", -2, -16)
    _G["ItemWatchHideCombatCheckText"]:SetText("Hide box during combat")
    combatCheck:SetScript("OnClick", function(self)
        ItemWatchDB.hideInCombat = self:GetChecked() and true or false
        UpdateBoxVisibility()
    end)
    panel.combatCheck = combatCheck

    local petBattleCheck = CreateFrame("CheckButton", "ItemWatchHidePetBattleCheck", panel, "UICheckButtonTemplate")
    petBattleCheck:SetPoint("TOPLEFT", combatCheck, "BOTTOMLEFT", 0, -8)
    _G["ItemWatchHidePetBattleCheckText"]:SetText("Hide box during pet battles")
    petBattleCheck:SetScript("OnClick", function(self)
        ItemWatchDB.hideInPetBattles = self:GetChecked() and true or false
        UpdateBoxVisibility()
    end)
    panel.petBattleCheck = petBattleCheck

    local minimapCheck = CreateFrame("CheckButton", "ItemWatchShowMinimapCheck", panel, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", petBattleCheck, "BOTTOMLEFT", 0, -8)
    _G["ItemWatchShowMinimapCheckText"]:SetText("Show minimap button")
    minimapCheck:SetScript("OnClick", function(self)
        local shouldShow = self:GetChecked() and true or false
        ItemWatchDB.minimapIcon.hide = not shouldShow
        local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if DBIcon then
            if shouldShow then
                DBIcon:Show("ItemWatch")
            else
                DBIcon:Hide("ItemWatch")
            end
        end
    end)
    panel.minimapCheck = minimapCheck

    panel:SetScript("OnShow", function()
        for _, btn in ipairs(optionButtons) do
            if btn.choice and ItemWatchDB.selectedSound and btn.choice.name == ItemWatchDB.selectedSound.name then
                btn:SetChecked(true)
            else
                btn:SetChecked(false)
            end
        end
        combatCheck:SetChecked(ItemWatchDB.hideInCombat)
        petBattleCheck:SetChecked(ItemWatchDB.hideInPetBattles)
        minimapCheck:SetChecked(not ItemWatchDB.minimapIcon.hide)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ItemWatchDB = CopyDefaults(defaults, ItemWatchDB or {})
        itemBox = CreateItemBox()
        quickAddFrame = CreateQuickAddPopup()
        itemEditFrame = CreateItemEditPopup()
        for _, entry in ipairs(ItemWatchDB.items) do
            frames[entry.id] = CreateItemFrame(entry)
        end
        RefreshAll()
        if LayoutBox then LayoutBox() end
        BuildOptionsPanel()
        CreateMinimapButton()
        UpdateBoxVisibility()
    elseif event == "BAG_UPDATE_DELAYED" then
        RefreshAll()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- item data can arrive late from the server; refresh once it's in
        RefreshAll()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateBoxVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateBoxVisibility()
    elseif event == "PET_BATTLE_OPENING_START" then
        inPetBattle = true
        UpdateBoxVisibility()
    elseif event == "PET_BATTLE_CLOSE" then
        inPetBattle = false
        UpdateBoxVisibility()
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
    elseif cmd == "options" or cmd == "config" then
        OpenItemWatchOptions()
    elseif cmd == "testsound" then
        PlayGoalSound()
        print("|cff00ff00ItemWatch:|r played the goal sound (if you didn't hear it, check your Sound Effects volume in Options).")
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
        print("Ctrl+Shift+Click an item in your bags to add it directly")
        print("/iw add <itemID> - start tracking an item")
        print("/iw remove <itemID> - stop tracking an item")
        print("/iw list - list tracked items")
        print("/iw clear - remove ALL tracked items (asks to confirm)")
        print("/iw lock / unlock - lock or unlock frame positions")
        print("/iw goal <itemID> <amount> - set a target (shows count/goal, turns green when met)")
        print("/iw goal <itemID> clear - remove the goal")
        print("/iw sound <itemID> on|off - toggle the goal-reached sound for that item")
        print("/iw testsound - play the goal sound right now, to test it")
        print("/iw options - open the settings panel to pick your alert sound")
    end
end
