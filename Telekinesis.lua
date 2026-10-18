-- Q & E : Kéo lại gần (-10) và đẩy ra xa (+10)
-- R     : Đặt lại góc xoay của khối về 0 và triệt tiêu vận tốc (Reset Orientation)
-- T     : Đẩy khối ra xa nhanh (Khoảng cách = 500)
-- Y     : Kéo khối lại gần nhanh (Khoảng cách = 10)
-- = & - : Tăng (x1.5) và giảm (x0.5) lực hút của BodyPosition

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- 1. Khởi tạo Tool & Handle
local Tool = Instance.new("Tool")
Tool.Name = "Telekinesis"
Tool.Grip = CFrame.new(0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0)

local Handle = Instance.new("Part")
Handle.Name = "Handle"
Handle.Size = Vector3.new(1, 1.2, 1)
Handle.Color = Color3.fromRGB(17, 17, 17)
Handle.Transparency = 1
Handle.CanCollide = false
Handle.Parent = Tool

-- 2. Khởi tạo Point & Laser (Giữ nguyên visual gốc nhưng tối ưu hiệu năng)
local Point = Instance.new("Part")
Point.Name = "Point"
Point.Locked = true
Point.Anchored = true
Point.Shape = Enum.PartType.Ball
Point.BrickColor = BrickColor.Black()
Point.Size = Vector3.new(1, 1, 1)
Point.CanCollide = false

local Mesh = Instance.new("SpecialMesh")
Mesh.MeshType = Enum.MeshType.Sphere
Mesh.Scale = Vector3.new(0.7, 0.7, 0.7)
Mesh.Parent = Point

local Laser = Instance.new("Part")
Laser.Name = "Laser"
Laser.TopSurface = Enum.SurfaceType.Smooth
Laser.BottomSurface = Enum.SurfaceType.Smooth
Laser.Reflectance = 0.5
Laser.BrickColor = Handle.BrickColor
Laser.Transparency = Handle.Transparency
Laser.Locked = true
Laser.CanCollide = false
Laser.Anchored = true
Laser.Size = Vector3.new(1, 1, 1)

local LaserMesh = Instance.new("BlockMesh")
LaserMesh.Parent = Laser

-- 3. Khởi tạo BodyPosition
local BP = Instance.new("BodyPosition")
BP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
BP.P = BP.P * 1.1

-- 4. Biến trạng thái
local object = nil
local dist = nil
local mousedown = false
local connections = {}
local renderConnection = nil

-- Hàm cập nhật vị trí tia Laser giữa 2 Part
local function updateLaser(part1, part2)
    if not part1 or not part2 or not part1.Parent or not part2.Parent then
        Laser.Parent = nil
        return
    end
    local pos1, pos2 = part1.Position, part2.Position
    local mag = (pos1 - pos2).Magnitude
    Laser.Parent = workspace
    Laser.CFrame = CFrame.lookAt((pos1 + pos2) / 2, pos2)
    LaserMesh.Scale = Vector3.new(0.25, 0.25, mag)
end

-- Hàm dọn dẹp khi nhả chuột hoặc cất Tool
local function cleanup()
    mousedown = false
    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
    BP.Parent = nil
    Point.Parent = nil
    Laser.Parent = nil
    object = nil
end

-- Xử lý giữ chuột trái
local function onButton1Down(mouse)
    if mousedown then return end
    mousedown = true

    Point.Parent = Tool

    renderConnection = RunService.RenderStepped:Connect(function()
        if not mousedown then
            cleanup()
            return
        end

        if object == nil then
            -- Chưa bắt được vật thể: Chiếu tia tới vị trí chuột và dò tìm Target
            if mouse.Target == nil then
                local lookDir = (mouse.Hit.Position - Handle.Position).Unit
                Point.CFrame = CFrame.new(Handle.Position + lookDir * 1000)
            else
                Point.CFrame = CFrame.new(mouse.Hit.Position)
                local target = mouse.Target
                if not target.Anchored then
                    object = target
                    dist = (object.Position - Handle.Position).Magnitude
                    Point.Parent = nil
                end
            end
            if object == nil then
                updateLaser(Handle, Point)
            end
        end

        if object ~= nil then
            -- Đã bắt được vật thể: Kéo vật thể theo hướng chuột
            if object.Parent == nil then
                cleanup()
                return
            end
            local t = CFrame.lookAt(Handle.Position, mouse.Hit.Position)
            BP.Parent = object
            BP.Position = Handle.Position + t.LookVector * dist
            updateLaser(Handle, object)
        end
    end)
end

-- Xử lý phím bấm (Giữ nguyên 100% logic gốc)
local function onKeyDown(key)
    key = key:lower()

    if key == "q" then
        if dist and dist >= 5 then
            dist = dist - 10
        end
    elseif key == "e" then
        if dist then
            dist = dist + 10
        end
    elseif key == "y" then
        if dist ~= 10 then
            dist = 10
        end
    elseif key == "t" then
        if dist ~= 500 then
            dist = 500
        end
    elseif key == "=" then
        BP.P = BP.P * 1.5
    elseif key == "-" then
        BP.P = BP.P * 0.5
    elseif key == "r" then
        if object == nil or object:FindFirstChildOfClass("BodyGyro") then
            return
        end
        local BG = Instance.new("BodyGyro")
        BG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        BG.CFrame = CFrame.new(object.Position)
        BG.Parent = object

        task.spawn(function()
            local startTime = os.clock()
            -- Giới hạn tối đa 0.5s để tránh treo vòng lặp vô hạn nếu vật thể bị kẹt
            repeat
                task.wait()
            until not object or not object.Parent or (object.Orientation.Magnitude < 0.5) or (os.clock() - startTime > 0.5)

            BG:Destroy()
            if not object or not object.Parent then return end

            for _, child in ipairs(object:GetChildren()) do
                if child:IsA("BodyGyro") then
                    child:Destroy()
                end
            end
            object.AssemblyLinearVelocity = Vector3.zero
            object.AssemblyAngularVelocity = Vector3.zero
            object.Orientation = Vector3.zero
        end)
    end
end

-- Sự kiện khi cầm Tool
Tool.Equipped:Connect(function(mouse)
    mouse.Icon = "rbxasset://textures\\GunCursor.png"

    table.insert(connections, mouse.Button1Down:Connect(function()
        onButton1Down(mouse)
    end))
    table.insert(connections, mouse.Button1Up:Connect(cleanup))
    table.insert(connections, mouse.KeyDown:Connect(onKeyDown))

    local char = Tool.Parent
    local human = char and char:FindFirstChildOfClass("Humanoid")
    if human then
        table.insert(connections, human.Died:Connect(function()
            cleanup()
            Tool:Destroy()
        end))
    end
end)

-- Ngắt kết nối khi cất Tool (Chống cộng dồn sự kiện gây lag/lỗi)
Tool.Unequipped:Connect(function()
    cleanup()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)
end)

Tool.Parent = LocalPlayer:WaitForChild("Backpack")