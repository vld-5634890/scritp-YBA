-- Отладочный поиск предметов для собственного проекта в Roblox Studio.
-- Поместите этот LocalScript в StarterPlayer > StarterPlayerScripts.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TARGET_NAMES = {
	"Pure Rokakaka",
	"Mysterious Arrow",
	"Lucky Arrow",
	"Rokakaka",
}

local SPAWN_POINTS = {
	Vector3.new(100, 10, 100),
	Vector3.new(-200, 15, 300),
	Vector3.new(50, 5, -400),
	Vector3.new(-50, 20, -50),
}

local SCAN_INTERVAL = 1
local scanning = false
local scanGeneration = 0
local currentHighlight = nil
local currentSpeed = 25
local currentSpawnIndex = 1
local activeTween = nil
local activePrompt = nil -- Для исправления бага с удержанием кнопки при выключении

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties) do
		instance[property] = value
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
	Size = UDim2.fromOffset(300, 370),
	BackgroundColor3 = Color3.fromRGB(28, 30, 36),
	BorderSizePixel = 0,
}, screenGui)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

create("TextLabel", {
	Name = "Title",
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Поиск предметов (Studio)",
	TextColor3 = Color3.fromRGB(240, 240, 245),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
}, frame)

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
	Size = UDim2.new(1, -24, 1, -180),
	BackgroundColor3 = Color3.fromRGB(21, 23, 28),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 5,
}, frame)
create("UICorner", { CornerRadius = UDim.new(0, 6) }, resultsFrame)

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

game:GetService("UserInputService").InputChanged:Connect(function(input)
	if holdingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateSlider(input)
	end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holdingSlider = false
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
	for _, child in ipairs(resultsFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function updateHighlight(adornee)
	if not currentHighlight then
		currentHighlight = create("Highlight", {
			Name = "StudioItemFinderHighlight",
			FillColor = Color3.fromRGB(255, 196, 70),
			OutlineColor = Color3.fromRGB(255, 240, 190),
			FillTransparency = 0.55,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}, Workspace)
	end
	currentHighlight.Adornee = adornee
end

local function interactWithObject(object)
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
			end
		end
		activePrompt = nil
	end
end

local function scanWorkspace(allowMovement)
	clearResults()

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local foundByObject = {}
	local results = {}

	for _, object in ipairs(Workspace:GetDescendants()) do
		local targetName = findTargetName(object.Name)
		if targetName then
			local adornee = getHighlightAdornee(object)
			if adornee and not foundByObject[adornee] then
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
	updateHighlight(nearest and nearest.adornee or nil)

	if #results == 0 then
		statusLabel.Text = (scanning and allowMovement ~= false) and "Предметы не найдены. Перехожу к точкам сканирования..." or "Предметы не найдены."
	else
		statusLabel.Text = string.format("Найдено: %d · лечу к ближайшему", #results)
	end

	-- Исправление бага с сортировкой списка: жестко задаем LayoutOrder = index
	for index, result in ipairs(results) do
		local distanceText = result.distance and string.format("%.0f studs", result.distance) or "неизвестно"
		create("TextLabel", {
			Name = "Result" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1, -4, 0, 34),
			BackgroundColor3 = index == 1 and Color3.fromRGB(56, 52, 39) or Color3.fromRGB(34, 36, 43),
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			Text = string.format("%s · %s · %s", result.name, result.objectName, distanceText),
			TextColor3 = Color3.fromRGB(232, 234, 240),
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, resultsFrame)
	end

	if scanning and allowMovement ~= false then
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
				end
				targetPosition = SPAWN_POINTS[currentSpawnIndex]
			end
		end

		if targetPosition then
			local distance = (rootPart.Position - targetPosition).Magnitude
			local duration = distance / currentSpeed
			local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(rootPart, tweenInfo, {
				CFrame = CFrame.new(targetPosition),
			})
			activeTween = tween
			tween:Play()

			if nearest and distance <= math.max(0, actDist - 0.5) then
				tween:Cancel()
				if activeTween == tween then
					activeTween = nil
				end
				interactWithObject(nearest.adornee)
			else
				tween.Completed:Wait()
				if activeTween == tween then
					activeTween = nil
				end
			end
		end
	end
end

refreshButton.Activated:Connect(function()
	scanWorkspace(false)
end)

toggleButton.Activated:Connect(function()
	scanning = not scanning
	scanGeneration += 1
	toggleButton.Text = scanning and "Авто-сбор: вкл" or "Авто-сбор: выкл"
	toggleButton.BackgroundColor3 = scanning
		and Color3.fromRGB(130, 91, 49)
		or Color3.fromRGB(60, 110, 78)

	if scanning then
		local thisGeneration = scanGeneration
		task.spawn(function()
			while scanning and scanGeneration == thisGeneration and screenGui.Parent do
				scanWorkspace(true)
				task.wait(SCAN_INTERVAL)
			end
		end)
	else
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		if activePrompt then
			activePrompt:InputHoldEnd()
			activePrompt = nil
		end
		statusLabel.Text = "Автоматизация остановлена."
		updateHighlight(nil)
	end
end)
