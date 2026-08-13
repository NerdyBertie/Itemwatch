local ADDON_NAME, ns = ...

-- Default saved-variable structure
local defaults = {
    items = {},      -- list of { id = itemID, point = "CENTER", x = 0, y = 0 }
    locked = false,
    selectedSound = { type = "file", id = 558132, name = "Orc Peon - Work Complete!" },
    box = { point = "CENTER", x = 0, y = 150, width = 220, height = 180 },
    hideInCombat = false,
    hideInPetBattles = false,
    minimapIcon = { hide = false },
    shoppingList = {
        active = false,      -- whether there's a current shopping list to show
        dismissed = true,    -- true = window closed/hidden by the user
        recipeName = nil,
        required = {},       -- { itemID, name, perCraft, needed, isBoP }
        optional = {},       -- { itemID, name } - reminder-only, no goal tracking
        point = "CENTER", x = 0, y = -150,
        width = 260, height = 400,
        locked = false,
        craftQuantity = 1,   -- how many of the recipe you're making; scales each required reagent's "needed" amount
    },
}

local MIN_BOX_WIDTH, MIN_BOX_HEIGHT = 160, 100

local frames = {}    -- itemID -> frame
local FRAME_SIZE = 36

-- Sets the count text, sizing the font off its length. Only ever shows
-- the current count now - the goal is visible on hover and in the edit
-- popup instead, and goal-reached is signaled by the green color change.
local function SetItemCountText(fontString, text)
    local size = 13
    if #text >= 5 then
        size = 10
    elseif #text >= 4 then
        size = 11
    end
    fontString:SetFont("Fonts\\FRIZQT__.ttf", size, "OUTLINE")
    fontString:SetJustifyV("MIDDLE")
    fontString:SetText(text)
end

-- Plays the "goal reached" sound for a specific tracked item - its own
-- custom sound if it has one set, otherwise the global default sound.
local function PlayGoalSound(entry)
    local sel = (entry and entry.sound) or (ItemWatchDB and ItemWatchDB.selectedSound)
    if not sel then return end
    if sel.type == "kit" and SOUNDKIT and SOUNDKIT[sel.id] then
        PlaySound(SOUNDKIT[sel.id], "Master")
    elseif sel.type == "kitid" and sel.id then
        -- Raw numeric Sound Kit ID. PlaySound() has accepted numeric IDs
        -- directly since patch 7.3.0 (this replaced the older, now
        -- unreliable PlaySoundKitID function).
        PlaySound(sel.id, "Master")
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

-- Confirmation before replacing an already-active Shopping List. text and
-- OnAccept get overwritten per-click right before StaticPopup_Show (this
-- is standard practice for a dialog whose message depends on which recipe
-- was clicked) - failsafe against both "I changed my mind on the recipe"
-- and an accidental double-click on the button.
StaticPopupDialogs["ITEMWATCH_CONFIRM_REPLACE_SHOPPING_LIST"] = {
    text = "Replace your current Shopping List?",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function() end, -- overwritten before showing
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
-- Only true once BAG_UPDATE_DELAYED has fired at least once - the very
-- first refresh on login can happen before WoW has actually finished
-- loading bag data, which would otherwise read a false "0 items" count
-- and incorrectly reset an already-earned goal, replaying its ding.
local bagsReady = false
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
local RefreshShoppingList -- forward declaration; defined after CreateShoppingListWindow, but the window's own resize handle needs it

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

    -- Lock/unlock toggle button, does the same thing as /iw lock and
    -- /iw unlock but visually shows the current state at a glance
    local lockBtn = CreateFrame("Button", nil, titleBar)
    lockBtn:SetSize(21, 21)
    lockBtn:SetPoint("RIGHT", addBtn, "LEFT", -2, 0)
    lockBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local function UpdateLockIcon()
        if ItemWatchDB.locked then
            lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        else
            lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        end
    end
    box.UpdateLockIcon = UpdateLockIcon
    UpdateLockIcon()

    lockBtn:SetScript("OnClick", function()
        ItemWatchDB.locked = not ItemWatchDB.locked
        UpdateLockIcon()
        print("|cff00ff00ItemWatch:|r box "..(ItemWatchDB.locked and "locked" or "unlocked"))
    end)
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ItemWatchDB.locked and "Unlock box" or "Lock box")
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
-- Shows WoW's own silver/gold reagent-quality badge on a tracked item's
-- icon, if that item actually has one (only crafting reagents do - most
-- tracked items like mounts or achievement items won't). Wrapped in
-- pcall since this reads from Blizzard's crafting API, which can behave
-- unpredictably for items that aren't reagents at all.
local function UpdateQualityBadge(f, itemID)
    local quality
    local ok = pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
            quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
        end
    end)
    if ok and quality then
        f.qualityBadge:SetAtlas("Professions-Icon-Quality-Tier"..(quality + 1), false)
        f.qualityBadge:Show()
    else
        f.qualityBadge:Hide()
    end
end

local function CreateItemFrame(entry)
    local f = CreateFrame("Button", "ItemWatchFrame"..entry.id, itemBox.content, "BackdropTemplate")
    f:SetSize(FRAME_SIZE, FRAME_SIZE)
    f:RegisterForClicks("RightButtonUp", "LeftButtonUp")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the default icon border

    -- Reagent quality badge (the small silver/gold marker WoW shows on
    -- crafting reagents) - only shown for items that actually have one
    f.qualityBadge = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.qualityBadge:SetSize(14, 14)
    f.qualityBadge:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.qualityBadge:Hide()

    f.countBg = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.countBg:SetColorTexture(0, 0, 0, 0.6)
    f.countBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.countBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.countBg:SetHeight(13)

    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFont("Fonts\\FRIZQT__.ttf", 11, "OUTLINE")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1) -- pins both edges so long text shrinks instead of overflowing
    f.count:SetJustifyH("RIGHT")

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
        GameTooltip:AddLine("ItemWatch", 0.4, 1, 0.4)
        if entry.goal then
            local count = C_Item.GetItemCount(entry.id, false, false, true)
            if count >= entry.goal then
                GameTooltip:AddLine("Goal reached! ("..count.."/"..entry.goal..")", 0.2, 1, 0.2)
            else
                GameTooltip:AddLine("Progress: "..count.."/"..entry.goal, 1, 0.82, 0)
            end
        end
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
local lowCountStreak = {} -- debounce: require 2 consecutive low readings
                          -- before trusting a goal reset, since a single
                          -- transient bad read (e.g. during a zone-load
                          -- hiccup) shouldn't be enough to wipe an
                          -- already-earned goal and risk a false re-ding
local function RefreshFrame(entry)
    local f = frames[entry.id]
    if not f then return end

    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(entry.id)
    if icon then
        f.icon:SetTexture(icon)
    end

    UpdateQualityBadge(f, entry.id)

    local count = C_Item.GetItemCount(entry.id, false, false, true)

    if entry.goal then
        SetItemCountText(f.count, tostring(count))

        if count >= entry.goal then
            f.count:SetTextColor(0.2, 1, 0.2) -- green once goal is met
            lowCountStreak[entry.id] = 0
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
            if bagsReady then
                lowCountStreak[entry.id] = (lowCountStreak[entry.id] or 0) + 1
                if lowCountStreak[entry.id] >= 2 then
                    entry.goalReached = false
                end
            end
        end
    else
        SetItemCountText(f.count, tostring(count))
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
    -- If you already have enough for this new goal, mark it reached
    -- silently (no ding) - only a genuinely new completion during actual
    -- gameplay should play a sound, not just setting/editing a goal that
    -- happens to already be satisfied.
    local count = C_Item.GetItemCount(itemID, false, false, true)
    entry.goalReached = (count >= amount)
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
    { type = "file", id = 558132, name = "Orc Peon - Work Complete!" },
    -- Both Orc Peon lines together, since they're the same voice
    { type = "file", id = 558146, name = "Orc Peon - Me not that kind of orc!" },
    { type = "kit", id = "READY_CHECK", name = "Ready Check (loud!)" },
    { type = "kitid", id = 12891, name = "Achievement Ding" },
    { type = "kit", id = "MONEY_FRAME_OPEN", name = "Coin Sound (quiet)" },
    { type = "file", id = 3598637, name = "Cat Meow" },
    { type = "kitid", id = 6574, name = "Aquatic Form Burp" },
    { type = "file", id = 563010, name = "Commander Ulthok (startling - you've been warned!)" },
    { type = "file", id = 552503, name = "Illidan - You are not prepared!" },
    { type = "file", id = 5768798, name = "Brann - Here we go!", header = "Brann Bronzebeard (in case you miss him <3)" },
    { type = "file", id = 5768826, name = "Brann - Time to go all out!" },
    -- Confirmed working in-game via the Custom FileDataID tester (all 10
    -- IDs sourced from Wowhead - same "listed doesn't always mean it
    -- plays" caveat as the cut Brann "Found a bit o' gold!" line above,
    -- but these all checked out fine).
    { type = "file", id = 2922117, name = "Thrall - Lok'tar!", header = "Horde Legends (fun & thematic)" },
    { type = "file", id = 561230, name = "Sylvanas - So it is done" },
    { type = "file", id = 2416540, name = "Baine Bloodhoof - For the Horde, always" },
    { type = "file", id = 2961766, name = "Monte Gazlowe - Business is Boomin'!" },
    { type = "file", id = 2973518, name = "Genn Greymane - So many... dead... (a bit morbid - fun for skinners!)", header = "Alliance Champions (fun & thematic)" },
    { type = "file", id = 2468409, name = "Tyrande Whisperwind - Ishnu-ala" },
    { type = "file", id = 5715478, name = "Magni Bronzebeard - Always more work to be done" },
    { type = "file", id = 3192654, name = "Gelbin Mekkatorque - There's always time to tinker" },
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
    label:SetTextColor(0.4, 1, 0.4) -- consistent ItemWatch accent green
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
    panel:SetSize(320, 700)
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

    -- Sound list now scrolls - the preset list has grown enough (and will
    -- likely keep growing) that a fixed-height popup can't reliably fit
    -- it all. Icon/name/goal stay pinned above, Save/Cancel stay pinned
    -- below; only this middle section scrolls.
    local soundScroll = CreateFrame("ScrollFrame", "ItemWatchItemEditSoundScroll", panel, "UIPanelScrollFrameTemplate")
    soundScroll:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 6, -10)
    soundScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 54)

    local soundContent = CreateFrame("Frame", "ItemWatchItemEditSoundContent", soundScroll)
    soundContent:SetSize(252, 10) -- height finalized below once every button is laid out
    soundScroll:SetScrollChild(soundContent)

    wipe(itemEditButtons)
    local lastBtn = nil
    local LABEL_WRAP_WIDTH = 252 -- fits comfortably within the widened popup
    local BASE_GAP = 10 -- original tight spacing for a normal single-line row
    local SINGLE_LINE_HEIGHT = 12 -- roughly one line at this font size
    local ITEM_BASE_HEIGHT = 20 -- approximate checkbox+label height, used only for the scroll content's total height estimate

    -- Constrains a radio label to wrap instead of running off the edge,
    -- and returns the vertical gap the NEXT item should use below this
    -- one - just the normal tight gap for a single-line label, or extra
    -- room if this label actually wrapped to two or more lines.
    local function ConstrainAndMeasure(labelOrBtn)
        local label = labelOrBtn.label or labelOrBtn
        label:SetWidth(LABEL_WRAP_WIDTH)
        label:SetWordWrap(true)
        label:SetJustifyH("LEFT")
        local textHeight = label:GetStringHeight() or SINGLE_LINE_HEIGHT
        local extra = math.max(0, textHeight - SINGLE_LINE_HEIGHT)
        return BASE_GAP + extra
    end

    -- Running total for the scroll content's final height - a slightly
    -- generous estimate (a little extra blank scroll space at the bottom
    -- is harmless; an underestimate would clip the last few presets,
    -- which is the exact bug this scroll frame exists to fix).
    local totalHeight = 0

    -- A few pixels of top padding - without it, the first checkbox's own
    -- highlight/glow texture (which extends slightly past its nominal
    -- frame bounds) sits flush with the scroll area's top edge and gets
    -- clipped by the ScrollFrame boundary.
    local TOP_PADDING = 6

    local defaultBtn = CreateOptionRadio(soundContent, "Use ItemWatch's global default\n(set in /iw options)")
    defaultBtn:SetPoint("TOPLEFT", soundContent, "TOPLEFT", 0, -TOP_PADDING)
    defaultBtn.choice = nil
    table.insert(itemEditButtons, defaultBtn)
    lastBtn = defaultBtn
    local nextGap = ConstrainAndMeasure(defaultBtn)
    totalHeight = totalHeight + TOP_PADDING + ITEM_BASE_HEIGHT + nextGap

    local muteBtn = CreateOptionRadio(soundContent, MUTED_SOUND.name)
    muteBtn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -nextGap)
    muteBtn.choice = MUTED_SOUND
    table.insert(itemEditButtons, muteBtn)
    lastBtn = muteBtn
    nextGap = ConstrainAndMeasure(muteBtn)
    totalHeight = totalHeight + ITEM_BASE_HEIGHT + nextGap

    for _, choice in ipairs(SOUND_PRESETS) do
        if choice.header then
            -- Divider line + extra breathing room above and below each
            -- new category, so groups read as visually distinct sections
            -- instead of one continuous block of checkboxes.
            local divider = soundContent:CreateTexture(nil, "ARTWORK")
            divider:SetColorTexture(0.5, 0.5, 0.5, 0.4)
            divider:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -(nextGap + 10))
            divider:SetSize(LABEL_WRAP_WIDTH, 1)
            totalHeight = totalHeight + nextGap + 10 + 1

            local header = soundContent:CreateFontString(nil, "OVERLAY")
            header:SetFont("Fonts\\FRIZQT__.ttf", 13, "OUTLINE")
            -- Flush with the checkbox column (x=0), not outdented - inside
            -- a ScrollFrame's clipped content area, any negative x-offset
            -- pushes past the visible/scrollable bounds and gets clipped,
            -- which is exactly what was cutting off the H in "Horde" and
            -- the A in "Alliance" here.
            header:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
            header:SetTextColor(1, 0.82, 0)
            header:SetWidth(LABEL_WRAP_WIDTH)
            header:SetWordWrap(true)
            header:SetJustifyH("LEFT")
            header:SetText(choice.header)
            lastBtn = header
            -- Extra +6 below the header itself before the group's first
            -- item, on top of the usual wrap-aware gap.
            nextGap = ConstrainAndMeasure(header) + 6
            totalHeight = totalHeight + 10 + ITEM_BASE_HEIGHT + nextGap
        end
        local btn = CreateOptionRadio(soundContent, choice.name)
        btn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -nextGap)
        btn.choice = choice
        table.insert(itemEditButtons, btn)
        lastBtn = btn
        nextGap = ConstrainAndMeasure(btn)
        totalHeight = totalHeight + ITEM_BASE_HEIGHT + nextGap
    end

    soundContent:SetHeight(totalHeight + 30)

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
        itemEditFrame.SelectEditSound(MUTED_SOUND)
    else
        itemEditFrame.SelectEditSound(entry.sound)
    end

    itemEditFrame:Show()
end

local shoppingListFrame = nil
local shoppingListRows = {} -- itemID -> row frame, for required reagents

-- Rescales every required reagent's "needed" amount by a new craft
-- quantity (e.g. making 20 potions instead of 1), using each reagent's
-- stored perCraft amount as the base so this can be called repeatedly
-- without compounding. Older saved lists from before this field existed
-- won't have perCraft yet - fall back to treating the current needed
-- amount as the per-craft base in that case.
local function ApplyCraftQuantity(newQty)
    local data = ItemWatchDB.shoppingList
    newQty = math.max(1, math.floor(tonumber(newQty) or 1))
    data.craftQuantity = newQty
    for _, reagent in ipairs(data.required) do
        reagent.perCraft = reagent.perCraft or reagent.needed or 1
        reagent.needed = reagent.perCraft * newQty
    end
    if RefreshShoppingList then RefreshShoppingList() end
end

-- Builds the Shopping List window - separate from the main Item Box,
-- for "I need this right now to craft something" rather than long-term
-- tracking goals. Required reagents show progress toward what's needed;
-- optional reagents (missives, embellishments) show as a plain reminder
-- checklist since picking one is a build-specific choice, not something
-- ItemWatch should choose for the player.
local function CreateShoppingListWindow()
    local panel = CreateFrame("Frame", "ItemWatchShoppingList", UIParent, "BackdropTemplate")
    panel:SetSize(ItemWatchDB.shoppingList.width or 260, ItemWatchDB.shoppingList.height or 400)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:SetResizable(true)
    panel:SetClampedToScreen(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(200, 200)
    else
        panel:SetMinResize(200, 200) -- older API, kept for compatibility
    end
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.75)
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    panel:Hide()

    local titleBar = CreateFrame("Frame", nil, panel)
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if not ItemWatchDB.shoppingList.locked then
            panel:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local point, _, _, x, y = panel:GetPoint()
        ItemWatchDB.shoppingList.point = point
        ItemWatchDB.shoppingList.x = x
        ItemWatchDB.shoppingList.y = y
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", -16, 0)
    title:SetText("Shopping List")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    local closeFS = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeFS:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeFS:SetText("X")
    closeFS:SetTextColor(1, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function()
        ItemWatchDB.shoppingList.dismissed = true
        panel:Hide()
    end)

    -- Lock/unlock toggle, same behavior and icon set as the main Item Box's
    -- lock button - locking here just stops accidental drags/resizes while
    -- you're clicking around inside the window
    local lockBtn = CreateFrame("Button", nil, titleBar)
    lockBtn:SetSize(18, 18)
    lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    lockBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local function UpdateShoppingListLockIcon()
        if ItemWatchDB.shoppingList.locked then
            lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        else
            lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        end
    end
    panel.UpdateLockIcon = UpdateShoppingListLockIcon
    UpdateShoppingListLockIcon()

    lockBtn:SetScript("OnClick", function()
        ItemWatchDB.shoppingList.locked = not ItemWatchDB.shoppingList.locked
        UpdateShoppingListLockIcon()
    end)
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ItemWatchDB.shoppingList.locked and "Unlock window" or "Lock window")
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local recipeNameText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipeNameText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
    recipeNameText:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -6, -6)
    recipeNameText:SetJustifyH("LEFT")
    recipeNameText:SetTextColor(1, 0.82, 0)
    panel.recipeNameText = recipeNameText

    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", recipeNameText, "BOTTOMLEFT", 0, -8)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 56)
    panel.content = content

    -- Craft quantity - "how many of the recipe are you making," not tied
    -- to the reagent row list, so it's anchored to the panel's own
    -- bottom edge (like statusText below) rather than living inside
    -- content. That keeps it always visible regardless of resizing or
    -- how many reagents there are to scroll past. Changing this re-scales
    -- every required reagent's needed amount live - see ApplyCraftQuantity.
    local craftQtyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftQtyLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 32)
    craftQtyLabel:SetText("Crafting:")

    local craftQtyBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    craftQtyBox:SetSize(44, 20)
    craftQtyBox:SetAutoFocus(false)
    craftQtyBox:SetNumeric(true)
    craftQtyBox:SetPoint("LEFT", craftQtyLabel, "RIGHT", 10, 0)
    craftQtyBox:SetText(tostring(ItemWatchDB.shoppingList.craftQuantity or 1))
    craftQtyBox:SetScript("OnEnterPressed", function(self)
        ApplyCraftQuantity(self:GetText())
        self:ClearFocus()
    end)
    craftQtyBox:SetScript("OnEditFocusLost", function(self)
        ApplyCraftQuantity(self:GetText())
    end)
    craftQtyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.craftQtyBox = craftQtyBox

    local craftQtyHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    craftQtyHint:SetPoint("LEFT", craftQtyBox, "RIGHT", 6, 0)
    craftQtyHint:SetText("x this recipe")

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 8)
    statusText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 8)
    statusText:SetJustifyH("CENTER")
    statusText:SetTextColor(0.4, 1, 0.4)
    panel.statusText = statusText

    -- Resize handle, bottom-right corner - same texture set as the Item Box's
    local resizeHandle = CreateFrame("Button", nil, panel)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeHandle:SetScript("OnMouseDown", function()
        if not ItemWatchDB.shoppingList.locked then
            panel:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        ItemWatchDB.shoppingList.width = panel:GetWidth()
        ItemWatchDB.shoppingList.height = panel:GetHeight()
        -- Rows are sized off the content area's width, so a resize needs
        -- a re-layout the same way the Item Box re-runs LayoutBox()
        if RefreshShoppingList then RefreshShoppingList() end
    end)

    return panel
end

-- Rebuilds the Shopping List's visible rows from ItemWatchDB.shoppingList
-- and updates each required reagent's "have vs. needed" progress.
function RefreshShoppingList()
    if not shoppingListFrame then return end
    local data = ItemWatchDB.shoppingList
    if not data.active then return end

    for _, row in pairs(shoppingListRows) do
        row:Hide()
    end
    wipe(shoppingListRows)

    shoppingListFrame.recipeNameText:SetText(data.recipeName or "")

    -- Keep the craft-quantity field in sync with saved data (e.g. after
    -- restoring from logout, or a resize triggering a re-layout) - but
    -- never stomp on it while the player's actively typing a new value.
    if shoppingListFrame.craftQtyBox and not shoppingListFrame.craftQtyBox:HasFocus() then
        shoppingListFrame.craftQtyBox:SetText(tostring(data.craftQuantity or 1))
    end

    local yOffset = 0
    local allSatisfied = true

    -- Conservative chars-per-line estimate for this label's font/width,
    -- same approach used for the optional-reagents note below and the
    -- options-panel doc pages - GetStringHeight() right after SetText can
    -- return a stale single-line value for wrapped text, so estimating
    -- from character count is the more reliable measure here.
    local ROW_CHARS_PER_LINE = 26
    local ROW_LINE_HEIGHT = 13
    local ROW_MIN_HEIGHT = 20
    local ROW_GAP = 3

    local contentWidth = shoppingListFrame.content:GetWidth()
    local rowWidth = math.max(150, contentWidth)

    for _, reagent in ipairs(data.required) do
        -- Unlike the main Item Box (deliberately bags + reagent bag only,
        -- for an always-exactly-accurate live count), the Shopping List is
        -- answering a different question - "do I still need to go buy
        -- this" - so it should count bank, reagent bank, AND warbank too.
        -- Otherwise it'll nag you to buy something you already have 300
        -- of sitting in your bank.
        local have = C_Item.GetItemCount(reagent.itemID, true, false, true, true)
        local satisfied = have >= reagent.needed
        if not satisfied then allSatisfied = false end

        local text = (reagent.name or ("item #"..reagent.itemID)).." ("..have.."/"..reagent.needed..")"
        if reagent.isBoP then
            text = text.." |cff888888[vendor/earned only]|r"
        end

        -- Strip WoW color escape codes before estimating wrapped line
        -- count - they add invisible characters that would otherwise
        -- inflate the estimate and reserve more row height than the
        -- visible text actually needs.
        local visibleText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

        -- Long item names (e.g. crafted gun components) can wrap to two
        -- or more lines - size the row to match instead of a fixed
        -- height, so the next row doesn't overlap this one's text.
        local estimatedLines = math.max(1, math.ceil(#visibleText / ROW_CHARS_PER_LINE))
        local rowHeight = math.max(ROW_MIN_HEIGHT, estimatedLines * ROW_LINE_HEIGHT + 6)

        local row = CreateFrame("Button", nil, shoppingListFrame.content)
        row:SetSize(rowWidth, rowHeight)
        row:SetPoint("TOPLEFT", shoppingListFrame.content, "TOPLEFT", 0, yOffset)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(reagent.itemID)
        icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
        label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetWordWrap(true)
        label:SetText(text)
        label:SetTextColor(satisfied and 0.2 or 1, satisfied and 1 or 1, satisfied and 0.2 or 1)

        -- Shift-click to link/search, same as the main Item Box's icons
        local itemID = reagent.itemID
        row:RegisterForClicks("AnyUp")
        row:SetScript("OnClick", function()
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                local _, itemLink = GetItemInfo(itemID)
                if itemLink and HandleModifiedItemClick then
                    HandleModifiedItemClick(itemLink)
                end
            elseif IsModifierKeyDown and IsModifierKeyDown() then
                local _, itemLink = GetItemInfo(itemID)
                if itemLink and HandleModifiedItemClick then
                    HandleModifiedItemClick(itemLink)
                end
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click: link in chat / paste into AH search", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        shoppingListRows[reagent.itemID] = row
        yOffset = yOffset - rowHeight - ROW_GAP
    end

    if #data.optional > 0 then
        yOffset = yOffset - 8
        local optText = #data.optional.." optional finishing reagent"..(#data.optional == 1 and "" or "s")..
            " can be used for this recipe, check the crafting window for details."

        -- Estimate wrapped line count from text length rather than a
        -- fixed height guess, same approach used for the docs pages -
        -- a fixed height here previously cut the text off with "..."
        local CHARS_PER_LINE = 34 -- conservative for this width/font
        local estimatedLines = math.max(1, math.ceil(#optText / CHARS_PER_LINE))
        local boxHeight = estimatedLines * 14 + 4

        local optNote = CreateFrame("Frame", nil, shoppingListFrame.content)
        optNote:SetPoint("TOPLEFT", shoppingListFrame.content, "TOPLEFT", 0, yOffset)
        optNote:SetPoint("TOPRIGHT", shoppingListFrame.content, "TOPRIGHT", 0, yOffset)
        optNote:SetHeight(boxHeight)
        local optNoteText = optNote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optNoteText:SetAllPoints(optNote)
        optNoteText:SetJustifyH("LEFT")
        optNoteText:SetJustifyV("TOP")
        optNoteText:SetWordWrap(true)
        optNoteText:SetTextColor(1, 0.82, 0)
        optNoteText:SetText(optText)
        shoppingListRows["_optheader"] = optNote
        yOffset = yOffset - boxHeight - 6
    end

    if allSatisfied and #data.required > 0 then
        shoppingListFrame.statusText:SetText("All set, close this after you craft it!")
        shoppingListFrame.statusText:Show()
    else
        shoppingListFrame.statusText:Hide()
    end
end

-- Reads the currently-open recipe (via the confirmed working path on the
-- Recipes tab) and populates the Shopping List with it.
-- Builds the Shopping List from an already-read recipe schematic. Split
-- out from AddRecipeToShoppingList so the confirmation prompt below can
-- read the recipe first (to know its name for the prompt text) before
-- deciding whether to apply it immediately or ask first.
local function ApplyRecipeToShoppingList(schematic)
    local data = ItemWatchDB.shoppingList
    data.recipeName = schematic.name
    data.required = {}
    data.optional = {}
    data.craftQuantity = 1 -- fresh recipe = fresh craft count, not whatever the last one was left at

    if schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            if slot.reagentType == 1 then
                -- Required reagents are a single fixed item per slot
                local itemID = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
                if itemID then
                    local name = GetItemInfo(itemID)
                    local bindType = select(14, GetItemInfo(itemID))
                    local perCraft = slot.quantityRequired or 1
                    table.insert(data.required, {
                        itemID = itemID,
                        name = name,
                        perCraft = perCraft,   -- amount needed for ONE craft; the craft-quantity field scales this
                        needed = perCraft,     -- craftQuantity is 1 on a fresh add, so needed == perCraft for now
                        isBoP = (bindType == 1),
                    })
                end
            elseif slot.reagentType == 2 then
                -- Optional/finishing slots can offer several eligible
                -- choices (e.g. different embellishments for the same
                -- socket) - list every choice, not just the first one,
                -- so the player can see the full menu of options.
                if slot.reagents then
                    for _, reagentChoice in ipairs(slot.reagents) do
                        if reagentChoice.itemID then
                            local name = GetItemInfo(reagentChoice.itemID)
                            table.insert(data.optional, { itemID = reagentChoice.itemID, name = name })
                        end
                    end
                end
            end
        end
    end

    data.active = true
    data.dismissed = false
    print("|cff00ff00ItemWatch:|r added \""..(data.recipeName or "recipe").."\" to your Shopping List.")

    RefreshShoppingList()
    shoppingListFrame:ClearAllPoints()
    shoppingListFrame:SetPoint(data.point or "CENTER", UIParent, data.point or "CENTER", data.x or 0, data.y or -150)
    shoppingListFrame:Show()
end

-- Reads the currently-open recipe (via the confirmed working path on the
-- Recipes tab). If a Shopping List is already active, confirms before
-- replacing it - protects both "I changed my mind on the recipe" and an
-- accidental double-click on the button.
local function AddRecipeToShoppingList()
    if not (ProfessionsFrame and ProfessionsFrame.CraftingPage
            and ProfessionsFrame.CraftingPage.SchematicForm
            and ProfessionsFrame.CraftingPage.SchematicForm.recipeSchematic) then
        print("|cffff8800ItemWatch:|r open a recipe on the Recipes tab first.")
        return
    end
    local recipeID = ProfessionsFrame.CraftingPage.SchematicForm.recipeSchematic.recipeID
    if not recipeID then
        print("|cffff8800ItemWatch:|r couldn't find a selected recipe.")
        return
    end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or not schematic then
        print("|cffff8800ItemWatch:|r couldn't read that recipe's reagents.")
        return
    end

    local data = ItemWatchDB.shoppingList
    -- Only prompt if there's a list that's both active AND still open -
    -- closing the window (the X button) signals "I'm done with this
    -- recipe," so a fresh add afterward should just proceed without
    -- asking. Same active-and-not-dismissed pairing the logout-restore
    -- logic already uses, for consistency.
    if data.active and not data.dismissed then
        StaticPopupDialogs["ITEMWATCH_CONFIRM_REPLACE_SHOPPING_LIST"].text =
            "Replace your current Shopping List (\""..(data.recipeName or "current recipe")..
            "\") with \""..(schematic.name or "this recipe").."\"?"
        StaticPopupDialogs["ITEMWATCH_CONFIRM_REPLACE_SHOPPING_LIST"].OnAccept = function()
            ApplyRecipeToShoppingList(schematic)
        end
        StaticPopup_Show("ITEMWATCH_CONFIRM_REPLACE_SHOPPING_LIST")
    else
        ApplyRecipeToShoppingList(schematic)
    end
end

local recipeAddButton = nil

-- "Add to ItemWatch" button on the Recipes tab's schematic form. Reuses
-- AddRecipeToShoppingList() - the same function /iw addrecipe already
-- calls - so the button and the slash command can never drift out of
-- sync with each other. Injecting a button into this frame is already
-- proven safe: Blizzard's own "Track Recipe" checkbox lives here, and
-- Auctionator injects into the sibling Crafting Order frame the same way.
local function CreateRecipeAddButton()
    if recipeAddButton then return end
    if not (ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm) then
        return
    end

    local form = ProfessionsFrame.CraftingPage.SchematicForm
    local btn = CreateFrame("Button", "ItemWatchAddRecipeButton", form, "UIPanelButtonTemplate")
    btn:SetSize(172, 22)
    btn:SetText("Add to Shopping List")

    -- NOTE: anchor is a first guess, not confirmed against the live frame -
    -- I can't see the actual SchematicForm layout, so this may overlap
    -- Blizzard's own Create button or the reagent list. Nudge the offsets
    -- below once you've seen it in-game.
    btn:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 10, 40)

    btn:SetScript("OnClick", function()
        AddRecipeToShoppingList()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add this recipe's reagents to your ItemWatch Shopping List")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    recipeAddButton = btn
end

-- Builds a scrollable canvas frame suitable for registering as a Settings
-- subcategory - same scroll-frame pattern the main panel uses, since
-- Blizzard doesn't provide this automatically for canvas-style panels.
local function CreateScrollableSubcategory(name)
    local panel = CreateFrame("Frame")
    panel.name = name

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -27, 4)

    local content = CreateFrame("Frame")
    content:SetParent(scrollFrame)
    content:SetSize(560, 1100)
    scrollFrame:SetScrollChild(content)

    return panel, content
end

-- Adds a labeled row with a copyable link: a colored button that
-- highlights the URL text on click, plus a read-only edit box holding
-- the raw link so Ctrl+C actually works (WoW can't open a browser link
-- directly, so this is the standard addon pattern for sharing one).
local function AddCopyableLink(content, anchor, labelText, url)
    local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btn:SetSize(150, 22)
    btn:SetText(labelText)
    btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)

    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(320, 20)
    box:SetAutoFocus(false)
    box:SetFont("Fonts\\FRIZQT__.ttf", 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("LEFT")
    box:SetPoint("LEFT", btn, "RIGHT", 12, 0)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    btn:SetScript("OnClick", function() box:SetFocus() end)

    return btn
end

-- Builds a sectioned subpage: a title, then repeated heading + body +
-- divider blocks. Used by both Helpful Information and Practical Uses so
-- they stay visually consistent and any future tweaks apply to both.
local function BuildSectionedSubpage(name, pageTitle, sections)
    local panel, content = CreateScrollableSubcategory(name)
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(pageTitle)

    local BODY_FONT_SIZE = 15
    local BODY_LINE_HEIGHT = 19
    local CHARS_PER_LINE = 58 -- conservative estimate for 480px width at this font size

    local yOffset = -(16 + (title:GetStringHeight() or 20) + 16)
    for _, section in ipairs(sections) do
        local heading = content:CreateFontString(nil, "OVERLAY")
        heading:SetFont("Fonts\\FRIZQT__.ttf", 15, "OUTLINE")
        heading:SetTextColor(1, 0.82, 0)
        heading:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOffset)
        heading:SetText(section[1])
        yOffset = yOffset - 20 - 6

        local body = content:CreateFontString(nil, "ARTWORK")
        body:SetFont("Fonts\\FRIZQT__.ttf", BODY_FONT_SIZE, "")
        body:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
        body:SetWidth(480)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        body:SetText(section[2])

        -- Estimating wrapped line count from text length instead of
        -- trusting GetStringHeight() right after SetText, since that
        -- occasionally returns a stale single-line value for wrapped
        -- text and silently threw off spacing before.
        local estimatedLines = math.max(1, math.ceil(#section[2] / CHARS_PER_LINE))
        yOffset = yOffset - (estimatedLines * BODY_LINE_HEIGHT) - 12

        local divider = content:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(0.5, 0.5, 0.5, 0.4)
        divider:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOffset)
        divider:SetSize(520, 1)
        yOffset = yOffset - 16
    end

    return panel
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "ItemWatch"

    -- Canvas category panels are NOT automatically wrapped in a scroll
    -- frame by Blizzard's Settings system the way fully-managed settings
    -- controls are - anything past the visible area just gets clipped
    -- unless we build our own scroll frame. So we do that here: `panel`
    -- stays the fixed-size frame registered with Settings, and everything
    -- we actually build lives on `content`, a scroll child inside it.
    local scrollFrame = CreateFrame("ScrollFrame", "ItemWatchOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -27, 4)

    local content = CreateFrame("Frame", "ItemWatchOptionsScrollChild", scrollFrame)
    content:SetSize(560, 1400) -- explicit size; scroll frames need this, not stretchy anchors. Bumped up to comfortably fit the now much-longer sound preset list plus everything below it.
    scrollFrame:SetScrollChild(content)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ItemWatch")

    -- Scroll hint lives up here now, not next to the Visibility header
    -- further down - the sound preset list has grown enough that anyone
    -- reading a "scroll down for more" note ON the Visibility section
    -- has, by definition, already had to scroll down to see it.
    local scrollHint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    scrollHint:SetPoint("LEFT", title, "RIGHT", 10, -2)
    scrollHint:SetText("(scroll down for more)")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Choose the sound played when a tracked item's goal is reached.")

    local testHint = content:CreateFontString(nil, "ARTWORK")
    testHint:SetFont("Fonts\\FRIZQT__.ttf", 13, "OUTLINE")
    testHint:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
    testHint:SetTextColor(1, 0.82, 0)
    testHint:SetText("Tip: use the Test Sound button below before picking, so you know what you're getting!")

    local lastButton = nil

    -- First pass: general presets, up until the first header-tagged one
    local splitIndex = #SOUND_PRESETS + 1
    for i, choice in ipairs(SOUND_PRESETS) do
        if choice.header then
            splitIndex = i
            break
        end
        local btn = CreateOptionRadio(content, choice.name)
        btn.choice = choice
        if lastButton then
            btn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -12)
        else
            btn:SetPoint("TOPLEFT", testHint, "BOTTOMLEFT", 0, -16)
        end
        btn:SetScript("OnClick", function() SelectSound(choice) end)
        table.insert(optionButtons, btn)
        lastButton = btn
    end

    -- Custom sound ID option sits with the general list, before any
    -- themed/grouped sections like Brann Bronzebeard's
    local customBtn = CreateOptionRadio(content, "Custom FileDataID:")
    customBtn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -12)
    table.insert(optionButtons, customBtn)

    local customBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    customBox:SetSize(100, 20)
    customBox:SetAutoFocus(false)
    customBox:SetPoint("LEFT", customBtn.label, "RIGHT", 12, 0)
    customBox:SetNumeric(true)

    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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

    lastButton = hint

    -- Second pass: any remaining themed/grouped sections (e.g. Brann
    -- Bronzebeard), rendered after the general list + custom ID option
    for i = splitIndex, #SOUND_PRESETS do
        local choice = SOUND_PRESETS[i]
        if choice.header then
            local header = content:CreateFontString(nil, "OVERLAY")
            header:SetFont("Fonts\\FRIZQT__.ttf", 13, "OUTLINE")
            header:SetTextColor(1, 0.82, 0)
            header:SetText(choice.header)
            header:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", -6, -20)
            lastButton = header
        end

        local btn = CreateOptionRadio(content, choice.name)
        btn.choice = choice
        btn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", choice.header and 6 or 0, -12)
        btn:SetScript("OnClick", function() SelectSound(choice) end)
        table.insert(optionButtons, btn)
        lastButton = btn
    end

    -- Test button
    local testBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 4, -20)
    testBtn:SetText("Test Sound")
    testBtn:SetScript("OnClick", function() PlayGoalSound() end)

    -- Visibility section
    local visTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    visTitle:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 4, -20)
    visTitle:SetText("Visibility")

    local visSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    visSubtitle:SetPoint("TOPLEFT", visTitle, "BOTTOMLEFT", 0, -6)
    visSubtitle:SetText("Tracking keeps running in the background even while hidden - nothing is lost.")

    local combatCheck = CreateFrame("CheckButton", "ItemWatchHideCombatCheck", content, "UICheckButtonTemplate")
    combatCheck:SetPoint("TOPLEFT", visSubtitle, "BOTTOMLEFT", -2, -12)
    _G["ItemWatchHideCombatCheckText"]:SetText("Hide box during combat")
    _G["ItemWatchHideCombatCheckText"]:SetTextColor(0.4, 1, 0.4)
    combatCheck:SetScript("OnClick", function(self)
        ItemWatchDB.hideInCombat = self:GetChecked() and true or false
        UpdateBoxVisibility()
    end)
    panel.combatCheck = combatCheck

    local petBattleCheck = CreateFrame("CheckButton", "ItemWatchHidePetBattleCheck", content, "UICheckButtonTemplate")
    petBattleCheck:SetPoint("TOPLEFT", combatCheck, "BOTTOMLEFT", 0, -6)
    _G["ItemWatchHidePetBattleCheckText"]:SetText("Hide box during pet battles")
    _G["ItemWatchHidePetBattleCheckText"]:SetTextColor(0.4, 1, 0.4)
    petBattleCheck:SetScript("OnClick", function(self)
        ItemWatchDB.hideInPetBattles = self:GetChecked() and true or false
        UpdateBoxVisibility()
    end)
    panel.petBattleCheck = petBattleCheck

    local minimapCheck = CreateFrame("CheckButton", "ItemWatchShowMinimapCheck", content, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", petBattleCheck, "BOTTOMLEFT", 0, -6)
    _G["ItemWatchShowMinimapCheckText"]:SetText("Show minimap button")
    _G["ItemWatchShowMinimapCheckText"]:SetTextColor(0.4, 1, 0.4)
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

        if Settings.RegisterCanvasLayoutSubcategory then
            -- Helpful Information
            local helpSections = {
                { "Tracking an item you have",
                  "Drag it from your bags straight onto the box. That's it - no commands needed." },
                { "Tracking an item you don't have yet",
                  "Click the \"+\" on the box (or right-click empty space inside it). Paste a Wowhead link, type the item ID, or shift-click an item to fill the field automatically." },
                { "Setting a goal and sound",
                  "Left-click any tracked item's icon to open its edit popup - set a goal amount and pick its own sound, or leave it on \"Use ItemWatch's global default.\"" },
                { "ItemWatch's global default sound",
                  "This is ItemWatch's own fallback sound, not a WoW setting - it's what plays for any item you haven't given its own specific sound. Set it by right-clicking the minimap button, or typing /iw options and picking a sound there." },
                { "Removing an item",
                  "Right-click its icon in the box." },
                { "Linking or previewing an item",
                  "Shift-click a tracked icon to post it in chat. Ctrl-click previews equippable gear in the dressing room." },
                { "Moving and resizing the box",
                  "Drag the title bar to move it, drag the bottom-right corner to resize it. /iw lock keeps it in place." },
                { "The minimap button",
                  "Left-click toggles the box, right-click opens these settings. It's fully compatible with minimap button tray addons like ElvUI, Dominos, and others." },
                { "Hiding the box automatically",
                  "The Visibility section below can hide the box during combat or pet battles. Tracking keeps running in the background either way - nothing is lost." },
                { "Prefer typing commands?",
                  "All the original /iw commands still work exactly as before - the box and popups are additional ways in, not replacements. Type /iw for the full list." },
                { "Missed the What's New popup?",
                  "If you closed it by accident, or just want to see the latest highlights again, type /iw whatsnew any time to bring it back up." },
            }
            local helpPanel = BuildSectionedSubpage("Helpful Information", "How to Use ItemWatch", helpSections)
            Settings.RegisterCanvasLayoutSubcategory(category, helpPanel, helpPanel.name)

            -- Practical Uses
            local practicalSections = {
                { "Real-time, bags only - on purpose",
                  "Some addons also track your bank, warbank, and guild bank. ItemWatch doesn't - it only watches what's actually in your bags right now. That's deliberate: the number you see is always exactly accurate, with nothing sitting somewhere else quietly padding the count." },
                { "Farming without the bag-checking",
                  "The obvious one: crafting materials. If you need a specific amount for something you're making right now, track it, set the goal, and glance at the box instead of stopping to open your bags every few kills." },
                { "Building an Auction House shopping list",
                  "Track everything you need to buy, with a goal set for each - your own shopping list. At the Auction House, click into the search bar, then shift-click the item's icon in ItemWatch's box to drop its name straight into the search. Repeat for each item on your list as you buy." },
                { "Tracking something you don't have yet",
                  "This is what the Quick-Add popup and per-item sounds are really for. Say you're fishing for Strange Goop - with auto-loot on, it's easy to miss picking one up while you're only half paying attention. Track it before you have a single one, set a goal of 1, pick a sound, and let ItemWatch tell you the moment it lands in your bags instead of hoping you noticed." },
                { "The green ding",
                  "However you're using it, the payoff is the same: hit your goal, the icon turns green, and you get a sound - so you know instantly without needing to actually look." },
                { "Got a use we haven't listed?",
                  "There are probably more ways to put ItemWatch to work than we've thought of. If you've found one, let us know on CurseForge - see the Contact/Support page." },
            }
            local practicalPanel = BuildSectionedSubpage("Practical Uses", "Practical Uses for ItemWatch", practicalSections)
            Settings.RegisterCanvasLayoutSubcategory(category, practicalPanel, practicalPanel.name)

            -- Shopping List (the recipe-based Shopping List window, not to
            -- be confused with the "build your own AH list" tip on the
            -- Practical Uses page above - that's the main Item Box being
            -- used informally as a shopping list; this is a separate,
            -- dedicated window)
            local shoppingListSections = {
                { "Not the same as the main box",
                  "This is a separate window from the Item Box, built specifically for \"I need this right now to craft something\" rather than long-term tracking goals. (If you've seen the Practical Uses tip about building an Auction House list from the main box - that's a different, informal use of the box itself. This page is about the dedicated Shopping List window.)" },
                { "Starting a Shopping List",
                  "Open a recipe on the Recipes tab of any profession and click \"Add to Shopping List.\" ItemWatch reads that recipe's full reagent list and builds the list for you automatically - no manual entry needed." },
                { "Required reagents",
                  "Each shows a live have/needed count and turns green once you've got enough. These count everything you own: bags, bank, reagent bank, AND warband bank - deliberately different from the main Item Box, which only ever counts bags." },
                { "Optional reagents",
                  "Missives, embellishments, and similar finishing reagents show as a plain reminder instead of an auto-added goal - which one you want is a build-specific choice ItemWatch shouldn't make for you." },
                { "\"[vendor/earned only]\" tag",
                  "Some required reagents (Sparks, Enchanted Crests, and similar) can't be bought on the Auction House at all. Rather than leave them off the list and risk you getting blindsided at craft time, they're included with this tag so you know it's earned, not purchased." },
                { "Moving, resizing, and locking",
                  "Drag the title bar to move the window, drag the bottom-right corner to resize it, and use the lock icon next to the X to stop accidental drags or resizes while you're clicking around inside it." },
                { "It stays open across logout",
                  "If you get pulled away mid-task, the Shopping List (including its progress) is still there when you log back in - it doesn't just vanish like the Quick-Add popup would." },
                { "\"All set, close this after you craft it!\"",
                  "Once every required reagent is satisfied, the window tells you so - but doesn't close itself automatically, since having the materials isn't the same as having actually crafted the item yet. Dismiss it with the X whenever you're done." },
            }
            local shoppingListPanel = BuildSectionedSubpage("Shopping List", "The Recipe Shopping List", shoppingListSections)
            Settings.RegisterCanvasLayoutSubcategory(category, shoppingListPanel, shoppingListPanel.name)

            -- Support
            local supportPanel, supportContent = CreateScrollableSubcategory("Contact/Support")
            local supportTitle = supportContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            supportTitle:SetPoint("TOPLEFT", 16, -16)
            supportTitle:SetText("Contact/Support ItemWatch")

            local supportBody = supportContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            supportBody:SetPoint("TOPLEFT", supportTitle, "BOTTOMLEFT", 0, -8)
            supportBody:SetWidth(500)
            supportBody:SetJustifyH("LEFT")
            supportBody:SetWordWrap(true)
            supportBody:SetText("If you find ItemWatch useful, support is completely optional and always appreciated!")

            local supportTip = supportContent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            supportTip:SetPoint("TOPLEFT", supportBody, "BOTTOMLEFT", 0, -6)
            supportTip:SetText("Tip: click the button to select the link, then Ctrl+C to copy it.")

            local kofiBtn = AddCopyableLink(supportContent, supportTip, "Ko-fi", "https://ko-fi.com/nerdybertie")

            local thanksText = supportContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            thanksText:SetPoint("TOPLEFT", kofiBtn, "BOTTOMLEFT", 0, -20)
            thanksText:SetText("Thank you to everyone who's supported ItemWatch's development!")

            local contactTitle = supportContent:CreateFontString(nil, "ARTWORK")
            contactTitle:SetFont("Fonts\\FRIZQT__.ttf", 14, "OUTLINE")
            contactTitle:SetTextColor(1, 0.82, 0)
            contactTitle:SetPoint("TOPLEFT", thanksText, "BOTTOMLEFT", 0, -24)
            contactTitle:SetText("Contact Me")

            local contactBody = supportContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            contactBody:SetPoint("TOPLEFT", contactTitle, "BOTTOMLEFT", 0, -6)
            contactBody:SetWidth(500)
            contactBody:SetJustifyH("LEFT")
            contactBody:SetWordWrap(true)
            contactBody:SetText("For comments, suggestions, or anything related to ItemWatch, please use CurseForge messaging.")

            AddCopyableLink(supportContent, contactBody, "CurseForge", "https://www.curseforge.com/wow/addons/item-watch")

            Settings.RegisterCanvasLayoutSubcategory(category, supportPanel, supportPanel.name)

            -- About
            local aboutPanel, aboutContent = CreateScrollableSubcategory("About")
            local aboutTitle = aboutContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            aboutTitle:SetPoint("TOPLEFT", 16, -16)
            aboutTitle:SetText("ItemWatch")

            local aboutBy = aboutContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            aboutBy:SetPoint("TOPLEFT", aboutTitle, "BOTTOMLEFT", 0, -6)
            aboutBy:SetText("Created by NerdyBertie")

            local aboutBody = aboutContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            aboutBody:SetPoint("TOPLEFT", aboutBy, "BOTTOMLEFT", 0, -14)
            aboutBody:SetWidth(500)
            aboutBody:SetJustifyH("LEFT")
            aboutBody:SetWordWrap(true)
            aboutBody:SetText("ItemWatch started as a way to stop opening bags every five seconds while farming. It's grown into a full item-goal tracker: a movable box, per-item sounds, and a minimap button - built for anyone who'd rather glance at a number than dig through their bags. More recently it picked up a Recipe Shopping List too, so a whole crafting run's worth of reagents comes together with one click instead of adding each mat by hand.")

            local aboutLinks = aboutContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            aboutLinks:SetPoint("TOPLEFT", aboutBody, "BOTTOMLEFT", -4, -20)
            aboutLinks:SetText("Links")

            local twitchBtn = AddCopyableLink(aboutContent, aboutLinks, "Twitch", "https://www.twitch.tv/nerdybertie")
            local youtubeBtn = AddCopyableLink(aboutContent, twitchBtn, "YouTube", "https://www.youtube.com/@nerdybertie")
            local githubBtn = AddCopyableLink(aboutContent, youtubeBtn, "GitHub", "https://github.com/NerdyBertie/Itemwatch")

            Settings.RegisterCanvasLayoutSubcategory(category, aboutPanel, aboutPanel.name)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Reads the addon's real version straight from the .toc, so this never
-- needs manual syncing with a hardcoded string somewhere else in the file.
local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, "Version")
    end
    return nil
end

-- Newest release first. Add a new entry here each time you ship - the
-- popup below automatically features whichever one is first in the list
-- and lists anything older underneath in compact form.
local CHANGELOG = {
    {
        version = "2.2.2",
        highlights = {
            "Fixed the sound picker running off the edge of the item-edit popup (left-click a tracked item) - it now scrolls properly and won't overflow again as more presets get added.",
            "Fixed the \"Horde Legends\" and \"Alliance Champions\" section labels getting their first letter clipped off.",
            "Added divider lines between sound categories so they're easier to scan at a glance.",
        },
    },
    {
        version = "2.2.1",
        highlights = {
            "NEW: Recipe Shopping List - click \"Add to Shopping List\" right on any recipe in the Professions Recipes tab, and ItemWatch reads its reagent list and builds your shopping list for you automatically. No more adding each mat by hand.",
            "Crafting more than one? Set how many in the Shopping List's own \"Crafting: __ x this recipe\" field, and every reagent's needed amount updates live - no need to re-open the recipe.",
            "Shift-click any item in the Shopping List to drop it straight into the Auction House search bar - same trick you already know from the main box, works here too.",
            "The Shopping List counts your bank, reagent bank, AND warband bank (not just bags), so it won't nag you to buy something you've already got stashed away.",
            "The Shopping List window is movable, resizable, and lockable, and stays put across logout if you get pulled away mid-farm.",
            "Clicking \"Add to Shopping List\" while one's already active now asks before replacing it, so an accidental click (or changing your mind on the recipe) won't wipe your progress.",
        },
    },
}

local whatsNewFrame = nil

-- Builds the "What's New" popup - a quick pitch for anyone new to
-- ItemWatch, plus the latest release's highlights. Shown once per
-- version, gated by comparing the addon's real .toc version against
-- ItemWatchDB.lastSeenVersion, so there's no manual "have they seen
-- this release yet" bookkeeping needed anywhere else.
local function CreateWhatsNewPopup()
    local panel = CreateFrame("Frame", "ItemWatchWhatsNew", UIParent, "BackdropTemplate")
    panel:SetSize(420, 460)
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

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("What's New in ItemWatch")

    local scrollFrame = CreateFrame("ScrollFrame", "ItemWatchWhatsNewScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 46)

    local content = CreateFrame("Frame", "ItemWatchWhatsNewScrollChild", scrollFrame)
    content:SetSize(340, 10) -- height gets finalized below once text is laid out
    scrollFrame:SetScrollChild(content)

    -- Conservative chars-per-line estimate, same reasoning as the
    -- Shopping List rows and the options-panel doc pages: GetStringHeight()
    -- right after SetText can return a stale single-line value for
    -- wrapped text, so estimating from character count is more reliable.
    local CHARS_PER_LINE = 48
    local LINE_HEIGHT = 16

    local introText = "Stop checking your bags! ItemWatch keeps an eye on your farming so "..
        "you don't have to - set a goal, watch the icon turn green, and let a sound of "..
        "your choosing tell you the second you're done. ItemWatch has got you, fam!"

    local intro = content:CreateFontString(nil, "ARTWORK")
    intro:SetFont("Fonts\\FRIZQT__.ttf", 13, "")
    intro:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    intro:SetWidth(340)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(introText)

    local introLines = math.max(1, math.ceil(#introText / CHARS_PER_LINE))
    local yOffset = -(introLines * LINE_HEIGHT) - 18

    local latest = CHANGELOG[1]
    if latest then
        local versionHeader = content:CreateFontString(nil, "OVERLAY")
        versionHeader:SetFont("Fonts\\FRIZQT__.ttf", 14, "OUTLINE")
        versionHeader:SetTextColor(1, 0.82, 0)
        versionHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
        versionHeader:SetText("New in "..latest.version)
        yOffset = yOffset - 20 - 8

        for _, line in ipairs(latest.highlights) do
            local bullet = content:CreateFontString(nil, "ARTWORK")
            bullet:SetFont("Fonts\\FRIZQT__.ttf", 12, "")
            bullet:SetPoint("TOPLEFT", content, "TOPLEFT", 4, yOffset)
            bullet:SetWidth(332)
            bullet:SetJustifyH("LEFT")
            bullet:SetWordWrap(true)
            bullet:SetText("- "..line)
            local estimatedLines = math.max(1, math.ceil(#line / CHARS_PER_LINE))
            yOffset = yOffset - (estimatedLines * LINE_HEIGHT) - 8
        end
    end

    -- Earlier versions, compact - one line each, just enough to jog the
    -- memory without turning this into a full changelog archive
    if #CHANGELOG > 1 then
        yOffset = yOffset - 6
        local earlierHeader = content:CreateFontString(nil, "OVERLAY")
        earlierHeader:SetFont("Fonts\\FRIZQT__.ttf", 12, "OUTLINE")
        earlierHeader:SetTextColor(0.6, 0.6, 0.6)
        earlierHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
        earlierHeader:SetText("Earlier updates")
        yOffset = yOffset - 18

        for i = 2, #CHANGELOG do
            local entry = CHANGELOG[i]
            local summary = entry.summary or (entry.highlights and entry.highlights[1]) or ""
            local line = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            line:SetPoint("TOPLEFT", content, "TOPLEFT", 4, yOffset)
            line:SetWidth(332)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(true)
            line:SetText(entry.version..": "..summary)
            local estimatedLines = math.max(1, math.ceil((#entry.version + 2 + #summary) / CHARS_PER_LINE))
            yOffset = yOffset - (estimatedLines * LINE_HEIGHT) - 6
        end
    end

    content:SetHeight(math.abs(yOffset) + 10)

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(110, 24)
    closeBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    closeBtn:SetText("Let's go!")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Mark this version "seen" on OnHide rather than only in the button's
    -- OnClick - this popup is registered with UISpecialFrames so pressing
    -- Escape also closes it, and that path bypasses OnClick entirely. If
    -- marking only happened on the button, an Escape-dismiss would leave
    -- lastSeenVersion unset and the popup would show again next login -
    -- exactly the repeat-every-login annoyance this is meant to avoid.
    -- OnHide fires no matter how the window gets closed, so this is the
    -- one place that actually guarantees "shows once per version."
    panel:SetScript("OnHide", function()
        ItemWatchDB.lastSeenVersion = GetAddonVersion() or ItemWatchDB.lastSeenVersion
    end)

    tinsert(UISpecialFrames, "ItemWatchWhatsNew")

    return panel
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
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- see hasCheckedWhatsNew below

-- PLAYER_ENTERING_WORLD fires on every loading screen (zone changes,
-- instance transitions, not just login), so this guards the What's New
-- check to only ever run once per session, the first time it fires.
local hasCheckedWhatsNew = false

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_Professions" then
        CreateRecipeAddButton()
    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ItemWatchDB = CopyDefaults(defaults, ItemWatchDB or {})
        itemBox = CreateItemBox()
        quickAddFrame = CreateQuickAddPopup()
        itemEditFrame = CreateItemEditPopup()
        shoppingListFrame = CreateShoppingListWindow()
        whatsNewFrame = CreateWhatsNewPopup()
        for _, entry in ipairs(ItemWatchDB.items) do
            frames[entry.id] = CreateItemFrame(entry)
        end
        RefreshAll()
        if LayoutBox then LayoutBox() end
        BuildOptionsPanel()
        CreateMinimapButton()
        UpdateBoxVisibility()

        -- Restore the Shopping List across logout/reload if it was left
        -- open and not dismissed - the whole point of persisting it is so
        -- someone who got pulled away mid-task sees it again on login
        local sl = ItemWatchDB.shoppingList
        if sl.active and not sl.dismissed then
            RefreshShoppingList()
            shoppingListFrame:ClearAllPoints()
            shoppingListFrame:SetPoint(sl.point or "CENTER", UIParent, sl.point or "CENTER", sl.x or 0, sl.y or -150)
            shoppingListFrame:Show()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        bagsReady = true
        RefreshAll()
        if ItemWatchDB.shoppingList.active and not ItemWatchDB.shoppingList.dismissed then
            RefreshShoppingList()
        end
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Deliberately NOT done in ADDON_LOADED: Blizzard runs its own
        -- "close any open special windows" pass as part of the normal
        -- load sequence, which happens AFTER ADDON_LOADED but BEFORE the
        -- player actually sees the world. A popup shown during
        -- ADDON_LOADED gets silently closed by that pass almost
        -- immediately - no error, just gone before anyone could see it.
        -- PLAYER_ENTERING_WORLD fires after that cleanup, so this is the
        -- correct place for a "show once per version" popup like this.
        if not hasCheckedWhatsNew then
            hasCheckedWhatsNew = true
            local currentVersion = GetAddonVersion()
            if currentVersion and ItemWatchDB.lastSeenVersion ~= currentVersion and whatsNewFrame then
                whatsNewFrame:Show()
            end
        end
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
        if itemBox and itemBox.UpdateLockIcon then itemBox.UpdateLockIcon() end
        print("|cff00ff00ItemWatch:|r frames locked.")
    elseif cmd == "unlock" then
        ItemWatchDB.locked = false
        if itemBox and itemBox.UpdateLockIcon then itemBox.UpdateLockIcon() end
        print("|cff00ff00ItemWatch:|r frames unlocked - drag them to move.")
    elseif cmd == "addrecipe" then
        AddRecipeToShoppingList()
    elseif cmd == "craftdebug" then
        -- Diagnostic tool: open a recipe in the Professions window first,
        -- then run this. Tries a few known ways to find the currently
        -- selected recipe and its reagent schematic, and reports exactly
        -- what worked and what didn't - Blizzard's crafting UI internals
        -- have shifted between expansions, so this checks reality instead
        -- of assuming any one path is still correct.
        print("|cff00ffffItemWatch craftdebug:|r starting diagnostic...")

        -- The crafting order window has been confirmed NOT to live inside
        -- ProfessionsFrame, so rather than guess another specific frame
        -- name, scan every global frame currently loaded for anything
        -- with "Order" in its name that's actually shown right now -
        -- this finds the real name empirically instead of guessing again.
        print("|cff00ffff  Scanning for shown frames with 'Order' in the name...")
        local foundAny = false
        for name, obj in pairs(_G) do
            if type(name) == "string" and name:lower():find("order") and type(obj) == "table"
               and obj.IsShown and type(obj.IsShown) == "function" then
                local ok, shown = pcall(obj.IsShown, obj)
                if ok and shown then
                    print("|cff00ff00    FOUND (shown): "..name)
                    foundAny = true
                end
            end
        end
        if not foundAny then
            print("|cffff8800    No shown frame with 'Order' in its name was found.")
        end

        if not ProfessionsFrame then
            print("|cffff8800  ProfessionsFrame doesn't exist - are you sure this client has it?")
            return
        end
        print("|cff00ffff  ProfessionsFrame exists. Shown: |r"..tostring(ProfessionsFrame:IsShown()))

        local recipeID = nil
        local foundVia = nil

        -- Confirmed via scan: the crafting order window is its own frame,
        -- ProfessionsCustomerOrdersFrame, not nested inside ProfessionsFrame
        -- at all. Rather than guess the exact nesting inside it, recursively
        -- search its children for anything with recipe data, bounded to a
        -- shallow depth so it doesn't take forever.
        if ProfessionsCustomerOrdersFrame and ProfessionsCustomerOrdersFrame:IsShown() then
            print("|cff00ff00  ProfessionsCustomerOrdersFrame is shown - searching its children...")
            local seen = {}
            local function searchForRecipe(frame, depth, path)
                if depth > 5 or type(frame) ~= "table" or seen[frame] then return nil end
                seen[frame] = true

                -- Print this frame's own name/type if it has one, so we
                -- can see the actual structure even if we don't find a
                -- match - useful for figuring out the next guess.
                local okName, fname = pcall(function() return frame.GetName and frame:GetName() end)
                if depth <= 2 and okName and fname then
                    print("|cff888888    (depth "..depth..") "..path.." = "..fname)
                end

                local ok, schematic = pcall(function() return frame.recipeSchematic end)
                if ok and type(schematic) == "table" and schematic.recipeID then
                    return schematic.recipeID, path.." (via .recipeSchematic.recipeID)"
                end
                -- Also check for a bare .recipeID directly on this object
                local ok2, directID = pcall(function() return frame.recipeID end)
                if ok2 and type(directID) == "number" then
                    return directID, path.." (via .recipeID directly)"
                end

                if frame.GetChildren then
                    local okC, children = pcall(function() return { frame:GetChildren() } end)
                    if okC then
                        for i, child in ipairs(children) do
                            local foundID, foundPath = searchForRecipe(child, depth + 1, path.."/child"..i)
                            if foundID then return foundID, foundPath end
                        end
                    end
                end
                return nil
            end
            local foundID, foundPath = searchForRecipe(ProfessionsCustomerOrdersFrame, 0, "ProfessionsCustomerOrdersFrame")
            if foundID then
                recipeID = foundID
                foundVia = foundPath
            else
                print("|cffff8800  Searched but didn't find a recipeSchematic or recipeID anywhere in its children.")
            end
        end

        local craftingShown = ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage:IsShown()
        local ordersShown = ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage:IsShown()
        print("|cff00ffff  CraftingPage shown: "..tostring(craftingShown)..
              " | OrdersPage shown: "..tostring(ordersShown))

        if recipeID then
            -- already found via the ProfessionsCustomerOrdersFrame search
            -- above, skip these older/fallback checks entirely
        elseif ordersShown then
            -- Place Crafting Order window - a different frame path than
            -- the regular Recipes tab. Trying a few plausible nestings
            -- since this hasn't been confirmed working yet.
            local attempts = {
                { "OrdersPage.OrderView.OrderInfo.SchematicForm", function()
                    return ProfessionsFrame.OrdersPage.OrderView
                       and ProfessionsFrame.OrdersPage.OrderView.OrderInfo
                       and ProfessionsFrame.OrdersPage.OrderView.OrderInfo.SchematicForm
                       and ProfessionsFrame.OrdersPage.OrderView.OrderInfo.SchematicForm.recipeSchematic
                       and ProfessionsFrame.OrdersPage.OrderView.OrderInfo.SchematicForm.recipeSchematic.recipeID
                end },
                { "OrdersPage.OrderView.SchematicForm", function()
                    return ProfessionsFrame.OrdersPage.OrderView
                       and ProfessionsFrame.OrdersPage.OrderView.SchematicForm
                       and ProfessionsFrame.OrdersPage.OrderView.SchematicForm.recipeSchematic
                       and ProfessionsFrame.OrdersPage.OrderView.SchematicForm.recipeSchematic.recipeID
                end },
                { "OrdersPage.SchematicForm", function()
                    return ProfessionsFrame.OrdersPage.SchematicForm
                       and ProfessionsFrame.OrdersPage.SchematicForm.recipeSchematic
                       and ProfessionsFrame.OrdersPage.SchematicForm.recipeSchematic.recipeID
                end },
            }
            for _, attempt in ipairs(attempts) do
                local label, fn = attempt[1], attempt[2]
                local ok, result = pcall(fn)
                if ok and result then
                    recipeID = result
                    foundVia = "OrdersPage: "..label
                    break
                end
            end
        elseif craftingShown then
            -- Regular Recipes tab
            local ok1, result1 = pcall(function()
                return ProfessionsFrame.CraftingPage.SchematicForm
                   and ProfessionsFrame.CraftingPage.SchematicForm.recipeSchematic
                   and ProfessionsFrame.CraftingPage.SchematicForm.recipeSchematic.recipeID
            end)
            if ok1 and result1 then
                recipeID = result1
                foundVia = "CraftingPage.SchematicForm.recipeSchematic.recipeID"
            end
        else
            print("|cffff8800  Neither CraftingPage nor OrdersPage is currently shown.")
        end

        if not recipeID then
            print("|cffff8800  Couldn't find a selected recipe through any known path.")
            print("|cffff8800  Make sure a recipe is actually open/selected, not just the profession window.")
            return
        end

        print("|cff00ff00  Found recipe ID: "..recipeID.." (via "..foundVia..")")

        local okS, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if not okS or not schematic then
            print("|cffff8800  GetRecipeSchematic call failed or returned nothing.")
            return
        end

        print("|cff00ff00  Recipe name: "..tostring(schematic.name))
        print("|cff00ff00  Reagent slots found: "..tostring(schematic.reagentSlotSchematics and #schematic.reagentSlotSchematics or 0))

        if schematic.reagentSlotSchematics then
            for i, slot in ipairs(schematic.reagentSlotSchematics) do
                local reagentType = slot.reagentType -- 1=required/basic, 2=optional/finishing, etc.
                local qtyRequired = slot.quantityRequired
                local itemID = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
                local itemName = itemID and (GetItemInfo(itemID) or ("item #"..itemID)) or "unknown"
                local bindType = itemID and select(14, GetItemInfo(itemID))
                local bopLabel = (bindType == 1) and "BoP (vendor/earned only)" or "not BoP (AH-purchasable)"
                print(string.format("|cff00ffff    Slot %d: %s | qty needed: %s | reagentType: %s | itemID: %s | %s",
                    i, itemName, tostring(qtyRequired), tostring(reagentType), tostring(itemID), bopLabel))
            end
        end
        print("|cff00ffffItemWatch craftdebug:|r done.")
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
    elseif cmd == "whatsnew" then
        local currentVersion = GetAddonVersion()
        print("|cff00ffffItemWatch debug:|r currentVersion=["..tostring(currentVersion).."] lastSeenVersion=["..tostring(ItemWatchDB.lastSeenVersion).."]")
        if whatsNewFrame then
            whatsNewFrame:Show()
        end
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
        print("/iw whatsnew - show the What's New popup again")
    end
end
