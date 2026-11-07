-- Drift + кнопки управления для телефона (Roblox, Brookhaven)
-- Работает только локально: влияет на машину, в которой ты сидишь.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

----------------------------------------------------------------
-- НАСТРОЙКИ (крути под свой вкус)
----------------------------------------------------------------
local CFG = {
	FORWARD_SIGN = 1,     -- если машина едет задом наперёд, поставь -1
	ACCEL        = 55,    -- разгон
	BRAKE        = 90,    -- торможение
	MAX_SPEED    = 120,   -- макс. скорость
	MAX_REVERSE  = 35,    -- макс. скорость назад
	TURN         = 2.4,   -- резкость поворота
	GRIP         = 8,     -- сцепление обычное (больше = меньше сноса)
	DRIFT_GRIP   = 1.1,   -- сцепление в дрифте (меньше = больше скольжение)
	DRIFT_TURN   = 1.5,   -- множитель поворота в дрифте
}

----------------------------------------------------------------
-- КНОПКИ
----------------------------------------------------------------
local keys = { up = false, down = false, left = false, right = false, drift = false }

local gui = Instance.new("ScreenGui")
gui.Name = "DriftControls"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")

local function makeButton(text, key, pos, size, color)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size or UDim2.fromOffset(70, 70)
	b.Position = pos
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = color or Color3.fromRGB(30, 30, 30)
	b.BackgroundTransparency = 0.35
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = false
	b.Parent = gui
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 16)

	local function press(state)
		keys[key] = state
		b.BackgroundTransparency = state and 0.05 or 0.35
	end
	b.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then
			press(true)
		end
	end)
	b.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then
			press(false)
		end
	end)
end

-- Лево/право слева, газ/тормоз справа, дрифт посередине
makeButton("◀", "left",  UDim2.new(0, 70, 1, -110))
makeButton("▶", "right", UDim2.new(0, 160, 1, -110))
makeButton("▲", "up",    UDim2.new(1, -70, 1, -190))
makeButton("▼", "down",  UDim2.new(1, -70, 1, -100))
makeButton("DRIFT", "drift", UDim2.new(1, -170, 1, -110),
	UDim2.fromOffset(80, 80), Color3.fromRGB(200, 40, 60))

----------------------------------------------------------------
-- ДЫМ ИЗ-ПОД КОЛЁС (виден только тебе)
----------------------------------------------------------------
local smoke = Instance.new("ParticleEmitter")
smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
smoke.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 1),
})
smoke.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2),
	NumberSequenceKeypoint.new(1, 6),
})
smoke.Lifetime = NumberRange.new(0.6, 1.1)
smoke.Rate = 45
smoke.Speed = NumberRange.new(2, 5)
smoke.SpreadAngle = Vector2.new(30, 30)
smoke.Enabled = false

----------------------------------------------------------------
-- ФИЗИКА
----------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart

	if not seat then
		smoke.Enabled = false
		return
	end

	local root = seat.AssemblyRootPart or seat
	if smoke.Parent ~= seat then smoke.Parent = seat end

	-- на земле ли машина
	rayParams.FilterDescendantsInstances = { char, root.Parent }
	local grounded = workspace:Raycast(root.Position, Vector3.new(0, -7, 0), rayParams) ~= nil
	if not grounded then
		smoke.Enabled = false
		return
	end

	-- направления (плоские, без наклона)
	local look = seat.CFrame.LookVector * CFG.FORWARD_SIGN
	local fwd = Vector3.new(look.X, 0, look.Z)
	if fwd.Magnitude < 0.01 then return end
	fwd = fwd.Unit
	local right = fwd:Cross(Vector3.yAxis)

	local vel = root.AssemblyLinearVelocity
	local fwdSpeed = vel:Dot(fwd)
	local latSpeed = vel:Dot(right)

	-- газ / тормоз
	local throttle = (keys.up and 1 or 0) - (keys.down and 1 or 0)
	if throttle > 0 then
		fwdSpeed = math.min(fwdSpeed + CFG.ACCEL * dt, CFG.MAX_SPEED)
	elseif throttle < 0 then
		if fwdSpeed > 1 then
			fwdSpeed = fwdSpeed - CFG.BRAKE * dt
		else
			fwdSpeed = math.max(fwdSpeed - CFG.ACCEL * 0.6 * dt, -CFG.MAX_REVERSE)
		end
	else
		fwdSpeed = fwdSpeed * (1 - 0.35 * dt) -- лёгкое торможение двигателем
	end

	-- сцепление: в дрифте боковая скорость гаснет медленно = красивый занос
	local gripRate = keys.drift and CFG.DRIFT_GRIP or CFG.GRIP
	latSpeed = latSpeed * math.exp(-gripRate * dt)

	root.AssemblyLinearVelocity = fwd * fwdSpeed + right * latSpeed + Vector3.new(0, vel.Y, 0)

	-- поворот (зависит от скорости, назад руль инвертируется)
	local steer = (keys.right and 1 or 0) - (keys.left and 1 or 0)
	if steer ~= 0 then
		local speedFactor = math.clamp(math.abs(fwdSpeed) / 20, 0, 1)
		local dir = fwdSpeed >= 0 and 1 or -1
		local turn = CFG.TURN * (keys.drift and CFG.DRIFT_TURN or 1)
		local av = root.AssemblyAngularVelocity
		root.AssemblyAngularVelocity = Vector3.new(av.X, -steer * turn * speedFactor * dir, av.Z)
	end

	-- дым при заносе
	smoke.Enabled = math.abs(latSpeed) > 8 and math.abs(fwdSpeed) > 15
end)
