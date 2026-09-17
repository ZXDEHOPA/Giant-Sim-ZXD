local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "Fire Auto",
    LoadingTitle = "Fire Auto",
    LoadingSubtitle = "FireMage + FireBrute",
    ConfigurationSaving = {
        Enabled = false
    }
})

local Tab = Window:CreateTab("Main")

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

-- =========================================================
-- SETTINGS
-- =========================================================

local FireMageEnabled = false
local FireBruteEnabled = false

-- FireMage settings
local AttackDistance = 1
local DodgeMin = 1.5
local DodgeMax = 3

-- FireBrute settings
local SpinSpeed = 360
local StopDistance = 5
local WalkAwayDistance = 15
local TargetTimeout = 5

-- =========================================================
-- COMMON FUNCTIONS
-- =========================================================

local function GetModelCenter(model)
    return model:GetBoundingBox().Position
end

local function GetDistanceToModel(root, model)
    local cf, size = model:GetBoundingBox()

    local localPos =
        cf:PointToObjectSpace(root.Position)

    local half = size / 2

    local closest = Vector3.new(
        math.clamp(localPos.X, -half.X, half.X),
        math.clamp(localPos.Y, -half.Y, half.Y),
        math.clamp(localPos.Z, -half.Z, half.Z)
    )

    local worldPoint =
        cf:PointToWorldSpace(closest)

    return (root.Position - worldPoint).Magnitude
end

-- =========================================================
-- FIRE MAGE FUNCTIONS
-- =========================================================

local function GetFireMage()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "FireMage"
            and obj:IsA("Model")
        then
            return obj
        end
    end

    return nil
end

local function GetDodgePosition(root, target, side)
    local targetPosition =
        GetModelCenter(target)

    local direction =
        root.Position - targetPosition

    direction = Vector3.new(
        direction.X,
        0,
        direction.Z
    )

    if direction.Magnitude < 0.05 then
        direction =
            Vector3.new(0, 0, 1)
    else
        direction =
            direction.Unit
    end

    local sideDirection =
        Vector3.new(
            -direction.Z,
            0,
            direction.X
        )

    return targetPosition
        + direction * AttackDistance
        + sideDirection * side
end

-- =========================================================
-- FIRE MAGE CONTROLLER
-- =========================================================

local function StartFireMage()
    task.spawn(function()

        local target = nil
        local dodgeSide = 1
        local nextDodgeTime = 0

        while FireMageEnabled do

            local character =
                Player.Character

            local humanoid =
                character
                and character:FindFirstChildOfClass(
                    "Humanoid"
                )

            local root =
                character
                and character:FindFirstChild(
                    "HumanoidRootPart"
                )

            if not humanoid or not root then
                task.wait(0.1)
                continue
            end

            -- Wait for respawn if dead
            if humanoid.Health <= 0 then
                target = nil
                task.wait(0.1)
                continue
            end

            -- Find FireMage
            if not target
                or not target.Parent
            then
                target = GetFireMage()

                if target then
                    nextDodgeTime = 0
                end
            end

            if target and target.Parent then

                local distance =
                    GetDistanceToModel(
                        root,
                        target
                    )

                -- Walk toward FireMage
                if distance > AttackDistance then

                    humanoid:MoveTo(
                        GetModelCenter(target)
                    )

                else

                    -- Randomly choose left/right
                    -- after the dodge timer expires
                    if os.clock() >= nextDodgeTime then

                        if math.random(1, 2) == 1 then
                            dodgeSide = 1
                        else
                            dodgeSide = -1
                        end

                        local minTime =
                            math.min(
                                DodgeMin,
                                DodgeMax
                            )

                        local maxTime =
                            math.max(
                                DodgeMin,
                                DodgeMax
                            )

                        local randomTime =
                            minTime
                            + math.random()
                            * (maxTime - minTime)

                        nextDodgeTime =
                            os.clock()
                            + randomTime
                    end

                    -- Dodge around FireMage
                    humanoid:MoveTo(
                        GetDodgePosition(
                            root,
                            target,
                            dodgeSide
                        )
                    )
                end

            else

                humanoid:Move(
                    Vector3.zero,
                    false
                )

                humanoid:MoveTo(
                    root.Position
                )
            end

            task.wait(0.1)
        end
    end)
end

-- =========================================================
-- FIREBRUTE FUNCTIONS
-- =========================================================

local function GetNearestFireBrute(
    root,
    excludedTarget
)

    local nearest = nil
    local nearestDistance = math.huge

    for _, obj in ipairs(
        workspace:GetDescendants()
    ) do

        if obj.Name == "FireBrute"
            and obj:IsA("Model")
            and obj ~= excludedTarget
        then

            local distance =
                (
                    root.Position
                    - GetModelCenter(obj)
                ).Magnitude

            if distance < nearestDistance then
                nearest = obj
                nearestDistance = distance
            end
        end
    end

    return nearest
end

local function FaceTarget(
    root,
    target,
    deltaTime
)

    if not target
        or not target.Parent
    then
        return false
    end

    local direction =
        GetModelCenter(target)
        - root.Position

    direction = Vector3.new(
        direction.X,
        0,
        direction.Z
    )

    if direction.Magnitude < 0.05 then
        return true
    end

    direction =
        direction.Unit

    local look =
        root.CFrame.LookVector

    look = Vector3.new(
        look.X,
        0,
        look.Z
    )

    if look.Magnitude < 0.05 then
        return false
    end

    look =
        look.Unit

    local currentAngle =
        math.atan2(
            look.X,
            look.Z
        )

    local targetAngle =
        math.atan2(
            direction.X,
            direction.Z
        )

    local difference =
        math.atan2(
            math.sin(
                targetAngle
                - currentAngle
            ),
            math.cos(
                targetAngle
                - currentAngle
            )
        )

    if math.abs(difference)
        <= math.rad(3)
    then

        root.CFrame =
            CFrame.lookAt(
                root.Position,
                root.Position
                + direction
            )

        return true
    end

    local maxRotation =
        math.rad(SpinSpeed)
        * deltaTime

    local rotation =
        math.clamp(
            difference,
            -maxRotation,
            maxRotation
        )

    root.CFrame =
        root.CFrame
        * CFrame.Angles(
            0,
            rotation,
            0
        )

    return false
end

local function GetWalkAwayPosition(
    root,
    target
)

    local targetPosition =
        GetModelCenter(target)

    local direction =
        root.Position
        - targetPosition

    direction = Vector3.new(
        direction.X,
        0,
        direction.Z
    )

    if direction.Magnitude < 0.05 then

        direction =
            Vector3.new(
                -root.CFrame.LookVector.X,
                0,
                -root.CFrame.LookVector.Z
            )
    end

    direction =
        direction.Unit

    return root.Position
        + direction
        * WalkAwayDistance
end

-- =========================================================
-- FIREBRUTE CONTROLLER
-- =========================================================

local function StartFireBrute()
    task.spawn(function()

        local target = nil
        local previousTarget = nil

        local state = "Find"

        local awayPosition = nil
        local lockStartTime = 0

        while FireBruteEnabled do

            local character =
                Player.Character

            local humanoid =
                character
                and character:FindFirstChildOfClass(
                    "Humanoid"
                )

            local root =
                character
                and character:FindFirstChild(
                    "HumanoidRootPart"
                )

            if not humanoid or not root then
                task.wait(0.1)
                continue
            end

            -- Wait for respawn if dead
            if humanoid.Health <= 0 then

                target = nil
                awayPosition = nil
                state = "Find"

                task.wait(0.1)
                continue
            end

            -- =================================================
            -- FIND
            -- =================================================

            if state == "Find" then

                target =
                    GetNearestFireBrute(
                        root,
                        previousTarget
                    )

                if target then

                    state = "Spin"

                else

                    previousTarget = nil

                    target =
                        GetNearestFireBrute(
                            root,
                            nil
                        )

                    if target then
                        state = "Spin"
                    end
                end
            end

            -- =================================================
            -- TARGET VALID
            -- =================================================

            if target
                and target.Parent
            then

                -- =============================================
                -- SPIN
                -- =============================================

                if state == "Spin" then

                    humanoid:Move(
                        Vector3.zero,
                        false
                    )

                    humanoid:MoveTo(
                        root.Position
                    )

                    local facing =
                        FaceTarget(
                            root,
                            target,
                            0.1
                        )

                    if facing then
                        state =
                            "WalkToward"
                    end
                end

                -- =============================================
                -- WALK TOWARD
                -- =============================================

                if state == "WalkToward" then

                    local distance =
                        GetDistanceToModel(
                            root,
                            target
                        )

                    if distance
                        <= StopDistance
                    then

                        humanoid:Move(
                            Vector3.zero,
                            false
                        )

                        humanoid:MoveTo(
                            root.Position
                        )

                        awayPosition =
                            GetWalkAwayPosition(
                                root,
                                target
                            )

                        state =
                            "WalkAway"

                    else

                        humanoid:MoveTo(
                            GetModelCenter(target)
                        )
                    end
                end

                -- =============================================
                -- WALK AWAY
                -- =============================================

                if state == "WalkAway" then

                    if not awayPosition then

                        awayPosition =
                            GetWalkAwayPosition(
                                root,
                                target
                            )
                    end

                    local distance =
                        (
                            root.Position
                            - awayPosition
                        ).Magnitude

                    if distance <= 2 then

                        humanoid:Move(
                            Vector3.zero,
                            false
                        )

                        humanoid:MoveTo(
                            root.Position
                        )

                        awayPosition = nil

                        lockStartTime =
                            os.clock()

                        state =
                            "Lock"

                    else

                        humanoid:MoveTo(
                            awayPosition
                        )
                    end
                end

                -- =============================================
                -- LOCK
                -- =============================================

                if state == "Lock" then

                    humanoid:Move(
                        Vector3.zero,
                        false
                    )

                    humanoid:MoveTo(
                        root.Position
                    )

                    FaceTarget(
                        root,
                        target,
                        0.1
                    )

                    if os.clock()
                        - lockStartTime
                        >= TargetTimeout
                    then

                        previousTarget =
                            target

                        target = nil
                        awayPosition = nil

                        state =
                            "Find"
                    end
                end

            else

                previousTarget =
                    target

                target = nil
                awayPosition = nil

                humanoid:Move(
                    Vector3.zero,
                    false
                )

                humanoid:MoveTo(
                    root.Position
                )

                state =
                    "Find"
            end

            task.wait(0.1)
        end
    end)
end

-- =========================================================
-- RESPAWN ROUTE
-- =========================================================

local Route = {

    -- Point 1:
    -- Get into a good starting position
    Vector3.new(
        22853.3047,
        800.6317,
        -1905.5050
    ),

    -- Point 2:
    -- Go straight to bridge entrance
    Vector3.new(
        22661.3848,
        798.9913,
        -2012.9749
    ),

    -- Point 3:
    -- Cross the bridge
    Vector3.new(
        22673.7344,
        799.5940,
        -2129.7021
    )
}

local function WalkTo(position)

    local character =
        Player.Character

    if not character then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid or not root then
        return false
    end

    while Player.Character == character
        and humanoid.Health > 0
    do

        local distance =
            (
                root.Position
                - position
            ).Magnitude

        if distance <= 3 then
            return true
        end

        humanoid:MoveTo(position)

        task.wait(0.15)
    end

    return false
end

local function WalkRoute()

    local character =
        Player.Character

    if not character then
        return
    end

    local humanoid =
        character:WaitForChild(
            "Humanoid"
        )

    if humanoid.Health <= 0 then
        return
    end

    for _, position in ipairs(Route) do

        local reached =
            WalkTo(position)

        if not reached then
            return
        end
    end
end

-- =========================================================
-- UI: FIRE MAGE
-- =========================================================

Tab:CreateToggle({
    Name = "Fire Mage [ BOSS ]",
    CurrentValue = false,
    Flag = "FireMageEnabled",

    Callback = function(Value)

        FireMageEnabled =
            Value

        if Value then
            StartFireMage()
        end
    end
})

Tab:CreateInput({
    Name = "Attack Distance",
    CurrentValue = "1",
    PlaceholderText = "Enter distance",
    RemoveTextAfterFocusLost = false,
    Flag = "AttackDistance",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number >= 0
        then
            AttackDistance =
                number
        end
    end
})

Tab:CreateInput({
    Name = "Dodge Min",
    CurrentValue = "1.5",
    PlaceholderText = "Seconds",
    RemoveTextAfterFocusLost = false,
    Flag = "DodgeMin",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number > 0
        then
            DodgeMin =
                number
        end
    end
})

Tab:CreateInput({
    Name = "Dodge Max",
    CurrentValue = "3",
    PlaceholderText = "Seconds",
    RemoveTextAfterFocusLost = false,
    Flag = "DodgeMax",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number > 0
        then
            DodgeMax =
                number
        end
    end
})

-- =========================================================
-- UI: FIREBRUTE
-- =========================================================

Tab:CreateToggle({
    Name = "FireBrute [ MOBS ]",
    CurrentValue = false,
    Flag = "FireBruteEnabled",

    Callback = function(Value)

        FireBruteEnabled =
            Value

        if Value then
            StartFireBrute()
        end
    end
})

Tab:CreateInput({
    Name = "Spin Speed",
    CurrentValue = "360",
    PlaceholderText = "Degrees per second",
    RemoveTextAfterFocusLost = false,
    Flag = "SpinSpeed",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number > 0
        then
            SpinSpeed =
                number
        end
    end
})

Tab:CreateInput({
    Name = "Stop Distance",
    CurrentValue = "5",
    PlaceholderText = "Enter distance",
    RemoveTextAfterFocusLost = false,
    Flag = "StopDistance",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number >= 0
        then
            StopDistance =
                number
        end
    end
})

Tab:CreateInput({
    Name = "Walk Away Distance",
    CurrentValue = "15",
    PlaceholderText = "Enter distance",
    RemoveTextAfterFocusLost = false,
    Flag = "WalkAwayDistance",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number >= 0
        then
            WalkAwayDistance =
                number
        end
    end
})

Tab:CreateInput({
    Name = "Target Timeout",
    CurrentValue = "5",
    PlaceholderText = "Seconds",
    RemoveTextAfterFocusLost = false,
    Flag = "TargetTimeout",

    Callback = function(Text)

        local number =
            tonumber(Text)

        if number
            and number >= 0
        then
            TargetTimeout =
                number
        end
    end
})

-- =========================================================
-- RESPAWN HANDLER
-- =========================================================

Player.CharacterAdded:Connect(function(character)

    character:WaitForChild(
        "Humanoid"
    )

    character:WaitForChild(
        "HumanoidRootPart"
    )

    -- Only run the route if at least
    -- one automation controller is enabled.
    if FireMageEnabled
        or FireBruteEnabled
    then

        task.wait(1)

        WalkRoute()
    end
end)