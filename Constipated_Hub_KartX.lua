--[[
	Constipated Hub | KartX Racing [HALLOWEEN]
	Orion UI · Track pathfinder · Auto Drive (race + free roam) · Speed · ESP
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
	DriveMode = "Path", -- Path | FreeRoam
	DriveSpeed = 140,
	DriveHeight = 2.5,
	LookAhead = 3, -- nodes ahead for steering
	LoopTrack = true,
	Recover = true,
	ReverseFix = true,

	SpeedBoost = false,
	SpeedMult = 1.7,
	MaxSpeed = 220,

	ESP = true,
	EspName = true,
	EspDist = true,
	EspChams = true,
	EspTrack = true, -- highlight path nodes

	WalkSpeed = false,
	WalkSpeedVal = 28,
	InfJump = false,
	Noclip = false,
	Fly = false,
	FlySpeed = 60,
	AntiAFK = true,
}

-- ===================== REMOTES (safe) =====================
local function getRemote(path)
	local cur = ReplicatedStorage
	for part in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end

local Remotes = {
	Input = getRemote("CrownKart.Input"),
	KartSpawn = getRemote("KartSpawnRequest"),
	KartSelect = getRemote("KartSelectRequest"),
	HubTP = getRemote("HubTeleportRequest"),
	MenuTP = getRemote("MenuTeleportRequest"),
	LapUpdate = getRemote("RaceEvents.LapDataUpdate"),
	OpenLocker = getRemote("lockerSystem.Events.OpenLocker"),
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
	local h = c:FindFirstChildOfClass("Humanoid")
	if h and h.SeatPart then
		local seat = h.SeatPart
		local model = seat:FindFirstAncestorOfClass("Model")
		if model and model ~= c then
			return model, seat
		end
		return seat.Parent, seat
	end
	return nil
end

local function getKartRoot()
	local kart = getKart()
	if not kart then return nil end
	if kart:IsA("Model") then
		return kart.PrimaryPart
			or kart:FindFirstChild("Chassis")
			or kart:FindFirstChild("Body")
			or kart:FindFirstChild("Root")
			or kart:FindFirstChildWhichIsA("BasePart")
	end
	return kart:IsA("BasePart") and kart or nil
end

-- ===================== TRACK PATHFINDER =====================
local Path = {
	nodes = {}, -- {CFrame or Vector3}
	index = 1,
	visual = {},
}

local TRACK_KEYWORDS = {
	"checkpoint", "check point", "cp", "gate", "lap", "waypoint",
	"node", "path", "trackpoint", "sector", "split", "marker",
}

local TRACK_FOLDERS = {
	"Checkpoints", "checkpoints", "CheckPoints", "CP", "CPs",
	"Track", "track", "Course", "course", "Racing", "Race",
	"Path", "Waypoints", "Nodes", "Gates", "Sectors",
	"Map", "Circuit", "Lap", "RaceTrack",
}

local function nameScore(n)
	n = string.lower(n or "")
	local s = 0
	for _, k in ipairs(TRACK_KEYWORDS) do
		if n:find(k, 1, true) then s += 2 end
	end
	if n:match("%d+") then s += 1 end
	return s
end

local function collectParts(root, out)
	if not root then return end
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("BasePart") and nameScore(obj.Name) > 0 then
			table.insert(out, obj)
		elseif obj:IsA("Attachment") and nameScore(obj.Name) > 0 then
			table.insert(out, obj)
		end
	end
end

local function orderNodes(parts)
	-- Prefer numeric order from name
	local numbered = {}
	local unnumbered = {}
	for _, p in ipairs(parts) do
		local num = tonumber(tostring(p.Name):match("%d+"))
		if num then
			table.insert(numbered, { n = num, p = p })
		else
			table.insert(unnumbered, p)
		end
	end
	table.sort(numbered, function(a, b) return a.n < b.n end)

	local ordered = {}
	for _, t in ipairs(numbered) do
		table.insert(ordered, t.p)
	end

	-- Append unnumbered by nearest-neighbor from last
	if #ordered > 0 and #unnumbered > 0 then
		local used = {}
		local lastPos = ordered[#ordered].Position
		while #unnumbered > 0 do
			local bestI, bestD = 1, math.huge
			for i, p in ipairs(unnumbered) do
				local d = (p.Position - lastPos).Magnitude
				if d < bestD then
					bestD = d
					bestI = i
				end
			end
			local pick = table.remove(unnumbered, bestI)
			table.insert(ordered, pick)
			lastPos = pick.Position
		end
	elseif #ordered == 0 then
		-- pure nearest neighbor chain from closest to player
		local start = hrp() and hrp().Position or Vector3.zero
		local pool = { table.unpack(parts) }
		local last = start
		while #pool > 0 do
			local bi, bd = 1, math.huge
			for i, p in ipairs(pool) do
				local d = (p.Position - last).Magnitude
				if d < bd then
					bd = d
					bi = i
				end
			end
			local pick = table.remove(pool, bi)
			table.insert(ordered, pick)
			last = pick.Position
		end
	end
	return ordered
end

local function clearPathVisual()
	for _, v in ipairs(Path.visual) do
		pcall(function() v:Destroy() end)
	end
	Path.visual = {}
end

local function drawPathVisual()
	clearPathVisual()
	if not F.EspTrack then return end
	for i, node in ipairs(Path.nodes) do
		local pos = typeof(node) == "CFrame" and node.Position or node
		local p = Instance.new("Part")
		p.Name = "CSW_PathNode"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(3, 1, 3)
		p.Material = Enum.Material.Neon
		p.Color = (i == Path.index) and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(255, 140, 40)
		p.Transparency = 0.35
		p.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		p.Parent = Workspace
		table.insert(Path.visual, p)
	end
end

local function scanTrack()
	local parts = {}
	-- known folders
	for _, name in ipairs(TRACK_FOLDERS) do
		local f = Workspace:FindFirstChild(name, true)
		if f then collectParts(f, parts) end
	end
	-- Workspace children heuristic
	if #parts < 4 then
		for _, child in ipairs(Workspace:GetChildren()) do
			local n = string.lower(child.Name)
			for _, k in ipairs(TRACK_FOLDERS) do
				if n:find(string.lower(k), 1, true) then
					collectParts(child, parts)
					break
				end
			end
		end
	end
	-- last resort: any BasePart with checkpoint-like name in Workspace
	if #parts < 3 then
		for _, obj in ipairs(Workspace:GetDescendants()) do
			if obj:IsA("BasePart") and nameScore(obj.Name) >= 2 then
				table.insert(parts, obj)
			end
			if #parts > 80 then break end
		end
	end

	-- dedupe by position
	local unique = {}
	local seen = {}
	for _, p in ipairs(parts) do
		local key = string.format("%.0f_%.0f_%.0f", p.Position.X, p.Position.Y, p.Position.Z)
		if not seen[key] then
			seen[key] = true
			table.insert(unique, p)
		end
	end

	local ordered = orderNodes(unique)
	Path.nodes = {}
	for _, p in ipairs(ordered) do
		table.insert(Path.nodes, p.CFrame or CFrame.new(p.Position))
	end
	Path.index = 1
	drawPathVisual()
	return #Path.nodes
end

local function nearestIndex(pos)
	local best, bd = 1, math.huge
	for i, node in ipairs(Path.nodes) do
		local p = typeof(node) == "CFrame" and node.Position or node
		local d = (p - pos).Magnitude
		if d < bd then
			bd = d
			best = i
		end
	end
	return best
end

-- ===================== DRIVE LOGIC =====================
local lastRecover = 0
local lastPos = Vector3.zero
local stuckTime = 0

local function targetNode()
	if #Path.nodes == 0 then return nil end
	local idx = Path.index
	local look = math.clamp(F.LookAhead, 1, 8)
	local t = Path.nodes[math.min(idx + look - 1, #Path.nodes)] or Path.nodes[idx]
	return t, idx
end

local function advanceIfClose(rootPos)
	if #Path.nodes == 0 then return end
	local node = Path.nodes[Path.index]
	local pos = typeof(node) == "CFrame" and node.Position or node
	if (rootPos - pos).Magnitude < 28 then
		Path.index += 1
		if Path.index > #Path.nodes then
			if F.LoopTrack then
				Path.index = 1
			else
				Path.index = #Path.nodes
			end
		end
		if F.EspTrack then drawPathVisual() end
	end
end

local function driveAlongPath()
	local root = getKartRoot() or hrp()
	if not root then return end
	local pos = root.Position

	if #Path.nodes == 0 then
		scanTrack()
		if #Path.nodes == 0 then return end
		Path.index = nearestIndex(pos)
	end

	-- snap to nearest if far off path
	local near = nearestIndex(pos)
	local nearPos = (typeof(Path.nodes[near]) == "CFrame") and Path.nodes[near].Position or Path.nodes[near]
	if (pos - nearPos).Magnitude > 120 then
		Path.index = near
	end

	advanceIfClose(pos)

	local target = Path.nodes[Path.index]
	if not target then return end
	local tPos = (typeof(target) == "CFrame") and target.Position or target
	tPos = tPos + Vector3.new(0, F.DriveHeight, 0)

	local flat = Vector3.new(tPos.X - pos.X, 0, tPos.Z - pos.Z)
	if flat.Magnitude < 0.5 then return end
	flat = flat.Unit

	-- face + push
	pcall(function()
		root.CFrame = CFrame.new(pos, pos + flat)
	end)
	pcall(function()
		local vy = root.AssemblyLinearVelocity.Y
		root.AssemblyLinearVelocity = flat * F.DriveSpeed + Vector3.new(0, math.clamp(vy, -20, 20), 0)
	end)

	-- stuck detect
	if F.Recover then
		local moved = (pos - lastPos).Magnitude
		if moved < 1.2 then
			stuckTime += 0.05
		else
			stuckTime = 0
		end
		lastPos = pos
		if stuckTime > 1.8 and (os.clock() - lastRecover) > 2 then
			lastRecover = os.clock()
			stuckTime = 0
			pcall(function()
				root.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0) + flat * 12, pos + flat * 30)
				root.AssemblyLinearVelocity = flat * (F.DriveSpeed * 0.8)
			end)
			-- skip node if still stuck next cycle will re-nearest
			Path.index = math.min(Path.index + 1, #Path.nodes)
		end
	end
end

local function driveFreeRoam()
	local root = getKartRoot() or hrp()
	if not root then return end
	local pos = root.Position
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end

	-- if path exists, gently steer toward next node (assist)
	if #Path.nodes > 0 then
		local idx = nearestIndex(pos)
		local ahead = Path.nodes[math.min(idx + F.LookAhead, #Path.nodes)] or Path.nodes[idx]
		local aPos = (typeof(ahead) == "CFrame") and ahead.Position or ahead
		local to = Vector3.new(aPos.X - pos.X, 0, aPos.Z - pos.Z)
		if to.Magnitude > 5 then
			to = to.Unit
			flat = (flat * 0.45 + to * 0.55).Unit
		end
		Path.index = idx
		advanceIfClose(pos)
	end

	pcall(function()
		root.CFrame = CFrame.new(pos, pos + flat)
		local vy = root.AssemblyLinearVelocity.Y
		root.AssemblyLinearVelocity = flat * F.DriveSpeed + Vector3.new(0, math.clamp(vy, -20, 20), 0)
	end)
end

local function applySpeedBoost()
	local root = getKartRoot()
	if not root then return end
	pcall(function()
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 4 then
			local boosted = flat.Unit * math.min(flat.Magnitude * F.SpeedMult, F.MaxSpeed)
			root.AssemblyLinearVelocity = Vector3.new(boosted.X, v.Y, boosted.Z)
		end
	end)
end

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
	bb.Size = UDim2.new(0, 110, 0, 36)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.Parent = espFolder
	local nameL = Instance.new("TextLabel")
	nameL.BackgroundTransparency = 1
	nameL.Size = UDim2.new(1, 0, 0, 16)
	nameL.Font = Enum.Font.GothamBold
	nameL.TextSize = 13
	nameL.TextColor3 = Color3.fromRGB(255, 130, 40)
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
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder
	espMap[plr] = { bb = bb, name = nameL, dist = distL, hl = hl }
	return espMap[plr]
end

Players.PlayerRemoving:Connect(clearESP)

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
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
	if not on then return end
	noclipConn = RunService.Stepped:Connect(function()
		if not F.Noclip or not alive() then return end
		local c = char()
		if not c then return end
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Space and F.InfJump then
		local h = hum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

task.spawn(function()
	while alive() do
		if F.AntiAFK then
			pcall(function()
				local vu = game:GetService("VirtualUser")
				vu:CaptureController()
				vu:ClickButton2(Vector2.new())
			end)
		end
		task.wait(55)
	end
end)

-- ===================== MAIN =====================
RunService.Heartbeat:Connect(function()
	if not alive() then return end

	if F.AutoDrive then
		if F.DriveMode == "FreeRoam" then
			driveFreeRoam()
		else
			driveAlongPath()
		end
	end
	if F.SpeedBoost then
		applySpeedBoost()
	end
	if F.WalkSpeed then
		local h = hum()
		if h then h.WalkSpeed = F.WalkSpeedVal end
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
			if move.Magnitude > 0 then move = move.Unit * F.FlySpeed end
			flyBV.Velocity = move
			flyBG.CFrame = cam
		end
	else
		stopFly()
	end
end)

RunService.Heartbeat:Connect(function()
	if not alive() or not F.ESP then
		if not F.ESP then for p in pairs(espMap) do clearESP(p) end end
		return
	end
	local me = hrp()
	local seen = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		local rh = plr.Character and (plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character.PrimaryPart)
		local hd = plr.Character and plr.Character:FindFirstChild("Head")
		if not rh then clearESP(plr) continue end
		seen[plr] = true
		local t = ensureESP(plr)
		t.bb.Adornee = hd or rh
		t.name.Text = plr.DisplayName or plr.Name
		t.name.Visible = F.EspName
		if F.EspDist and me then
			t.dist.Text = math.floor((rh.Position - me.Position).Magnitude) .. "m"
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

TabRace:AddButton({
	Name = "1) Scan Track / Build Path",
	Callback = function()
		local n = scanTrack()
		OrionLib:MakeNotification({
			Name = "Track Scan",
			Content = n > 0 and ("Path built: " .. n .. " nodes (orange markers)") or "No checkpoints found — use Free Roam",
			Time = 4,
		})
	end,
})

TabRace:AddDropdown({
	Name = "Drive Mode",
	Default = "Path",
	Options = { "Path", "FreeRoam" },
	Callback = function(v)
		F.DriveMode = v
	end,
})

TabRace:AddToggle({
	Name = "Auto Drive",
	Default = false,
	Callback = function(v)
		F.AutoDrive = v
		if v then
			if #Path.nodes == 0 then scanTrack() end
			local root = getKartRoot() or hrp()
			if root and #Path.nodes > 0 then
				Path.index = nearestIndex(root.Position)
			end
			OrionLib:MakeNotification({
				Name = "Auto Drive",
				Content = F.DriveMode .. " | nodes: " .. #Path.nodes,
				Time = 3,
			})
		end
	end,
})

TabRace:AddSlider({
	Name = "Drive Speed",
	Min = 50,
	Max = 280,
	Default = 140,
	Increment = 5,
	Callback = function(v) F.DriveSpeed = v end,
})
TabRace:AddSlider({
	Name = "Look-Ahead Nodes",
	Min = 1,
	Max = 8,
	Default = 3,
	Increment = 1,
	Callback = function(v) F.LookAhead = v end,
})
TabRace:AddToggle({
	Name = "Loop Track",
	Default = true,
	Callback = function(v) F.LoopTrack = v end,
})
TabRace:AddToggle({
	Name = "Stuck Recover",
	Default = true,
	Callback = function(v) F.Recover = v end,
})
TabRace:AddToggle({
	Name = "Speed Boost",
	Default = false,
	Callback = function(v) F.SpeedBoost = v end,
})
TabRace:AddSlider({
	Name = "Boost Multiplier",
	Min = 1.1,
	Max = 3,
	Default = 1.7,
	Increment = 0.1,
	Callback = function(v) F.SpeedMult = v end,
})
TabRace:AddSlider({
	Name = "Max Speed Cap",
	Min = 100,
	Max = 400,
	Default = 220,
	Increment = 10,
	Callback = function(v) F.MaxSpeed = v end,
})
TabRace:AddButton({
	Name = "Spawn Kart (remote)",
	Callback = function()
		if Remotes.KartSpawn then
			pcall(function() Remotes.KartSpawn:FireServer() end)
		end
	end,
})
TabRace:AddLabel("Sit in kart → Scan Track → Auto Drive ON")

TabESP:AddToggle({
	Name = "ESP Players",
	Default = true,
	Callback = function(v)
		F.ESP = v
		if not v then for p in pairs(espMap) do clearESP(p) end end
	end,
})
TabESP:AddToggle({ Name = "Names", Default = true, Callback = function(v) F.EspName = v end })
TabESP:AddToggle({ Name = "Distance", Default = true, Callback = function(v) F.EspDist = v end })
TabESP:AddToggle({ Name = "Chams", Default = true, Callback = function(v) F.EspChams = v end })
TabESP:AddToggle({
	Name = "Show Path Markers",
	Default = true,
	Callback = function(v)
		F.EspTrack = v
		if v then drawPathVisual() else clearPathVisual() end
	end,
})

TabMisc:AddToggle({ Name = "WalkSpeed", Default = false, Callback = function(v) F.WalkSpeed = v end })
TabMisc:AddSlider({
	Name = "Speed Value",
	Min = 16, Max = 50, Default = 28, Increment = 1,
	Callback = function(v) F.WalkSpeedVal = v end,
})
TabMisc:AddToggle({ Name = "Infinite Jump", Default = false, Callback = function(v) F.InfJump = v end })
TabMisc:AddToggle({
	Name = "Noclip",
	Default = false,
	Callback = function(v) F.Noclip = v setNoclip(v) end,
})
TabMisc:AddToggle({
	Name = "Fly (WASD + Space/Ctrl)",
	Default = false,
	Callback = function(v) F.Fly = v if not v then stopFly() end end,
})
TabMisc:AddSlider({
	Name = "Fly Speed",
	Min = 20, Max = 150, Default = 60, Increment = 5,
	Callback = function(v) F.FlySpeed = v end,
})
TabMisc:AddToggle({ Name = "Anti AFK", Default = true, Callback = function(v) F.AntiAFK = v end })
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
		clearPathVisual()
		for p in pairs(espMap) do clearESP(p) end
		pcall(function() espFolder:Destroy() end)
		OrionLib:Destroy()
	end,
})

OrionLib:MakeNotification({
	Name = "Constipated Hub",
	Content = "KartX — Scan Track first, then Auto Drive",
	Time = 4,
})
OrionLib:Init()
