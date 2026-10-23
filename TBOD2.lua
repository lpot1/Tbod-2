if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Services
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local CoreGui             = game:GetService("CoreGui")
local PathfindingService  = game:GetService("PathfindingService")
local GuiService          = game:GetService("GuiService")
local StarterGui          = game:GetService("StarterGui")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace           = game:GetService("Workspace")
local VirtualUser         = game:GetService("VirtualUser")

local localPlayer = Players.LocalPlayer

-- Configuration
local CONFIG = {
	GuiName = "TycoonManagerGui",
	Font    = Enum.Font.Arcade,

	Colors = {
		Background = Color3.fromRGB(15, 15, 18),
		Panel      = Color3.fromRGB(25, 25, 30),
		Header     = Color3.fromRGB(35, 35, 45),
		Stroke     = Color3.fromRGB(35, 35, 45),
		On         = Color3.fromRGB(60, 200, 120),
		Accent     = Color3.fromRGB(60, 120, 200),
		Danger     = Color3.fromRGB(255, 65, 65),
		Text       = Color3.fromRGB(255, 255, 255),
		TextDim    = Color3.fromRGB(180, 180, 180),
		TextMuted  = Color3.fromRGB(200, 200, 200),
	},

	Window = {
		Position        = UDim2.new(0, 20, 0, 20),
		Size            = UDim2.new(0, 430, 0, 365),
		MinimizedHeight = 30,
		HeaderHeight    = 30,
		PanelY          = 70,
	},

	Intervals = {
		Shop            = 0.20,
		Stats           = 0.50,
		Merchant        = 0.25,
		Locator         = 0.20,
		Rebirth         = 0.50,
		AutoBuyCooldown = 0.22,
		CardCooldown    = 0.40,
	},

	Rebirth = {
		EssencePhrase   = "your essence is capped",
		ConfirmDelay    = 2,
		Cooldown        = 4,
		RetryCooldown   = 6,
		TeleportDelay   = 3,
		PlotSpawnOffset = 6,
	},

	Pathfinding = {
		AgentRadius         = 2.5,
		AgentHeight         = 5,
		AgentCanJump        = true,
		AgentCanClimb       = true,
		WaypointSpacing     = 3,
		WaterCost           = 20,
		ReachDistance       = 4.5,
		WaypointReach       = 3.2,
		WaypointTimeout     = 2.5,
		JumpHeightThreshold = 3,
		JumpInterval        = 1,
		FallbackSeconds     = 10,
		StuckDistance       = 0.55,
		StuckTime           = 0.5,
		StuckPush           = 2.2,
		StuckLift           = 1.2,
	},

	Guidelines = {
		MaxDistance   = 4000,
		Color         = Color3.fromRGB(60, 200, 120),
		Width         = 2,
		Texture       = "rbxassetid://446111271",
		TextureSpeed  = 3,
		TextureLength = 3,
	},

	AutoPickMinCards = 5,

	MerchantLocator = {
		MinY        = 30,
		MaxDistance = 4000,
		Color       = Color3.fromRGB(77, 0, 201),
	},

	-- Remote keeps the original default; Teleport is the most reliable mode
	-- because tycoon button purchases are validated server-side.
	DefaultBuyMode = 1,
	BuyModes = {
		{ id = "Remote",   text = "Mode: Remote" },
		{ id = "Teleport", text = "Mode: Teleport" },
		{ id = "Pathfind", text = "Mode: Pathfind" },
	},
}

local C = CONFIG.Colors

-- Real abbreviation table used by the game (ReplicatedStorage.MODULES.NumberService)
local SUFFIX_MULT = {
	K = 1e3, M = 1e6, B = 1e9, T = 1e12,
	QA = 1e15, QN = 1e18, SX = 1e21, SP = 1e24,
	OC = 1e27, NO = 1e30, DE = 1e33, UD = 1e36,
}

local FORMAT_STEPS = {
	{ 1e36, "Ud" }, { 1e33, "De" }, { 1e30, "No" }, { 1e27, "Oc" },
	{ 1e24, "Sp" }, { 1e21, "Sx" }, { 1e18, "Qn" }, { 1e15, "Qa" },
	{ 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" },
}

local ROMAN = {
	{ 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" },
	{ 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" },
	{ 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" },
}

-- Shared state & cleanup
local env = (getgenv and getgenv()) or _G

if env.TBODManagerCleanup then
	pcall(env.TBODManagerCleanup)
end
if env.TycoonManagerCleanup then
	pcall(env.TycoonManagerCleanup)
end

local function getGuiParent()
	return (gethui and gethui()) or CoreGui
end

local guiParent = getGuiParent()
for _, parent in ipairs({ guiParent, CoreGui }) do
	for _, name in ipairs({ CONFIG.GuiName, "TBODManagerGui" }) do
		local oldGui = parent and parent:FindFirstChild(name)
		if oldGui then oldGui:Destroy() end
	end
end

local running = true
local connections = {}
local cleanupHooks = {}

local function track(connection)
	connections[#connections + 1] = connection
	return connection
end

local State = {
	beamsEnabled           = false,
	autoBuyEnabled         = false,
	autoRebirthEnabled     = false,
	essenceCapEnabled      = true,
	autoPickCardEnabled    = false,
	merchantLocatorEnabled = false,
	antiAfkEnabled         = false,
	buyModeIndex           = CONFIG.DefaultBuyMode,
	isRebirthing           = false,
	isBuying               = false,
	autoRebirthArmed       = false,
	isMinimized            = false,
	isLoadingTelekinesis   = false,
	inventoryEnabled       = false,
	activeTab              = "Stats",
	status                 = "Idle",
	lastRebirthAttempt     = 0,
	lastCardBuy            = 0,
}

-- Helpers
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function addCorner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function addStroke(parent, color, thickness)
	return new("UIStroke", { Color = color or C.Stroke, Thickness = thickness or 1 }, parent)
end

local function setText(label, text)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function parseNumber(str)
	if str == nil then return nil end
	local s = string.upper(tostring(str)):gsub("[%,%$%s]", "")
	if s == "" then return nil end
	if s:find("FREE", 1, true) then return 0 end

	local num, suffix = string.match(s, "^([%d%.]+)(%a*)$")
	if not num then
		num = string.match(s, "([%d%.]+)")
		suffix = nil
	end

	num = tonumber(num)
	if not num then return nil end

	if suffix and suffix ~= "" then
		local mult = SUFFIX_MULT[suffix]
		if mult then return num * mult end
	end
	return num
end

local function formatNumber(num)
	if not num or num ~= num then return "0" end
	for _, step in ipairs(FORMAT_STEPS) do
		if num >= step[1] then
			return string.format("%.2f%s", num / step[1], step[2])
		end
	end
	if num == math.floor(num) then
		return string.format("%d", num)
	end
	return (string.format("%.2f", num):gsub("0+$", ""):gsub("%.$", ""))
end

local function romanToNumber(str)
	if not str then return nil end
	local s = string.upper(tostring(str)):gsub("%s", "")
	if s == "" then return nil end
	if s:match("^%d+$") then return tonumber(s) end

	local i, total = 1, 0
	while i <= #s do
		local matched = false
		for _, pair in ipairs(ROMAN) do
			local len = #pair[2]
			if string.sub(s, i, i + len - 1) == pair[2] then
				total = total + pair[1]
				i = i + len
				matched = true
				break
			end
		end
		if not matched then return nil end
	end
	return total
end

local function parseProgress(text)
	if not text or text == "" then return 0 end
	if string.find(string.upper(text), "COMPLETE", 1, true) then return 100 end

	local currentStr, requiredStr = string.match(text, "([%d%.,]+%s*%a*)%s*/%s*([%d%.,]+%s*%a*)")
	if currentStr and requiredStr then
		local current = parseNumber(currentStr)
		local required = parseNumber(requiredStr)
		if current and required and required > 0 then
			return math.clamp((current / required) * 100, 0, 100)
		end
	end

	local percent = string.match(text, "(%d+%.?%d*)%%")
	if percent then return math.clamp(tonumber(percent) or 0, 0, 100) end
	return 0
end

-- GUI setup
local ScreenGui = new("ScreenGui", { Name = CONFIG.GuiName, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
ScreenGui.Parent = guiParent

local W = CONFIG.Window

local MainFrame = new("Frame", {
	Name = "MainFrame", BackgroundColor3 = C.Background, Position = W.Position,
	Size = W.Size, ClipsDescendants = true, Active = true,
}, ScreenGui)
addCorner(MainFrame, 8)
addStroke(MainFrame, C.Stroke, 1.5)

local Header = new("Frame", { Name = "Header", BackgroundColor3 = C.Header, Size = UDim2.new(1, 0, 0, W.HeaderHeight) }, MainFrame)
addCorner(Header, 8)

new("TextLabel", {
	Name = "Title", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -70, 1, 0),
	Font = CONFIG.Font, RichText = true, Text = "TBOD^2 Manager [Stats & Auto Farm]",
	TextColor3 = C.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, Header)

local MinimizeBtn = new("TextButton", {
	Name = "MinimizeBtn", BackgroundTransparency = 1, Position = UDim2.new(1, -60, 0, 0), Size = UDim2.new(0, 30, 1, 0),
	Font = CONFIG.Font, Text = "v", TextColor3 = C.Text, TextSize = 14,
}, Header)

local CloseBtn = new("TextButton", {
	Name = "CloseBtn", BackgroundTransparency = 1, Position = UDim2.new(1, -30, 0, 0), Size = UDim2.new(0, 30, 1, 0),
	Font = CONFIG.Font, Text = "X", TextColor3 = C.Danger, TextSize = 14,
}, Header)

CloseBtn.MouseButton1Click:Connect(function()
	if env.TycoonManagerCleanup then
		env.TycoonManagerCleanup()
	elseif env.TBODManagerCleanup then
		env.TBODManagerCleanup()
	else
		ScreenGui:Destroy()
	end
end)

local CategoryBar = new("ScrollingFrame", {
	Name = "CategoryBar", BackgroundTransparency = 1, Position = UDim2.new(0, 5, 0, 33), Size = UDim2.new(1, -10, 0, 28),
	CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 2, AutomaticCanvasSize = Enum.AutomaticSize.X,
}, MainFrame)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, CategoryBar)

local function makeButton(parent, name, text, bg)
	local btn = new("TextButton", {
		Name = name, BackgroundColor3 = bg or C.Panel, Size = UDim2.new(1, 0, 0, 25),
		Font = CONFIG.Font, Text = text, TextColor3 = C.Text, TextSize = 14,
	}, parent)
	addCorner(btn, 6)
	return btn
end

local function makeListPanel(name, scrolling)
	local props = {
		Name = name, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, W.PanelY),
		Size = UDim2.new(1, -20, 1, -(W.PanelY + 5)), Visible = false,
	}
	if scrolling then
		props.BorderSizePixel = 0
		props.CanvasSize = UDim2.new(0, 0, 0, 0)
		props.ScrollBarThickness = 4
		props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	else
		props.Size = UDim2.new(1, 0, 0, 285)
	end
	local panel = new(scrolling and "ScrollingFrame" or "Frame", props, MainFrame)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, panel)
	return panel
end

-- Stats panel
local PanelStats = new("Frame", {
	Name = "PanelStats", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, W.PanelY),
	Size = UDim2.new(1, 0, 0, 285), Visible = true,
}, MainFrame)

local StatsLabel = new("TextLabel", {
	Name = "StatsLabel", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 0, 78),
	Font = CONFIG.Font, Text = "Stats:\nCash: $0\nPlot: Searching...\nEssence Capped: False\nBit Generator: --:--", TextColor3 = C.On, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, PanelStats)

local RebirthContentFrame = new("Frame", {
	Name = "RebirthContentFrame", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 84), Size = UDim2.new(1, 0, 0, 84),
}, PanelStats)

local function statLabel(name, y, height, text, color, size)
	return new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y), Size = UDim2.new(1, -20, 0, height),
		Font = CONFIG.Font, Text = text, TextColor3 = color, TextSize = size, TextWrapped = size <= 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, RebirthContentFrame)
end

local PercentLabel      = statLabel("PercentLabel", 0, 18, "0%", C.Text, 16)
local RebirthLabel      = statLabel("RebirthLabel", 34, 16, "Progress: Loading...", C.TextMuted, 14)
local CappedStatusLabel = statLabel("CappedStatusLabel", 52, 16, "Capped: Loading...", C.TextMuted, 14)

local ProgressBarBg = new("Frame", {
	Name = "ProgressBarBg", BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 10, 0, 20),
	Size = UDim2.new(1, -20, 0, 10), ClipsDescendants = true,
}, RebirthContentFrame)
addCorner(ProgressBarBg, 6)

local ProgressBarFill = new("Frame", {
	Name = "ProgressBarFill", BackgroundColor3 = C.Text, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0),
}, ProgressBarBg)
addCorner(ProgressBarFill, 6)

local ProgressGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 200, 120)),
	}),
}, ProgressBarFill)

local MerchantsListFrame = new("ScrollingFrame", {
	Name = "MerchantsListFrame", BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 116),
	Position = UDim2.new(0, 10, 0, 168), CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, BorderSizePixel = 0,
}, PanelStats)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, MerchantsListFrame)
local merchantButtons = {}

-- Auto farm panel
local PanelAutoFarm = makeListPanel("PanelAutoFarm", true)
local AutoBuyToggleBtn     = makeButton(PanelAutoFarm, "AutoBuyToggleBtn", "Auto Buy: OFF", C.Panel)
local MoveModeBtn          = makeButton(PanelAutoFarm, "MoveModeBtn", CONFIG.BuyModes[State.buyModeIndex].text,
	(CONFIG.BuyModes[State.buyModeIndex].id == "Remote" and C.On) or C.Panel)
local AutoRebirthToggleBtn = makeButton(PanelAutoFarm, "AutoRebirthToggleBtn", "Auto Rebirth: OFF", C.Panel)
local EssenceCapToggleBtn  = makeButton(PanelAutoFarm, "EssenceCapToggleBtn", "Essence Cap: ON", C.On)
local BeamToggleBtn        = makeButton(PanelAutoFarm, "BeamToggleBtn", "Guidelines: OFF", C.Panel)
local MerchantLocatorBtn   = makeButton(PanelAutoFarm, "MerchantLocatorBtn", "Merchant Locator: OFF", C.Panel)
local AutoPickToggleBtn    = makeButton(PanelAutoFarm, "AutoPickToggleBtn", "Auto Bits: OFF", C.Panel)
local AntiAfkToggleBtn     = makeButton(PanelAutoFarm, "AntiAfkToggleBtn", "Anti-AFK: OFF", C.Panel)
local ManualRebirthBtn     = makeButton(PanelAutoFarm, "ManualRebirthBtn", "Open Rebirth GUI", C.Panel)

local StatusLabel = new("TextLabel", {
	Name = "StatusLabel", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
	Font = CONFIG.Font, Text = "Status: idle", TextColor3 = C.TextDim, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, PanelAutoFarm)

-- Misc panel
local PanelMisc = makeListPanel("PanelMisc", true)

new("TextLabel", {
	Name = "MiscInfo", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40),
	Font = CONFIG.Font, Text = "Extra tools:", TextColor3 = C.TextDim, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
}, PanelMisc)

local LoadTelekinesisBtn = makeButton(PanelMisc, "LoadTelekinesisBtn", "Telekinesis", C.Panel)
local InventoryToggleBtn = makeButton(PanelMisc, "InventoryToggleBtn", "Inventory: OFF", C.Panel)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Tabs
local panels = { Stats = PanelStats, ["Auto Farm"] = PanelAutoFarm, Misc = PanelMisc }
local tabOrder = { "Stats", "Auto Farm", "Misc" }
local tabButtons = {}

local function refreshTabs()
	for name, panel in pairs(panels) do
		panel.Visible = (not State.isMinimized) and name == State.activeTab
	end
	for name, btn in pairs(tabButtons) do
		local active = name == State.activeTab
		btn.BackgroundColor3 = active and C.Accent or C.Panel
		btn.TextColor3 = active and C.Text or C.TextDim
	end
end

for _, name in ipairs(tabOrder) do
	local btn = new("TextButton", {
		Name = name .. "Tab", Size = UDim2.new(0, 100, 1, 0), Font = CONFIG.Font,
		Text = name, TextSize = 14, BackgroundColor3 = C.Panel,
	}, CategoryBar)
	addCorner(btn, 6)
	addStroke(btn, C.Stroke, 1)
	tabButtons[name] = btn
	btn.MouseButton1Click:Connect(function()
		State.activeTab = name
		refreshTabs()
	end)
end
refreshTabs()

local function bindToggle(btn, label, stateKey, onColor)
	btn.MouseButton1Click:Connect(function()
		State[stateKey] = not State[stateKey]
		local on = State[stateKey]
		btn.BackgroundColor3 = on and onColor or C.Panel
		btn.Text = label .. (on and ": ON" or ": OFF")
	end)
end

bindToggle(BeamToggleBtn, "Guidelines", "beamsEnabled", C.On)
bindToggle(AutoBuyToggleBtn, "Auto Buy", "autoBuyEnabled", C.On)
bindToggle(AutoRebirthToggleBtn, "Auto Rebirth", "autoRebirthEnabled", C.On)
bindToggle(EssenceCapToggleBtn, "Essence Cap", "essenceCapEnabled", C.On)
bindToggle(AutoPickToggleBtn, "Auto Bits", "autoPickCardEnabled", C.On)
bindToggle(MerchantLocatorBtn, "Merchant Locator", "merchantLocatorEnabled", C.On)
bindToggle(AntiAfkToggleBtn, "Anti-AFK", "antiAfkEnabled", C.On)

MoveModeBtn.MouseButton1Click:Connect(function()
	State.buyModeIndex = State.buyModeIndex % #CONFIG.BuyModes + 1
	local mode = CONFIG.BuyModes[State.buyModeIndex]
	MoveModeBtn.Text = mode.text
	MoveModeBtn.BackgroundColor3 = (mode.id == "Remote" and C.On) or (mode.id == "Pathfind" and C.Accent) or C.Panel
end)

-- Window dragging & minimize
local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

Header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = MainFrame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end)

Header.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

track(UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end))

MinimizeBtn.MouseButton1Click:Connect(function()
	State.isMinimized = not State.isMinimized
	local minimized = State.isMinimized
	MainFrame.Size = minimized and UDim2.new(W.Size.X.Scale, W.Size.X.Offset, 0, W.MinimizedHeight) or W.Size
	MinimizeBtn.Text = minimized and ">" or "v"
	CategoryBar.Visible = not minimized
	refreshTabs()
end)

-- Queries
local function getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui")
end

local tycoonCache = { time = 0, obj = nil }
local function getMyTycoon()
	local cached = tycoonCache.obj
	if cached and cached.Parent and tick() - tycoonCache.time < 2 then
		return cached
	end

	local tycoons = Workspace:FindFirstChild("Tycoons")
	if not tycoons then return nil end

	for _, tycoon in ipairs(tycoons:GetChildren()) do
		if tycoon:GetAttribute("OwnerId") == localPlayer.UserId then
			tycoonCache = { time = tick(), obj = tycoon }
			return tycoon
		end
	end
	return nil
end

local function getMyPlot()
	local tycoon = getMyTycoon()
	local plots = Workspace:FindFirstChild("Plots")
	if not tycoon or not plots then return nil end

	local base = tycoon:FindFirstChild("Base") or tycoon:FindFirstChild("SpawnPart")
	if not (base and base:IsA("BasePart")) then return nil end

	local closest, shortest = nil, math.huge
	for _, plot in ipairs(plots:GetChildren()) do
		local origin = plot:FindFirstChild("BuildOrigin")
		if origin and origin:IsA("BasePart") then
			local distance = (origin.Position - base.Position).Magnitude
			if distance < shortest then
				shortest, closest = distance, plot
			end
		end
	end
	if closest and shortest <= 8 then return closest, closest.Name end
	return nil
end

local cashCache = { time = 0, num = 0, str = "$0" }
local function getPlayerCash(force)
	local now = tick()
	if not force and now - cashCache.time < 0.12 then
		return cashCache.num, cashCache.str
	end

	local playerGui = getPlayerGui()
	if playerGui then
		local system = playerGui:FindFirstChild("System")
		local main = system and system:FindFirstChild("Main")
		local cashFrame = main and main:FindFirstChild("Cash")
		local cashLabel = cashFrame and cashFrame:FindFirstChild("CashText")
		if cashLabel and cashLabel:IsA("TextLabel") and cashLabel.Text ~= "" then
			local parsed = parseNumber(cashLabel.Text)
			if parsed then
				cashCache = { time = now, num = parsed, str = cashLabel.Text }
				return parsed, cashLabel.Text
			end
		end

		local playerList = system and system:FindFirstChild("PlayerList")
		local holder = playerList and playerList:FindFirstChild("Holder")
		local myFrame = holder and holder:FindFirstChild(localPlayer.Name)
		local myCash = myFrame and myFrame:FindFirstChild("CashText")
		if myCash and myCash:IsA("TextLabel") and myCash.Text ~= "" then
			local parsed = parseNumber(myCash.Text)
			if parsed then
				cashCache = { time = now, num = parsed, str = myCash.Text }
				return parsed, myCash.Text
			end
		end
	end

	return 0, "$0"
end

local function getProgressText()
	local playerGui = getPlayerGui()
	local system = playerGui and playerGui:FindFirstChild("System")
	local holder = system and system:FindFirstChild("RebirthProgress")
	local progress = holder and holder:FindFirstChild("Progress")
	local label = progress and progress:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then return label.Text end
	return ""
end

local function getBitsGeneratorTime()
	local playerGui = getPlayerGui()
	local system = playerGui and playerGui:FindFirstChild("System")
	local bitsGenerator = system and system:FindFirstChild("BitsGenerator")
	local holder = bitsGenerator and bitsGenerator:FindFirstChild("Holder")
	local output = holder and holder:FindFirstChild("Output")
	local stats = output and output:FindFirstChild("Stats")
	local timeLabel = stats and stats:FindFirstChild("Time")
	if timeLabel and timeLabel:IsA("TextLabel") and timeLabel.Text ~= "" then
		return timeLabel.Text
	end
	return "--:--"
end

local function getRebirthCount()
	local playerGui = getPlayerGui()
	local system = playerGui and playerGui:FindFirstChild("System")
	if not system then return nil end

	local main = system:FindFirstChild("Main")
	local rebirths = main and main:FindFirstChild("Rebirths")
	if rebirths then
		local number = rebirths:FindFirstChild("Number")
		if number and number:IsA("TextLabel") then
			local digits = string.match(number.Text, "%((%d+)%)") or string.match(number.Text, "(%d+)")
			if digits then return tonumber(digits) end
		end
		local numeral = rebirths:FindFirstChild("Numeral")
		if numeral and numeral:IsA("TextLabel") then
			local parsed = romanToNumber(numeral.Text)
			if parsed then return parsed end
		end
	end

	local playerList = system:FindFirstChild("PlayerList")
	local holder = playerList and playerList:FindFirstChild("Holder")
	local myFrame = holder and holder:FindFirstChild(localPlayer.Name)
	local rebsText = myFrame and myFrame:FindFirstChild("RebsText")
	if rebsText and rebsText:IsA("TextLabel") then
		return romanToNumber(rebsText.Text)
	end
	return nil
end

local function hasRebirthNotification()
	local playerGui = getPlayerGui()
	local system = playerGui and playerGui:FindFirstChild("System")
	local notifications = system and system:FindFirstChild("Notifications")
	local holder = notifications and notifications:FindFirstChild("NotiHolder")
	return holder ~= nil and holder:FindFirstChild("RebirthNotification") ~= nil
end

local essenceCache = { time = 0, value = false }
local function isEssenceCapped()
	local now = tick()
	if now - essenceCache.time < 0.1 then return essenceCache.value end

	local capped = false
	local playerGui = getPlayerGui()
	local system = playerGui and playerGui:FindFirstChild("System")
	local notifications = system and system:FindFirstChild("Notifications")
	local holder = notifications and notifications:FindFirstChild("NotiHolder")

	-- Only the real "Your essence is capped!" notification counts.
	local noti = holder and holder:FindFirstChild("EssenceCappedTemp")
	if noti then
		local pos = noti:FindFirstChild("Pos")
		local textObj = (pos and pos:FindFirstChild("Text")) or noti:FindFirstChild("Text")
		if textObj and textObj:IsA("TextLabel") then
			capped = string.find(string.lower(textObj.Text), CONFIG.Rebirth.EssencePhrase, 1, true) ~= nil
		else
			capped = true
		end
	end

	essenceCache.time, essenceCache.value = now, capped
	return capped
end

local function isButtonActive(btn)
	if not btn or not btn.Parent then return false end
	if btn:IsA("BasePart") then
		-- Sold buttons stay in the folder but are made invisible and non-collidable.
		if btn.Transparency >= 1 or not btn.CanCollide then return false end
	end
	return true
end

local function getTargetPosition(target)
	if target:IsA("BasePart") then return target.Position end
	if target:IsA("Model") then
		local part = target:FindFirstChild("Head") or target:FindFirstChild("Part") or target:FindFirstChildWhichIsA("BasePart")
		return part and part.Position or target:GetPivot().Position
	end
	return nil
end

local buttonCache = setmetatable({}, { __mode = "k" })
local function getButtonDetails(btn)
	if not isButtonActive(btn) then return nil end

	local priceDisplay = btn:FindFirstChild("PriceDisplay")
	local priceLabel = priceDisplay and priceDisplay:FindFirstChildWhichIsA("TextLabel", true)
	local nameDisplay = btn:FindFirstChild("NameDisplay")
	local nameLabel = nameDisplay and nameDisplay:FindFirstChildWhichIsA("TextLabel", true)

	local priceText = priceLabel and priceLabel.Text or ""
	local buttonName = (nameLabel and nameLabel.Text ~= "" and nameLabel.Text) or btn.Name

	local cached = buttonCache[btn]
	if cached and cached.priceText == priceText and cached.name == buttonName then
		return cached.price, cached.priceText, cached.name
	end

	local price = parseNumber(priceText)
	if not price then
		for _, desc in ipairs(btn:GetDescendants()) do
			if desc:IsA("TextLabel") and desc.Text ~= "" then
				local parsed = parseNumber(desc.Text)
				if parsed then
					price, priceText = parsed, desc.Text
					break
				end
			end
		end
	end
	if not price and string.find(string.lower(buttonName), "free", 1, true) then
		price, priceText = 0, "Free"
	end
	if not price then return nil end

	buttonCache[btn] = { price = price, priceText = priceText, name = buttonName }
	return price, priceText, buttonName
end

-- Movement
local pathToken = 0

local function cancelPath()
	pathToken = pathToken + 1
end

local function touchPart(root, part)
	if not root or not part then return end
	pcall(firetouchinterest, root, part, 1)
	task.wait(0.02)
	pcall(firetouchinterest, root, part, 0)
end

local function moveToTarget(target)
	local character = localPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local targetPos = getTargetPosition(target)
	if not targetPos then return end

	cancelPath()
	local myToken = pathToken

	local modeId = CONFIG.BuyModes[State.buyModeIndex].id
	if modeId == "Remote" then
		local part = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart")
		if part then
			touchPart(root, part)
		else
			pcall(function() root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0)) end)
		end
		return
	elseif modeId == "Teleport" then
		pcall(function() root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0)) end)
		return
	end

	task.spawn(function()
		local P = CONFIG.Pathfinding
		local path = PathfindingService:CreatePath({
			AgentRadius = P.AgentRadius, AgentHeight = P.AgentHeight, AgentCanJump = P.AgentCanJump,
			AgentCanClimb = P.AgentCanClimb, WaypointSpacing = P.WaypointSpacing,
			Costs = { Water = P.WaterCost, Danger = math.huge },
		})
		local startedAt, lastJump = tick(), 0

		local function aborted()
			return not running or myToken ~= pathToken or not root.Parent
				or humanoid.Health <= 0 or not target.Parent or not isButtonActive(target)
		end

		local function jumpIfHigher()
			local pos = getTargetPosition(target)
			if pos and pos.Y - root.Position.Y > P.JumpHeightThreshold and tick() - lastJump >= P.JumpInterval then
				lastJump = tick()
				humanoid.Jump = true
			end
		end

		local function fallbackTeleport()
			if tick() - startedAt < P.FallbackSeconds then return false end
			local pos = getTargetPosition(target)
			if pos and (root.Position - pos).Magnitude > P.ReachDistance then
				root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
			end
			return true
		end

		while not aborted() do
			if fallbackTeleport() then return end
			targetPos = getTargetPosition(target)
			if not targetPos then return end
			jumpIfHigher()

			if (root.Position - targetPos).Magnitude <= P.ReachDistance then
				humanoid:MoveTo(targetPos)
				task.wait(0.35)
			else
				local ok = pcall(function() path:ComputeAsync(root.Position, targetPos) end)
				if not ok or path.Status ~= Enum.PathStatus.Success then
					humanoid:MoveTo(targetPos)
					task.wait(0.45)
				else
					local waypoints = path:GetWaypoints()
					if #waypoints < 2 then
						humanoid:MoveTo(targetPos)
						task.wait(0.3)
					else
						for i = 2, #waypoints do
							if aborted() then return end
							local waypointPos = waypoints[i].Position
							targetPos = getTargetPosition(target)
							if not targetPos then return end
							if (root.Position - targetPos).Magnitude <= P.ReachDistance then break end

							humanoid:MoveTo(waypointPos)
							local startTime = tick()
							local lastPos, stuckTimer = root.Position, 0
							while (root.Position - waypointPos).Magnitude > P.WaypointReach do
								if aborted() or fallbackTeleport() then return end
								targetPos = getTargetPosition(target)
								if targetPos and (root.Position - targetPos).Magnitude <= P.ReachDistance then break end
								if tick() - startTime > P.WaypointTimeout then break end
								jumpIfHigher()

								if (root.Position - lastPos).Magnitude < P.StuckDistance then
									stuckTimer = stuckTimer + 0.08
									if stuckTimer > P.StuckTime then
										local away = root.Position - waypointPos
										if away.Magnitude < 0.1 then
											away = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1))
										end
										root.CFrame = root.CFrame + (away.Unit * P.StuckPush) + Vector3.new(0, P.StuckLift, 0)
										stuckTimer = 0
										lastPos = root.Position
										task.wait(0.1)
									end
								else
									stuckTimer = 0
									lastPos = root.Position
								end
								task.wait(0.07)
							end
						end
					end
				end
			end
			task.wait(0.12)
		end
	end)
end

-- Beams
local beams = {}
local merchantBeams = {}

local function destroyBeam(set, key)
	local data = set[key]
	if not data then return end
	pcall(function() data.beam:Destroy() end)
	pcall(function() data.att0:Destroy() end)
	pcall(function() data.att1:Destroy() end)
	set[key] = nil
end

local function clearBeams(set)
	local keys = {}
	for key in pairs(set) do keys[#keys + 1] = key end
	for _, key in ipairs(keys) do destroyBeam(set, key) end
end

local function clearGuidelines()
	clearBeams(beams)
end

local function beamValid(data, root)
	return data
		and data.root == root
		and data.att0.Parent ~= nil
		and data.att1.Parent ~= nil
		and data.beam.Parent ~= nil
end

local function ensureBeam(set, key, root, targetPart, color)
	if beamValid(set[key], root) then return end
	if set[key] then destroyBeam(set, key) end
	local G = CONFIG.Guidelines
	local att0 = Instance.new("Attachment", root)
	local att1 = Instance.new("Attachment", targetPart)
	local beam = new("Beam", {
		Attachment0 = att0, Attachment1 = att1, Color = ColorSequence.new(color or G.Color),
		Width0 = G.Width, Width1 = G.Width, Texture = G.Texture, TextureMode = Enum.TextureMode.Wrap,
		TextureSpeed = G.TextureSpeed, TextureLength = G.TextureLength, FaceCamera = true,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
	}, root)
	set[key] = { beam = beam, att0 = att0, att1 = att1, root = root }
end

local function updateGuidelines(allItems)
	if not State.beamsEnabled then
		clearGuidelines()
		return
	end

	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		clearGuidelines()
		return
	end

	local G = CONFIG.Guidelines
	local valid = {}
	for _, item in ipairs(allItems) do
		if item.canAfford then
			local btn = item.instance
			valid[btn] = true
			local part = btn:IsA("BasePart") and btn or btn:FindFirstChildWhichIsA("BasePart")
			if part then
				if (root.Position - part.Position).Magnitude <= G.MaxDistance then
					ensureBeam(beams, btn, root, part)
				else
					destroyBeam(beams, btn)
				end
			end
		end
	end

	for btn in pairs(beams) do
		if not valid[btn] then destroyBeam(beams, btn) end
	end
end

-- Merchant locator & cards
local function getMerchantPart(shop)
	local merchant = shop:FindFirstChild("Merchant")
	if not merchant then return nil end
	if merchant:IsA("BasePart") then return merchant end
	if merchant:IsA("Model") then
		local inner = merchant:FindFirstChild("Merchant")
		if inner and inner:IsA("BasePart") then return inner end
		if inner and inner:IsA("Model") then
			return inner.PrimaryPart or inner:FindFirstChildWhichIsA("BasePart", true)
		end
		return merchant.PrimaryPart or merchant:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function updateMerchantLocator()
	if not State.merchantLocatorEnabled then
		clearBeams(merchantBeams)
		return
	end

	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bitsShops = Workspace:FindFirstChild("BitsShops")
	if not root or not bitsShops then
		clearBeams(merchantBeams)
		return
	end

	local M = CONFIG.MerchantLocator
	local current = {}
	for _, shop in ipairs(bitsShops:GetChildren()) do
		local part = getMerchantPart(shop)
		if part and part.Position.Y > M.MinY and (root.Position - part.Position).Magnitude <= M.MaxDistance then
			current[part] = true
			ensureBeam(merchantBeams, part, root, part, M.Color)
		end
	end

	for part in pairs(merchantBeams) do
		if not current[part] then destroyBeam(merchantBeams, part) end
	end
end

local function fireCardDetector(card)
	local detector = card:FindFirstChild("ClickDetector", true) or card:FindFirstChildOfClass("ClickDetector")
	if detector then
		detector.MaxActivationDistance = math.huge
		pcall(fireclickdetector, detector, 0, "mouseclick")
	end
end

local function readCardInfo(card)
	local bits = card:GetAttribute("Bits")
	if type(bits) ~= "number" then
		local surfaceGui = card:FindFirstChildWhichIsA("SurfaceGui", true)
		local bitsDisplay = surfaceGui and surfaceGui:FindFirstChild("bitsDisplay")
		bits = (bitsDisplay and parseNumber(bitsDisplay.Text)) or 0
	end

	local priceStr
	if localPlayer:GetAttribute("BitDiscount") then
		priceStr = card:GetAttribute("DiscountedPrice") or card:GetAttribute("FormattedPrice")
	else
		priceStr = card:GetAttribute("FormattedPrice") or card:GetAttribute("DiscountedPrice")
	end

	if not priceStr then
		local surfaceGui = card:FindFirstChildWhichIsA("SurfaceGui", true)
		local priceDisplay = surfaceGui and surfaceGui:FindFirstChild("priceDisplay")
		priceStr = priceDisplay and priceDisplay.Text or "N/A"
	end

	return bits, tostring(priceStr), parseNumber(priceStr)
end

local function highlightMerchants()
	local bitsShops = Workspace:FindFirstChild("BitsShops")
	local cardData = {}

	if bitsShops then
		for _, shop in ipairs(bitsShops:GetChildren()) do
			local cardsFolder = shop:FindFirstChild("Cards")
			if cardsFolder then
				for _, card in ipairs(cardsFolder:GetChildren()) do
					if card:IsA("Model") or card:IsA("BasePart") then
						local bits, priceStr = readCardInfo(card)
						cardData[#cardData + 1] = { card = card, bits = bits, priceStr = priceStr }
					end
				end
			end
		end
	end

	table.sort(cardData, function(a, b) return a.bits > b.bits end)

	if State.autoPickCardEnabled and #cardData >= CONFIG.AutoPickMinCards then
		local best = cardData[1]
		if best and best.bits > 0 and tick() - State.lastCardBuy >= CONFIG.Intervals.CardCooldown then
			State.lastCardBuy = tick()
			fireCardDetector(best.card)
		end
	end

	local current = {}
	for rank, data in ipairs(cardData) do
		local card = data.card
		current[card] = true

		local entry = merchantButtons[card]
		if not entry then
			local btn = new("TextButton", {
				Name = "CardEntry", Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.Panel,
				Font = CONFIG.Font, TextSize = 14, TextColor3 = C.On, TextStrokeTransparency = 1,
				TextWrapped = false, AutoButtonColor = false, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, MerchantsListFrame)
			addCorner(btn, 6)
			addStroke(btn, C.Stroke, 1)
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, btn)
			entry = { btn = btn, text = "" }
			merchantButtons[card] = entry

			btn.MouseButton1Click:Connect(function()
				fireCardDetector(card)
			end)
			btn.MouseEnter:Connect(function() btn.BackgroundColor3 = C.Header end)
			btn.MouseLeave:Connect(function() btn.BackgroundColor3 = C.Panel end)
		end

		local text = string.format("%s  |  %s  |  %s bits", card.Name, data.priceStr, formatNumber(data.bits))
		if entry.text ~= text then
			entry.text = text
			entry.btn.Text = text
		end
		entry.btn.LayoutOrder = rank
		entry.btn.Visible = true
	end

	for card, entry in pairs(merchantButtons) do
		if not current[card] then
			entry.btn:Destroy()
			merchantButtons[card] = nil
		end
	end
end

-- Rebirth
local function setStatus(text)
	if State.status ~= text then
		State.status = text
		setText(StatusLabel, "Status: " .. text)
	end
end

local function getObeliskClick()
	local obelisk = Workspace:FindFirstChild("Obelisk")
	local button = obelisk and obelisk:FindFirstChild("RebirthButton")
	return button and button:FindFirstChild("Click")
end

local function clickRebirthButton()
	local playerGui = getPlayerGui()
	local main = playerGui and playerGui:FindFirstChild("Main")
	local frame = main and main:FindFirstChild("Rebirth")
	if not frame or not frame.Visible then return false end

	local button = frame:FindFirstChild("Rebirth", true)
	if not (button and button:IsA("GuiButton") and button.Visible) then return false end

	local pos, size = button.AbsolutePosition, button.AbsoluteSize
	local inset = GuiService:GetGuiInset()
	local x = pos.X + size.X / 2
	local y = pos.Y + size.Y / 2 + inset.Y
	VirtualInputManager:SendMouseMoveEvent(x, y, game)
	task.wait(0.02)
	VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
	task.wait(0.05)
	VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	return true
end

-- Manual: press the physical Rebirth button; the game opens its own GUI.
local function openRebirthGui()
	if State.isRebirthing then return end

	local playerGui = getPlayerGui()
	local main = playerGui and playerGui:FindFirstChild("Main")
	local frame = main and main:FindFirstChild("Rebirth")
	if frame and frame.Visible then
		setStatus("Rebirth GUI already open")
		return
	end

	local clickPart = getObeliskClick()
	local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")
	if not detector then
		setStatus("Rebirth button not found")
		return
	end

	detector.MaxActivationDistance = math.huge
	pcall(fireclickdetector, detector, 0, "mouseclick")
	setStatus("Rebirth GUI opened")
end

-- Auto: press the physical button, wait for the game's GUI, then press REBIRTH.
local function triggerRebirth()
	if State.isRebirthing then return end
	if tick() - State.lastRebirthAttempt < CONFIG.Rebirth.RetryCooldown then return end
	State.lastRebirthAttempt = tick()
	State.isRebirthing = true
	setStatus("Rebirthing...")

	task.spawn(function()
		local ok, err = pcall(function()
			local clickPart = getObeliskClick()
			local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")
			if not detector then
				State.autoRebirthArmed = false
				return
			end

			local playerGui = getPlayerGui()
			local main = playerGui and playerGui:FindFirstChild("Main")
			local frame = main and main:FindFirstChild("Rebirth")
			local alreadyOpen = frame ~= nil and frame.Visible

			local before = getRebirthCount()
			if not alreadyOpen then
				detector.MaxActivationDistance = math.huge
				pcall(fireclickdetector, detector, 0, "mouseclick")
			end

			-- Wait for the game's Rebirth GUI (or an immediate rebirth).
			local guiDeadline = tick() + 4
			local guiShown = alreadyOpen
			local rebirthStarted = false
			while not guiShown and tick() < guiDeadline do
				local now = getRebirthCount()
				if before ~= nil and now ~= nil and now > before then
					rebirthStarted = true
					break
				end
				local pg = getPlayerGui()
				local m = pg and pg:FindFirstChild("Main")
				local f = m and m:FindFirstChild("Rebirth")
				if f and f.Visible then
					guiShown = true
					break
				end
				task.wait(0.1)
			end

			if rebirthStarted then
				setStatus("Rebirth done")
				return
			end

			if not guiShown then
				setStatus("Rebirth GUI did not open")
				State.autoRebirthArmed = false
				return
			end

			task.wait(CONFIG.Rebirth.ConfirmDelay)
			if not clickRebirthButton() then
				setStatus("Rebirth button not found")
				State.autoRebirthArmed = false
				if frame then frame.Visible = false end
				return
			end

			local deadline = tick() + 6
			local confirmed = false
			while tick() < deadline do
				local now = getRebirthCount()
				if before ~= nil and now ~= nil and now > before then
					confirmed = true
					break
				end
				task.wait(0.2)
			end

			if confirmed then
				setStatus("Rebirth done")
			else
				setStatus("Rebirth click sent")
				State.autoRebirthArmed = false
				if frame then frame.Visible = false end
			end
		end)

		if not ok then
			setStatus("Rebirth error: " .. tostring(err):sub(1, 50))
			State.autoRebirthArmed = false
		end

		task.wait(CONFIG.Rebirth.Cooldown)
		State.isRebirthing = false
	end)
end

ManualRebirthBtn.MouseButton1Click:Connect(openRebirthGui)

LoadTelekinesisBtn.MouseButton1Click:Connect(function()
	if State.isLoadingTelekinesis then return end
	State.isLoadingTelekinesis = true
	LoadTelekinesisBtn.Text = "Loading..."
	LoadTelekinesisBtn.BackgroundColor3 = C.Accent
	setStatus("Loading Telekinesis...")

	task.spawn(function()
		local ok, err = pcall(function()
			local source = game:HttpGet("https://raw.githubusercontent.com/lpot1/poop-script/refs/heads/main/Telekinesis.lua")
			local chunk, compileErr = loadstring(source)
			if not chunk then error(compileErr or "loadstring failed") end
			chunk()
		end)

		if ok then
			LoadTelekinesisBtn.Text = "Telekinesis"
			LoadTelekinesisBtn.BackgroundColor3 = C.Panel
			setStatus("Telekinesis ready")
		else
			LoadTelekinesisBtn.Text = "Failed"
			LoadTelekinesisBtn.BackgroundColor3 = C.Danger
			setStatus("Telekinesis error: " .. tostring(err):sub(1, 60))
		end
		State.isLoadingTelekinesis = false
	end)
end)

InventoryToggleBtn.MouseButton1Click:Connect(function()
	State.inventoryEnabled = not State.inventoryEnabled
	local on = State.inventoryEnabled
	InventoryToggleBtn.Text = "Inventory: " .. (on and "ON" or "OFF")
	InventoryToggleBtn.BackgroundColor3 = on and C.On or C.Panel

	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, on)
	end)
	if not ok then
		setStatus("Inventory error: " .. tostring(err):sub(1, 50))
	end
end)

-- Jobs
local function scanButtons(tycoon, cash)
	local all, affordable = {}, {}
	local buttons = tycoon and tycoon:FindFirstChild("Buttons")
	if not buttons then return all, affordable end

	for _, btn in ipairs(buttons:GetChildren()) do
		local price, priceStr, name = getButtonDetails(btn)
		if price then
			local item = {
				instance = btn,
				name = name,
				price = price,
				priceStr = priceStr,
				canAfford = cash >= price,
			}
			all[#all + 1] = item
			if item.canAfford then affordable[#affordable + 1] = item end
		end
	end

	table.sort(affordable, function(a, b) return a.price < b.price end)
	return all, affordable
end

local function performRemoteBuy(tycoon, affordable)
	if State.isBuying or State.isRebirthing then return end
	State.isBuying = true

	task.spawn(function()
		pcall(function()
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			for _ = 1, 4 do
				if not running or not root or not root.Parent then break end
				local bought = false
				for _, item in ipairs(affordable) do
					if isButtonActive(item.instance) then
						pcall(firetouchinterest, root, item.instance, 1)
						task.wait(0.015)
						pcall(firetouchinterest, root, item.instance, 0)
						bought = true
					end
				end
				if not bought then break end

				task.wait(0.12)
				if not running then break end
				local cash = getPlayerCash(true)
				local _, nextAffordable = scanButtons(tycoon, cash)
				affordable = nextAffordable
				if #affordable == 0 then break end
			end
		end)

		State.isBuying = false
	end)
end

local lastAutoBuy = 0
local function updateShop()
	local cash, cashStr = getPlayerCash()
	local tycoon = getMyTycoon()
	local all, affordable = scanButtons(tycoon, cash)

	if State.autoBuyEnabled and not State.isRebirthing and #affordable > 0 then
		local mode = CONFIG.BuyModes[State.buyModeIndex].id
		if mode == "Remote" then
			performRemoteBuy(tycoon, affordable)
		elseif tick() - lastAutoBuy >= CONFIG.Intervals.AutoBuyCooldown then
			local target = affordable[1]
			if target and isButtonActive(target.instance) then
				lastAutoBuy = tick()
				moveToTarget(target.instance)
			end
		end
	end

	updateGuidelines(all)
	return cashStr
end

local lastStats = ""
local function updateStats()
	local _, cashStr = getPlayerCash()
	local plot = getMyPlot()
	local essenceCapped = isEssenceCapped()
	local progressText = getProgressText()
	local percent = parseProgress(progressText)

	local statsText = string.format("Stats:\nCash: %s\nPlot: %s\nEssence Capped: %s\nBit Generator: %s",
		cashStr, plot and plot.Name or "?", essenceCapped and "True" or "False", getBitsGeneratorTime())
	if statsText ~= lastStats then
		lastStats = statsText
		StatsLabel.Text = statsText
	end

	setText(RebirthLabel, "Progress: " .. (progressText ~= "" and progressText or "N/A"))
	setText(CappedStatusLabel, "Capped: " .. (essenceCapped and "TRUE" or "FALSE"))
	setText(PercentLabel, string.format("%.1f%%", percent))
	setText(StatusLabel, "Status: " .. State.status)

	ProgressGradient.Color = percent >= 99
		and ColorSequence.new(C.On)
		or ColorSequence.new(Color3.fromRGB(255, 0, 0):Lerp(C.On, percent / 100))

	local targetSize = UDim2.new(percent / 100, 0, 1, 0)
	if ProgressBarFill.Size.X.Scale ~= targetSize.X.Scale then
		ProgressBarFill:TweenSize(targetSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
	end
end

local function updateRebirth()
	if not State.autoRebirthEnabled or State.isRebirthing then
		State.autoRebirthArmed = false
		return
	end

	-- Essence Cap ON  -> only when essence is capped AND the game is ready to rebirth.
	-- Essence Cap OFF -> normal rebirth readiness only.
	local ready = parseProgress(getProgressText()) >= 100 or hasRebirthNotification()
	local should
	if State.essenceCapEnabled then
		should = ready and isEssenceCapped()
	else
		should = ready
	end

	if should then
		if not State.autoRebirthArmed and tick() - State.lastRebirthAttempt >= CONFIG.Rebirth.RetryCooldown then
			State.autoRebirthArmed = true
			triggerRebirth()
		end
	else
		State.autoRebirthArmed = false
	end
end

-- Main scheduler
local jobs = {
	{ interval = CONFIG.Intervals.Shop,     last = 0, fn = updateShop },
	{ interval = CONFIG.Intervals.Stats,    last = 0, fn = updateStats },
	{ interval = CONFIG.Intervals.Merchant, last = 0, fn = highlightMerchants },
	{ interval = CONFIG.Intervals.Locator,  last = 0, fn = updateMerchantLocator },
	{ interval = CONFIG.Intervals.Rebirth,  last = 0, fn = updateRebirth },
}

track(RunService.Heartbeat:Connect(function()
	if not running then return end
	local now = tick()
	for _, job in ipairs(jobs) do
		if now - job.last >= job.interval then
			job.last = now
			local ok, err = pcall(job.fn)
			if not ok then
				setStatus("Error: " .. tostring(err):sub(1, 60))
			end
		end
	end
end))

-- Anti-AFK
track(localPlayer.Idled:Connect(function()
	if State.antiAfkEnabled then
		VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
		task.wait(1)
		VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
	end
end))

-- Cleanup
env.TycoonManagerCleanup = function()
	running = false
	cancelPath()

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)

	for _, connection in ipairs(connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(connections)

	for _, hook in ipairs(cleanupHooks) do
		pcall(hook)
	end
	table.clear(cleanupHooks)

	pcall(clearGuidelines)
	pcall(clearBeams, merchantBeams)

	for _, entry in pairs(merchantButtons) do
		pcall(function() entry.btn:Destroy() end)
	end
	table.clear(merchantButtons)
	table.clear(buttonCache)

	ScreenGui:Destroy()
	env.TycoonManagerCleanup = nil
end
