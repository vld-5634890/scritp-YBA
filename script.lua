-- Панель отладки автосбора для собственного проекта Roblox Studio.
-- LocalScript поместить в StarterPlayer > StarterPlayerScripts.
-- Скрипт намеренно работает только в Studio.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("StudioItemFinder")
if oldGui then
	oldGui:Destroy()
end

local TARGET_NAMES = {
	"Pure Rokakaka",
	"Mysterious Arrow",
	"Lucky Arrow",
	"Rokakaka",
	"Rib Cage of the Saint's Corpse",
	"Gold Coin",
	"Diamond",
	"Stone Mask",
	"Ancient Scroll",
	"Quinton's Glove",
	"Headband",
	"Steel Ball",
}

local TARGET_ENABLED = {}
local sessionStats = {}
for _, targetName in ipairs(TARGET_NAMES) do
	TARGET_ENABLED[targetName] = true
	sessionStats[targetName] = 0
end

local MIN_SPEED = 25
local MAX_SPEED = 125
local SCAN_INTERVAL = 1
local MAX_RESULT_ROWS = 15
local LOCAL_SEARCH_RADII = { 400, 800, 1200, 1600, 2000 }
local LOCAL_SEARCH_POINTS_PER_RING = 32
local LOCAL_SEARCH_MAX_RADIUS = 2000
local LOCAL_SEARCH_CLEARANCE = 8

local scanning = false
local scanGeneration = 0
local currentSpeed = 25
local currentCharacter
local currentRootPart
local activeTween
local activePrompt
local activePromptConnection
local visiblePrompts = setmetatable({}, { __mode = "k" })
local targetRetryAfter = setmetatable({}, { __mode = "k" })
local patrolRoute = {}
local patrolRouteIndex = 1
local patrolCenter
local lastItemPosition
local routeRandom = Random.new()
local scanHighlights = {}
local noClipEnabled = false
local originalCollisions = {}
local originalAutoRotate = {}
local noClipDescendantConnection
local noClipCharacterConnection
local startScanLoop
local setNoClip
local scanWorkspace
local toggleAutomation
local statusLabel

ProximityPromptService.PromptShown:Connect(function(prompt)
	visiblePrompts[prompt] = true
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	visiblePrompts[prompt] = nil
end)

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties) do
		instance[property] = value
	end
	if instance:IsA("GuiButton") then
		instance.Active = true
	end
	instance.Parent = parent
	return instance
end

local function getHighlightAdornee(target)
	local object = target.object
	if not object then
		return nil
	end
	if object:IsA("Model") or object:IsA("BasePart") then
		return object
	end

	local promptParent = target.prompt and target.prompt.Parent
	local ancestor = promptParent and (
		promptParent:FindFirstAncestorOfClass("Model")
		or promptParent:FindFirstAncestorWhichIsA("BasePart")
	)
	if ancestor then
		return ancestor
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("Model") or descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function updateScannedHighlights(results)
	local currentObjects = {}
	for _, target in ipairs(results) do
		local object = target.object
		local adornee = getHighlightAdornee(target)
		if object and object.Parent and adornee then
			currentObjects[object] = true
			local highlight = scanHighlights[object]
			if not highlight or not highlight.Parent then
				highlight = Instance.new("Highlight")
				highlight.Name = "ScannedItemHighlight"
				highlight.FillColor = Color3.fromRGB(119, 190, 132)
				highlight.FillTransparency = 0.58
				highlight.OutlineColor = Color3.fromRGB(155, 211, 165)
				highlight.OutlineTransparency = 0.12
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = Workspace
				scanHighlights[object] = highlight
			end
			highlight.Adornee = adornee
		end
	end

	for object, highlight in pairs(scanHighlights) do
		if not currentObjects[object] or not object.Parent then
			highlight:Destroy()
			scanHighlights[object] = nil
		end
	end
end

local screenGui = create("ScreenGui", {
	Name = "StudioItemFinder",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local frame = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 18, 0.5, 0),
	Size = UDim2.fromOffset(340, 590),
	BackgroundColor3 = Color3.fromRGB(23, 26, 33),
	BorderSizePixel = 0,
}, screenGui)
local frameCorner = create("UICorner", {
	CornerRadius = UDim.new(0, 10),
}, frame)
create("UIStroke", {
	Color = Color3.fromRGB(64, 72, 88),
	Transparency = 0.35,
	Thickness = 1,
}, frame)

local header = create("Frame", {
	Name = "Header",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = Color3.fromRGB(30, 34, 43),
	BorderSizePixel = 0,
}, frame)
create("UICorner", {
	CornerRadius = UDim.new(0, 10),
}, header)

local titleLabel = create("TextLabel", {
	Name = "Title",
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(1, -62, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "ПОИСК ПРЕДМЕТОВ · STUDIO",
	TextColor3 = Color3.fromRGB(239, 242, 248),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local collapseButton = create("TextButton", {
	Name = "CollapseButton",
	Position = UDim2.new(1, -38, 0, 7),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = Color3.fromRGB(48, 54, 66),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "−",
	TextColor3 = Color3.fromRGB(245, 246, 250),
	TextSize = 17,
}, header)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, collapseButton)

local toggleButton = create("TextButton", {
	Name = "ToggleButton",
	Position = UDim2.fromOffset(12, 48),
	Size = UDim2.new(1, -24, 0, 40),
	BackgroundColor3 = Color3.fromRGB(55, 63, 78),
	AutoButtonColor = false,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	Text = "Авто-сбор: выкл",
	TextColor3 = Color3.fromRGB(248, 249, 252),
	TextSize = 13,
	ZIndex = 5,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, toggleButton)

local function updateToggleVisual()
	toggleButton.Text = scanning and "Авто-сбор: вкл" or "Авто-сбор: выкл"
	toggleButton.BackgroundColor3 = scanning
		and Color3.fromRGB(42, 132, 98)
		or Color3.fromRGB(55, 63, 78)
end

local function cancelCurrentAction()
	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end
	if activePrompt then
		pcall(function()
			activePrompt:InputHoldEnd()
		end)
		activePrompt = nil
	end
	if activePromptConnection then
		activePromptConnection:Disconnect()
		activePromptConnection = nil
	end
end

-- Подключаем главный переключатель сразу при создании.
-- Даже если инициализация сканера завершится ошибкой, нажатие изменит состояние и покажет причину.
toggleButton.Activated:Connect(function()
	if toggleAutomation then
		local ok, err = pcall(toggleAutomation)
		if not ok then
			scanning = false
			scanGeneration += 1
			cancelCurrentAction()
			if setNoClip then
				pcall(setNoClip, false)
			end
			updateToggleVisual()
			if statusLabel then
				statusLabel.Text = "Ошибка кнопки: " .. tostring(err)
			end
			warn("[StudioItemFinder] Ошибка переключателя: " .. tostring(err))
		end
	else
		scanning = not scanning
		updateToggleVisual()
		if statusLabel then
			statusLabel.Text = "Инициализация сканера..."
		end
	end
end)

local speedPanel = create("Frame", {
	Name = "SpeedPanel",
	Position = UDim2.fromOffset(12, 98),
	Size = UDim2.new(1, -24, 0, 48),
	BackgroundColor3 = Color3.fromRGB(32, 36, 45),
	BorderSizePixel = 0,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, speedPanel)

local speedLabel = create("TextLabel", {
	Name = "SpeedLabel",
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Скорость полёта: 25 studs/s",
	TextColor3 = Color3.fromRGB(198, 204, 216),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, speedPanel)

local sliderTrack = create("TextButton", {
	Name = "SpeedSlider",
	Position = UDim2.new(0, 10, 0, 29),
	Size = UDim2.new(1, -20, 0, 8),
	BackgroundColor3 = Color3.fromRGB(57, 64, 78),
	BorderSizePixel = 0,
	Text = "",
}, speedPanel)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, sliderTrack)

local sliderFill = create("Frame", {
	Name = "SliderFill",
	Size = UDim2.new((currentSpeed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED), 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(100, 164, 246),
	BorderSizePixel = 0,
}, sliderTrack)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, sliderFill)

statusLabel = create("TextLabel", {
	Name = "Status",
	Position = UDim2.fromOffset(12, 151),
	Size = UDim2.new(1, -24, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Готово · нажмите «Авто-сбор»",
	TextColor3 = Color3.fromRGB(185, 192, 205),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, frame)

create("TextLabel", {
	Name = "ResultsTitle",
	Position = UDim2.fromOffset(12, 181),
	Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "НАЙДЕННЫЕ ПРЕДМЕТЫ",
	TextColor3 = Color3.fromRGB(167, 177, 194),
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
}, frame)

local resultsFrame = create("ScrollingFrame", {
	Name = "Results",
	Position = UDim2.fromOffset(12, 203),
	Size = UDim2.new(1, -24, 0, 145),
	BackgroundColor3 = Color3.fromRGB(17, 20, 26),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Color3.fromRGB(100, 108, 124),
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, resultsFrame)

local resultLayout = create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, resultsFrame)
create("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, resultsFrame)

local resultRows = {}
for index = 1, MAX_RESULT_ROWS do
	resultRows[index] = create("TextLabel", {
		Name = "Result" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, -4, 0, 25),
		BackgroundColor3 = Color3.fromRGB(35, 39, 48),
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(228, 232, 240),
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, resultsFrame)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, resultRows[index])
end

resultLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	resultsFrame.CanvasSize = UDim2.new(0, 0, 0, resultLayout.AbsoluteContentSize.Y + 12)
end)

local statsLabel = create("TextLabel", {
	Name = "SessionStats",
	Position = UDim2.fromOffset(12, 355),
	Size = UDim2.new(1, -24, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = Color3.fromRGB(195, 201, 213),
	TextSize = 10,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, frame)

local function updateStatsLabel()
	local entries = {}
	for _, targetName in ipairs(TARGET_NAMES) do
		local count = sessionStats[targetName] or 0
		if count > 0 then
			table.insert(entries, targetName .. " ×" .. tostring(count))
		end
	end
	statsLabel.Text = #entries == 0
		and "Собрано за сессию: пока ничего"
		or "Собрано за сессию: " .. table.concat(entries, " · ")
end
updateStatsLabel()

create("TextLabel", {
	Name = "FilterTitle",
	Position = UDim2.fromOffset(12, 401),
	Size = UDim2.fromOffset(118, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "ФИЛЬТРЫ",
	TextColor3 = Color3.fromRGB(167, 177, 194),
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
}, frame)

local filterButtons = {}
local filterScroll = create("ScrollingFrame", {
	Name = "Filters",
	Position = UDim2.fromOffset(12, 433),
	Size = UDim2.new(1, -24, 0, 144),
	BackgroundColor3 = Color3.fromRGB(29, 33, 41),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, #TARGET_NAMES * 26 + 8),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Color3.fromRGB(100, 108, 124),
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 7) }, filterScroll)

local enableAllButton = create("TextButton", {
	Name = "EnableAll",
	Position = UDim2.new(1, -202, 0, 401),
	Size = UDim2.fromOffset(92, 24),
	BackgroundColor3 = Color3.fromRGB(47, 91, 70),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Включить все",
	TextColor3 = Color3.fromRGB(238, 241, 247),
	TextSize = 9,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 5) }, enableAllButton)

local disableAllButton = create("TextButton", {
	Name = "DisableAll",
	Position = UDim2.new(1, -106, 0, 401),
	Size = UDim2.fromOffset(94, 24),
	BackgroundColor3 = Color3.fromRGB(83, 54, 59),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Выключить",
	TextColor3 = Color3.fromRGB(238, 241, 247),
	TextSize = 9,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 5) }, disableAllButton)

for index, targetName in ipairs(TARGET_NAMES) do
	local button = create("TextButton", {
		Name = "Filter_" .. string.gsub(targetName, "%W", ""),
		Position = UDim2.fromOffset(6, 6 + (index - 1) * 26),
		Size = UDim2.new(1, -18, 0, 22),
		BackgroundColor3 = Color3.fromRGB(47, 83, 66),
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(237, 240, 246),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, filterScroll)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, button)
	filterButtons[targetName] = button
end

local function updateFilterButton(targetName)
	local button = filterButtons[targetName]
	if not button then
		return
	end
	local enabled = TARGET_ENABLED[targetName]
	button.Text = (enabled and "[✓] " or "[ ] ") .. targetName
	button.BackgroundColor3 = enabled
		and Color3.fromRGB(47, 83, 66)
		or Color3.fromRGB(48, 52, 62)
end

for _, targetName in ipairs(TARGET_NAMES) do
	updateFilterButton(targetName)
end

local function setAllFilters(enabled)
	for _, targetName in ipairs(TARGET_NAMES) do
		TARGET_ENABLED[targetName] = enabled
		updateFilterButton(targetName)
	end
	if scanning then
		scanGeneration += 1
		cancelCurrentAction()
		if startScanLoop then
			startScanLoop(scanGeneration)
		end
	elseif not enabled then
		for _, row in ipairs(resultRows) do
			row.Visible = false
		end
		statusLabel.Text = "Все фильтры выключены."
	end
end

enableAllButton.Activated:Connect(function()
	setAllFilters(true)
end)
disableAllButton.Activated:Connect(function()
	setAllFilters(false)
end)

local dragging = false
local dragStart
local panelStart
titleLabel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		panelStart = frame.Position
	end
end)

local speedDragging = false
local function updateSpeed(input)
	local width = math.max(1, sliderTrack.AbsoluteSize.X)
	local percent = math.clamp((input.Position.X - sliderTrack.AbsolutePosition.X) / width, 0, 1)
	currentSpeed = math.clamp(
		math.floor(MIN_SPEED + percent * (MAX_SPEED - MIN_SPEED) + 0.5),
		MIN_SPEED,
		MAX_SPEED
	)
	sliderFill.Size = UDim2.new(percent, 0, 1, 0)
	speedLabel.Text = "Скорость полёта: " .. currentSpeed .. " studs/s"
end

sliderTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		speedDragging = true
		updateSpeed(input)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if speedDragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
		updateSpeed(input)
	end
	if dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			panelStart.X.Scale,
			panelStart.X.Offset + delta.X,
			panelStart.Y.Scale,
			panelStart.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		speedDragging = false
		dragging = false
	end
end)

local expandedSize = frame.Size
local collapsed = false
local collapseTween
local function setCollapsed(value)
	collapsed = value
	collapseButton.Text = collapsed and "+" or "−"
	for _, child in ipairs(frame:GetChildren()) do
		if child ~= header and child:IsA("GuiObject") then
			child.Visible = not collapsed
		end
	end
	if collapseTween then
		collapseTween:Cancel()
	end
	local size = collapsed
		and UDim2.fromOffset(expandedSize.X.Offset, 42)
		or expandedSize
	collapseTween = TweenService:Create(
		frame,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = size }
	)
	collapseTween:Play()
	frameCorner.CornerRadius = collapsed and UDim.new(0, 20) or UDim.new(0, 10)
end
collapseButton.Activated:Connect(function()
	setCollapsed(not collapsed)
end)

local function restoreNoClip()
	for part, oldValue in pairs(originalCollisions) do
		if part.Parent then
			part.CanCollide = oldValue
		end
		originalCollisions[part] = nil
	end
end

local function getUprightCFrame(rootPart, position)
	local look = rootPart.CFrame.LookVector
	local horizontalLook = Vector3.new(look.X, 0, look.Z)
	if horizontalLook.Magnitude < 0.001 then
		horizontalLook = Vector3.new(0, 0, -1)
	else
		horizontalLook = horizontalLook.Unit
	end
	return CFrame.lookAt(position, position + horizontalLook, Vector3.yAxis)
end

local function setCharacterUpright(character, enabled)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if enabled then
		if originalAutoRotate[humanoid] == nil then
			originalAutoRotate[humanoid] = humanoid.AutoRotate
		end
		humanoid.AutoRotate = false
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			rootPart.CFrame = getUprightCFrame(rootPart, rootPart.Position)
		end
	else
		local oldValue = originalAutoRotate[humanoid]
		if oldValue ~= nil then
			humanoid.AutoRotate = oldValue
			originalAutoRotate[humanoid] = nil
		end
	end
end

local function restoreAutoRotate()
	for humanoid, oldValue in pairs(originalAutoRotate) do
		if humanoid.Parent then
			humanoid.AutoRotate = oldValue
		end
		originalAutoRotate[humanoid] = nil
	end
end

local function applyNoClipToCharacter(character)
	if noClipDescendantConnection then
		noClipDescendantConnection:Disconnect()
		noClipDescendantConnection = nil
	end
	restoreNoClip()
	setCharacterUpright(character, true)

	local function disableCollision(instance)
		if instance:IsA("BasePart") then
			if originalCollisions[instance] == nil then
				originalCollisions[instance] = instance.CanCollide
			end
			instance.CanCollide = false
		end
	end

	for _, instance in ipairs(character:GetDescendants()) do
		disableCollision(instance)
	end
	noClipDescendantConnection = character.DescendantAdded:Connect(disableCollision)
end

setNoClip = function(enabled)
	if noClipEnabled == enabled then
		return
	end
	noClipEnabled = enabled

	if enabled then
		if player.Character then
			applyNoClipToCharacter(player.Character)
		end
		noClipCharacterConnection = player.CharacterAdded:Connect(function(character)
			if noClipEnabled then
				applyNoClipToCharacter(character)
			end
		end)
	else
		if noClipCharacterConnection then
			noClipCharacterConnection:Disconnect()
			noClipCharacterConnection = nil
		end
		if noClipDescendantConnection then
			noClipDescendantConnection:Disconnect()
			noClipDescendantConnection = nil
		end
		restoreNoClip()
		restoreAutoRotate()
	end
end

local function getCurrentRootPart()
	local character = player.Character
	if not character then
		currentCharacter = nil
		currentRootPart = nil
		return nil
	end
	if currentCharacter ~= character then
		currentCharacter = character
		currentRootPart = character:FindFirstChild("HumanoidRootPart")
	end
	if not currentRootPart or currentRootPart.Parent ~= character then
		currentRootPart = character:FindFirstChild("HumanoidRootPart")
	end
	return currentRootPart
end

player.CharacterAdded:Connect(function(character)
	currentCharacter = character
	currentRootPart = nil
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart")
		if player.Character == character then
			currentRootPart = root
			if scanning then
				statusLabel.Text = "Персонаж восстановлен · продолжаю сканирование"
			end
		end
	end)
end)

player.CharacterRemoving:Connect(function(character)
	if currentCharacter == character then
		cancelCurrentAction()
		setCharacterUpright(character, false)
		currentCharacter = nil
		currentRootPart = nil
	end
end)

local function normalizeName(name)
	return string.gsub(string.lower(name), "[^%w]", "")
end

local function findTargetName(objectName)
	local normalizedObjectName = normalizeName(objectName)
	for _, targetName in ipairs(TARGET_NAMES) do
		local normalizedTargetName = normalizeName(targetName)
		if normalizedTargetName ~= ""
			and string.find(normalizedObjectName, normalizedTargetName, 1, true) then
			return targetName
		end
	end
	return nil
end

local function isPlayerCharacterAncestor(object)
	local ancestor = object
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") and Players:GetPlayerFromCharacter(ancestor) then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function getWorldPosition(object)
	if not object then
		return nil
	end
	if object:IsA("Attachment") then
		return object.WorldPosition
	end
	if object:IsA("BasePart") then
		return object.Position
	end
	if object:IsA("Model") then
		local ok, pivot = pcall(function()
			return object:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end
	local part = object:FindFirstAncestorWhichIsA("BasePart")
	if part then
		return part.Position
	end
	local model = object:FindFirstAncestorOfClass("Model")
	if model then
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end
	return nil
end

local function findPromptTarget(prompt)
	if not prompt or not prompt.Parent or not prompt.Enabled then
		return nil
	end
	local ancestor = prompt.Parent
	local matchedObject
	local targetName
	while ancestor and ancestor ~= Workspace do
		targetName = findTargetName(ancestor.Name)
		if targetName then
			matchedObject = ancestor
			break
		end
		ancestor = ancestor.Parent
	end

	-- В собственном Studio-проекте ObjectText помогает, если модель названа общо.
	-- Сначала всегда проверяются имена физического объекта и его предков.
	if not targetName then
		targetName = findTargetName(prompt.ObjectText)
			or findTargetName(prompt.ActionText)
		matchedObject = prompt.Parent:FindFirstAncestorOfClass("Model") or prompt.Parent
	end
	if not targetName or isPlayerCharacterAncestor(prompt.Parent) then
		return nil
	end

	local position = getWorldPosition(prompt.Parent) or getWorldPosition(matchedObject)
	if not position then
		return nil
	end
	return {
		prompt = prompt,
		object = matchedObject,
		name = targetName,
		objectName = matchedObject.Name,
		position = position,
		activationDistance = math.max(1, prompt.MaxActivationDistance),
	}
end

local function findTargets(origin)
	local results = {}
	local seen = {}
	local activePromptCount = 0
	local searchCenter = lastItemPosition or patrolCenter
	if not searchCenter and scanning then
		patrolCenter = origin
		searchCenter = origin
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("ProximityPrompt") and instance.Enabled then
			activePromptCount += 1
			local target = findPromptTarget(instance)
			if target
				and TARGET_ENABLED[target.name]
				and (not searchCenter
					or (target.position - searchCenter).Magnitude <= LOCAL_SEARCH_MAX_RADIUS - 5)
				and (targetRetryAfter[target.object] or 0) <= os.clock()
				and not seen[target.object] then
				seen[target.object] = true
				target.distance = (origin - target.position).Magnitude
				table.insert(results, target)
			end
		end
	end

	table.sort(results, function(a, b)
		return a.distance < b.distance
	end)
	return results, activePromptCount
end

local function renderResults(results)
	for index, row in ipairs(resultRows) do
		local result = results[index]
		if result then
			row.Visible = true
			row.Text = string.format(
				"  %s · %s · %.0f studs",
				result.name,
				result.objectName,
				result.distance
			)
			row.BackgroundColor3 = index == 1
				and Color3.fromRGB(46, 64, 58)
				or Color3.fromRGB(35, 39, 48)
		else
			row.Visible = false
			row.Text = ""
		end
	end
end

scanWorkspace = function()
	local root = getCurrentRootPart()
	if not root then
		statusLabel.Text = "Ожидаю персонажа..."
		renderResults({})
		updateScannedHighlights({})
		return {}
	end

	local results, activePromptCount = findTargets(root.Position)
	renderResults(results)
	updateScannedHighlights(results)
	if #results == 0 then
		statusLabel.Text = string.format(
			"Нет совпадений · активных ProximityPrompt: %d",
			activePromptCount
		)
	end
	return results
end

local function buildLocalSearchRoute(originPosition)
	local center = lastItemPosition or patrolCenter or originPosition
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { currentCharacter }

	local route = {}
	local centerRayOrigin = center + Vector3.new(0, 512, 0)
	local centerGround = Workspace:Raycast(centerRayOrigin, Vector3.new(0, -4096, 0), raycastParams)
	if centerGround then
		table.insert(route, Vector3.new(
			center.X,
			centerGround.Position.Y + LOCAL_SEARCH_CLEARANCE,
			center.Z
		))
	end

	-- Обходим широкую зону кольцами; точки без поверхности под ними пропускаются,
	-- чтобы патруль не уходил в пустоту за пределами карты.
	for ringIndex, radius in ipairs(LOCAL_SEARCH_RADII) do
		local angleOffset = (ringIndex - 1) * math.pi / LOCAL_SEARCH_POINTS_PER_RING
		for pointIndex = 1, LOCAL_SEARCH_POINTS_PER_RING do
			local angle = (pointIndex - 1) * (2 * math.pi / LOCAL_SEARCH_POINTS_PER_RING) + angleOffset
			local x = center.X + math.cos(angle) * radius
			local z = center.Z + math.sin(angle) * radius
			local rayOrigin = Vector3.new(x, center.Y + 512, z)
			local ground = Workspace:Raycast(rayOrigin, Vector3.new(0, -4096, 0), raycastParams)
			if ground then
				local point = Vector3.new(x, ground.Position.Y + LOCAL_SEARCH_CLEARANCE, z)
				local offset = point - center
				if offset.Magnitude > LOCAL_SEARCH_MAX_RADIUS then
					point = center + offset.Unit * LOCAL_SEARCH_MAX_RADIUS
				end
				table.insert(route, point)
			end
		end
	end
	if #route == 0 then
		table.insert(route, originPosition)
	end

	return route
end

local function getNextLocalSearchPoint(originPosition)
	if #patrolRoute == 0 or patrolRouteIndex > #patrolRoute then
		patrolRoute = buildLocalSearchRoute(originPosition)
		for index = #patrolRoute, 2, -1 do
			local swapIndex = routeRandom:NextInteger(1, index)
			patrolRoute[index], patrolRoute[swapIndex] = patrolRoute[swapIndex], patrolRoute[index]
		end
		patrolRouteIndex = 1

		-- Перемешиваем порядок перелётов и начинаем с ближайшей точки.
		local nearestDistance = math.huge
		for index, position in ipairs(patrolRoute) do
			local distance = (originPosition - position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				patrolRouteIndex = index
			end
		end
	end

	local index = patrolRouteIndex
	local position = patrolRoute[index]
	patrolRouteIndex += 1
	return position, index, #patrolRoute
end

local function moveTo(position, generation, scanDuringTravel)
	local root = getCurrentRootPart()
	if not root or not scanning or generation ~= scanGeneration then
		return false
	end

	local distance = (root.Position - position).Magnitude
	if distance < 1 then
		return true
	end

	local duration = math.max(0.1, distance / math.max(MIN_SPEED, currentSpeed))
	local tween = TweenService:Create(
		root,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = getUprightCFrame(root, position) }
	)
	activeTween = tween
	tween:Play()

	local deadline = os.clock() + duration + 2
	local nextTravelScan = os.clock() + SCAN_INTERVAL
	local foundTargetDuringTravel = false
	while scanning and generation == scanGeneration and os.clock() < deadline do
		if not root.Parent then
			break
		end
		if (root.Position - position).Magnitude <= 1.25 then
			break
		end
		if tween.PlaybackState ~= Enum.PlaybackState.Playing then
			break
		end
		if scanDuringTravel and os.clock() >= nextTravelScan then
			local results = scanWorkspace()
			if #results > 0 then
				foundTargetDuringTravel = true
				break
			end
			nextTravelScan = os.clock() + SCAN_INTERVAL
			statusLabel.Text = "Облёт карты · продолжаю поиск предметов..."
		end
		task.wait(0.05)
	end

	local reached = not foundTargetDuringTravel
		and root.Parent ~= nil
		and (root.Position - position).Magnitude <= 2.5
	if tween.PlaybackState == Enum.PlaybackState.Playing then
		tween:Cancel()
	end
	if activeTween == tween then
		activeTween = nil
	end
	return reached, foundTargetDuringTravel
end

local function interactWithTarget(target, generation, attempt)
	attempt = attempt or 1
	local prompt = target.prompt
	if not scanning or generation ~= scanGeneration
		or not prompt.Parent or not prompt.Enabled then
		return false, "invalid"
	end

	local root = getCurrentRootPart()
	local promptPosition = getWorldPosition(prompt.Parent)
	if not root or not promptPosition then
		statusLabel.Text = "Не удалось определить позицию ProximityPrompt."
		return false, "invalid"
	end
	local distance = (root.Position - promptPosition).Magnitude
	local activationDistance = prompt.MaxActivationDistance
	if activationDistance <= 0 or distance > activationDistance then
		statusLabel.Text = string.format(
			"Вне радиуса E: %.1f / %.1f studs",
			distance,
			activationDistance
		)
		return false, "out-of-range"
	end

	-- Даём Roblox обновить видимость prompt после последнего перемещения.
	local visibleDeadline = os.clock() + 0.75
	while scanning and generation == scanGeneration
		and prompt.Parent and prompt.Enabled
		and not visiblePrompts[prompt]
		and os.clock() < visibleDeadline do
		task.wait(0.05)
	end
	if not scanning or generation ~= scanGeneration then
		return false, "stopped"
	end
	if not visiblePrompts[prompt] then
		statusLabel.Text = "ProximityPrompt не показан · проверьте дальность и видимость."
		return false, "not-visible"
	end

	local triggered = false
	local holdBegan = prompt.HoldDuration <= 0
	local holdDuration = prompt.HoldDuration
	local triggerConnection = prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == nil or triggeringPlayer == player then
			triggered = true
			holdBegan = true
		end
	end)
	local holdConnection
	if holdDuration > 0 then
		holdConnection = prompt.PromptButtonHoldBegan:Connect(function(triggeringPlayer)
			if triggeringPlayer == nil or triggeringPlayer == player then
				holdBegan = true
			end
		end)
	end
	activePromptConnection = triggerConnection
	activePrompt = prompt

	local ok, err = pcall(function()
		prompt:InputHoldBegin()
	end)
	if ok then
		local endAt = os.clock() + math.max(0.15, holdDuration + 0.25)
		while scanning and generation == scanGeneration
			and not triggered
			and prompt.Parent and prompt.Enabled
			and os.clock() < endAt do
			task.wait(0.03)
		end
	end

	pcall(function()
		prompt:InputHoldEnd()
	end)
	if activePrompt == prompt then
		activePrompt = nil
	end
	if activePromptConnection == triggerConnection then
		activePromptConnection = nil
	end
	triggerConnection:Disconnect()
	if holdConnection then
		holdConnection:Disconnect()
	end

	if ok and prompt.Parent and prompt.Enabled
		and target.object:IsDescendantOf(Workspace) then
		-- Даём серверному обработчику время удалить или отключить предмет.
		local ackDeadline = os.clock() + 2
		while scanning and generation == scanGeneration
			and os.clock() < ackDeadline
			and prompt.Parent and prompt.Enabled
			and target.object:IsDescendantOf(Workspace) do
			task.wait(0.05)
		end
	end

	local collected = not prompt.Parent
		or not prompt.Enabled
		or not target.object:IsDescendantOf(Workspace)
	if collected then
		sessionStats[target.name] += 1
		updateStatsLabel()
		statusLabel.Text = "Подобрано: " .. target.name
		return true, "collected"
	end

	if ok and scanning and generation == scanGeneration and attempt < 2
		and prompt.Parent and prompt.Enabled then
		statusLabel.Text = string.format("Повторяю удержание E · %s (%d/2)", target.name, attempt + 1)
		task.wait(0.15)
		return interactWithTarget(target, generation, attempt + 1)
	end

	if not ok then
		warn("[StudioItemFinder] Не удалось активировать ProximityPrompt: " .. tostring(err))
	end
	if triggered then
		statusLabel.Text = "E сработала, но предмет остался · проверьте серверный подбор."
	elseif not holdBegan then
		statusLabel.Text = "Roblox не начал удержание E: " .. target.name
	else
		statusLabel.Text = "Подбор не подтвердился: " .. target.name
	end
	return false, "failed"
end

local function moveAndCollect(target, generation)
	local hoverPosition = target.position + Vector3.new(0, 4.5, 0)
	if not moveTo(hoverPosition, generation) then
		return false
	end
	if not scanning or generation ~= scanGeneration then
		return false
	end

	local currentTarget = findPromptTarget(target.prompt)
	if not currentTarget then
		return false
	end
	if (currentTarget.position - target.position).Magnitude > 2 then
		target = currentTarget
		hoverPosition = target.position + Vector3.new(0, 4.5, 0)
		if not moveTo(hoverPosition, generation) then
			return false
		end
	end

	local lateralDirections = {
		Vector3.zero,
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	}

	for _, direction in ipairs(lateralDirections) do
		if not scanning or generation ~= scanGeneration then
			return false
		end
		local liveTarget = findPromptTarget(target.prompt)
		if not liveTarget then
			return false
		end
		if (liveTarget.position - target.position).Magnitude > 2 then
			target = liveTarget
		else
			target = liveTarget
		end

		local descentHeight = math.clamp(target.activationDistance * 0.25, 0.35, 1.5)
		local lateralDistance = math.clamp(target.activationDistance * 0.2, 0.2, 1.25)
		local approachPosition = target.position
			+ Vector3.new(0, descentHeight, 0)
			+ direction * lateralDistance
		if not moveTo(approachPosition, generation) then
			return false
		end

		liveTarget = findPromptTarget(target.prompt)
		if liveTarget then
			if (liveTarget.position - target.position).Magnitude > 2 then
				target = liveTarget
				descentHeight = math.clamp(target.activationDistance * 0.25, 0.35, 1.5)
				approachPosition = target.position
					+ Vector3.new(0, descentHeight, 0)
					+ direction * lateralDistance
				if not moveTo(approachPosition, generation) then
					return false
				end
				liveTarget = findPromptTarget(target.prompt)
			end
			if liveTarget then
				local collected, reason = interactWithTarget(liveTarget, generation)
				if collected then
					return true
				end
				if reason ~= "not-visible" and reason ~= "out-of-range" then
					return false
				end
				target = liveTarget
			end
		end
	end
	return false
end

local function hasEnabledTargets()
	for _, targetName in ipairs(TARGET_NAMES) do
		if TARGET_ENABLED[targetName] then
			return true
		end
	end
	return false
end

local function stopAutomation(message)
	scanning = false
	scanGeneration += 1
	cancelCurrentAction()
	if setNoClip then
		pcall(setNoClip, false)
	end
	updateScannedHighlights({})
	updateToggleVisual()
	statusLabel.Text = message
end

startScanLoop = function(generation)
	task.spawn(function()
		while scanning and generation == scanGeneration and screenGui.Parent do
			local ok, scanError = pcall(function()
				local results = scanWorkspace()
				if not scanning or generation ~= scanGeneration then
					return
				end

				if #results > 0 then
					local target = results[1]
					lastItemPosition = target.position
					patrolRoute = {}
					patrolRouteIndex = 1
					statusLabel.Text = string.format(
						"Найдено: %d · цель: %s",
						#results,
						target.name
					)
					local activated = moveAndCollect(target, generation)
					targetRetryAfter[target.object] = os.clock() + (activated and 2 or 5)
				elseif not hasEnabledTargets() then
					statusLabel.Text = "Все фильтры выключены."
				else
					local root = getCurrentRootPart()
					if root then
						local searchPoint, pointIndex, pointCount = getNextLocalSearchPoint(root.Position)
						statusLabel.Text = string.format(
			"Предметов нет · круговой поиск %d/%d (до 1500 studs)",
							pointIndex,
							pointCount
						)
						moveTo(searchPoint, generation, true)
					end
				end
			end)
			if not ok then
				warn("[StudioItemFinder] Ошибка цикла сканирования: " .. tostring(scanError))
				stopAutomation("Ошибка сканирования: " .. tostring(scanError))
				break
			end
			task.wait(SCAN_INTERVAL)
		end
	end)
end

toggleAutomation = function()
	scanning = not scanning
	scanGeneration += 1
	local generation = scanGeneration
	updateToggleVisual()

	if scanning then
		local root = getCurrentRootPart()
		patrolCenter = root and root.Position or nil
		lastItemPosition = nil
		patrolRoute = {}
		patrolRouteIndex = 1
		if not hasEnabledTargets() then
			for _, targetName in ipairs(TARGET_NAMES) do
				TARGET_ENABLED[targetName] = true
				updateFilterButton(targetName)
			end
		end

		statusLabel.Text = "Запускаю сканирование..."
		task.defer(function()
			if not scanning or generation ~= scanGeneration then
				return
			end
			local noClipOk, noClipError = pcall(setNoClip, true)
			if not noClipOk then
				warn("[StudioItemFinder] Ошибка noclip: " .. tostring(noClipError))
			end
			if startScanLoop then
				startScanLoop(generation)
			else
				scanning = false
				scanGeneration += 1
				updateToggleVisual()
				statusLabel.Text = "Сканер не инициализирован."
			end
		end)
	else
		patrolRoute = {}
		patrolRouteIndex = 1
		patrolCenter = nil
		cancelCurrentAction()
		if setNoClip then
			pcall(setNoClip, false)
		end
		statusLabel.Text = "Авто-сбор остановлен."
		renderResults({})
		updateScannedHighlights({})
	end
end

for _, targetName in ipairs(TARGET_NAMES) do
	local button = filterButtons[targetName]
	button.Activated:Connect(function()
		TARGET_ENABLED[targetName] = not TARGET_ENABLED[targetName]
		updateFilterButton(targetName)
		if scanning then
			scanGeneration += 1
			cancelCurrentAction()
			startScanLoop(scanGeneration)
		elseif not TARGET_ENABLED[targetName] then
			statusLabel.Text = "Фильтр изменён · включите авто-сбор для поиска"
		end
	end)
end

player.CharacterRemoving:Connect(function(character)
	if currentCharacter == character then
		cancelCurrentAction()
		currentRootPart = nil
	end
end)

script.Destroying:Connect(function()
	scanning = false
	scanGeneration += 1
	cancelCurrentAction()
	if setNoClip then
		pcall(setNoClip, false)
	end
	updateScannedHighlights({})
	if collapseTween then
		collapseTween:Cancel()
	end
	if screenGui.Parent then
		screenGui:Destroy()
	end
end)
