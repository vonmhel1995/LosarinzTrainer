--[[
	LosarinzUI — custom dashboard UI, Rayfield-compatible.
	Implements the API surface AutoBreakEggs uses: CreateWindow, CreateTab,
	CreateToggle, CreateDropdown, CreateSlider, CreateInput, CreateButton,
	CreateSection, CreateParagraph (:Set), Notify, Flags, LoadConfiguration,
	Destroy. Flag values save to the executor workspace as JSON.
]]
local LOSARINZ_UI_URL = "https://raw.githubusercontent.com/vonmhel1995/LosarinzTrainer/main/LosarinzUI.luau"
local MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/vonmhel1995/LosarinzTrainer/main/AutoBreakEggs.lua"
local LosarinzUI = {}

-- Theme. Accent is swappable at runtime through Change Theme.
local THEME = {
	accent = Color3.fromRGB(138, 66, 255),
	accentDark = Color3.fromRGB(88, 36, 180),
	window = Color3.fromRGB(12, 7, 20),
	card = Color3.fromRGB(24, 15, 38),
	row = Color3.fromRGB(18, 11, 30),
	text = Color3.fromRGB(235, 228, 250),
	dim = Color3.fromRGB(150, 140, 175),
	stroke = Color3.fromRGB(110, 50, 220),
}
local THEME_NAMES = {
	Purple = Color3.fromRGB(138, 66, 255),
	Blue = Color3.fromRGB(66, 140, 255),
	Green = Color3.fromRGB(70, 220, 140),
	Red = Color3.fromRGB(255, 80, 90),
	Pink = Color3.fromRGB(255, 90, 200),
}
local themeName = "Purple"

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

-- Helpers ----------------------------------------------------------------

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function stroke(parent, color, transparency, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or THEME.stroke
	s.Transparency = transparency or 0.55
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

local function label(parent, text, size, color, weight, xalign, yalign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 14
	l.TextColor3 = color or THEME.text
	l.Font = weight == "b" and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = xalign or Enum.TextXAlignment.Left
	l.TextYAlignment = yalign or Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function pad(parent, px, py)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px or 12)
	p.PaddingRight = UDim.new(0, px or 12)
	p.PaddingTop = UDim.new(0, py or 8)
	p.PaddingBottom = UDim.new(0, py or 8)
	p.Parent = parent
	return p
end

local function list(parent, gap)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function accentTween(instance, propTable)
	TweenService:Create(instance, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), propTable):Play()
end

-- Module state -----------------------------------------------------------

local activityLog = {}
local activityListeners = {}
local sessionStarted = os.clock()
local currentThemeName = themeName

local function logActivity(kind, text)
	local entry = { kind = kind, text = text, at = os.time() }
	table.insert(activityLog, 1, entry)
	while #activityLog > 20 do
		table.remove(activityLog)
	end
	for _, fn in ipairs(activityListeners) do
		pcall(fn, entry)
	end
end

-- Compat object ----------------------------------------------------------

function LosarinzUI.CreateRayfieldCompat()
	local flags = {}

	-- root gui
	local parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "LosarinzTrainer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	gui.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Parent = gui
	if gui.AbsoluteSize.Y > 0 then
		scale.Scale = math.clamp(gui.AbsoluteSize.Y / 700, 0.65, 1)
	end

	-- window frame
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(920, 620)
	root.Position = UDim2.new(0.5, -460, 0.5, -310)
	root.BackgroundColor3 = THEME.window
	root.Visible = false
	root.Parent = gui
	corner(root, 14)
	local rootStroke = stroke(root, THEME.accent, 0.35, 1.5)

	-- window drag
	local dragging, dragStart, startPos
	local titleBarHit = nil -- assigned after title bar exists
	titleBarHit = root
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = root.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	-- visibility
	local window = { Flags = flags, Name = "Losarinz Trainer", _visible = false, _tabs = {} }
	local openCallbacks = {}
	local configFolder, configFile = "AutoBreakEggs", "AutoBreakEggs/settings.json"

	local function setFlagValue(flagName, value)
		local entry = flags[flagName]
		if entry and entry.Set then
			entry.Set(value)
		end
	end

	local function setVisible(state)
		window._visible = state
		root.Visible = state
	end

	function window:Toggle()
		setVisible(not window._visible)
		if window._visible then
			logActivity("ok", "Menu opened")
		end
	end

	---Rayfield-style entry: applies the window config and returns the same object.
	function window:CreateWindow(data)
		if type(data) == "table" then
			window.Name = data.Name or window.Name
			local saving = data.ConfigurationSaving
			if type(saving) == "table" then
				configFolder = tostring(saving.FolderName or configFolder)
				configFile = configFolder .. "/" .. (tostring(saving.FileName or "settings") .. ".json")
			end
		end
		return window
	end

	function window:Show()
		setVisible(true)
	end

	function window:Destroy()
		gui:Destroy()
	end

	-- sidebar ------------------------------------------------------------

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 210, 1, -24)
	sidebar.Position = UDim2.fromOffset(12, 12)
	sidebar.BackgroundColor3 = THEME.card
	sidebar.Parent = root
	corner(sidebar, 12)
	stroke(sidebar, THEME.stroke, 0.7)

	do
		local logo = Instance.new("Frame")
		logo.Size = UDim2.new(1, -16, 0, 74)
		logo.Position = UDim2.fromOffset(8, 12)
		logo.BackgroundTransparency = 1
		logo.Parent = sidebar

		local l1 = label(logo, "LOSARINZ", 22, THEME.accent, "b", Enum.TextXAlignment.Center)
		l1.Size = UDim2.new(1, 0, 0, 26)
		l1.Position = UDim2.fromOffset(0, 8)
		local l2 = label(logo, "TRAINER", 20, THEME.text, "b", Enum.TextXAlignment.Center)
		l2.Size = UDim2.new(1, 0, 0, 24)
		l2.Position = UDim2.fromOffset(0, 32)
		local l3 = label(logo, "v1.0.0", 12, THEME.dim, nil, Enum.TextXAlignment.Center)
		l3.Size = UDim2.new(1, 0, 0, 14)
		l3.Position = UDim2.fromOffset(0, 56)
	end

	local nav = Instance.new("ScrollingFrame")
	nav.Size = UDim2.new(1, -16, 1, -160)
	nav.Position = UDim2.fromOffset(8, 94)
	nav.BackgroundTransparency = 1
	nav.BorderSizePixel = 0
	nav.ScrollBarThickness = 2
	nav.ScrollBarImageColor3 = THEME.accent
	nav.CanvasSize = UDim2.new()
	nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
	nav.Parent = sidebar
	list(nav, 6)

	local credit = Instance.new("Frame")
	credit.Size = UDim2.new(1, -16, 0, 52)
	credit.Position = UDim2.new(0, 8, 1, -64)
	credit.BackgroundColor3 = THEME.row
	credit.Parent = sidebar
	corner(credit, 10)
	stroke(credit, THEME.stroke, 0.7)
	do
		local crown = label(credit, "👑", 16, Color3.fromRGB(255, 200, 80), nil, Enum.TextXAlignment.Center)
		crown.Size = UDim2.new(1, 0, 0, 18)
		crown.Position = UDim2.fromOffset(0, 4)
		local d1 = label(credit, "Developed by", 11, THEME.dim, nil, Enum.TextXAlignment.Center)
		d1.Size = UDim2.new(1, 0, 0, 14)
		d1.Position = UDim2.fromOffset(0, 22)
		local d2 = label(credit, "Losarinz", 13, THEME.accent, "b", Enum.TextXAlignment.Center)
		d2.Size = UDim2.new(1, 0, 0, 16)
		d2.Position = UDim2.fromOffset(0, 34)
	end

	-- content host --------------------------------------------------------

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -252, 1, -24)
	content.Position = UDim2.fromOffset(234, 12)
	content.BackgroundColor3 = THEME.window
	content.Parent = root

	local pages = {} -- name -> scrolling frame
	local navButtons = {}
	local navMeta = {} -- name -> {label, stroke} (instances can't hold custom fields)
	local activePage = nil
	local windowRef = window

	local TITLE_BAR = 46

	do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, TITLE_BAR)
		bar.BackgroundColor3 = THEME.card
		bar.Parent = content
		corner(bar, 12)
		stroke(bar, THEME.stroke, 0.7)
		pad(bar, 14, 6)

		local title = label(bar, "Losarinz Trainer", 15, THEME.text, "b")
		title.Size = UDim2.new(0, 200, 1, 0)

		local function winButton(x, glyph, onClick)
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(28, 28)
			b.Position = UDim2.new(1, x, 0, 9)
			b.BackgroundColor3 = THEME.row
			b.Text = glyph
			b.TextSize = 13
			b.TextColor3 = THEME.text
			b.Font = Enum.Font.GothamBold
			b.AutoButtonColor = true
			b.Parent = bar
			corner(b, 8)
			b.MouseButton1Click:Connect(onClick)
			return b
		end

		winButton(-38, "—", function()
			window:Toggle()
		end)
		winButton(-72, "▣", function()
			root.Position = UDim2.new(0.5, -460, 0.5, -310)
		end)
		winButton(-106, "✕", function()
			setVisible(false)
			logActivity("err", "UI hidden — RightShift to reopen")
		end)
	end

	local function selectPage(name)
		activePage = name
		for pageName, page in pairs(pages) do
			page.frame.Visible = pageName == name
			local btn = navButtons[pageName]
			local meta = navMeta[pageName]
			if btn and meta then
				local selected = pageName == name
				accentTween(btn, { BackgroundColor3 = selected and THEME.accentDark or THEME.row })
				meta.label.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or THEME.dim
				meta.stroke.Transparency = selected and 0.1 or 0.75
			end
		end
	end
	window._select = selectPage
	window._pages = pages

	-- notifications -------------------------------------------------------

	local notifyHolder = Instance.new("Frame")
	notifyHolder.Size = UDim2.new(0, 280, 1, -40)
	notifyHolder.Position = UDim2.new(1, -292, 0, 20)
	notifyHolder.BackgroundTransparency = 1
	notifyHolder.Parent = root
	list(notifyHolder, 8)

	local function notify(data)
		local toast = Instance.new("Frame")
		toast.Size = UDim2.new(1, 0, 0, 62)
		toast.BackgroundColor3 = THEME.card
		toast.Parent = notifyHolder
		corner(toast, 10)
		stroke(toast, THEME.accent, 0.4)
		pad(toast, 12, 8)

		local t = label(toast, tostring(data.Title or "Notice"), 13, THEME.text, "b")
		t.Size = UDim2.new(1, 0, 0, 18)
		local c = label(toast, tostring(data.Content or ""), 12, THEME.dim)
		c.Size = UDim2.new(1, 0, 1, -20)
		c.Position = UDim2.fromOffset(0, 20)
		c.TextWrapped = true

		logActivity("info", tostring(data.Title or "Notice"))
		task.delay(data.Duration or 3, function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end

	function window:Notify(data)
		notify(data)
	end

	-- dashboard -----------------------------------------------------------

	local function buildDashboard()
		local page = pages.Dashboard.frame

		-- welcome card
		local welcome = Instance.new("Frame")
		welcome.Size = UDim2.new(1, 0, 0, 96)
		welcome.BackgroundColor3 = THEME.card
		welcome.Parent = page
		corner(welcome, 12)
		stroke(welcome, THEME.stroke, 0.55)
		pad(welcome, 14, 10)

		local avatar = Instance.new("ImageLabel")
		avatar.Size = UDim2.fromOffset(68, 68)
		avatar.Position = UDim2.fromOffset(0, 6)
		avatar.BackgroundColor3 = THEME.row
		avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. localPlayer.UserId .. "&w=150&h=150"
		avatar.Parent = welcome
		corner(avatar, 34)

		local wTitle = label(welcome, "Welcome to Losarinz! ✅", 18, THEME.text, "b")
		wTitle.Position = UDim2.fromOffset(84, 14)
		wTitle.Size = UDim2.new(1, -240, 0, 24)
		local wPlayer = label(welcome, "Player: " .. localPlayer.DisplayName, 14, THEME.dim)
		wPlayer.Position = UDim2.fromOffset(84, 40)
		wPlayer.Size = UDim2.new(1, -240, 0, 18)
		local wSub = label(welcome, "Premium Roblox Trainer Interface", 12, THEME.dim)
		wSub.Position = UDim2.fromOffset(84, 60)
		wSub.Size = UDim2.new(1, -240, 0, 16)

		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(150, 52)
		badge.Position = UDim2.new(1, -160, 0, 22)
		badge.BackgroundColor3 = THEME.row
		badge.Parent = welcome
		corner(badge, 10)
		stroke(badge, THEME.accent, 0.4)
		local bCrown = label(badge, "👑", 15, Color3.fromRGB(255, 200, 80), nil, Enum.TextXAlignment.Center)
		bCrown.Size = UDim2.fromOffset(24, 52)
		local b1 = label(badge, "LOSARINZ TRAINER", 11, THEME.text, "b")
		b1.Position = UDim2.fromOffset(26, 10)
		b1.Size = UDim2.new(1, -30, 0, 14)
		local b2 = label(badge, "v1.0.0", 11, THEME.dim)
		b2.Position = UDim2.fromOffset(26, 26)
		b2.Size = UDim2.new(1, -30, 0, 14)

		-- stat cards
		local stats = Instance.new("Frame")
		stats.Size = UDim2.new(1, 0, 0, 64)
		stats.Position = UDim2.fromOffset(0, 106)
		stats.BackgroundTransparency = 1
		stats.Parent = page
		local statList = Instance.new("UIGridLayout")
		statList.CellSize = UDim2.new(0.25, -6, 1, 0)
		statList.CellPadding = UDim2.new(0, 8, 0, 0)
		statList.Parent = stats

		local accountAge = tostring(localPlayer.AccountAge) .. " Days"
		local cards = {
			{ icon = "👤", value = localPlayer.Name, label = "Username" },
			{ icon = "📅", value = accountAge, label = "Account Age" },
			{ icon = "#️⃣", value = tostring(localPlayer.UserId), label = "User ID" },
			{ icon = "📊", value = "00:00:00", label = "Session Time", live = true },
		}
		local sessionLabel
		for _, cardData in ipairs(cards) do
			local card = Instance.new("Frame")
			card.BackgroundColor3 = THEME.card
			card.Parent = stats
			corner(card, 10)
			stroke(card, THEME.stroke, 0.7)
			pad(card, 10, 8)
			local icon = label(card, cardData.icon, 18, THEME.accent)
			icon.Size = UDim2.fromOffset(24, 24)
			local value = label(card, cardData.value, 13, THEME.text, "b")
			value.Position = UDim2.fromOffset(30, 8)
			value.Size = UDim2.new(1, -34, 0, 22)
			value.TextTruncate = Enum.TextTruncate.AtEnd
			local lbl = label(card, cardData.label, 11, THEME.dim)
			lbl.Position = UDim2.fromOffset(30, 32)
			lbl.Size = UDim2.new(1, -34, 0, 14)
			if cardData.live then
				sessionLabel = value
			end
		end

		-- session timer loop
		task.spawn(function()
			while gui.Parent do
				if sessionLabel then
					local elapsed = math.floor(os.clock() - sessionStarted)
					sessionLabel.Text = string.format("%02d:%02d:%02d", math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60, elapsed % 60)
				end
				task.wait(1)
			end
		end)

		-- quick access
		local quick = Instance.new("Frame")
		quick.Size = UDim2.new(1, 0, 0, 108)
		quick.Position = UDim2.fromOffset(0, 180)
		quick.BackgroundColor3 = THEME.card
		quick.Parent = page
		corner(quick, 12)
		stroke(quick, THEME.stroke, 0.55)
		pad(quick, 12, 8)
		local qTitle = label(quick, "⚡ Quick Access", 14, THEME.text, "b")
		qTitle.Size = UDim2.new(1, 0, 0, 20)

		local gridFrame = Instance.new("Frame")
		gridFrame.Size = UDim2.new(1, 0, 1, -26)
		gridFrame.Position = UDim2.fromOffset(0, 26)
		gridFrame.BackgroundTransparency = 1
		gridFrame.Parent = quick

		local actions = {
			{ icon = "🚀", title = "Enable Features", sub = "Toggle Auto Farm", onClick = function()
				local entry = flags.AutoFarm
				setFlagValue("AutoFarm", not (entry and entry.CurrentValue))
			end },
			{ icon = "🎨", title = "Change Theme", sub = themeName .. " Theme", onClick = function(button)
				local order = { "Purple", "Blue", "Green", "Red", "Pink" }
				local next_ = order[(table.find(order, themeName) or 0) % #order + 1]
				THEME.accent = THEME_NAMES[next_]
				THEME.accentDark = THEME.accent:Lerp(Color3.new(0, 0, 0), 0.45)
				THEME.stroke = THEME.accent:Lerp(Color3.new(0, 0, 0), 0.35)
				themeName = next_
				rootStroke.Color = THEME.accent
				selectPage(activePage)
				if button and button.sub then
					button.sub.Text = themeName .. " Theme"
				end
				logActivity("ok", "Theme changed: " .. themeName)
			end },
			{ icon = "🗡", title = "Steal Tab", sub = "Open stealing", onClick = function()
				selectPage("Steal")
			end },
			{ icon = "ℹ", title = "View Info", sub = "About Losarinz", onClick = function()
				notify({ Title = "Losarinz Trainer", Content = "Break & Steal an Egg trainer. Developed by Losarinz.", Duration = 4 })
			end },
		}

		local quickGrid = Instance.new("UIGridLayout")
		quickGrid.CellSize = UDim2.new(0.5, -5, 0, 34)
		quickGrid.CellPadding = UDim2.new(0, 8, 0, 6)
		quickGrid.Parent = gridFrame

		for _, action in ipairs(actions) do
			local b = Instance.new("TextButton")
			b.BackgroundColor3 = THEME.row
			b.Text = ""
			b.AutoButtonColor = true
			b.Parent = gridFrame
			corner(b, 8)
			stroke(b, THEME.accent, 0.6)
			pad(b, 10, 5)
			local icon = label(b, action.icon, 14, THEME.accent)
			icon.Size = UDim2.fromOffset(20, 22)
			local t = label(b, action.title, 12, THEME.text, "b")
			t.Position = UDim2.fromOffset(26, 0)
			t.Size = UDim2.new(1, -30, 0, 12)
			t.TextTruncate = Enum.TextTruncate.AtEnd
			local sub = label(b, action.sub, 10, THEME.dim)
			sub.Position = UDim2.fromOffset(26, 14)
			sub.Size = UDim2.new(1, -30, 0, 12)
			sub.TextTruncate = Enum.TextTruncate.AtEnd
			b.MouseButton1Click:Connect(function()
				action.onClick({ sub = sub })
			end)
		end

		-- recent activity
		local activity = Instance.new("Frame")
		activity.Size = UDim2.new(1, 0, 0, 108)
		activity.Position = UDim2.fromOffset(0, 298)
		activity.BackgroundColor3 = THEME.card
		activity.Parent = page
		corner(activity, 12)
		stroke(activity, THEME.stroke, 0.55)
		pad(activity, 12, 8)
		local aTitle = label(activity, "📊 Recent Activity", 14, THEME.text, "b")
		aTitle.Size = UDim2.new(1, 0, 0, 20)
		aTitle.LayoutOrder = 0

		local feed = Instance.new("Frame")
		feed.Size = UDim2.new(1, 0, 1, -26)
		feed.Position = UDim2.fromOffset(0, 26)
		feed.BackgroundTransparency = 1
		feed.Parent = activity
		local feedList = list(feed, 4)

		local dotColors = { ok = Color3.fromRGB(90, 220, 130), info = Color3.fromRGB(90, 160, 255), err = Color3.fromRGB(255, 90, 90) }

		local function renderFeed()
			for _, c in ipairs(feed:GetChildren()) do
				if c:IsA("Frame") then c:Destroy() end
			end
			for i, entry in ipairs(activityLog) do
				if i > 4 then break end
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 15)
				row.BackgroundTransparency = 1
				row.Parent = feed
				local dot = Instance.new("Frame")
				dot.Size = UDim2.fromOffset(8, 8)
				dot.Position = UDim2.fromOffset(0, 4)
				dot.BackgroundColor3 = dotColors[entry.kind] or dotColors.info
				dot.Parent = row
				corner(dot, 4)
				local txt = label(row, entry.text, 11, THEME.text)
				txt.Position = UDim2.fromOffset(16, 0)
				txt.Size = UDim2.new(1, -16, 1, 0)
				txt.TextTruncate = Enum.TextTruncate.AtEnd
			end
		end

		table.insert(activityListeners, renderFeed)
		renderFeed()

		-- system status
		local status = Instance.new("Frame")
		status.Size = UDim2.new(1, 0, 0, 150)
		status.Position = UDim2.fromOffset(0, 416)
		status.BackgroundColor3 = THEME.card
		status.Parent = page
		corner(status, 12)
		stroke(status, THEME.stroke, 0.55)
		pad(status, 12, 8)
		local sTitle = label(status, "🛡 System Status", 14, THEME.text, "b")
		sTitle.Size = UDim2.new(1, 0, 0, 20)

		local rows = {
			{ "Interface Status", "Online", Color3.fromRGB(90, 220, 130) },
			{ "Framework Version", "v1.0.0", nil },
			{ "Theme", themeName, nil },
			{ "Executor", tostring(identifyexecutor and identifyexecutor() or "Unknown"), nil },
		}
		for i, rowData in ipairs(rows) do
			local lbl = label(status, rowData[1], 12, THEME.dim)
			lbl.Position = UDim2.fromOffset(0, 26 + (i - 1) * 20)
			lbl.Size = UDim2.new(1, -90, 0, 18)
			local val = label(status, rowData[2], 12, rowData[3] or THEME.text, "b", Enum.TextXAlignment.Right)
			val.Position = UDim2.new(1, -90, 0, 26 + (i - 1) * 20)
			val.Size = UDim2.new(0, 90, 0, 18)
		end
	end

	-- page factory --------------------------------------------------------

	local dashboardBuilt = false

	function window:CreateTab(name, iconId)
		local pageName = name
		local frame = Instance.new("ScrollingFrame")
		frame.Size = UDim2.new(1, 0, 1, -TITLE_BAR - 8)
		frame.Position = UDim2.fromOffset(0, TITLE_BAR + 8)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ScrollBarThickness = 3
		frame.ScrollBarImageColor3 = THEME.accent
		frame.CanvasSize = UDim2.new()
		frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		frame.Visible = false
		frame.Parent = content
		list(frame, 8)
		pages[pageName] = { frame = frame }

		-- nav button
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 34)
		btn.BackgroundColor3 = THEME.row
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.Parent = nav
		corner(btn, 10)
		local btnStroke = stroke(btn, THEME.stroke, 0.75)
		pad(btn, 12, 6)
		local glyph = "▪"
		local lower = name:lower()
		if lower:find("farm") or lower:find("dashboard") then glyph = "🏠" end
		if lower:find("collect") then glyph = "🎒" end
		if lower:find("steal") then glyph = "🗡" end
		if lower:find("pet") then glyph = "🐾" end
		if lower:find("enchant") then glyph = "✨" end
		if lower:find("upgrade") then glyph = "⬆" end
		if lower:find("visual") then glyph = "👁" end
		if lower:find("webhook") then glyph = "🔗" end
		if lower:find("misc") or lower:find("setting") then glyph = "⚙" end
		local icon = label(btn, glyph, 14, THEME.accent)
		icon.Size = UDim2.fromOffset(22, 22)
		local lbl = label(btn, name, 13, THEME.dim)
		lbl.Position = UDim2.fromOffset(30, 0)
		lbl.Size = UDim2.new(1, -34, 1, 0)
		navMeta[pageName] = { label = lbl, stroke = btnStroke }
		navButtons[pageName] = btn
		btn.MouseButton1Click:Connect(function()
			selectPage(pageName)
		end)

		table.insert(window._tabs, { Name = pageName })

		local tab = {}

		function tab:CreateSection(text)
			local s = label(frame, text, 13, THEME.accent, "b")
			s.Size = UDim2.new(1, 0, 0, 22)
			s.LayoutOrder = #frame:GetChildren() + 1
		end

		local function newRow(subText)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, subText and 46 or 36)
			row.BackgroundColor3 = THEME.row
			row.Parent = frame
			corner(row, 10)
			stroke(row, THEME.stroke, 0.8)
			pad(row, 12, 6)
			row.LayoutOrder = #frame:GetChildren() + 1
			return row
		end

		function tab:CreateToggle(data)
			local row = newRow()

			local chip = Instance.new("Frame")
			chip.Size = UDim2.fromOffset(24, 24)
			chip.BackgroundColor3 = THEME.accentDark
			chip.Parent = row
			corner(chip, 7)
			local chipIcon = label(chip, "⚙", 11, THEME.text, nil, Enum.TextXAlignment.Center)

			local t = label(row, data.Name, 13, THEME.text)
			t.Position = UDim2.fromOffset(34, 0)
			t.Size = UDim2.new(1, -120, 0, 34)
			t.TextTruncate = Enum.TextTruncate.AtEnd

			local pill = Instance.new("TextButton")
			pill.Size = UDim2.fromOffset(46, 22)
			pill.Position = UDim2.new(1, -54, 0, 7)
			pill.BackgroundColor3 = data.CurrentValue and THEME.accent or THEME.card
			pill.Text = ""
			pill.Parent = row
			corner(pill, 11)
			stroke(pill, THEME.stroke, 0.5)
			local knob = Instance.new("Frame")
			knob.Size = UDim2.fromOffset(16, 16)
			knob.Position = data.CurrentValue and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3)
			knob.BackgroundColor3 = Color3.fromRGB(240, 236, 250)
			knob.Parent = pill
			corner(knob, 8)

			local state = data.CurrentValue == true

			local function render()
				accentTween(pill, { BackgroundColor3 = state and THEME.accent or THEME.card })
				accentTween(knob, { Position = state and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3) })
			end

		local flagEntry = { Type = "Toggle", CurrentValue = state }
		local function apply(value, fromLoad)
			state = value == true
			flagEntry.CurrentValue = state
			render()
			if data.Callback and not fromLoad then
				task.spawn(data.Callback, state)
			end
		end

			function flagEntry.Set(value)
				apply(value, true)
				if data.Callback then
					task.spawn(data.Callback, value == true)
				end
				saveConfigDebounced()
			end

			pill.MouseButton1Click:Connect(function()
				apply(not state)
				saveConfigDebounced()
			end)

			if data.Flag then
				flags[data.Flag] = flagEntry
			end

			return flagEntry
		end

		function tab:CreateDropdown(data)
			local multi = data.MultipleOptions == true
			local selected = {}
			for _, option in ipairs(data.CurrentOption or {}) do
				selected[option] = true
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 36)
			row.BackgroundColor3 = THEME.row
			row.Parent = frame
			corner(row, 10)
			stroke(row, THEME.stroke, 0.8)
			pad(row, 12, 6)
			row.LayoutOrder = #frame:GetChildren() + 1

			local t = label(row, data.Name, 13, THEME.text)
			t.Size = UDim2.new(1, -160, 0, 24)
			t.TextTruncate = Enum.TextTruncate.AtEnd

			local countText = {}
			for option in pairs(selected) do
				table.insert(countText, option)
			end
			local valueLabel = label(row, #countText > 0 and table.concat(countText, ", ") or "None", 12, THEME.dim, nil, Enum.TextXAlignment.Right)
			valueLabel.Position = UDim2.new(1, -150, 0, 0)
			valueLabel.Size = UDim2.new(0, 130, 0, 24)
			valueLabel.TextTruncate = Enum.TextTruncate.AtEnd

			local arrow = label(row, "▾", 13, THEME.dim, nil, Enum.TextXAlignment.Right)
			arrow.Position = UDim2.new(1, -22, 0, 0)
			arrow.Size = UDim2.fromOffset(16, 24)

			local flagEntry = { Type = "Dropdown", CurrentOption = data.CurrentOption or {} }

			local function fire()
				local chosen = {}
				if multi then
					for option in pairs(selected) do
						table.insert(chosen, option)
					end
				else
					for option in pairs(selected) do
						chosen = { option }
						break
					end
				end
				table.sort(chosen)
				flagEntry.CurrentOption = chosen
				valueLabel.Text = #chosen > 0 and table.concat(chosen, ", ") or "None"
				if data.Callback then
					task.spawn(data.Callback, chosen)
				end
				saveConfigDebounced()
			end

			local listFrame = Instance.new("ScrollingFrame")
			listFrame.Size = UDim2.new(1, 0, 0, 0)
			listFrame.BackgroundColor3 = THEME.card
			listFrame.BorderSizePixel = 0
			listFrame.ScrollBarThickness = 2
			listFrame.ScrollBarImageColor3 = THEME.accent
			listFrame.CanvasSize = UDim2.new()
			listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
			listFrame.Visible = false
			listFrame.ClipsDescendants = true
			listFrame.Parent = frame
			corner(listFrame, 10)
			stroke(listFrame, THEME.accent, 0.6)
			list(listFrame, 3)
			listFrame.LayoutOrder = #frame:GetChildren() + 1

			local open = false
			local toggleOpen = function()
				open = not open
				listFrame.Visible = open
				listFrame.Size = open and UDim2.new(1, 0, 0, math.min(#data.Options * 26 + 10, 150)) or UDim2.new(1, 0, 0, 0)
				arrow.Text = open and "▴" or "▾"
			end

			row.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					-- only clicks on the right side toggle the list, the label area is display
					toggleOpen()
				end
			end)

			for _, option in ipairs(data.Options or {}) do
				local optionButton = Instance.new("TextButton")
				optionButton.Size = UDim2.new(1, 0, 0, 24)
				optionButton.BackgroundColor3 = selected[option] and THEME.accentDark or THEME.row
				optionButton.Text = option
				optionButton.TextSize = 12
				optionButton.TextColor3 = selected[option] and THEME.text or THEME.dim
				optionButton.Font = Enum.Font.Gotham
				optionButton.TextXAlignment = Enum.TextXAlignment.Left
				optionButton.AutoButtonColor = true
				optionButton.Parent = listFrame
				corner(optionButton, 6)
				pad(optionButton, 10, 2)
				optionButton.MouseButton1Click:Connect(function()
					if multi then
						selected[option] = not selected[option] or nil
						optionButton.BackgroundColor3 = selected[option] and THEME.accentDark or THEME.row
						optionButton.TextColor3 = selected[option] and THEME.text or THEME.dim
					else
						selected = { [option] = true }
						for _, other in ipairs(listFrame:GetChildren()) do
							if other:IsA("TextButton") then
								other.BackgroundColor3 = THEME.row
								other.TextColor3 = THEME.dim
							end
						end
						optionButton.BackgroundColor3 = THEME.accentDark
						optionButton.TextColor3 = THEME.text
						toggleOpen()
					end
					fire()
				end)
			end

			function flagEntry.Set(options)
				selected = {}
				for _, option in ipairs(options or {}) do
					selected[option] = true
				end
				fire()
			end

			if data.Flag then
				flags[data.Flag] = flagEntry
			end

			return flagEntry
		end

		function tab:CreateSlider(data)
			local min_ = data.Range and data.Range[1] or 0
			local max_ = data.Range and data.Range[2] or 100
			local increment = data.Increment or 1

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 46)
			row.BackgroundColor3 = THEME.row
			row.Parent = frame
			corner(row, 10)
			stroke(row, THEME.stroke, 0.8)
			pad(row, 12, 6)
			row.LayoutOrder = #frame:GetChildren() + 1

			local t = label(row, data.Name .. (data.Suffix and (" (" .. data.Suffix .. ")") or ""), 13, THEME.text)
			t.Size = UDim2.new(1, -90, 0, 16)

			local valueBox = Instance.new("Frame")
			valueBox.Size = UDim2.fromOffset(56, 22)
			valueBox.Position = UDim2.new(1, -60, 0, 5)
			valueBox.BackgroundColor3 = THEME.card
			valueBox.Parent = row
			corner(valueBox, 6)
			stroke(valueBox, THEME.stroke, 0.5)
			local valueLabel = label(valueBox, tostring(data.CurrentValue or min_), 12, THEME.text, nil, Enum.TextXAlignment.Center)

			local track = Instance.new("Frame")
			track.Size = UDim2.new(1, -4, 0, 8)
			track.Position = UDim2.fromOffset(2, 30)
			track.BackgroundColor3 = THEME.card
			track.Parent = row
			corner(track, 4)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.new(0.5, 0, 1, 0)
			fill.BackgroundColor3 = THEME.accent
			fill.Parent = track
			corner(fill, 4)
			local knob = Instance.new("Frame")
			knob.Size = UDim2.fromOffset(14, 14)
			knob.Position = UDim2.new(0.5, -7, 0, -3)
			knob.BackgroundColor3 = Color3.fromRGB(240, 236, 250)
			knob.Parent = track
			corner(knob, 7)

			local flagEntry = { Type = "Slider", CurrentValue = data.CurrentValue or min_ }

			local function setFromFraction(fraction)
				local raw = min_ + (max_ - min_) * math.clamp(fraction, 0, 1)
				local stepped = math.floor(raw / increment + 0.5) * increment
				stepped = math.clamp(stepped, min_, max_)
				stepped = math.floor(stepped * 100 + 0.5) / 100
				flagEntry.CurrentValue = stepped
				valueLabel.Text = tostring(stepped)
				fill.Size = UDim2.new((stepped - min_) / (max_ - min_), 0, 1, 0)
				knob.Position = UDim2.new((stepped - min_) / (max_ - min_), -7, 0, -3)
				if data.Callback then
					task.spawn(data.Callback, stepped)
				end
			end

			local sliding = false
			track.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					sliding = true
					local fraction = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
					setFromFraction(fraction)
				end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					local fraction = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
					setFromFraction(fraction)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if sliding then
						sliding = false
						saveConfigDebounced()
					end
				end
			end)

			setFromFraction(((data.CurrentValue or min_) - min_) / (max_ - min_))

			function flagEntry.Set(value)
				setFromFraction((value - min_) / (max_ - min_))
				saveConfigDebounced()
			end

			if data.Flag then
				flags[data.Flag] = flagEntry
			end

			return flagEntry
		end

		function tab:CreateInput(data)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 40)
			row.BackgroundColor3 = THEME.row
			row.Parent = frame
			corner(row, 10)
			stroke(row, THEME.stroke, 0.8)
			pad(row, 12, 6)
			row.LayoutOrder = #frame:GetChildren() + 1

			local t = label(row, data.Name, 13, THEME.text)
			t.Size = UDim2.new(0.5, 0, 0, 28)

			local box = Instance.new("TextBox")
			box.Size = UDim2.new(0.45, 0, 0, 26)
			box.Position = UDim2.new(1, -10, 0, 7)
			box.AnchorPoint = Vector2.new(1, 0)
			box.BackgroundColor3 = THEME.card
			box.Text = data.CurrentValue or ""
			box.PlaceholderText = data.PlaceholderText or ""
			box.PlaceholderColor3 = THEME.dim
			box.TextSize = 12
			box.TextColor3 = THEME.text
			box.Font = Enum.Font.Gotham
			box.ClearTextOnFocus = false
			box.Parent = row
			corner(box, 6)
			stroke(box, THEME.stroke, 0.5)
			pad(box, 8, 0)

			local flagEntry = { Type = "Input", CurrentValue = box.Text }

			box.FocusLost:Connect(function()
				flagEntry.CurrentValue = box.Text
				if data.Callback then
					task.spawn(data.Callback, box.Text)
				end
				saveConfigDebounced()
			end)

			function flagEntry.Set(value)
				box.Text = tostring(value or "")
				flagEntry.CurrentValue = box.Text
				if data.Callback then
					task.spawn(data.Callback, box.Text)
				end
			end

			if data.Flag then
				flags[data.Flag] = flagEntry
			end

			return flagEntry
		end

		function tab:CreateButton(data)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, 0, 0, 34)
			b.BackgroundColor3 = THEME.accentDark
			b.Text = data.Name or "Button"
			b.TextSize = 13
			b.TextColor3 = THEME.text
			b.Font = Enum.Font.GothamBold
			b.AutoButtonColor = true
			b.Parent = frame
			corner(b, 10)
			stroke(b, THEME.accent, 0.5)
			b.LayoutOrder = #frame:GetChildren() + 1
			b.MouseButton1Click:Connect(function()
				if data.Callback then
					task.spawn(data.Callback)
				end
			end)
		end

		function tab:CreateParagraph(data)
			local p = Instance.new("Frame")
			p.Size = UDim2.new(1, 0, 0, 60)
			p.BackgroundColor3 = THEME.row
			p.Parent = frame
			corner(p, 10)
			stroke(p, THEME.stroke, 0.8)
			pad(p, 12, 6)
			p.LayoutOrder = #frame:GetChildren() + 1

			local title = label(p, data.Title or "", 13, THEME.text, "b")
			title.Size = UDim2.new(1, 0, 0, 18)
			local body = label(p, data.Content or "", 12, THEME.dim)
			body.Position = UDim2.fromOffset(0, 20)
			body.Size = UDim2.new(1, 0, 1, -22)
			body.TextWrapped = true

			local paragraph = {}

			function paragraph:Set(newData)
				title.Text = newData.Title or title.Text
				body.Text = newData.Content or body.Text
				p.Size = UDim2.new(1, 0, 0, math.max(48, 28 + math.ceil(#(newData.Content or "") / 60) * 14))
			end

			return paragraph
		end

		return tab
	end

	-- dashboard tab is built on first SelectPage
	window.CreateDashboard = function()
		if not dashboardBuilt then
			dashboardBuilt = true
			buildDashboard()
		end
	end

	-- config save/load ----------------------------------------------------

	local savePending = false

	function saveConfigDebounced()
		if savePending then return end
		savePending = true
		task.delay(1, function()
			savePending = false
			pcall(function()
				if not makefolder then return end
				if not isfolder(configFolder) then makefolder(configFolder) end
				local payload = {}
				for flagName, entry in pairs(flags) do
					payload[flagName] = entry.CurrentValue or entry.CurrentOption
				end
				writefile(configFile, HttpService:JSONEncode(payload))
			end)
		end)
	end

	function window:LoadConfiguration()
		pcall(function()
			if not (isfile and readfile and isfile(configFile)) then return end
			local payload = HttpService:JSONDecode(readfile(configFile))
			for flagName, value in pairs(payload) do
				local entry = flags[flagName]
				if entry and entry.Set then
					entry.Set(value)
				end
			end
			logActivity("ok", "Settings loaded")
		end)
	end

	-- dashboard tab + nav assembly
	pages.Dashboard = { frame = Instance.new("ScrollingFrame") }
	local dashFrame = pages.Dashboard.frame
	dashFrame.Size = UDim2.new(1, 0, 1, -TITLE_BAR - 8)
	dashFrame.Position = UDim2.fromOffset(0, TITLE_BAR + 8)
	dashFrame.BackgroundTransparency = 1
	dashFrame.BorderSizePixel = 0
	dashFrame.ScrollBarThickness = 3
	dashFrame.CanvasSize = UDim2.new()
	dashFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	dashFrame.Visible = false
	dashFrame.Parent = content
	list(dashFrame, 8)

	local dashButton = Instance.new("TextButton")
	dashButton.Size = UDim2.new(1, 0, 0, 34)
	dashButton.BackgroundColor3 = THEME.accentDark
	dashButton.Text = ""
	dashButton.AutoButtonColor = true
	dashButton.Parent = nav
	corner(dashButton, 10)
	local dashStroke = stroke(dashButton, THEME.accent, 0.1)
	pad(dashButton, 12, 6)
	local dashIcon = label(dashButton, "🏠", 14, THEME.text)
	dashIcon.Size = UDim2.fromOffset(22, 22)
	local dashLabel = label(dashButton, "Dashboard", 13, THEME.text)
	dashLabel.Position = UDim2.fromOffset(30, 0)
	dashLabel.Size = UDim2.new(1, -34, 1, 0)
	navMeta.Dashboard = { label = dashLabel, stroke = dashStroke }
	navButtons.Dashboard = dashButton
	dashButton.MouseButton1Click:Connect(function()
		window.CreateDashboard()
		selectPage("Dashboard")
	end)

	buildDashboard()
	selectPage("Dashboard")
	logActivity("ok", "UI loaded successfully")

	-- keybind
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			window:Toggle()
		end
	end)

	logActivity("info", "Welcome to Losarinz Trainer!")

	return window
end

return LosarinzUI
