-- MockInventoryTester (cicicic)
-- Drop this inside StarterPlayerScripts (or run it as a Plugin script).
-- It injects fake horse items directly into InventoryMenu using the same
-- AddOrUpdateItem / RemoveItem API that the live server uses, so the real
-- Backpack UI renders them exactly as production items would appear.
--
-- Usage:
--   1. Open the Backpack menu in-game.
--   2. A small draggable GUI will appear in the top-left corner.
--   3. Pick a preset (or "Custom"), fill any fields you want to override,
--      then press "Spawn" to inject the horse.
--   4. "Clear All Mock" removes every item this script spawned.

-- ── Services / references ─────────────────────────────────────────────────────

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")

local LocalPlayer        = Players.LocalPlayer
local PlayerScripts      = LocalPlayer:WaitForChild("PlayerScripts")

local References         = require(game:GetService("ReplicatedStorage"):WaitForChild("References"))
local Utilities          = References.Utilities
local Network            = Utilities.Shared.Network

-- Wait for InventoryMenu to be ready (it's required lazily once menus load)
local InventoryMenu = require(
	PlayerScripts:WaitForChild("Secondary"):WaitForChild("InventoryMenu")
)

local Data = require(PlayerScripts:WaitForChild("Priority"):WaitForChild("Data"))

-- ── Preset table ──────────────────────────────────────────────────────────────
-- Add, remove, or edit entries freely.
-- Any field not listed here falls back to the defaults used in BuildItemData().
-- "stats" values are 0–1 floats.

local PRESETS = {
	{
		label = "Average QH",
		data = {
			id      = 370,
			name    = "Test Quarter Horse",
			pId     = 1,   -- Bold
			gId     = 2,   -- Stallion
			height  = 0.5,
			purity  = 0.5,
			baby    = false,
			invLock = false,
			stats   = { speed = 0.5, agility = 0.5, strength = 0.5, stamina = 0.5, jump = 0.5 },
			variants = {
				colour     = "mummy",
				maneColour = "neonPurple",
				tailColour = "neonPurple",
				maneStyle  = "longQH2",
				tailStyle  = "mediumQH2",
			},
		},
	},
	{
		label = "Elite Sprinter",
		data = {
			id      = 370,
			name    = "Blaze",
			pId     = 3,   -- Energetic
			gId     = 2,   -- Stallion
			height  = 0.82,
			purity  = 0.95,
			baby    = false,
			invLock = false,
			stats   = { speed = 0.97, agility = 0.88, strength = 0.60, stamina = 0.75, jump = 0.55 },
			variants = {
				colour     = "chestnut",
				maneColour = "flaxen",
				tailColour = "flaxen",
				maneStyle  = "longQH2",
				tailStyle  = "mediumQH2",
			},
		},
	},
	{
		label = "Locked Mare",
		data = {
			id      = 370,
			name    = "Rosie",
			pId     = 4,   -- Calm
			gId     = 1,   -- Mare
			height  = 0.55,
			purity  = 0.4,
			baby    = false,
			invLock = true,
			stats   = { speed = 0.45, agility = 0.50, strength = 0.40, stamina = 0.65, jump = 0.35 },
			variants = {
				colour     = "bay",
				maneColour = "black",
				tailColour = "black",
				maneStyle  = "longQH2",
				tailStyle  = "mediumQH2",
			},
		},
	},
	{
		label = "Foal (baby)",
		data = {
			id             = 370,
			name           = "Tiny",
			pId            = 2,   -- Shy
			gId            = 1,   -- Mare
			height         = 0.2,
			purity         = 0.6,
			baby           = true,
			timeUntilGrown = 3600,
			invLock        = false,
			stats          = { speed = 0.3, agility = 0.3, strength = 0.3, stamina = 0.3, jump = 0.3 },
			variants = {
				colour     = "grey",
				maneColour = "white",
				tailColour = "white",
				maneStyle  = "longQH2",
				tailStyle  = "mediumQH2",
			},
		},
	},
	{
		label = "Custom",  -- selecting this lets all fields be typed manually
		data  = {},
	},
}

-- ── Mass spawn preset table ───────────────────────────────────────────────────
-- Add as many horses as you like here. All fields are optional and fall back
-- to DefaultItemData() just like single-spawn presets do.
-- Press "Mass Spawn" in the GUI to inject every entry in this table at once.

local MASS_SPAWN_PRESETS = {
	{
		id      = 370,
		name    = "Mass Horse 1",
		pId     = 1,
		gId     = 2,
		height  = 0.6,
		purity  = 0.7,
		stats   = { speed = 0.8, agility = 0.7, strength = 0.6, stamina = 0.75, jump = 0.5 },
		variants = { colour = "bay", maneColour = "black", tailColour = "black", maneStyle = "longQH2", tailStyle = "mediumQH2" },
	},
	{
		id      = 370,
		name    = "Mass Horse 2",
		pId     = 3,
		gId     = 1,
		height  = 0.72,
		purity  = 0.85,
		stats   = { speed = 0.9, agility = 0.6, strength = 0.8, stamina = 0.65, jump = 0.7 },
		variants = { colour = "chestnut", maneColour = "flaxen", tailColour = "flaxen", maneStyle = "longQH2", tailStyle = "mediumQH2" },
	},
	{
		id      = 370,
		name    = "Mass Horse 3",
		pId     = 2,
		gId     = 1,
		height  = 0.45,
		purity  = 0.3,
		baby    = true,
		timeUntilGrown = 3600,
		stats   = { speed = 0.3, agility = 0.4, strength = 0.3, stamina = 0.35, jump = 0.25 },
		variants = { colour = "grey", maneColour = "white", tailColour = "white", maneStyle = "longQH2", tailStyle = "mediumQH2" },
	},
}

-- ── Defaults used for any field not supplied by a preset ─────────────────────

local function DefaultItemData()
	return {
		id             = 370,
		name           = nil,
		pId            = 1,
		gId            = 1,
		height         = 0.5,
		purity         = 0.5,
		madeAt         = os.time(),
		baby           = false,
		timeUntilGrown = nil,
		invLock        = false,
		untradeable    = false,
		equipped       = false,
		food           = "Golden Carrot",
		lineage        = {},
		strengthMod    = 1.0,
		agilityMod     = 1.0,
		speedMod       = 1.0,
		staminaMod     = 1.0,
		jumpMod        = 1.0,
		stats = {
			speed    = 0.5,
			agility  = 0.5,
			strength = 0.5,
			stamina  = 0.5,
			jump     = 0.5,
		},
		variants = {
			colour     = "mummy",
			maneColour = "neonPurple",
			tailColour = "neonPurple",
			maneStyle  = "longQH2",
			tailStyle  = "mediumQH2",
		},
	}
end

-- Deep-merge: copies fields from `src` into `dst` (one level deep for sub-tables)
local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			for sk, sv in pairs(v) do
				dst[k][sk] = sv
			end
		else
			dst[k] = v
		end
	end
	return dst
end

-- ── Spawned-slot tracking (declared early; referenced by the network intercept) ─

local spawnedSlots = {}  -- array of slotId strings injected by this script

-- ── Mock network intercept ───────────────────────────────────────────────────
-- The server will reject FireServer calls for mock slots since they don't exist
-- server-side. We wrap Network.FireServer to catch "Inventory", "Use", <mockSlot>,
-- "Follow" calls and handle them locally instead, so the game UI (follower label,
-- mount button, AnimalHandler) all update exactly as they would for real horses.

local originalFireServer = Network.FireServer
Network.FireServer = function(self, eventName, subAction, slotId, action, ...)
	-- Only intercept mock slots
	if eventName == "Inventory" and subAction == "Use" and action == "Follow"
		and table.find(spawnedSlots, slotId) then

		local cache = Data.Get(LocalPlayer)
		if not cache then return end

		local currentFollower = Data.GetLocal("follower")

		if currentFollower == slotId then
			-- Unfollow: clear the follower key
			cache.follower = nil
			Data.Fire(LocalPlayer, {"follower"}, nil)
		else
			-- Follow: set the new follower key
			cache.follower = slotId
			Data.Fire(LocalPlayer, {"follower"}, slotId)
		end
		return
	end

	-- Everything else passes through normally
	return originalFireServer(self, eventName, subAction, slotId, action, ...)
end

local function SpawnHorse(overrides)
	local itemData = Merge(DefaultItemData(), overrides or {})
	itemData.madeAt = os.time()

	local slotId = HttpService:GenerateGUID(false)
	table.insert(spawnedSlots, slotId)

	-- Write into the Data cache so AnimalHandler / trade validation / item info
	-- options can all find this slot exactly as they would a real inventory item
	local cache = Data.Get(LocalPlayer)
	if cache and cache.inventory then
		cache.inventory[slotId] = itemData
	end

	-- isInitialLoad = false so the "item added" alert fires, matching live behaviour
	InventoryMenu.AddOrUpdateItem(slotId, itemData, nil, false)
	return slotId
end

local function ClearAllMock()
	local cache = Data.Get(LocalPlayer)

	-- If a mock horse is the current follower, unfollow it first so AnimalHandler
	-- cleans up the mount control and FollowerUpdated fires correctly
	local currentFollower = Data.GetLocal("follower")
	if currentFollower and table.find(spawnedSlots, currentFollower) then
		cache.follower = nil
		Data.Fire(LocalPlayer, {"follower"}, nil)
	end

	for _, slotId in ipairs(spawnedSlots) do
		if cache and cache.inventory then
			cache.inventory[slotId] = nil
		end
		InventoryMenu.RemoveItem(slotId)
	end
	spawnedSlots = {}
end

-- ── GUI ───────────────────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "MockInventoryTester"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder    = 999
screenGui.Parent          = LocalPlayer:WaitForChild("PlayerGui")

-- Draggable container
local panel = Instance.new("Frame")
panel.Name              = "Panel"
panel.Size              = UDim2.fromOffset(260, 0)   -- height set by AutomaticSize
panel.Position          = UDim2.fromOffset(16, 16)
panel.BackgroundColor3  = Color3.fromRGB(22, 18, 12)
panel.BorderSizePixel   = 0
panel.AutomaticSize     = Enum.AutomaticSize.Y
panel.Parent            = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 6)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = Color3.fromRGB(100, 75, 40)
panelStroke.Thickness = 1
panelStroke.Parent    = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection  = Enum.FillDirection.Vertical
panelLayout.SortOrder      = Enum.SortOrder.LayoutOrder
panelLayout.Padding        = UDim.new(0, 0)
panelLayout.Parent         = panel

-- ── Header (drag handle) ──────────────────────────────────────────────────────

local header = Instance.new("TextButton")
header.Name              = "Header"
header.Size              = UDim2.new(1, 0, 0, 32)
header.BackgroundColor3  = Color3.fromRGB(48, 34, 16)
header.BorderSizePixel   = 0
header.Text              = "🐎  Mock Inventory Tester"
header.TextColor3        = Color3.fromRGB(200, 169, 110)
header.TextSize          = 13
header.Font              = Enum.Font.GothamBold
header.AutoButtonColor   = false
header.LayoutOrder       = 0
header.Parent            = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 6)
headerCorner.Parent = header

-- Fix: square off bottom corners of header
local headerSquare = Instance.new("Frame")
headerSquare.Size             = UDim2.new(1, 0, 0.5, 0)
headerSquare.Position         = UDim2.new(0, 0, 0.5, 0)
headerSquare.BackgroundColor3 = Color3.fromRGB(48, 34, 16)
headerSquare.BorderSizePixel  = 0
headerSquare.ZIndex           = header.ZIndex
headerSquare.Parent           = header

-- ── Body ─────────────────────────────────────────────────────────────────────

local body = Instance.new("Frame")
body.Name             = "Body"
body.Size             = UDim2.new(1, 0, 0, 0)
body.AutomaticSize    = Enum.AutomaticSize.Y
body.BackgroundTransparency = 1
body.LayoutOrder      = 1
body.Parent           = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.FillDirection = Enum.FillDirection.Vertical
bodyLayout.SortOrder     = Enum.SortOrder.LayoutOrder
bodyLayout.Padding       = UDim.new(0, 6)
bodyLayout.Parent        = body

local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingTop    = UDim.new(0, 8)
bodyPad.PaddingBottom = UDim.new(0, 10)
bodyPad.PaddingLeft   = UDim.new(0, 10)
bodyPad.PaddingRight  = UDim.new(0, 10)
bodyPad.Parent        = body

-- Helper: create a labelled row
local function MakeRow(labelText, layoutOrder)
	local row = Instance.new("Frame")
	row.Size              = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize     = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.LayoutOrder       = layoutOrder
	row.Parent            = body

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Vertical
	rowLayout.SortOrder     = Enum.SortOrder.LayoutOrder
	rowLayout.Padding       = UDim.new(0, 2)
	rowLayout.Parent        = row

	local lbl = Instance.new("TextLabel")
	lbl.Size              = UDim2.new(1, 0, 0, 14)
	lbl.BackgroundTransparency = 1
	lbl.Text              = labelText
	lbl.TextColor3        = Color3.fromRGB(140, 110, 65)
	lbl.TextSize          = 10
	lbl.Font              = Enum.Font.GothamBold
	lbl.TextXAlignment    = Enum.TextXAlignment.Left
	lbl.LayoutOrder       = 0
	lbl.Parent            = row

	return row
end

-- Helper: create a TextBox input
local function MakeInput(parent, placeholder, layoutOrder)
	local box = Instance.new("TextBox")
	box.Size              = UDim2.new(1, 0, 0, 26)
	box.BackgroundColor3  = Color3.fromRGB(12, 8, 4)
	box.BorderSizePixel   = 0
	box.Text              = ""
	box.PlaceholderText   = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(90, 70, 45)
	box.TextColor3        = Color3.fromRGB(232, 216, 176)
	box.TextSize          = 13
	box.Font              = Enum.Font.Gotham
	box.TextXAlignment    = Enum.TextXAlignment.Left
	box.ClearTextOnFocus  = false
	box.LayoutOrder       = layoutOrder or 1
	box.Parent            = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = box

	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 6)
	p.Parent      = box

	local s = Instance.new("UIStroke")
	s.Color     = Color3.fromRGB(70, 50, 25)
	s.Thickness = 1
	s.Parent    = box

	return box
end

-- Helper: styled button
local function MakeButton(text, color, parent, layoutOrder)
	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(1, 0, 0, 30)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel  = 0
	btn.Text             = text
	btn.TextColor3       = Color3.fromRGB(232, 216, 176)
	btn.TextSize         = 12
	btn.Font             = Enum.Font.GothamBold
	btn.LayoutOrder      = layoutOrder or 0
	btn.Parent           = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = btn

	return btn
end

-- ── Preset selector ───────────────────────────────────────────────────────────

local presetRow = MakeRow("PRESET", 0)
local presetIndex = 1

local presetDisplay = Instance.new("TextButton")
presetDisplay.Size             = UDim2.new(1, 0, 0, 28)
presetDisplay.BackgroundColor3 = Color3.fromRGB(30, 22, 10)
presetDisplay.BorderSizePixel  = 0
presetDisplay.Text             = PRESETS[1].label
presetDisplay.TextColor3       = Color3.fromRGB(200, 169, 110)
presetDisplay.TextSize         = 13
presetDisplay.Font             = Enum.Font.Gotham
presetDisplay.AutoButtonColor  = false
presetDisplay.LayoutOrder      = 1
presetDisplay.Parent           = presetRow

do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = presetDisplay
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(100,75,40); s.Thickness = 1; s.Parent = presetDisplay

	-- Arrow label
	local arrow = Instance.new("TextLabel")
	arrow.Size             = UDim2.new(0, 20, 1, 0)
	arrow.Position         = UDim2.new(1, -22, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text             = "▼"
	arrow.TextColor3       = Color3.fromRGB(140, 110, 65)
	arrow.TextSize         = 10
	arrow.Font             = Enum.Font.GothamBold
	arrow.Parent           = presetDisplay
end

-- Dropdown list (shown/hidden)
local dropdownFrame = Instance.new("Frame")
dropdownFrame.Name             = "Dropdown"
dropdownFrame.Size             = UDim2.new(1, 0, 0, 0)
dropdownFrame.AutomaticSize    = Enum.AutomaticSize.Y
dropdownFrame.BackgroundColor3 = Color3.fromRGB(18, 12, 6)
dropdownFrame.BorderSizePixel  = 0
dropdownFrame.Visible          = false
dropdownFrame.ZIndex           = 10
dropdownFrame.LayoutOrder      = 2
dropdownFrame.Parent           = presetRow

do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = dropdownFrame
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(100,75,40); s.Thickness = 1; s.Parent = dropdownFrame
	local l = Instance.new("UIListLayout"); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = dropdownFrame
end

-- Populate dropdown options
local dropdownCallbacks = {}
for i, preset in ipairs(PRESETS) do
	local opt = Instance.new("TextButton")
	opt.Size             = UDim2.new(1, 0, 0, 26)
	opt.BackgroundColor3 = Color3.fromRGB(18, 12, 6)
	opt.BackgroundTransparency = (i % 2 == 0) and 0 or 0.5
	opt.BorderSizePixel  = 0
	opt.Text             = preset.label
	opt.TextColor3       = Color3.fromRGB(200, 169, 110)
	opt.TextSize         = 12
	opt.Font             = Enum.Font.Gotham
	opt.LayoutOrder      = i
	opt.ZIndex           = 11
	opt.Parent           = dropdownFrame

	opt.MouseButton1Click:Connect(function()
		presetIndex = i
		presetDisplay.Text = preset.label
		dropdownFrame.Visible = false
	end)
end

presetDisplay.MouseButton1Click:Connect(function()
	dropdownFrame.Visible = not dropdownFrame.Visible
end)

-- ── Override fields (shown always; populated from preset on spawn) ─────────────

local overrideName       = MakeInput(MakeRow("NAME OVERRIDE", 1), "leave blank = preset name")
local overrideId         = MakeInput(MakeRow("ITEM ID",        2), "e.g. 370")
local overrideColour     = MakeInput(MakeRow("COLOUR",         3), "e.g. bay, chestnut, grey")
local overrideManeColour = MakeInput(MakeRow("MANE COLOUR",    4), "e.g. black, flaxen, white")
local overrideTailColour = MakeInput(MakeRow("TAIL COLOUR",    5), "e.g. black, flaxen, white")

-- Stat overrides (compact)
local statRow = Instance.new("Frame")
statRow.Size              = UDim2.new(1, 0, 0, 0)
statRow.AutomaticSize     = Enum.AutomaticSize.Y
statRow.BackgroundTransparency = 1
statRow.LayoutOrder       = 6
statRow.Parent            = body

local statLayout = Instance.new("UIListLayout")
statLayout.FillDirection = Enum.FillDirection.Vertical
statLayout.SortOrder     = Enum.SortOrder.LayoutOrder
statLayout.Padding       = UDim.new(0, 2)
statLayout.Parent        = statRow

local statLabel = Instance.new("TextLabel")
statLabel.Size            = UDim2.new(1, 0, 0, 14)
statLabel.BackgroundTransparency = 1
statLabel.Text            = "STAT OVERRIDES  (0–1, blank = preset)"
statLabel.TextColor3      = Color3.fromRGB(140, 110, 65)
statLabel.TextSize        = 10
statLabel.Font            = Enum.Font.GothamBold
statLabel.TextXAlignment  = Enum.TextXAlignment.Left
statLabel.LayoutOrder     = 0
statLabel.Parent          = statRow

local STAT_NAMES = {"speed", "agility", "strength", "stamina", "jump"}
local statInputs = {}

local statGrid = Instance.new("Frame")
statGrid.Size              = UDim2.new(1, 0, 0, 0)
statGrid.AutomaticSize     = Enum.AutomaticSize.Y
statGrid.BackgroundTransparency = 1
statGrid.LayoutOrder       = 1
statGrid.Parent            = statRow

local statGridLayout = Instance.new("UIGridLayout")
statGridLayout.CellSize        = UDim2.new(0.5, -3, 0, 26)
statGridLayout.CellPaddingX    = UDim2.new(0, 6, 0, 0)
statGridLayout.CellPaddingY    = UDim2.new(0, 4, 0, 0)
statGridLayout.SortOrder       = Enum.SortOrder.LayoutOrder
statGridLayout.Parent          = statGrid

for i, statName in ipairs(STAT_NAMES) do
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(12, 8, 4)
	box.BorderSizePixel  = 0
	box.PlaceholderText  = statName
	box.PlaceholderColor3 = Color3.fromRGB(90, 70, 45)
	box.Text             = ""
	box.TextColor3       = Color3.fromRGB(232, 216, 176)
	box.TextSize         = 12
	box.Font             = Enum.Font.Gotham
	box.TextXAlignment   = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.LayoutOrder      = i
	box.Parent           = statGrid

	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = box
	local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,5); p.Parent = box
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(70,50,25); s.Thickness = 1; s.Parent = box

	statInputs[statName] = box
end

-- Fix statGrid height (UIGridLayout doesn't drive AutomaticSize cleanly)
local function UpdateStatGridHeight()
	local rows = math.ceil(#STAT_NAMES / 2)
	statGrid.Size = UDim2.new(1, 0, 0, rows * 26 + (rows - 1) * 4)
end
UpdateStatGridHeight()

-- ── Buttons ───────────────────────────────────────────────────────────────────

local spawnBtn     = MakeButton("🐎  Spawn Horse",             Color3.fromRGB(60, 42, 18),  body, 10)
local massSpawnBtn = MakeButton("🐎🐎  Mass Spawn Horses",     Color3.fromRGB(35, 50, 20),  body, 11)
local clearBtn     = MakeButton("✕  Clear All Mock Horses",    Color3.fromRGB(50, 18, 18),  body, 12)

do
	local s  = Instance.new("UIStroke"); s.Color  = Color3.fromRGB(100, 75,  40); s.Thickness = 1; s.Parent = spawnBtn
	local s2 = Instance.new("UIStroke"); s2.Color = Color3.fromRGB(70,  110, 40); s2.Thickness = 1; s2.Parent = massSpawnBtn
	local s3 = Instance.new("UIStroke"); s3.Color = Color3.fromRGB(120, 40,  40); s3.Thickness = 1; s3.Parent = clearBtn
end

-- ── Spawn logic ───────────────────────────────────────────────────────────────

spawnBtn.MouseButton1Click:Connect(function()
	local preset = PRESETS[presetIndex]

	-- Start from defaults, layer on preset, then apply any typed overrides
	local overrides = {}

	-- Copy preset data
	for k, v in pairs(preset.data) do
		overrides[k] = v
	end

	-- Name override
	local nameText = overrideName.Text ~= "" and overrideName.Text or nil
	if nameText then
		overrides.name = nameText
	end

	-- Item ID override
	local idText = tonumber(overrideId.Text)
	if idText then
		overrides.id = idText
	end

	-- Colour override
	local colText = overrideColour.Text ~= "" and overrideColour.Text or nil
	if colText then
		overrides.variants = overrides.variants or {}
		overrides.variants.colour = colText
	end

	-- Mane colour override
	local maneText = overrideManeColour.Text ~= "" and overrideManeColour.Text or nil
	if maneText then
		overrides.variants = overrides.variants or {}
		overrides.variants.maneColour = maneText
	end

	-- Tail colour override
	local tailText = overrideTailColour.Text ~= "" and overrideTailColour.Text or nil
	if tailText then
		overrides.variants = overrides.variants or {}
		overrides.variants.tailColour = tailText
	end

	-- Stat overrides
	local statsOverride = {}
	for _, statName in ipairs(STAT_NAMES) do
		local val = tonumber(statInputs[statName].Text)
		if val then
			statsOverride[statName] = math.clamp(val, 0, 1)
		end
	end
	if next(statsOverride) then
		overrides.stats = overrides.stats or {}
		for k, v in pairs(statsOverride) do
			overrides.stats[k] = v
		end
	end

	local ok, err = pcall(SpawnHorse, overrides)
	if not ok then
		warn("[MockInventoryTester] SpawnHorse failed:", err)
	end
end)

clearBtn.MouseButton1Click:Connect(function()
	local ok, err = pcall(ClearAllMock)
	if not ok then
		warn("[MockInventoryTester] ClearAllMock failed:", err)
	end
end)

massSpawnBtn.MouseButton1Click:Connect(function()
	if #MASS_SPAWN_PRESETS == 0 then
		warn("[MockInventoryTester] MASS_SPAWN_PRESETS is empty — add entries to the table at the top of the script.")
		return
	end
	for _, horseData in ipairs(MASS_SPAWN_PRESETS) do
		local ok, err = pcall(SpawnHorse, horseData)
		if not ok then
			warn("[MockInventoryTester] Mass spawn entry failed:", err)
		end
	end
	print(("[MockInventoryTester] Mass spawned %d horses."):format(#MASS_SPAWN_PRESETS))
end)

-- ── Drag logic ────────────────────────────────────────────────────────────────

do
	local dragging, dragStart, startPos

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging  = true
			dragStart = input.Position
			startPos  = panel.Position
		end
	end)

	header.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	game:GetService("UserInputService").InputChanged:Connect(function(input)
		if dragging and (
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		) then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- ── Done ──────────────────────────────────────────────────────────────────────

print("[MockInventoryTester] Ready — drag the panel, pick a preset, press Spawn.")
