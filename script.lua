-- Отладочный поиск предметов для собственного проекта в Roblox Studio.
-- Поместите этот LocalScript в StarterPlayer > StarterPlayerScripts.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local sessionStats = {}
local countedObjects = setmetatable({}, { __mode = "k" })
for _, targetName in ipairs(TARGET_NAMES) do
	sessionStats[targetName] = 0
end

local TARGET_ENABLED = {
	["Pure Rokakaka"] = true,
	["Mysterious Arrow"] = true,
	["Lucky Arrow"] = true,
	["Rokakaka"] = true,
	["Rib Cage of the Saint's Corpse"] = true,
	["Gold Coin"] = true,
	["Diamond"] = true,
	["Stone Mask"] = true,
	["Ancient Scroll"] = true,
	["Quinton's Glove"] = true,
	["Headband"] = true,
	["Steel Ball"] = true,
}

local SPAWN_POINTS = {
	Vector3.new(100, 10, 100),
	Vector3.new(-200, 15, 300),
	Vector3.new(50, 5, -400),
	Vector3.new(-50, 20, -50),
}

local SCAN_INTERVAL = 1
local TARGET_BLACKLIST_DURATION = 30
local MAX_RESULT_ROWS = 20
local scanning = false
local scanGeneration = 0
local currentHighlight = nil
local currentSpeed = 25
local currentSpawnIndex = 1
local emptySpawnLaps = 0
local targetBlacklist = {}
local activeTween = nil
local activePrompt = nil -- Для исправления бага с удержанием кнопки при выключении
local currentCharacter = nil
local currentRootPart = nil
local inputChangedConnection = nil
local inputEndedConnection = nil
local draggingPanel = false
local dragInputObject = nil
local dragStartPosition = nil
local frameStartPosition = nil
local characterReferenceAddedConnection = nil
local characterReferenceRemovingConnection = nil
local startScanLoop
local setNoClip
local stopAutomation

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

local screenGui = create("ScreenGui", {
	Name = "StudioItemFinder",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
}, playerGui)

local frame = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 20, 0.5, 0),
	Size = UDim2.fromOffset(300, 580),
	BackgroundColor3 = Color3.fromRGB(28, 30, 36),
	BorderSizePixel = 0,
}, screenGui)
local panelCorner = create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

local titleLabel = create("TextLabel", {
	Name = "Title",
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -88, 0, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Поиск предметов (Studio)",
	TextColor3 = Color3.fromRGB(240, 240, 245),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	Active = true,
}, frame)

local lockButton = create("TextButton", {
	Name = "DragLockButton",
	Position = UDim2.fromOffset(236, 8),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(48, 51, 60),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "🔓",
	TextColor3 = Color3.fromRGB(240, 240, 245),
	TextSize = 14,
}, frame)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, lockButton)

local collapseButton = create("TextButton", {
	Name = "CollapseButton",
	Position = UDim2.fromOffset(264, 8),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(48, 51, 60),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "-",
	TextColor3 = Color3.fromRGB(240, 240, 245),
	TextSize = 18,
}, frame)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, collapseButton)

local expandedPanelSize = frame.Size
local panelCollapsed = false
local collapseTween = nil

local function setPanelCollapsed(collapsed)
	panelCollapsed = collapsed
	collapseButton.Text = collapsed and "+" or "-"
	panelCorner.CornerRadius = collapsed and UDim.new(0, 20) or UDim.new(0, 8)

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject")
			and child ~= titleLabel
			and child ~= collapseButton
			and child ~= lockButton then
			child.Visible = not collapsed
		end
	end

	if collapseTween then
		collapseTween:Cancel()
	end
	local targetSize = collapsed and UDim2.fromOffset(300, 40) or expandedPanelSize
	collapseTween = TweenService:Create(
		frame,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	collapseTween:Play()
end

collapseButton.Activated:Connect(function()
	setPanelCollapsed(not panelCollapsed)
end)

local dragLocked = false
lockButton.Activated:Connect(function()
	dragLocked = not dragLocked
	lockButton.Text = dragLocked and "🔒" or "🔓"
	lockButton.BackgroundColor3 = dragLocked
		and Color3.fromRGB(105, 67, 67)
		or Color3.fromRGB(48, 51, 60)
	if dragLocked then
		draggingPanel = false
		dragInputObject = nil
	end
end)

titleLabel.InputBegan:Connect(function(input)
	if dragLocked then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingPanel = true
		dragInputObject = input.UserInputType == Enum.UserInputType.Touch and input or nil
		dragStartPosition = input.Position
		frameStartPosition = frame.Position
	end
end)

local refreshButton = create("TextButton", {
	Name = "RefreshButton",
	Position = UDim2.fromOffset(12, 44),
	Size = UDim2.fromOffset(128, 32),
	BackgroundColor3 = Color3.fromRGB(65, 91, 140),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Обновить",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 13,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, refreshButton)

local toggleButton = create("TextButton", {
	Name = "ToggleButton",
	Position = UDim2.fromOffset(150, 44),
	Size = UDim2.fromOffset(138, 32),
	BackgroundColor3 = Color3.fromRGB(60, 110, 78),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Авто-сбор: выкл",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 12,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, toggleButton)

local sliderFrame = create("Frame", {
	Name = "SliderFrame",
	Position = UDim2.fromOffset(12, 88),
	Size = UDim2.new(1, -24, 0, 40),
	BackgroundColor3 = Color3.fromRGB(35, 38, 45),
	BorderSizePixel = 0,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, sliderFrame)

local sliderLabel = create("TextLabel", {
	Name = "SliderLabel",
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Скорость полёта: 25 studs/s",
	TextColor3 = Color3.fromRGB(200, 200, 205),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, sliderFrame)

local sliderBtn = create("TextButton", {
	Name = "SliderBtn",
	Position = UDim2.new(0, 10, 0, 24),
	Size = UDim2.new(1, -20, 0, 8),
	BackgroundColor3 = Color3.fromRGB(55, 60, 70),
	Text = "",
}, sliderFrame)

local sliderFill = create("Frame", {
	Name = "Fill",
	Size = UDim2.new(0.44, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(100, 150, 240),
	BorderSizePixel = 0,
}, sliderBtn)

local statusLabel = create("TextLabel", {
	Name = "Status",
	Position = UDim2.fromOffset(12, 138),
	Size = UDim2.new(1, -24, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Нажмите «Авто-сбор» для запуска.",
	TextColor3 = Color3.fromRGB(190, 194, 205),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
}, frame)

local resultsFrame = create("ScrollingFrame", {
	Name = "Results",
	Position = UDim2.fromOffset(12, 168),
	Size = UDim2.new(1, -24, 1, -400),
	BackgroundColor3 = Color3.fromRGB(21, 23, 28),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 5,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, resultsFrame)

local statsLabel = create("TextLabel", {
	Name = "SessionStats",
	Position = UDim2.fromOffset(12, 358),
	Size = UDim2.new(1, -24, 0, 54),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = Color3.fromRGB(200, 204, 215),
	TextSize = 9,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, frame)

local function updateStatsLabel()
	local collected = {}

	for _, targetName in ipairs(TARGET_NAMES) do
		local count = sessionStats[targetName] or 0
		if count > 0 then
			table.insert(collected, string.format("%s ×%d", targetName, count))
		end
	end

	if #collected == 0 then
		statsLabel.Text = "Собрано за сессию: пока ничего"
	else
		statsLabel.Text = "Собрано за сессию: " .. table.concat(collected, " · ")
	end
end

updateStatsLabel()

local filterScrollingFrame = create("ScrollingFrame", {
	Name = "FilterScrollingFrame",
	Position = UDim2.fromOffset(12, 418),
	Size = UDim2.new(1, -24, 0, 150),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 350),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Color3.fromRGB(105, 110, 124),
}, frame)

create("TextLabel", {
	Name = "FilterTitle",
	Position = UDim2.fromOffset(6, 4),
	Size = UDim2.fromOffset(100, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Фильтр предметов",
	TextColor3 = Color3.fromRGB(200, 204, 215),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, filterScrollingFrame)

local enableAllButton = create("TextButton", {
	Name = "EnableAllButton",
	Position = UDim2.fromOffset(110, 4),
	Size = UDim2.fromOffset(76, 22),
	BackgroundColor3 = Color3.fromRGB(54, 93, 70),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Включить всё",
	TextColor3 = Color3.fromRGB(235, 237, 242),
	TextSize = 9,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, filterScrollingFrame)
create("UICorner", { CornerRadius = UDim.new(0, 5) }, enableAllButton)

local disableAllButton = create("TextButton", {
	Name = "DisableAllButton",
	Position = UDim2.fromOffset(190, 4),
	Size = UDim2.fromOffset(80, 22),
	BackgroundColor3 = Color3.fromRGB(74, 55, 55),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "Выключить всё",
	TextColor3 = Color3.fromRGB(235, 237, 242),
	TextSize = 9,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, filterScrollingFrame)
create("UICorner", { CornerRadius = UDim.new(0, 5) }, disableAllButton)

local filterButtons = {}
local filterDefinitions = {
	{ name = "Pure Rokakaka", position = UDim2.fromOffset(6, 34) },
	{ name = "Mysterious Arrow", position = UDim2.fromOffset(6, 60) },
	{ name = "Lucky Arrow", position = UDim2.fromOffset(6, 86) },
	{ name = "Rokakaka", position = UDim2.fromOffset(6, 112) },
	{ name = "Rib Cage of the Saint's Corpse", position = UDim2.fromOffset(6, 138) },
	{ name = "Gold Coin", position = UDim2.fromOffset(6, 164) },
	{ name = "Diamond", position = UDim2.fromOffset(6, 190) },
	{ name = "Stone Mask", position = UDim2.fromOffset(6, 216) },
	{ name = "Ancient Scroll", position = UDim2.fromOffset(6, 242) },
	{ name = "Quinton's Glove", position = UDim2.fromOffset(6, 268) },
	{ name = "Headband", position = UDim2.fromOffset(6, 294) },
	{ name = "Steel Ball", position = UDim2.fromOffset(6, 320) },
}

for _, definition in ipairs(filterDefinitions) do
	local targetName = definition.name
	local enabled = TARGET_ENABLED[targetName]
	local button = create("TextButton", {
		Name = "Filter_" .. string.gsub(targetName, "%W", ""),
		Position = definition.position,
		Size = UDim2.new(1, -18, 0, 22),
		BackgroundColor3 = enabled and Color3.fromRGB(54, 93, 70) or Color3.fromRGB(48, 51, 60),
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = (enabled and "[✓] " or "[ ] ") .. targetName,
		TextColor3 = Color3.fromRGB(235, 237, 242),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, filterScrollingFrame)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, button)
	filterButtons[targetName] = button
end

local listLayout = create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, resultsFrame)
create("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, resultsFrame)

local resultRowPool = {}
for index = 1, MAX_RESULT_ROWS do
	local row = create("TextLabel", {
		Name = "Result" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, -4, 0, 34),
		BackgroundColor3 = Color3.fromRGB(34, 36, 43),
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(232, 234, 240),
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, resultsFrame)
	resultRowPool[index] = row
end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	resultsFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 12)
end)

local holdingSlider = false
local function updateSlider(input)
	local percentage = math.clamp((input.Position.X - sliderBtn.AbsolutePosition.X) / sliderBtn.AbsoluteSize.X, 0, 1)
	sliderFill.Size = UDim2.new(percentage, 0, 1, 0)
	currentSpeed = math.round(5 + (percentage * 45))
	sliderLabel.Text = "Скорость полёта: " .. currentSpeed .. " studs/s"
end

sliderBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holdingSlider = true
		updateSlider(input)
	end
end)

inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
	if holdingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateSlider(input)
	end
	if draggingPanel and not dragLocked
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInputObject) then
		local delta = input.Position - dragStartPosition
		frame.Position = UDim2.new(
			frameStartPosition.X.Scale,
			frameStartPosition.X.Offset + delta.X,
			frameStartPosition.Y.Scale,
			frameStartPosition.Y.Offset + delta.Y
		)
	end
end)

inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holdingSlider = false
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInputObject then
		draggingPanel = false
		dragInputObject = nil
	end
end)

local function findTargetName(objectName)
	local loweredName = string.lower(objectName)
	for _, targetName in ipairs(TARGET_NAMES) do
		if string.find(loweredName, string.lower(targetName), 1, true) then
			return targetName
		end
	end
	return nil
end

local function getHighlightAdornee(object)
	if object:IsA("Model") or object:IsA("BasePart") then
		return object
	end
	local containingModel = object:FindFirstAncestorOfClass("Model")
	if containingModel then
		return containingModel
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- Исправление бага с Attachment: корректно определяем мировую позицию для любых объектов
local function getObjectWorldPosition(object)
	if object:IsA("BasePart") then
		return object.Position
	elseif object:IsA("Attachment") then
		return object.WorldPosition
	elseif object:IsA("Model") then
		return object:GetPivot().Position
	end
	return nil
end

local function getPromptData(object)
	local prompt = object:FindFirstChildOfClass("ProximityPrompt") or (object.Parent and object.Parent:FindFirstChildOfClass("ProximityPrompt"))
	if not prompt then
		for _, desc in ipairs(object:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then prompt = desc break end
		end
	end
	return prompt
end

local function clearResults()
	for _, row in ipairs(resultRowPool) do
		row.Visible = false
		row.Text = ""
	end
end

local function updateHighlight(adornee)
	if not adornee then
		if currentHighlight then
			currentHighlight:Destroy()
			currentHighlight = nil
		end
		return
	end

	if not currentHighlight or not currentHighlight.Parent then
		currentHighlight = create("Highlight", {
			Name = "StudioItemFinderHighlight",
			FillColor = Color3.fromRGB(255, 196, 70),
			OutlineColor = Color3.fromRGB(255, 240, 190),
			FillTransparency = 0.55,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}, Workspace)
	end
	currentHighlight.Adornee = adornee
	currentHighlight.Enabled = true
end

local function interactWithObject(object, detectedTargetName)
	local prompt = getPromptData(object)
	if prompt and prompt.Enabled then
		activePrompt = prompt
		statusLabel.Text = "Активация взаимодействия..."
		task.wait(0.1)
		if scanning and activePrompt == prompt then
			prompt:InputHoldBegin()
			task.wait(prompt.HoldDuration + 0.05)
			if activePrompt == prompt then
				prompt:InputHoldEnd()

				local targetName = findTargetName(detectedTargetName or "")
					or findTargetName(object.Name)
				if targetName
					and sessionStats[targetName] ~= nil
					and not countedObjects[object] then
					countedObjects[object] = true
					sessionStats[targetName] += 1
					updateStatsLabel()
				end
			end
		end
		activePrompt = nil
	end
end

local function scanWorkspace(allowMovement)
	clearResults()

	local rootPart = currentRootPart
	if not rootPart or not rootPart.Parent or currentCharacter ~= player.Character then
		statusLabel.Text = "Ожидаю персонажа и HumanoidRootPart..."
		return
	end

	local hasEnabledTargets = false
	for _, targetName in ipairs(TARGET_NAMES) do
		if TARGET_ENABLED[targetName] then
			hasEnabledTargets = true
			break
		end
	end

	local foundByObject = {}
	local results = {}
	local scanTime = os.clock()

	for adornee, expiresAt in pairs(targetBlacklist) do
		if expiresAt <= scanTime or not adornee:IsDescendantOf(Workspace) then
			targetBlacklist[adornee] = nil
		end
	end

	for _, object in ipairs(Workspace:GetDescendants()) do
		local targetName = findTargetName(object.Name)
		if targetName and TARGET_ENABLED[targetName] then
			local adornee = getHighlightAdornee(object)
			local blockedUntil = adornee and targetBlacklist[adornee]
			if adornee and not blockedUntil and not foundByObject[adornee] then
				foundByObject[adornee] = true
				
				local prompt = getPromptData(adornee)
				local targetObject = prompt and prompt.Parent or adornee
				local position = getObjectWorldPosition(targetObject)
				
				if position then
					local distance = (rootPart.Position - position).Magnitude
					local actDistance = prompt and prompt.MaxActivationDistance or 8
					
					table.insert(results, {
						adornee = adornee,
						distance = distance,
						name = targetName,
						objectName = adornee.Name,
						position = position,
						activationDistance = actDistance
					})
				end
			end
		end
	end

	table.sort(results, function(a, b)
		if a.distance and b.distance then return a.distance < b.distance
		elseif a.distance then return true
		elseif b.distance then return false end
		return a.name < b.name
	end)

	local nearest = results[1]
	if nearest then
		emptySpawnLaps = 0
	end
	updateHighlight(nearest and nearest.adornee or nil)

	if not hasEnabledTargets then
		statusLabel.Text = "Все фильтры выключены. Включите хотя бы один предмет."
	elseif #results == 0 then
		statusLabel.Text = (scanning and allowMovement ~= false) and "Предметы не найдены. Перехожу к точкам сканирования..." or "Предметы не найдены."
	else
		statusLabel.Text = string.format("Найдено: %d · лечу к ближайшему", #results)
	end

	-- Перезаполняем уже созданные строки, не создавая новые GUI-объекты при каждом скане.
	for index = 1, math.min(#results, MAX_RESULT_ROWS) do
		local result = results[index]
		local row = resultRowPool[index]
		local distanceText = result.distance and string.format("%.0f studs", result.distance) or "неизвестно"
		row.LayoutOrder = index
		row.BackgroundColor3 = index == 1 and Color3.fromRGB(56, 52, 39) or Color3.fromRGB(34, 36, 43)
		row.Text = string.format("%s · %s · %s", result.name, result.objectName, distanceText)
		row.Visible = true
	end

	if scanning and allowMovement ~= false and hasEnabledTargets then
		local targetPosition = nil
		local actDist = 8

		if nearest then
			targetPosition = nearest.position
			actDist = nearest.activationDistance
		elseif #SPAWN_POINTS > 0 then
			targetPosition = SPAWN_POINTS[currentSpawnIndex]
			if (rootPart.Position - targetPosition).Magnitude < 12 then
				currentSpawnIndex += 1
				if currentSpawnIndex > #SPAWN_POINTS then
					currentSpawnIndex = 1
					emptySpawnLaps += 1
					if emptySpawnLaps >= 3 then
						statusLabel.Text = "Сервер пуст. Смена сервера требует серверного обработчика."
						return
					end
				end
				targetPosition = SPAWN_POINTS[currentSpawnIndex]
			end
		end

		local function moveTo(position, blockedTarget)
			if not scanning or currentRootPart ~= rootPart then
				return false, false
			end

			local distance = (rootPart.Position - position).Magnitude
			local duration = distance / currentSpeed
			local timeoutAt = os.clock() + duration + 2
			local tween = TweenService:Create(
				rootPart,
				TweenInfo.new(duration, Enum.EasingStyle.Linear),
				{ CFrame = CFrame.new(position) }
			)
			local finished = false
			local playbackState = nil
			local completedConnection = tween.Completed:Connect(function(state)
				playbackState = state
				finished = true
			end)

			activeTween = tween
			tween:Play()

			while not finished
				and scanning
				and activeTween == tween
				and currentRootPart == rootPart
				and os.clock() < timeoutAt do
				task.wait(0.05)
			end

			local timedOut = not finished
				and scanning
				and activeTween == tween
				and currentRootPart == rootPart
				and os.clock() >= timeoutAt

			if not finished then
				tween:Cancel()
				playbackState = Enum.PlaybackState.Cancelled
			end
			completedConnection:Disconnect()

			if activeTween == tween then
				activeTween = nil
			end

			if finished
				and playbackState == Enum.PlaybackState.Completed
				and (rootPart.Position - position).Magnitude > 1.5 then
				timedOut = true
			end

			if timedOut and blockedTarget and blockedTarget:IsDescendantOf(Workspace) then
				targetBlacklist[blockedTarget] = os.clock() + TARGET_BLACKLIST_DURATION
				statusLabel.Text = "Цель недоступна. Пропускаю её на 30 секунд."
			end

			return scanning and playbackState == Enum.PlaybackState.Completed and not timedOut, timedOut
		end

		local function getCurrentTargetState(adornee)
			if not adornee or not adornee:IsDescendantOf(Workspace) then
				return nil, nil
			end
			local prompt = getPromptData(adornee)
			local targetObject = prompt and prompt.Parent or adornee
			return getObjectWorldPosition(targetObject), prompt
		end

		if targetPosition then
			if nearest then
				local currentPosition, currentPrompt = getCurrentTargetState(nearest.adornee)
				if not currentPosition then
					return scanWorkspace(true)
				end
				targetPosition = currentPosition
				actDist = currentPrompt and currentPrompt.MaxActivationDistance or actDist

				local descentOffset = math.min(0.5, actDist * 0.25)
				local interactionPosition = targetPosition + Vector3.new(0, descentOffset, 0)
				local horizontalOffset = Vector3.new(
					rootPart.Position.X - targetPosition.X,
					0,
					rootPart.Position.Z - targetPosition.Z
				)
				local distanceToInteraction = (rootPart.Position - interactionPosition).Magnitude
				local withinActivationDistance = (rootPart.Position - targetPosition).Magnitude
					<= math.max(0, actDist - 0.5)

				if horizontalOffset.Magnitude <= 0.25
					and distanceToInteraction <= 0.25
					and withinActivationDistance then
					local validatedPosition, validatedPrompt = getCurrentTargetState(nearest.adornee)
					local validatedDistance = validatedPrompt and validatedPrompt.MaxActivationDistance or actDist
					if validatedPosition
						and (validatedPosition - targetPosition).Magnitude <= 2
						and (rootPart.Position - validatedPosition).Magnitude <= math.max(0, validatedDistance - 0.5) then
						interactWithObject(nearest.adornee, nearest.name)
						return
					end
				end

				local readyToDescend = false
				for _ = 1, 4 do
					local latestPosition, latestPrompt = getCurrentTargetState(nearest.adornee)
					if not latestPosition then
						return scanWorkspace(true)
					end
					actDist = latestPrompt and latestPrompt.MaxActivationDistance or actDist
					targetPosition = latestPosition

					local hoverPosition = targetPosition + Vector3.new(0, 4.5, 0)
					if (rootPart.Position - hoverPosition).Magnitude > 0.25 then
						local arrived, timedOut = moveTo(hoverPosition, nearest.adornee)
						if timedOut then
							return scanWorkspace(true)
						end
						if not arrived then
							return
						end
					else
						local beforeDescent, beforePrompt = getCurrentTargetState(nearest.adornee)
						if not beforeDescent then
							return scanWorkspace(true)
						end
						actDist = beforePrompt and beforePrompt.MaxActivationDistance or actDist
						if (beforeDescent - targetPosition).Magnitude <= 2 then
							targetPosition = beforeDescent
							readyToDescend = true
							break
						end
						targetPosition = beforeDescent
					end
				end

				if not readyToDescend then
					return
				end

				local beforeDescent, beforePrompt = getCurrentTargetState(nearest.adornee)
				if not beforeDescent then
					return scanWorkspace(true)
				end
				actDist = beforePrompt and beforePrompt.MaxActivationDistance or actDist
				if (beforeDescent - targetPosition).Magnitude > 2 then
					local correctedHover = beforeDescent + Vector3.new(0, 4.5, 0)
					local arrived, timedOut = moveTo(correctedHover, nearest.adornee)
					if timedOut then
						return scanWorkspace(true)
					end
					if not arrived then
						return
					end
					return
				end

				targetPosition = beforeDescent
				descentOffset = math.min(0.5, actDist * 0.25)
				interactionPosition = targetPosition + Vector3.new(0, descentOffset, 0)
				local arrived, timedOut = moveTo(interactionPosition, nearest.adornee)
				if timedOut then
					return scanWorkspace(true)
				end
				if arrived then
					local finalPosition, finalPrompt = getCurrentTargetState(nearest.adornee)
					local finalActivationDistance = finalPrompt and finalPrompt.MaxActivationDistance or actDist
					if finalPosition
						and (finalPosition - targetPosition).Magnitude <= 2
						and (rootPart.Position - finalPosition).Magnitude <= math.max(0, finalActivationDistance - 0.5) then
						interactWithObject(nearest.adornee, nearest.name)
					end
				end
			else
				moveTo(targetPosition)
			end
		end
	end
end

local function cancelCurrentAction()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if activePrompt then
		pcall(function()
			activePrompt:InputHoldEnd()
		end)
		activePrompt = nil
	end
end

startScanLoop = function()
	local thisGeneration = scanGeneration
	task.spawn(function()
		while scanning and scanGeneration == thisGeneration and screenGui.Parent do
			local ok, scanError = pcall(scanWorkspace, true)
			if not ok then
				warn("[StudioItemFinder] Ошибка сканирования: " .. tostring(scanError))
				stopAutomation("Ошибка сканирования: " .. tostring(scanError))
				break
			end
			if scanning and emptySpawnLaps >= 3 then
				stopAutomation("Сервер пуст. Смена сервера требует серверного обработчика.")
				break
			end
			task.wait(SCAN_INTERVAL)
		end
	end)
end

local function updateFilterButton(targetName)
	local button = filterButtons[targetName]
	if not button then
		return
	end
	local enabled = TARGET_ENABLED[targetName]
	button.Text = (enabled and "[✓] " or "[ ] ") .. targetName
	button.BackgroundColor3 = enabled
		and Color3.fromRGB(54, 93, 70)
		or Color3.fromRGB(48, 51, 60)
end

local function refreshAfterFilterChange()
	emptySpawnLaps = 0
	local hasEnabledTargets = false
	for _, targetName in ipairs(TARGET_NAMES) do
		if TARGET_ENABLED[targetName] then
			hasEnabledTargets = true
			break
		end
	end
	if not hasEnabledTargets then
		clearResults()
		updateHighlight(nil)
		statusLabel.Text = "Все фильтры выключены. Включите хотя бы один предмет."
	end

	if scanning then
		scanGeneration += 1
		cancelCurrentAction()
		startScanLoop()
	else
		local ok, scanError = pcall(scanWorkspace, false)
		if not ok then
			warn("[StudioItemFinder] Ошибка сканирования: " .. tostring(scanError))
			statusLabel.Text = "Ошибка сканирования: " .. tostring(scanError)
		end
	end
end

for targetName, button in pairs(filterButtons) do
	button.Activated:Connect(function()
		TARGET_ENABLED[targetName] = not TARGET_ENABLED[targetName]
		updateFilterButton(targetName)
		refreshAfterFilterChange()
	end)
end

enableAllButton.Activated:Connect(function()
	for _, targetName in ipairs(TARGET_NAMES) do
		TARGET_ENABLED[targetName] = true
		updateFilterButton(targetName)
	end
	refreshAfterFilterChange()
end)

disableAllButton.Activated:Connect(function()
	for _, targetName in ipairs(TARGET_NAMES) do
		TARGET_ENABLED[targetName] = false
		updateFilterButton(targetName)
	end
	refreshAfterFilterChange()
end)

local function updateCharacterReferences(character)
	scanGeneration += 1
	cancelCurrentAction()
	currentCharacter = character
	currentRootPart = nil

	task.spawn(function()
		local rootPart = character:WaitForChild("HumanoidRootPart")
		if player.Character ~= character or currentCharacter ~= character then
			return
		end
		currentRootPart = rootPart
		if scanning then
			startScanLoop()
		end
	end)
end

characterReferenceAddedConnection = player.CharacterAdded:Connect(updateCharacterReferences)
characterReferenceRemovingConnection = player.CharacterRemoving:Connect(function(character)
	if currentCharacter ~= character then
		return
	end
	scanGeneration += 1
	cancelCurrentAction()
	currentCharacter = nil
	currentRootPart = nil
end)

if player.Character then
	updateCharacterReferences(player.Character)
end

local noClipEnabled = false
local originalCanCollide = {}
local characterAddedConnection = nil
local descendantAddedConnection = nil

local function restoreNoClipCollisions()
	for part, canCollide in pairs(originalCanCollide) do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	table.clear(originalCanCollide)
end

local function applyNoClip(character)
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end
	restoreNoClipCollisions()

	local function disableCollision(instance)
		if not instance:IsA("BasePart") then
			return
		end
		if originalCanCollide[instance] == nil then
			originalCanCollide[instance] = instance.CanCollide
		end
		instance.CanCollide = false
	end

	for _, instance in ipairs(character:GetDescendants()) do
		disableCollision(instance)
	end
	descendantAddedConnection = character.DescendantAdded:Connect(disableCollision)
end

setNoClip = function(enabled)
	if noClipEnabled == enabled then
		return
	end
	noClipEnabled = enabled

	if enabled then
		if player.Character then
			applyNoClip(player.Character)
		end
		characterAddedConnection = player.CharacterAdded:Connect(function(character)
			if noClipEnabled then
				applyNoClip(character)
			end
		end)
	else
		if characterAddedConnection then
			characterAddedConnection:Disconnect()
			characterAddedConnection = nil
		end
		if descendantAddedConnection then
			descendantAddedConnection:Disconnect()
			descendantAddedConnection = nil
		end
		restoreNoClipCollisions()
	end
end

stopAutomation = function(message)
	if not scanning then
		return
	end
	scanning = false
	scanGeneration += 1
	setNoClip(false)
	cancelCurrentAction()
	toggleButton.Text = "Авто-сбор: выкл"
	toggleButton.BackgroundColor3 = Color3.fromRGB(60, 110, 78)
	statusLabel.Text = message
	updateHighlight(nil)
end

script.Destroying:Connect(function()
	scanning = false
	scanGeneration += 1
	cancelCurrentAction()
	setNoClip(false)

	if inputChangedConnection then
		inputChangedConnection:Disconnect()
		inputChangedConnection = nil
	end
	if inputEndedConnection then
		inputEndedConnection:Disconnect()
		inputEndedConnection = nil
	end
	if characterReferenceAddedConnection then
		characterReferenceAddedConnection:Disconnect()
		characterReferenceAddedConnection = nil
	end
	if characterReferenceRemovingConnection then
		characterReferenceRemovingConnection:Disconnect()
		characterReferenceRemovingConnection = nil
	end
	if collapseTween then
		collapseTween:Cancel()
		collapseTween = nil
	end
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	if screenGui.Parent then
		screenGui:Destroy()
	end
end)
refreshButton.Activated:Connect(function()
	local ok, scanError = pcall(scanWorkspace, false)
	if not ok then
		warn("[StudioItemFinder] Ошибка сканирования: " .. tostring(scanError))
		statusLabel.Text = "Ошибка сканирования: " .. tostring(scanError)
	end
end)

toggleButton.Activated:Connect(function()
	scanning = not scanning
	if scanning then
		emptySpawnLaps = 0
	end
	setNoClip(scanning)
	scanGeneration += 1
	toggleButton.Text = scanning and "Авто-сбор: вкл" or "Авто-сбор: выкл"
	toggleButton.BackgroundColor3 = scanning
		and Color3.fromRGB(130, 91, 49)
		or Color3.fromRGB(60, 110, 78)

	if scanning then
		statusLabel.Text = "Сканирование запущено..."
		startScanLoop()
	else
		cancelCurrentAction()
		statusLabel.Text = "Автоматизация остановлена."
		updateHighlight(nil)
	end
end)


