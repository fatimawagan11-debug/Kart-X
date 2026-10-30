--[[
	Constipated Hub | KartX Racing [HALLOWEEN]
	Orion UI · Auto Drive · Speed · ESP · Race helpers
]]

repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer

local ok, OrionLib = pcall(function()
	return loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Orion/main/source"))()
end)
if not ok or not OrionLib then
	warn("[Constipated] Orion failed")
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
GENV.__ConstipatedKartX = (GENV.__ConstipatedKartX or 0) + 1
local GEN = GENV.__ConstipatedKartX
local function alive()
	return GENV.__ConstipatedKartX == GEN
end

-- ===================== FLAGS =====================
local F = {
	AutoDrive = false,
	AutoDriveSpeed = 120, -- studs/s when tweening checkpoints
	DriveRecover = true,
	SpeedBoost = false,
	SpeedMult = 1.8,
	MaxSpeed = 200,

	ESP = true,
	EspName = true,
	EspDist = true,
	EspChams = true,

	WalkSpeed = false,
	WalkSpeedVal = 28,
	InfJump = false,
	Noclip = false,
	Fly = false,
	FlySpeed = 60,

	AntiAFK = true,
	AutoClickStart = false,
}

-- ===================== HELPERS =====================
local function char()
	return LP.Character
end
local function hum()
	local c = char()
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function hrp()
	local c = char()
	return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function getKart()
	local c = char()
	if not c then return nil end
	-- seat / vehicle patterns
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		local seat = hum.SeatPart
		local model = seat:FindFirstAncestorOfClass("Model")
		if model and model ~= c then
			return model, seat
		end
		return seat.Parent, seat
	end
	-- fallback: look for VehicleSeat near player
	local root = hrp()
	if not root then return nil end
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("VehicleSeat") or m:IsA("Seat") then
			if m.Occupant == hum then
				return m:FindFirstAncestorOfClass("Model") or m.Parent, m
			end
		end
	end
	return nil
end

local function getKartRoot()
	local kart = getKart()
	if not kart then return nil end
	if kart:IsA("Model") then
		return kart.PrimaryPart or kart:FindFirstChild("Chassis") or kart:FindFirstChildWhichIsA("BasePart")
	end
	return kart:IsA("BasePart") and kart or nil
end

-- find checkpoint parts
local function findCheckpoints()
	local list = {}
	local folders = {
		Workspace:FindFirstChild("Checkpoints"),
		Workspace:FindFirstChild("checkpoints"),
		Workspace:FindFirstChild("Course"),
		Workspace:FindFirstChild("Track"),
		Workspace:FindFirstChild("Racing"),
	}
	local function scan(root)
		if not root then return end
		for _, obj in ipairs(root:GetDescendants()) do
			local n = string.lower(obj.Name)
			if obj:IsA("BasePart") and (n:find("checkpoint") or n:find("checkpoint") or n:find("cp") or n:find("gate") or n:find("lap")) then
				table.insert(list, obj)
			end
		end
	end
	for _, f in ipairs(folders) do
		scan(f)
	end
	if #list == 0 then
		-- broad scan (limited)
		for _, obj in ipairs(Workspace:GetChildren()) do
			local n = string.lower(obj.Name)
			if n:find("check") or n:find("track") or n:find("course") or n:find("race") then
				scan(obj)
			end
		end
	end
	-- sort roughly by name number if present
	table.sort(list, function(a, b)
		local na = tonumber(a.Name:match("%d+")) or 0
		local nb = tonumber(b.Name:match("%d+")) or 0
		return na < nb
	end)
	return list
end

local checkpoints = {}
task.spawn(function()
	while alive() do
		checkpoints = findCheckpoints()
		task.wait(5)
	end
end)

-- ===================== ESP =====================
local espFolder = Instance.new("Folder")
espFolder.Name = "CSW_KartX_ESP"
espFolder.Parent = Workspace
local espMap = {}

local function clearESP(plr)
	local t = espMap[plr]
	if not t then return end
	pcall(function()
		if t.bb then t.bb:Destroy() end
		if t.hl then t.hl:Destroy() end
	end)
	espMap[plr] = nil
end

local function ensureESP(plr)
	if espMap[plr] and espMap[plr].bb and espMap[plr].bb.Parent then
		return espMap[plr]
	end
	clearESP(plr)
	local bb = Instance.new("BillboardGui")
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 100, 0, 36)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Parent = espFolder
	local nameL = Instance.new("TextLabel")
	nameL.BackgroundTransparency = 1
	nameL.Size = UDim2.new(1, 0, 0, 16)
	nameL.Font = Enum.Font.GothamBold
	nameL.TextSize = 13
	nameL.TextColor3 = Color3.fromRGB(255, 120, 50)
	nameL.TextStrokeTransparency = 0.4
	nameL.Text = plr.DisplayName or plr.Name
	nameL.Parent = bb
	local distL = Instance.new("TextLabel")
	distL.BackgroundTransparency = 1
	distL.Size = UDim2.new(1, 0, 0, 14)
	distL.Position = UDim2.new(0, 0, 0, 16)
	distL.Font = Enum.Font.Gotham
	distL.TextSize = 12
	distL.TextColor3 = Color3.fromRGB(220, 220, 220)
	distL.TextStrokeTransparency = 0.5
	distL.Text = ""
	distL.Parent = bb
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 120, 40)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder
	espMap[plr] = { bb = bb, name = nameL, dist = distL, hl = hl }
	return espMap[plr]
end

Players.PlayerRemoving:Connect(clearESP)

-- ===================== AUTO DRIVE =====================
local cpIndex = 1
local lastRecover = 0

local function nextCheckpoint()
	if #checkpoints == 0 then
		checkpoints = findCheckpoints()
	end
	if #checkpoints == 0 then return nil end
	if cpIndex > #checkpoints then
		cpIndex = 1
	end
	return checkpoints[cpIndex]
end

local function advanceCP(root)
	local cp = nextCheckpoint()
	if not cp or not root then return end
	if (root.Position - cp.Position).Magnitude < 25 then
		cpIndex += 1
		if cpIndex > #checkpoints then
			cpIndex = 1
		end
	end
end

local function autoDriveStep()
	local root = getKartRoot() or hrp()
	if not root then return end
	local cp = nextCheckpoint()
	if not cp then return end

	advanceCP(root)

	local target = cp.Position + Vector3.new(0, 2, 0)
	local pos = root.Position
	local dir = target - pos
	local dist = dir.Magnitude
	if dist < 1 then return end
	dir = dir.Unit

	-- velocity push (works on many vehicle chassis)
	local speed = F.AutoDriveSpeed
	if root:IsA("BasePart") then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then
			flat = flat.Unit
			local look = CFrame.lookAt(pos, pos + flat)
			pcall(function()
				root.CFrame = CFrame.new(pos, pos + flat)
			end)
			-- AssemblyLinearVelocity boost
			pcall(function()
				local vy = root.AssemblyLinearVelocity.Y
				root.AssemblyLinearVelocity = flat * speed + Vector3.new(0, vy, 0)
			end)
		end
	end

	-- stuck recovery
	if F.DriveRecover and (os.clock() - lastRecover) > 2.5 then
		local v = root.AssemblyLinearVelocity
		if v and v.Magnitude < 3 then
			lastRecover = os.clock()
			pcall(function()
				root.CFrame = root.CFrame + Vector3.new(0, 4, 0) + dir * 8
			end)
		end
	end
end

-- ===================== SPEED BOOST =====================
local function applySpeedBoost()
	local root = getKartRoot()
	if not root then return end
	pcall(function()
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 5 then
			local boosted = flat.Unit * math.min(flat.Magnitude * F.SpeedMult, F.MaxSpeed)
			root.AssemblyLinearVelocity = Vector3.new(boosted.X, v.Y, boosted.Z)
		end
	end)
end

-- ===================== FLY / NOCLIP =====================
local flyBV, flyBG
local function stopFly()
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
end

local function startFly()
	stopFly()
	local root = hrp()
	if not root then return end
	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = root
	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	flyBG.P = 1e4
	flyBG.Parent = root
end

local noclipConn
local function setNoclip(on)
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if not on then return end
	noclipConn = RunService.Stepped:Connect(function()
		if not F.Noclip or not alive() then return end
		local c = char()
		if not c then return end
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Space and F.InfJump then
		local h = hum()
		if h then
			h:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

-- Anti AFK
task.spawn(function()
	while alive() do
		if F.AntiAFK then
			pcall(function()
				local vu = game:GetService("VirtualUser")
				vu:CaptureController()
				vu:ClickButton2(Vector2.new())
			end)
		end
		task.wait(60)
	end
end)

-- ===================== MAIN LOOP =====================
RunService.Heartbeat:Connect(function(dt)
	if not alive() then return end

	if F.AutoDrive then
		autoDriveStep()
	end
	if F.SpeedBoost then
		applySpeedBoost()
	end

	if F.WalkSpeed then
		local h = hum()
		if h then
			h.WalkSpeed = F.WalkSpeedVal
		end
	end

	if F.Fly then
		local root = hrp()
		if root then
			if not flyBV then startFly() end
			local cam = Camera.CFrame
			local move = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
			if move.Magnitude > 0 then
				move = move.Unit * F.FlySpeed
			end
			flyBV.Velocity = move
			flyBG.CFrame = cam
		end
	else
		stopFly()
	end
end)

-- ESP loop
RunService.Heartbeat:Connect(function()
	if not alive() then return end
	if not F.ESP then
		for p in pairs(espMap) do
			clearESP(p)
		end
		return
	end
	local me = hrp()
	local seen = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		local rh = plr.Character and (plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character.PrimaryPart)
		local hd = plr.Character and plr.Character:FindFirstChild("Head")
		if not rh then
			clearESP(plr)
			continue
		end
		seen[plr] = true
		local t = ensureESP(plr)
		local adorn = hd or rh
		t.bb.Adornee = adorn
		if F.EspName then
			t.name.Text = plr.DisplayName or plr.Name
			t.name.Visible = true
		else
			t.name.Visible = false
		end
		if F.EspDist and me then
			local d = (rh.Position - me.Position).Magnitude
			t.dist.Text = math.floor(d) .. "m"
			t.dist.Visible = true
		else
			t.dist.Visible = false
		end
		if F.EspChams and plr.Character then
			t.hl.Adornee = plr.Character
			t.hl.Enabled = true
		else
			t.hl.Enabled = false
		end
	end
	for p in pairs(espMap) do
		if not seen[p] then clearESP(p) end
	end
end)

-- ===================== UI =====================
local Window = OrionLib:MakeWindow({
	Name = "Constipated Hub | KartX Racing",
	HidePremium = true,
	SaveConfig = false,
	IntroEnabled = false,
})

local TabRace = Window:MakeTab({ Name = "Race", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabESP = Window:MakeTab({ Name = "ESP", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabMisc = Window:MakeTab({ Name = "Misc", Icon = "rbxassetid://4483345998", PremiumOnly = false })

TabRace:AddToggle({
	Name = "Auto Drive (checkpoints)",
	Default = false,
	Callback = function(v)
		F.AutoDrive = v
		if v then
			checkpoints = findCheckpoints()
			cpIndex = 1
			OrionLib:MakeNotification({
				Name = "Auto Drive",
				Content = #checkpoints > 0 and ("Found " .. #checkpoints .. " checkpoints") or "No checkpoints found — still boosts forward",
				Time = 3,
			})
		end
	end,
})
TabRace:AddSlider({
	Name = "Auto Drive Speed",
	Min = 40,
	Max = 250,
	Default = 120,
	Increment = 5,
	Callback = function(v)
		F.AutoDriveSpeed = v
	end,
})
TabRace:AddToggle({
	Name = "Recover When Stuck",
	Default = true,
	Callback = function(v)
		F.DriveRecover = v
	end,
})
TabRace:AddToggle({
	Name = "Speed Boost (while moving)",
	Default = false,
	Callback = function(v)
		F.SpeedBoost = v
	end,
})
TabRace:AddSlider({
	Name = "Speed Multiplier",
	Min = 1.1,
	Max = 3,
	Default = 1.8,
	Increment = 0.1,
	Callback = function(v)
		F.SpeedMult = v
	end,
})
TabRace:AddSlider({
	Name = "Max Speed Cap",
	Min = 80,
	Max = 400,
	Default = 200,
	Increment = 10,
	Callback = function(v)
		F.MaxSpeed = v
	end,
})
TabRace:AddButton({
	Name = "Rescan Checkpoints",
	Callback = function()
		checkpoints = findCheckpoints()
		cpIndex = 1
		OrionLib:MakeNotification({ Name = "Checkpoints", Content = tostring(#checkpoints) .. " found", Time = 2 })
	end,
})
TabRace:AddLabel("Sit in a kart first, then enable Auto Drive")

TabESP:AddToggle({
	Name = "ESP",
	Default = true,
	Callback = function(v)
		F.ESP = v
		if not v then
			for p in pairs(espMap) do clearESP(p) end
		end
	end,
})
TabESP:AddToggle({
	Name = "Names",
	Default = true,
	Callback = function(v)
		F.EspName = v
	end,
})
TabESP:AddToggle({
	Name = "Distance",
	Default = true,
	Callback = function(v)
		F.EspDist = v
	end,
})
TabESP:AddToggle({
	Name = "Chams",
	Default = true,
	Callback = function(v)
		F.EspChams = v
	end,
})

TabMisc:AddToggle({
	Name = "WalkSpeed",
	Default = false,
	Callback = function(v)
		F.WalkSpeed = v
	end,
})
TabMisc:AddSlider({
	Name = "Speed Value",
	Min = 16,
	Max = 50,
	Default = 28,
	Increment = 1,
	Callback = function(v)
		F.WalkSpeedVal = v
	end,
})
TabMisc:AddToggle({
	Name = "Infinite Jump",
	Default = false,
	Callback = function(v)
		F.InfJump = v
	end,
})
TabMisc:AddToggle({
	Name = "Noclip",
	Default = false,
	Callback = function(v)
		F.Noclip = v
		setNoclip(v)
	end,
})
TabMisc:AddToggle({
	Name = "Fly (WASD + Space/Ctrl)",
	Default = false,
	Callback = function(v)
		F.Fly = v
		if not v then stopFly() end
	end,
})
TabMisc:AddSlider({
	Name = "Fly Speed",
	Min = 20,
	Max = 150,
	Default = 60,
	Increment = 5,
	Callback = function(v)
		F.FlySpeed = v
	end,
})
TabMisc:AddToggle({
	Name = "Anti AFK",
	Default = true,
	Callback = function(v)
		F.AntiAFK = v
	end,
})
TabMisc:AddButton({
	Name = "Unload",
	Callback = function()
		GENV.__ConstipatedKartX = GEN + 1
		F.AutoDrive = false
		F.SpeedBoost = false
		F.ESP = false
		F.Fly = false
		F.Noclip = false
		stopFly()
		setNoclip(false)
		for p in pairs(espMap) do clearESP(p) end
		pcall(function() espFolder:Destroy() end)
		OrionLib:Destroy()
	end,
})

OrionLib:MakeNotification({
	Name = "Constipated Hub",
	Content = "KartX Racing loaded — sit in kart, enable Auto Drive",
	Time = 4,
})
OrionLib:Init()
