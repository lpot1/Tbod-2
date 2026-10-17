if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Services
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local CoreGui             = game:GetService("CoreGui")
local PathfindingService  = game:GetService("PathfindingService")
local GuiService          = game:GetService("GuiService")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")

local Workspace           = game:GetService("Workspace")
local VirtualUser         = game:GetService("VirtualUser")

local localPlayer = Players.LocalPlayer

-- Configuration
local CONFIG = {
	GuiName = "TycoonManagerGui",
	Font    = Enum.Font.GothamBold,

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
		PanelPadding    = 5,
	},

	Intervals = {
		MerchantUpdate  = 0.1,
		MerchantGate    = 1,
		ShopUpdate      = 0.1,
		MonitorPoll     = 1.2,
		TextPoll        = 1.5,
		AutoBuyCooldown = 0.125,
		MerchantLocator = 0.1,
	},

	Rebirth = {
		EssencePhrase    = "your essence is capped",
		EssenceScanCache = 0.1,
		ConfirmDelay     = 2,
		Cooldown         = 4,
		TeleportDelay    = 3,
		PlotSpawnOffset  = 6,
		DefaultMode      = 2,
		Modes = {
			{ id = "Any",         text = "Rebirth Trigger: Both" },
			{ id = "Essence",     text = "Essence Cap" },
			{ id = "RebirthNoti", text = "Progress 100%" },
		},
		ObeliskPath       = { "Obelisk", "RebirthButton", "Click" },
		ManualTitle       = "Manual Rebirth",
		ManualFailText    = "Conditions for rebirth have not been met.",
		ManualFailSeconds = 3,
	},

	TrackedTexts = {
		EssenceCappedTemp   = { "Players", localPlayer.Name, "PlayerGui", "System", "Notifications", "NotiHolder", "EssenceCappedTemp", "Pos", "Text" },
		RebirthNotification = { "Players", localPlayer.Name, "PlayerGui", "System", "Notifications", "NotiHolder", "RebirthNotification", "Pos", "Text" },
	},

	Suffixes = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18, SX = 1e21, SP = 1e24, O = 1e27, N = 1e30, D = 1e33 },

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
}

local C = CONFIG.Colors

-- Shared state & cleanup
local env = (getgenv and getgenv()) or _G

if env.TycoonManagerCleanup then
	pcall(env.TycoonManagerCleanup)
end

local oldGui = CoreGui:FindFirstChild(CONFIG.GuiName)
if oldGui then
	oldGui:Destroy()
end

local running = true
local connections = {}
local cleanupHooks = {}

local function track(connection)
	connections[#connections + 1] = connection
	return connection
end

-- Everything default to OFF
local State = {
	beamsEnabled           = false,
	autoBuyEnabled         = false,
	autoRebirthEnabled     = false,
	autoPickCardEnabled    = false,
	merchantLocatorEnabled = false,
	antiAfkEnabled         = false,
	usePathfind            = false,
	rebirthModeIndex       = CONFIG.Rebirth.DefaultMode,
	isRebirthing           = false,
	isTeleportingPlot      = false,
	isMinimized            = false,
	activeTab              = "Stats",
}

local trackedTexts = {}

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

local function resolvePath(pathParts)
	local current = game
	for _, name in ipairs(pathParts) do
		current = current:FindFirstChild(name)
		if not current then return nil end
	end
	return current
end

local function parseSuffixValue(str)
	if not str then return 0 end
	str = string.upper(string.gsub(str, "[%,%$%s]", ""))
	local num, suffix = string.match(str, "([%d%.]+)(%a*)")
	num = tonumber(num) or 0
	local mult = suffix and CONFIG.Suffixes[suffix]
	return mult and num * mult or num
end

local FORMAT_STEPS = { { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
local function formatNumber(num)
	for _, step in ipairs(FORMAT_STEPS) do
		if num >= step[1] then
			return string.format("%.2f%s", num / step[1], step[2])
		end
	end
	return string.format("%.0f", num)
end

local function parsePrice(str)
	if not str or str == "" then return nil end
	local cleanStr = str:gsub("[$,]", ""):lower():gsub("%s+", "")
	if cleanStr:find("free") then return 0 end
	local num = tonumber(cleanStr:match("[%d%.]+"))
	if not num then return nil end
	-- Check longer suffixes first to avoid false-positive (qi before q, qa before q, etc.)
	if     cleanStr:find("qi$") or cleanStr:find("qi[^a-z]") then num = num * 1e18
	elseif cleanStr:find("qa$") or cleanStr:find("qa[^a-z]") then num = num * 1e15
	elseif cleanStr:find("sp$") or cleanStr:find("sp[^a-z]") then num = num * 1e24
	elseif cleanStr:find("sx$") or cleanStr:find("sx[^a-z]") then num = num * 1e21
	elseif cleanStr:find("t$")  or cleanStr:find("t[^a-z]")  then num = num * 1e12
	elseif cleanStr:find("b$")  or cleanStr:find("b[^a-z]")  then num = num * 1e9
	elseif cleanStr:find("m$")  or cleanStr:find("m[^a-z]")  then num = num * 1e6
	elseif cleanStr:find("k$")  or cleanStr:find("k[^a-z]")  then num = num * 1e3
	end
	return num
end

local function parseProgress(text)
	if string.find(string.upper(text), "COMPLETE") then return 100 end

	local currentStr, maxStr = string.match(text, "([%d%,%.%a]+)%s*/%s*([%d%,%.%a]+)")
	if currentStr and maxStr then
		local current = parseSuffixValue(currentStr)
		local max = parseSuffixValue(maxStr)
		local leaderstats = localPlayer:FindFirstChild("leaderstats")
		local cashVal = leaderstats and (leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money"))
		if cashVal then
			local rawCash = tonumber(cashVal.Value) or 0
			if rawCash > current then current = rawCash end
		end
		if max > 0 then return math.clamp((current / max) * 100, 0, 100) end
	end

	local rawPercent = string.match(text, "(%d+%.?%d*)%%")
	if rawPercent then return math.clamp(tonumber(rawPercent) or 0, 0, 100) end
	return 0
end

local function monitorText(key, pathParts)
	task.spawn(function()
		local activeConnection
		local lastObj = nil
		while running do
			local obj = resolvePath(pathParts)
			if obj then
				if obj ~= lastObj then
					if activeConnection then
						activeConnection:Disconnect()
						activeConnection = nil
					end
					lastObj = obj
				end

				local actualText
				if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
					actualText = obj.Text
				elseif obj:IsA("StringValue") then
					actualText = obj.Value
				else
					pcall(function() actualText = obj.Text end)
				end

				if actualText ~= nil then
					trackedTexts[key] = tostring(actualText)
					if not activeConnection then
						local prop = obj:IsA("StringValue") and "Value" or "Text"
						activeConnection = obj:GetPropertyChangedSignal(prop):Connect(function()
							trackedTexts[key] = tostring(obj[prop])
						end)
					end
				else
					trackedTexts[key] = nil
				end
			else
				if activeConnection then
					activeConnection:Disconnect()
					activeConnection = nil
				end
				lastObj = nil
				trackedTexts[key] = nil
			end
			task.wait(CONFIG.Intervals.TextPoll)
		end
		if activeConnection then activeConnection:Disconnect() end
	end)
end

for key, path in pairs(CONFIG.TrackedTexts) do
	monitorText(key, path)
end

-- GUI Setup
local ScreenGui = new("ScreenGui", { Name = CONFIG.GuiName })
ScreenGui.Parent = CoreGui

local W = CONFIG.Window

local MainFrame = new("Frame", {
	Name = "MainFrame", BackgroundColor3 = C.Background, Position = W.Position,
	Size = W.Size, ClipsDescendants = true, Active = true,
}, ScreenGui)
addCorner(MainFrame, 8)
addStroke(MainFrame, C.Stroke, 1.5)

local Header = new("Frame", { Name = "Header", BackgroundColor3 = C.Header, Size = UDim2.new(1, 0, 0, W.HeaderHeight) }, MainFrame)
addCorner(Header, 8)

local Title = new("TextLabel", {
	Name = "Title", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -70, 1, 0),
	Font = CONFIG.Font, RichText = true, Text = "TBOD^2 Manager [Stats & Auto Farm]",
	TextColor3 = C.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
}, Header)

local MinimizeBtn = new("TextButton", {
	Name = "MinimizeBtn", BackgroundTransparency = 1, Position = UDim2.new(1, -60, 0, 0), Size = UDim2.new(0, 30, 1, 0),
	Font = CONFIG.Font, Text = "v", TextColor3 = C.Text, TextSize = 13,
}, Header)

local CloseBtn = new("TextButton", {
	Name = "CloseBtn", BackgroundTransparency = 1, Position = UDim2.new(1, -30, 0, 0), Size = UDim2.new(0, 30, 1, 0),
	Font = CONFIG.Font, Text = "X", TextColor3 = C.Danger, TextSize = 13,
}, Header)

CloseBtn.MouseButton1Click:Connect(function()
	if env.TycoonManagerCleanup then
		env.TycoonManagerCleanup()
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
		Font = CONFIG.Font, Text = text, TextColor3 = C.Text, TextSize = 12,
	}, parent)
	addCorner(btn, 6)
	return btn
end

local function makeListPanel(name, height, scrolling)
	local props = {
		Name = name, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, W.PanelY),
		Size = UDim2.new(1, -20, 0, height), Visible = false,
	}
	if scrolling then
		props.Size = UDim2.new(1, -20, 1, -(W.PanelY + W.PanelPadding))
		props.BorderSizePixel = 0
		props.CanvasSize = UDim2.new(0, 0, 0, 0)
		props.ScrollBarThickness = 4
		props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end
	local panel = new(scrolling and "ScrollingFrame" or "Frame", props, MainFrame)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, panel)
	return panel
end

-- Stats Panel
local PanelStats = new("Frame", {
	Name = "PanelStats", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, W.PanelY),
	Size = UDim2.new(1, 0, 0, 170), Visible = true,
}, MainFrame)

local StatsLabel = new("TextLabel", {
	Name = "StatsLabel", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 0, 45),
	Font = CONFIG.Font, Text = "Stats:\nCash: $0\nPlot: Searching...", TextColor3 = C.On, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, PanelStats)

local RebirthContentFrame = new("Frame", {
	Name = "RebirthContentFrame", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 115),
}, PanelStats)

local function statLabel(name, y, height, text, color, size)
	return new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y), Size = UDim2.new(1, -20, 0, height),
		Font = CONFIG.Font, Text = text, TextColor3 = color, TextSize = size, TextWrapped = size == 12,
	}, RebirthContentFrame)
end

local PercentLabel      = statLabel("PercentLabel", 2, 18, "0%", C.Text, 14)
local RebirthLabel      = statLabel("RebirthLabel", 36, 16, "Progress: Loading...", C.TextMuted, 12)
local CappedStatusLabel = statLabel("CappedStatusLabel", 54, 16, "Capped: Loading...", C.TextMuted, 12)
local NumbersLabel      = statLabel("NumbersLabel", 72, 32, "Numbers: Loading...", C.TextMuted, 12)

local ProgressBarBg = new("Frame", {
	Name = "ProgressBarBg", BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 10, 0, 22),
	Size = UDim2.new(1, -20, 0, 10), ClipsDescendants = true,
}, RebirthContentFrame)
addCorner(ProgressBarBg, 6)

local ProgressBarFill = new("Frame", {
	Name = "ProgressBarFill", BackgroundColor3 = C.Text, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0),
}, ProgressBarBg)
addCorner(ProgressBarFill, 6)

local UIGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 200, 120)),
	}),
}, ProgressBarFill)

local MerchantsListFrame = new("Frame", {
	Name = "MerchantsListFrame", BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0, 10, 0, 155),
}, PanelStats)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, MerchantsListFrame)
local merchantListButtons = {}

-- Auto Farm Panel
local PanelAutoFarm = makeListPanel("PanelAutoFarm", 200, true)
local AutoBuyToggleBtn     = makeButton(PanelAutoFarm, "AutoBuyToggleBtn", "Auto Buy: OFF", C.Panel)
local MoveModeBtn          = makeButton(PanelAutoFarm, "MoveModeBtn", "Mode: Teleport", C.Panel)
local AutoRebirthToggleBtn = makeButton(PanelAutoFarm, "AutoRebirthToggleBtn", "Auto Rebirth: OFF", C.Panel)
local RebirthModeBtn       = makeButton(PanelAutoFarm, "RebirthModeBtn", CONFIG.Rebirth.Modes[State.rebirthModeIndex].text, C.Panel)
local BeamToggleBtn        = makeButton(PanelAutoFarm, "BeamToggleBtn", "Guidelines: OFF", C.Panel)
local MerchantLocatorBtn   = makeButton(PanelAutoFarm, "MerchantLocatorBtn", "Merchant Locator: OFF", C.Panel)
local AutoPickToggleBtn    = makeButton(PanelAutoFarm, "AutoPickToggleBtn", "Auto Bits: OFF", C.Panel)
local AntiAfkToggleBtn     = makeButton(PanelAutoFarm, "AntiAfkToggleBtn", "Anti-AFK: OFF", C.Panel)
local ManualRebirthBtn     = makeButton(PanelAutoFarm, "ManualRebirthBtn", "Manual Rebirth", C.Panel)

-- Tab management
local panels = { Stats = PanelStats, ["Auto Farm"] = PanelAutoFarm }
local tabOrder = { "Stats", "Auto Farm" }
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
	local btn = new("TextButton", { Name = name .. "Tab", Size = UDim2.new(0, 100, 1, 0), Font = CONFIG.Font, Text = name, TextSize = 12 }, CategoryBar)
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
bindToggle(AutoPickToggleBtn, "Auto Bits", "autoPickCardEnabled", C.On)
bindToggle(MerchantLocatorBtn, "Merchant Locator", "merchantLocatorEnabled", C.On)
bindToggle(AntiAfkToggleBtn, "Anti-AFK", "antiAfkEnabled", C.On)

MoveModeBtn.MouseButton1Click:Connect(function()
	State.usePathfind = not State.usePathfind
	MoveModeBtn.BackgroundColor3 = State.usePathfind and C.Accent or C.Panel
	MoveModeBtn.Text = State.usePathfind and "Mode: Pathfind" or "Mode: Teleport"
end)

RebirthModeBtn.MouseButton1Click:Connect(function()
	State.rebirthModeIndex = State.rebirthModeIndex % #CONFIG.Rebirth.Modes + 1
	RebirthModeBtn.Text = CONFIG.Rebirth.Modes[State.rebirthModeIndex].text
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

local function getMyPlot()
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return "None" end
	local myName, myDisplay = string.lower(localPlayer.Name), string.lower(localPlayer.DisplayName)
	for _, plot in ipairs(plots:GetChildren()) do
		local sign = plot:FindFirstChild("SignPlace")
		local nameLabel = sign and sign:FindFirstChild("DefaultSign")
		nameLabel = nameLabel and nameLabel:FindFirstChild("Screen")
		nameLabel = nameLabel and nameLabel:FindFirstChild("SurfaceGui")
		nameLabel = nameLabel and nameLabel:FindFirstChild("NameLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			local text = string.lower(nameLabel.Text)
			if text == myName or text == myDisplay then return plot.Name end
		end
	end
	return "None"
end

local function getMyTycoon()
	local tycoons = Workspace:FindFirstChild("Tycoons")
	if not tycoons then return nil end

	for _, tycoon in ipairs(tycoons:GetChildren()) do
		local ownerId = tycoon:GetAttribute("OwnerId")
		if ownerId == localPlayer.UserId then
			return tycoon
		end
	end

	local myPlotName = getMyPlot()
	if myPlotName == "None" then return nil end
	local plots = Workspace:FindFirstChild("Plots")
	local plotObj = plots and plots:FindFirstChild(myPlotName)
	if not plotObj then return nil end

	local function positionOf(obj)
		if obj:IsA("Model") then return obj:GetPivot().Position end
		local part = obj:FindFirstChildWhichIsA("BasePart")
		return part and part.Position
	end

	local plotPos = positionOf(plotObj)
	if not plotPos then return nil end

	local closest, shortest = nil, math.huge
	for _, tycoon in ipairs(tycoons:GetChildren()) do
		if tycoon:FindFirstChild("Buttons") then
			local pivot = positionOf(tycoon)
			if pivot then
				local dist = (plotPos - pivot).Magnitude
				if dist < shortest then
					shortest, closest = dist, tycoon
				end
			end
		end
	end
	return closest
end

local function getPlotSpawnCFrame(plotObj)
	local offset = Vector3.new(0, CONFIG.Rebirth.PlotSpawnOffset, 0)
	local spawnPad = plotObj:FindFirstChild("Spawn") or plotObj:FindFirstChild("SpawnLocation") or plotObj:FindFirstChild("ClaimPart")
	if spawnPad and spawnPad:IsA("BasePart") then return spawnPad.CFrame + offset end
	return plotObj:GetPivot() + offset
end

local essenceCache = { time = 0, value = false }
local function isEssenceCapped()
	local now = tick()
	if now - essenceCache.time < CONFIG.Rebirth.EssenceScanCache then return essenceCache.value end
	local phrase = CONFIG.Rebirth.EssencePhrase
	local tracked = trackedTexts["EssenceCappedTemp"]
	local capped = tracked ~= nil and string.find(string.lower(tracked), phrase, 1, true) ~= nil
	if not capped then
		local pGui = getPlayerGui()
		if pGui then
			for _, v in ipairs(pGui:GetDescendants()) do
				if (v:IsA("TextLabel") or v:IsA("TextButton")) and v.Visible and string.find(string.lower(tostring(v.Text or "")), phrase, 1, true) then
					capped = true
					break
				end
			end
		end
	end
	essenceCache.time, essenceCache.value = now, capped
	return capped
end

local function getPlayerCash()
	local playerGui = getPlayerGui()
	if playerGui then
		local system = playerGui:FindFirstChild("System")
		local main = system and system:FindFirstChild("Main")
		local cashFrame = main and main:FindFirstChild("Cash")
		local cashTextLabel = cashFrame and cashFrame:FindFirstChild("CashText")
		if cashTextLabel and cashTextLabel:IsA("TextLabel") and cashTextLabel.Text ~= "" then
			local parsed = parsePrice(cashTextLabel.Text)
			if parsed then return parsed, cashTextLabel.Text end
		end

		local playerList = system and system:FindFirstChild("PlayerList")
		local holder = playerList and playerList:FindFirstChild("Holder")
		local myFrame = holder and holder:FindFirstChild(localPlayer.Name)
		if myFrame then
			for _, desc in ipairs(myFrame:GetDescendants()) do
				if desc:IsA("TextLabel") and desc.Text ~= "" then
					local parsed = parsePrice(desc.Text)
					if parsed and parsed > 0 then return parsed, desc.Text end
				end
			end
		end
	end

	local leaderstats = localPlayer:FindFirstChild("leaderstats") or localPlayer:FindFirstChild("stats")
	if leaderstats then
		local cashObj = leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Coins")
		if cashObj and cashObj:IsA("ValueBase") then
			local val = tonumber(cashObj.Value) or 0
			return val, "$" .. formatNumber(val)
		end
	end
	return 0, "$0"
end

local function isButtonActive(btn)
	if not btn or not btn.Parent then return false end
	if btn:IsA("BasePart") and (btn.Transparency >= 1 or not btn.CanCollide) then return false end
	local head = btn:FindFirstChild("Head") or btn:FindFirstChild("Part") or btn:FindFirstChildWhichIsA("BasePart")
	if head and (head.Transparency >= 1 or not head.CanCollide) then return false end
	local billboard = btn:FindFirstChildWhichIsA("BillboardGui", true)
	if billboard and not billboard.Enabled then return false end
	return true
end

local function getTargetPosition(target)
	if target:IsA("BasePart") then return target.Position end
	if target:IsA("Model") then
		local head = target:FindFirstChild("Head") or target:FindFirstChild("Part") or target:FindFirstChildWhichIsA("BasePart")
		return head and head.Position or target:GetPivot().Position
	end
	return nil
end

local function getButtonDetails(btn)
	if not btn or not isButtonActive(btn) then return nil, nil, nil end
	local priceNum, priceStr, buttonName = nil, nil, btn.Name
	local nameDisplay = btn:FindFirstChild("NameDisplay", true)
	if nameDisplay then
		local textLabel = nameDisplay:FindFirstChildWhichIsA("TextLabel", true) or (nameDisplay:IsA("TextLabel") and nameDisplay)
		if textLabel and textLabel.Text ~= "" and textLabel.Visible then buttonName = textLabel.Text end
	end
	local priceDisplay = btn:FindFirstChild("PriceDisplay", true)
	if priceDisplay then
		local textLabel = priceDisplay:FindFirstChildWhichIsA("TextLabel", true) or (priceDisplay:IsA("TextLabel") and priceDisplay)
		if textLabel and textLabel.Text ~= "" and textLabel.Visible then
			priceNum = parsePrice(textLabel.Text)
			priceStr = textLabel.Text
		end
	end
	if not priceNum then
		for _, desc in ipairs(btn:GetDescendants()) do
			if desc:IsA("TextLabel") and desc.Text ~= "" and desc.Visible then
				local parsed = parsePrice(desc.Text)
				if parsed then priceNum = parsed; priceStr = desc.Text; break end
			end
		end
	end
	if not priceNum and buttonName:lower():find("free") then priceNum, priceStr = 0, "Free" end
	return priceNum, priceStr, buttonName
end

-- Movement & Auto Buy
local activePathTask

local function cancelPath()
	if activePathTask then
		task.cancel(activePathTask)
		activePathTask = nil
	end
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

	if not State.usePathfind then
		pcall(function()
			root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
		end)
		return
	end

	local P = CONFIG.Pathfinding
	activePathTask = task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = P.AgentRadius, AgentHeight = P.AgentHeight, AgentCanJump = P.AgentCanJump,
			AgentCanClimb = P.AgentCanClimb, WaypointSpacing = P.WaypointSpacing,
			Costs = { Water = P.WaterCost, Danger = math.huge },
		})
		local startedAt, lastJump = tick(), 0
		local function aborted()
			return not root.Parent or humanoid.Health <= 0 or not target.Parent or not isButtonActive(target)
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

		while true do
			if aborted() or fallbackTeleport() then return end
			targetPos = getTargetPosition(target)
			if not targetPos then return end
			jumpIfHigher()
			if (root.Position - targetPos).Magnitude <= P.ReachDistance then
				humanoid:MoveTo(targetPos)
				task.wait(0.35)
				continue
			end
			local ok = pcall(function() path:ComputeAsync(root.Position, targetPos) end)
			if not ok or path.Status ~= Enum.PathStatus.Success then
				humanoid:MoveTo(targetPos)
				task.wait(0.45)
				continue
			end
			local waypoints = path:GetWaypoints()
			if #waypoints < 2 then
				humanoid:MoveTo(targetPos)
				task.wait(0.3)
				continue
			end
			for i = 2, #waypoints do
				if aborted() or fallbackTeleport() then return end
				local wpPos = waypoints[i].Position
				targetPos = getTargetPosition(target)
				if not targetPos then return end
				if (root.Position - targetPos).Magnitude <= P.ReachDistance then break end
				humanoid:MoveTo(wpPos)
				local startTime = tick()
				local stuckCheck, stuckTimer = root.Position, 0
				while (root.Position - wpPos).Magnitude > P.WaypointReach do
					if aborted() or fallbackTeleport() then return end
					targetPos = getTargetPosition(target)
					if targetPos and (root.Position - targetPos).Magnitude <= P.ReachDistance then break end
					if tick() - startTime > P.WaypointTimeout then break end
					jumpIfHigher()
					if (root.Position - stuckCheck).Magnitude < P.StuckDistance then
						stuckTimer += 0.08
						if stuckTimer > P.StuckTime then
							local away = root.Position - wpPos
							if away.Magnitude < 0.1 then away = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)) end
							root.CFrame = root.CFrame + (away.Unit * P.StuckPush) + Vector3.new(0, P.StuckLift, 0)
							stuckTimer = 0
							stuckCheck = root.Position
							task.wait(0.1)
						end
					else
						stuckTimer = 0
						stuckCheck = root.Position
					end
					task.wait(0.07)
				end
			end
			task.wait(0.12)
		end
	end)
end

-- Guidelines & Beams
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

local function ensureBeam(set, key, root, targetPart, color)
	if set[key] then return end
	local G = CONFIG.Guidelines
	local att0 = Instance.new("Attachment", root)
	local att1 = Instance.new("Attachment", targetPart)
	local beam = new("Beam", {
		Attachment0 = att0, Attachment1 = att1, Color = ColorSequence.new(color or G.Color),
		Width0 = G.Width, Width1 = G.Width, Texture = G.Texture, TextureMode = Enum.TextureMode.Wrap,
		TextureSpeed = G.TextureSpeed, TextureLength = G.TextureLength, FaceCamera = true,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.1) }),
	}, root)
	set[key] = { beam = beam, att0 = att0, att1 = att1 }
end

local function updateGuidelines(validButtons)
	if not State.beamsEnabled then return clearGuidelines() end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return clearGuidelines() end
	local G = CONFIG.Guidelines
	local currentValid = {}
	for _, item in ipairs(validButtons) do
		if item.canAfford then
			local btn = item.instance
			currentValid[btn] = true
			local targetPart = btn:IsA("BasePart") and btn
				or (btn:IsA("Model") and (btn:FindFirstChild("Head") or btn:FindFirstChild("Part") or btn:FindFirstChildWhichIsA("BasePart") or btn.PrimaryPart))
			if targetPart then
				if (root.Position - targetPart.Position).Magnitude <= G.MaxDistance then
					ensureBeam(beams, btn, root, targetPart)
				else
					destroyBeam(beams, btn)
				end
			end
		end
	end
	for btn in pairs(beams) do
		if not currentValid[btn] then destroyBeam(beams, btn) end
	end
end

-- Merchant Locator & Auto Bits
local function getMerchantPart(shop)
	local merchant = shop:FindFirstChild("Merchant")
	if not merchant then return nil end
	if merchant:IsA("BasePart") then return merchant end
	if merchant:IsA("Model") then
		local inner = merchant:FindFirstChild("Merchant")
		if inner and inner:IsA("BasePart") then return inner end
		if inner and inner:IsA("Model") then return inner.PrimaryPart or inner:FindFirstChildWhichIsA("BasePart", true) end
	end
	return nil
end

local function updateMerchantLocator()
	if not State.merchantLocatorEnabled then return clearBeams(merchantBeams) end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bitsShops = Workspace:FindFirstChild("BitsShops")
	if not root or not bitsShops then return clearBeams(merchantBeams) end
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
	local detector = card:FindFirstChildOfClass("ClickDetector") or card:FindFirstChild("ClickDetector", true)
	if detector then
		detector.MaxActivationDistance = math.huge
		fireclickdetector(detector)
	end
end

local function readCardTexts(card)
	local surfaceGui = card:FindFirstChildWhichIsA("SurfaceGui", true)
	if not surfaceGui then return "N/A", "N/A", nil end
	local priceDisplay = surfaceGui:FindFirstChild("priceDisplay") or surfaceGui:FindFirstChild("oldpriceDisplay")
	local bitsDisplay = surfaceGui:FindFirstChild("bitsDisplay") or surfaceGui:FindFirstChild("oldbitsDisplay")
	local priceText, bitsText = "N/A", "N/A"
	if priceDisplay and (priceDisplay:IsA("TextLabel") or priceDisplay:IsA("TextButton")) then priceText = priceDisplay.Text end
	if bitsDisplay and (bitsDisplay:IsA("TextLabel") or bitsDisplay:IsA("TextButton")) then bitsText = bitsDisplay.Text end
	return priceText, bitsText, bitsDisplay
end

local function highlightMerchants()
	local activeCards = {}
	local bitsShops = Workspace:FindFirstChild("BitsShops")
	if bitsShops then
		for _, shop in ipairs(bitsShops:GetChildren()) do
			local cardsFolder = shop:FindFirstChild("Cards")
			if cardsFolder then
				for _, card in ipairs(cardsFolder:GetChildren()) do
					if card:IsA("Model") or card:IsA("BasePart") then table.insert(activeCards, card) end
				end
			end
		end
	end

	local cardData = {}
	for _, card in ipairs(activeCards) do
		local priceText, bitsText, bitsDisplay = readCardTexts(card)
		local bitsVal = 0
		if bitsDisplay and (bitsDisplay:IsA("TextLabel") or bitsDisplay:IsA("TextButton")) then
			bitsVal = parseSuffixValue(bitsDisplay.Text)
		end
		table.insert(cardData, { card = card, priceText = priceText, bitsText = bitsText, bitsVal = bitsVal })
	end

	table.sort(cardData, function(a, b) return a.bitsVal > b.bitsVal end)

	if State.autoPickCardEnabled and #cardData >= CONFIG.AutoPickMinCards then
		local bestCard = cardData[1]
		if bestCard and bestCard.bitsVal > 0 then
			fireCardDetector(bestCard.card)
		end
	end

	local currentValidCards = {}
	for rank, data in ipairs(cardData) do
		local card = data.card
		currentValidCards[card] = true
		local btn = merchantListButtons[card]
		if not btn then
			btn = new("TextButton", {
				Name                   = "CardEntry",
				Size                   = UDim2.new(1, 0, 0, 28),
				BackgroundColor3       = Color3.fromRGB(25, 145, 65),
				Font                   = CONFIG.Font,
				TextSize               = 13,
				TextColor3             = Color3.fromRGB(255, 255, 255),
				TextStrokeTransparency = 0.5,
				TextStrokeColor3       = Color3.fromRGB(0, 0, 0),
				TextWrapped            = false,
				AutoButtonColor        = false,
			}, MerchantsListFrame)

			addCorner(btn, 8)
			addStroke(btn, Color3.fromRGB(74, 222, 128), 1.5)

			new("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0,   Color3.fromRGB(34, 180, 80)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(25, 145, 65)),
					ColorSequenceKeypoint.new(1,   Color3.fromRGB(18, 115, 50)),
				}),
				Rotation = 90,
			}, btn)

			new("UIPadding", {
				PaddingLeft  = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}, btn)

			merchantListButtons[card] = btn
			btn.MouseButton1Click:Connect(function() fireCardDetector(card) end)

			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = Color3.fromRGB(18, 115, 50)
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundColor3 = Color3.fromRGB(25, 145, 65)
			end)
		end

		btn.Text = string.format("• %s  |  %s  |  %s", card.Name, data.priceText, data.bitsText)
		btn.LayoutOrder = rank
		btn.Visible = true
	end

	for item, btn in pairs(merchantListButtons) do
		if not currentValidCards[item] then
			btn:Destroy()
			merchantListButtons[item] = nil
		end
	end
end

-- Rebirth
local globalProgressLabel, globalCappedObj, globalNumbersLabel
local lastNumbersText = ""

local function rebirthPair(n) return string.format("(%d --> %d)", n, n + 1) end
local function isBlank(s) return s == nil or s == "" or s == "N/A" end

local function checkCappedState()
	if not globalCappedObj then
		local playerGui = getPlayerGui()
		local main = playerGui and playerGui:FindFirstChild("Main")
		if main and main:FindFirstChild("Rebirth", true) then
			globalCappedObj = main.Rebirth:FindFirstChild("Capped", true)
		end
		if not globalCappedObj then
			local starterMain = StarterGui:FindFirstChild("Main")
			if starterMain then globalCappedObj = starterMain:FindFirstChild("Capped", true) end
		end
	end
	if not globalCappedObj then return false end
	local targetObj = globalCappedObj
	local playerGui = getPlayerGui()
	if globalCappedObj:IsDescendantOf(StarterGui) and playerGui then
		local relativePath = globalCappedObj:GetFullName():gsub("^StarterGui", "PlayerGui")
		local found = playerGui
		for part in relativePath:gmatch("[^%.]+") do
			if part ~= "PlayerGui" then
				found = found:FindFirstChild(part)
				if not found then break end
			end
		end
		if found then targetObj = found end
	end
	local current = targetObj
	local ok, result = pcall(function()
		while current do
			if current:IsA("GuiObject") and not current.Visible then return false end
			if current:IsA("ScreenGui") then return current.Enabled end
			current = current.Parent
		end
		return true
	end)
	return ok and result or false
end

local function clickRebirthConfirm()
	local gui = getPlayerGui() or localPlayer:WaitForChild("PlayerGui", 3)
	if not gui then return end
	local function realClick(btn)
		local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
		local inset = GuiService:GetGuiInset()
		local x = pos.X + size.X / 2
		local y = pos.Y + size.Y / 2 + inset.Y
		VirtualInputManager:SendMouseMoveEvent(x, y, game)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		task.wait(0.05)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end
	for _, v in ipairs(gui:GetDescendants()) do
		if (v:IsA("TextButton") or v:IsA("ImageButton")) and v.Visible then
			local nameCheck = string.upper(tostring(v.Name or ""))
			local textCheck = ""
			if v:IsA("TextButton") then
				pcall(function() textCheck = string.upper(tostring(v.Text or "")) end)
			end
			if nameCheck == "REBIRTH" or nameCheck == "REBIRTHBUTTON" or string.find(textCheck, "REBIRTH") then
				realClick(v)
				break
			end
		end
	end
end

local function triggerRebirth()
	if not State.isRebirthing then
		State.isRebirthing = true
		task.spawn(function()
			pcall(function()
				local clickPart = resolvePath({ "Workspace", table.unpack(CONFIG.Rebirth.ObeliskPath) })
				local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")
				if detector then
					detector.MaxActivationDistance = math.huge
					fireclickdetector(detector)
				end
			end)
			task.wait(CONFIG.Rebirth.ConfirmDelay)
			pcall(clickRebirthConfirm)
			task.wait(CONFIG.Rebirth.Cooldown)
			State.isRebirthing = false
		end)
	end
	if not State.isTeleportingPlot then
		State.isTeleportingPlot = true
		task.spawn(function()
			pcall(function()
				task.wait(CONFIG.Rebirth.TeleportDelay)
				local myPlotName = getMyPlot()
				local plots = Workspace:FindFirstChild("Plots")
				local plotObj = myPlotName ~= "None" and plots and plots:FindFirstChild(myPlotName)
				local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
				if plotObj and root then root.CFrame = getPlotSpawnCFrame(plotObj) end
			end)
			State.isTeleportingPlot = false
		end)
	end
end

local function updateMonitor()
	local textVal = globalProgressLabel and globalProgressLabel.Text or ""
	local rawNumbersVal = globalNumbersLabel and globalNumbersLabel.Text or ""
	local numbersVal = rawNumbersVal

	if not isBlank(rawNumbersVal) then
		local current = tonumber(string.match(rawNumbersVal, "(%d+)"))
		if current then numbersVal = rebirthPair(current) end
	end

	if isBlank(numbersVal) then
		local leaderstats = localPlayer:FindFirstChild("leaderstats") or localPlayer:FindFirstChild("stats")
		local rebirthVal = leaderstats and (leaderstats:FindFirstChild("Rebirths") or leaderstats:FindFirstChild("Rebirth") or leaderstats:FindFirstChild("Rank") or leaderstats:FindFirstChild("RebirthsCount"))
		if rebirthVal then numbersVal = rebirthPair(tonumber(rebirthVal.Value) or 0) end
	end

	if isBlank(numbersVal) then
		local pGui = getPlayerGui()
		if pGui then
			for _, v in ipairs(pGui:GetDescendants()) do
				if v:IsA("TextLabel") and v.Visible then
					local nameCheck = string.lower(v.Name)
					if (string.find(nameCheck, "reb") or string.find(nameCheck, "rank")) and string.match(v.Text, "%d+") then
						local num = tonumber(string.match(v.Text, "(%d+)"))
						if num then numbersVal = rebirthPair(num); break end
					end
				end
			end
		end
	end

	if not isBlank(numbersVal) then
		if lastNumbersText == "" then
			lastNumbersText = numbersVal
		elseif numbersVal ~= lastNumbersText then
			local oldFrom = string.match(lastNumbersText, "%((%d+)%s*%-%->%s*%d+%)")
			local newFrom = string.match(numbersVal, "%((%d+)%s*%-%->%s*%d+%)")
			if oldFrom and newFrom and tonumber(newFrom) > tonumber(oldFrom) then lastNumbersText = numbersVal end
		end
	end

	local displayNumbers = (not isBlank(numbersVal)) and numbersVal or (lastNumbersText ~= "" and lastNumbersText or "N/A")
	local isCappedVisible = checkCappedState()

	RebirthLabel.Text = "Progress: " .. (textVal ~= "" and textVal or "N/A")
	CappedStatusLabel.Text = "Capped: " .. (isCappedVisible and "TRUE" or "FALSE")
	NumbersLabel.Text = "Rebirth(s): " .. displayNumbers

	local percent = textVal ~= "" and parseProgress(textVal) or 0

	if State.autoRebirthEnabled then
		local rebirthNotiText = trackedTexts["RebirthNotification"]
		local hasRebirthNoti = rebirthNotiText ~= nil and rebirthNotiText ~= "" and rebirthNotiText ~= "N/A"
		local mode = CONFIG.Rebirth.Modes[State.rebirthModeIndex].id
		local shouldRebirth
		if mode == "Any" then
			shouldRebirth = isEssenceCapped() or hasRebirthNoti
		elseif mode == "Essence" then
			shouldRebirth = isEssenceCapped()
		else
			shouldRebirth = hasRebirthNoti
		end
		if shouldRebirth then triggerRebirth() end
	end

	PercentLabel.Text = string.format("%.1f%%", percent)

	if (State.autoRebirthEnabled and percent >= 100) or percent >= 99 then
		UIGradient.Color = ColorSequence.new(C.On)
	else
		UIGradient.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0):Lerp(C.On, percent / 100))
	end

	ProgressBarFill:TweenSize(UDim2.new(percent / 100, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
end

local function notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = duration })
	end)
end

ManualRebirthBtn.MouseButton1Click:Connect(function()
	local progressText = globalProgressLabel and globalProgressLabel.Text or ""
	local rebirthNotiText = trackedTexts["RebirthNotification"]
	local hasRebirthNoti = rebirthNotiText ~= nil and rebirthNotiText ~= "" and rebirthNotiText ~= "N/A"
	if parseProgress(progressText) >= 100 or hasRebirthNoti then
		triggerRebirth()
	else
		notify(CONFIG.Rebirth.ManualTitle, CONFIG.Rebirth.ManualFailText, CONFIG.Rebirth.ManualFailSeconds)
	end
end)

task.spawn(function()
	local textConn, cappedConn, numbersConn, leaderConn
	cleanupHooks[#cleanupHooks + 1] = function()
		for _, conn in ipairs({ textConn, cappedConn, numbersConn, leaderConn }) do
			if conn then conn:Disconnect() end
		end
	end
	local function hookMonitor(gui)
		if textConn then textConn:Disconnect() textConn = nil end
		if cappedConn then cappedConn:Disconnect() cappedConn = nil end
		if numbersConn then numbersConn:Disconnect() numbersConn = nil end
		pcall(function()
			globalProgressLabel = gui:WaitForChild("System", 2):WaitForChild("RebirthProgress", 2):WaitForChild("Progress", 2):WaitForChild("TextLabel", 2)
		end)
		pcall(function()
			local rebirthFrame = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Rebirth")
			if rebirthFrame then globalCappedObj = rebirthFrame:FindFirstChild("Capped", true) end
			if not globalCappedObj then
				local starterRebirth = StarterGui:FindFirstChild("Main") and StarterGui.Main:FindFirstChild("Rebirth")
				if starterRebirth then globalCappedObj = starterRebirth:FindFirstChild("Capped", true) end
			end
		end)
		pcall(function()
			local holder = gui:WaitForChild("System", 2):WaitForChild("PlayerList", 2):WaitForChild("Holder", 2)
			local myHolder = holder:FindFirstChild(localPlayer.Name) or holder:FindFirstChildWhichIsA("Frame")
			if myHolder then globalNumbersLabel = myHolder:WaitForChild("RebsText", 2) end
		end)
		pcall(function()
			if not globalNumbersLabel then
				local rebirthFrame = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Rebirth")
				if rebirthFrame then globalNumbersLabel = rebirthFrame:FindFirstChild("Numbers", true) end
			end
		end)
		if globalProgressLabel then textConn = globalProgressLabel:GetPropertyChangedSignal("Text"):Connect(updateMonitor) end
		if globalCappedObj then cappedConn = globalCappedObj:GetPropertyChangedSignal("Visible"):Connect(updateMonitor) end
		if globalNumbersLabel then numbersConn = globalNumbersLabel:GetPropertyChangedSignal("Text"):Connect(updateMonitor) end
		local leaderstats = localPlayer:FindFirstChild("leaderstats") or localPlayer:FindFirstChild("stats")
		local cashVal = leaderstats and (leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money"))
		if cashVal then
			if leaderConn then leaderConn:Disconnect() end
			leaderConn = cashVal:GetPropertyChangedSignal("Value"):Connect(updateMonitor)
		end
		updateMonitor()
	end
	hookMonitor(localPlayer:WaitForChild("PlayerGui"))
	track(localPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		if running then hookMonitor(localPlayer:WaitForChild("PlayerGui")) end
	end))
	while running do
		task.wait(CONFIG.Intervals.MonitorPoll)
		if running then updateMonitor() end
	end
end)

-- Auto Buy Loop
local lastAutoBuyTime = 0

local function updateShop()
	local cashNum, cashStr = getPlayerCash()
	local currentPlot = getMyPlot()

	StatsLabel.Text = string.format("Stats:\nCash: %s\nPlot: %s\nEssence Capped: %s", cashStr or tostring(cashNum), currentPlot, isEssenceCapped() and "True" or "False")

	local myTycoon = getMyTycoon()
	if not myTycoon or not myTycoon:FindFirstChild("Buttons") then
		clearGuidelines()
		return
	end

	local affordable, allItems = {}, {}
	for _, btn in ipairs(myTycoon.Buttons:GetChildren()) do
		local priceNum, priceStr, displayName = getButtonDetails(btn)
		if priceNum then
			local item = {
				instance = btn,
				name = displayName or btn.Name,
				price = priceNum,
				priceStr = priceStr or tostring(priceNum),
				canAfford = cashNum >= priceNum,
			}
			table.insert(allItems, item)
			if item.canAfford then
				table.insert(affordable, item)
			end
		end
	end

	table.sort(affordable, function(a, b) return a.price < b.price end)

	if State.autoBuyEnabled and localPlayer.Character and #affordable > 0 then
		if tick() - lastAutoBuyTime >= CONFIG.Intervals.AutoBuyCooldown then
			local target = affordable[1]
			if target and isButtonActive(target.instance) then
				lastAutoBuyTime = tick()
				moveToTarget(target.instance)
			end
		end
	end

	updateGuidelines(allItems)
end

-- Main Scheduler
local scheduled = {
	{ interval = CONFIG.Intervals.MerchantUpdate, last = 0, fn = highlightMerchants },
	{ interval = CONFIG.Intervals.ShopUpdate,     last = 0, fn = updateShop },
	{ interval = CONFIG.Intervals.MerchantLocator,last = 0, fn = updateMerchantLocator },
}

track(RunService.Heartbeat:Connect(function()
	local now = tick()
	for _, job in ipairs(scheduled) do
		if now - job.last >= job.interval then
			job.last = now
			job.fn(now)
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

-- Cleanup on re-execution or close
env.TycoonManagerCleanup = function()
	running = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)

	for _, hook in ipairs(cleanupHooks) do
		pcall(hook)
	end
	table.clear(cleanupHooks)

	pcall(cancelPath)
	pcall(clearGuidelines)
	pcall(clearBeams, merchantBeams)

	for _, btn in pairs(merchantListButtons) do
		btn:Destroy()
	end
	table.clear(merchantListButtons)

	ScreenGui:Destroy()
	env.TycoonManagerCleanup = nil
end