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

local AttackDistance = 1
local DodgeMin = 1.5
local DodgeMax = 3

local SpinSpeed = 360
local StopDistance = 5
local WalkAwayDistance = 15
local TargetTimeout = 5

-- =========================================================
-- GLOBAL STATE
-- =========================================================

-- When true, NOTHING except the respawn route is allowed
-- to control the character's movement.
local RespawnRouteActive = false
local RespawnRouteRunning = false

-- Prevent duplicate controller loops.
local FireMageControllerRunning = false
local FireBruteControllerRunning = false

-- Current targets.
local FireMageTarget = nil
local FireBruteTarget = nil

-- FireBrute state.
local FireBrutePreviousTarget = nil
local FireBruteState = "Find"
local FireBruteAwayPosition = nil
local FireBruteLockStart = 0

-- FireMage dodge state.
local FireMageDodgeSide = 1
local FireMageNextDodgeTime = 0

-- =========================================================
-- CHARACTER HELPERS
-- =========================================================

local function GetCharacter()
    local character = Player.Character

    if not character then
        return nil, nil, nil
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    return character, humanoid, root
end

local function StopCharacter(humanoid, root)
    if not humanoid or not root then
        return
    end

    humanoid:Move(Vector3.zero, false)
    humanoid:MoveTo(root.Position)
end

-- =========================================================
-- MODEL HELPERS
-- =========================================================

local function GetModelCenter(model)
    if not model or not model.Parent then
        return nil
    end

    local success, cf = pcall(function()
        return model:GetBoundingBox()
    end)

    if not success or not cf then
        return nil
    end

    return cf.Position
end

local function GetDistanceToModel(root, model)
    if not root or not model or not model.Parent then
        return math.huge
    end

    local success, cf, size =
        pcall(function()
            return model:GetBoundingBox()
        end)

    if not success or not cf or not size then
        return math.huge
    end

    local localPos =
        cf:PointToObjectSpace(root.Position)

    local half =
        size / 2

    local closest =
        Vector3.new(
            math.clamp(
                localPos.X,
                -half.X,
                half.X
            ),

            math.clamp(
                localPos.Y,
                -half.Y,
                half.Y
            ),

            math.clamp(
                localPos.Z,
                -half.Z,
                half.Z
            )
        )

    local worldPoint =
        cf:PointToWorldSpace(closest)

    return (
        root.Position
        - worldPoint
    ).Magnitude
end

-- =========================================================
-- FIRE MAGE FINDER
-- =========================================================

local function GetFireMage()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "FireMage"
            and obj:IsA("Model")
            and obj.Parent
        then
            return obj
        end
    end

    return nil
end

-- =========================================================
-- FIRE BRUTE FINDER
-- =========================================================

local function GetNearestFireBrute(root, excludedTarget)
    local nearest = nil
    local nearestDistance = math.huge

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "FireBrute"
            and obj:IsA("Model")
            and obj.Parent
            and obj ~= excludedTarget
        then
            local center =
                GetModelCenter(obj)

            if center then
                local distance =
                    (
                        root.Position
                        - center
                    ).Magnitude

                if distance < nearestDistance then
                    nearest = obj
                    nearestDistance = distance
                end
            end
        end
    end

    return nearest
end

-- =========================================================
-- RESET FIRE MAGE
-- =========================================================

local function ResetFireMage()
    FireMageTarget = nil
    FireMageDodgeSide = 1
    FireMageNextDodgeTime = 0
end

-- =========================================================
-- RESET FIRE BRUTE
-- =========================================================

local function ResetFireBrute()
    FireBruteTarget = nil
    FireBrutePreviousTarget = nil
    FireBruteState = "Find"
    FireBruteAwayPosition = nil
    FireBruteLockStart = 0
end

-- =========================================================
-- RESET ALL COMBAT
-- =========================================================

local function ResetCombat()
    ResetFireMage()
    ResetFireBrute()

    local character, humanoid, root =
        GetCharacter()

    if humanoid and root then
        StopCharacter(humanoid, root)
    end
end

-- =========================================================
-- FIRE MAGE DODGE POSITION
-- =========================================================

local function GetDodgePosition(root, target, side)
    local targetPosition =
        GetModelCenter(target)

    if not targetPosition then
        return root.Position
    end

    local direction =
        root.Position
        - targetPosition

    direction =
        Vector3.new(
            direction.X,
            0,
            direction.Z
        )

    if direction.Magnitude < 0.05 then
        direction =
            Vector3.new(
                0,
                0,
                1
            )
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

    return
        targetPosition
        + direction * AttackDistance
        + sideDirection * side
end

-- =========================================================
-- FIRE MAGE CONTROLLER
-- =========================================================

local function StartFireMageController()

    if FireMageControllerRunning then
        return
    end

    FireMageControllerRunning = true

    task.spawn(function()

        while FireMageEnabled do

            -- Respawn route has absolute control.
            if RespawnRouteActive then
                ResetFireMage()
                task.wait(0.1)
                continue
            end

            local character, humanoid, root =
                GetCharacter()

            if not character
                or not humanoid
                or not root
            then
                ResetFireMage()
                task.wait(0.1)
                continue
            end

            if humanoid.Health <= 0 then
                ResetFireMage()
                task.wait(0.1)
                continue
            end

            -- =================================================
            -- FIND MAGE
            -- =================================================

            if not FireMageTarget
                or not FireMageTarget.Parent
            then

                FireMageTarget =
                    GetFireMage()

                FireMageNextDodgeTime = 0

                if FireMageTarget then
                    FireMageDodgeSide =
                        math.random(1, 2) == 1
                        and 1
                        or -1
                end
            end

            -- =================================================
            -- NO MAGE
            -- =================================================

            if not FireMageTarget
                or not FireMageTarget.Parent
            then

                ResetFireMage()

                task.wait(0.1)
                continue
            end

            -- =================================================
            -- FIRE MAGE OWNS MOVEMENT
            --
            -- This is the important part:
            -- FireBrute will NOT move the character while
            -- FireMage has a valid target.
            -- =================================================

            local distance =
                GetDistanceToModel(
                    root,
                    FireMageTarget
                )

            if distance > AttackDistance then

                local center =
                    GetModelCenter(
                        FireMageTarget
                    )

                if center then
                    humanoid:MoveTo(center)
                end

            else

                if os.clock()
                    >= FireMageNextDodgeTime
                then

                    FireMageDodgeSide =
                        math.random(1, 2) == 1
                        and 1
                        or -1

                    local minTime =
                        math.floor(
                            DodgeMin * 100
                        )

                    local maxTime =
                        math.floor(
                            DodgeMax * 100
                        )

                    if maxTime < minTime then
                        maxTime = minTime
                    end

                    local delayTime =
                        math.random(
                            minTime,
                            maxTime
                        ) / 100

                    FireMageNextDodgeTime =
                        os.clock()
                        + delayTime
                end

                local dodgePosition =
                    GetDodgePosition(
                        root,
                        FireMageTarget,
                        FireMageDodgeSide
                    )

                humanoid:MoveTo(
                    dodgePosition
                )
            end

            task.wait(0.1)
        end

        FireMageControllerRunning = false
        ResetFireMage()
    end)
end

-- =========================================================
-- FIRE BRUTE HELPERS
-- =========================================================

local function FaceTarget(root, target, deltaTime)

    if not target
        or not target.Parent
    then
        return false
    end

    local targetPosition =
        GetModelCenter(target)

    if not targetPosition then
        return false
    end

    local direction =
        targetPosition
        - root.Position

    direction =
        Vector3.new(
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

    look =
        Vector3.new(
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

local function GetWalkAwayPosition(root, target)

    local targetPosition =
        GetModelCenter(target)

    if not targetPosition then
        return root.Position
    end

    local direction =
        root.Position
        - targetPosition

    direction =
        Vector3.new(
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

    if direction.Magnitude < 0.05 then
        direction =
            Vector3.new(
                0,
                0,
                1
            )
    end

    direction =
        direction.Unit

    return
        root.Position
        + direction * WalkAwayDistance
end

-- =========================================================
-- FIRE BRUTE CONTROLLER
-- =========================================================

local function StartFireBruteController()

    if FireBruteControllerRunning then
        return
    end

    FireBruteControllerRunning = true

    task.spawn(function()

        while FireBruteEnabled do

            -- Respawn route has absolute control.
            if RespawnRouteActive then
                ResetFireBrute()
                task.wait(0.1)
                continue
            end

            local character, humanoid, root =
                GetCharacter()

            if not character
                or not humanoid
                or not root
            then
                ResetFireBrute()
                task.wait(0.1)
                continue
            end

            if humanoid.Health <= 0 then
                ResetFireBrute()
                task.wait(0.1)
                continue
            end

            -- =================================================
            -- FIRE MAGE MOVEMENT LOCK
            --
            -- If FireMage is enabled AND currently exists,
            -- FireBrute does NOT issue movement commands.
            -- =================================================

            if FireMageEnabled then

                local mage =
                    FireMageTarget

                if not mage
                    or not mage.Parent
                then
                    mage =
                        GetFireMage()

                    if mage then
                        FireMageTarget = mage
                    end
                end

                if mage
                    and mage.Parent
                then
                    ResetFireBrute()
                    task.wait(0.1)
                    continue
                end
            end

            -- =================================================
            -- FIND FIREBRUTE
            -- =================================================

            if FireBruteState == "Find"
                or not FireBruteTarget
                or not FireBruteTarget.Parent
            then

                FireBruteTarget =
                    GetNearestFireBrute(
                        root,
                        FireBrutePreviousTarget
                    )

                if FireBruteTarget then
                    FireBruteState = "Spin"
                    FireBruteAwayPosition = nil
                    FireBruteLockStart = 0
                else

                    FireBrutePreviousTarget = nil

                    FireBruteTarget =
                        GetNearestFireBrute(
                            root,
                            nil
                        )

                    if FireBruteTarget then
                        FireBruteState = "Spin"
                    end
                end
            end

            if not FireBruteTarget
                or not FireBruteTarget.Parent
            then
                ResetFireBrute()
                task.wait(0.1)
                continue
            end

            -- =================================================
            -- SPIN
            -- =================================================

            if FireBruteState == "Spin" then

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
                        FireBruteTarget,
                        0.1
                    )

                if facing then
                    FireBruteState =
                        "WalkToward"
                end

            -- =================================================
            -- WALK TOWARD
            -- =================================================

            elseif FireBruteState == "WalkToward" then

                local distance =
                    GetDistanceToModel(
                        root,
                        FireBruteTarget
                    )

                if distance <= StopDistance then

                    humanoid:Move(
                        Vector3.zero,
                        false
                    )

                    humanoid:MoveTo(
                        root.Position
                    )

                    FireBruteAwayPosition =
                        GetWalkAwayPosition(
                            root,
                            FireBruteTarget
                        )

                    FireBruteState =
                        "WalkAway"

                else

                    local center =
                        GetModelCenter(
                            FireBruteTarget
                        )

                    if center then
                        humanoid:MoveTo(center)
                    end
                end

            -- =================================================
            -- WALK AWAY
            -- =================================================

            elseif FireBruteState == "WalkAway" then

                if not FireBruteAwayPosition then

                    FireBruteAwayPosition =
                        GetWalkAwayPosition(
                            root,
                            FireBruteTarget
                        )
                end

                local distance =
                    (
                        root.Position
                        - FireBruteAwayPosition
                    ).Magnitude

                if distance <= 2 then

                    humanoid:Move(
                        Vector3.zero,
                        false
                    )

                    humanoid:MoveTo(
                        root.Position
                    )

                    FireBruteAwayPosition = nil

                    FireBruteLockStart =
                        os.clock()

                    FireBruteState =
                        "Lock"

                else

                    humanoid:MoveTo(
                        FireBruteAwayPosition
                    )
                end

            -- =================================================
            -- LOCK
            -- =================================================

            elseif FireBruteState == "Lock" then

                humanoid:Move(
                    Vector3.zero,
                    false
                )

                humanoid:MoveTo(
                    root.Position
                )

                FaceTarget(
                    root,
                    FireBruteTarget,
                    0.1
                )

                if os.clock()
                    - FireBruteLockStart
                    >= TargetTimeout
                then

                    FireBrutePreviousTarget =
                        FireBruteTarget

                    FireBruteTarget = nil
                    FireBruteAwayPosition = nil

                    FireBruteState =
                        "Find"
                end
            end

            task.wait(0.1)
        end

        FireBruteControllerRunning = false
        ResetFireBrute()
    end)
end

-- =========================================================
-- RESPAWN ROUTE
-- =========================================================

local Route = {

    -- 1. Good starting position
    Vector3.new(
        22853.3047,
        800.6317,
        -1905.5050
    ),

    -- 2. Straight to bridge entrance
    Vector3.new(
        22661.3848,
        798.9913,
        -2012.9749
    ),

    -- 3. Across the bridge
    Vector3.new(
        22673.7344,
        799.5940,
        -2129.7021
    )
}

local function WalkToRoutePoint(
    character,
    humanoid,
    root,
    position
)

    while RespawnRouteActive
        and Player.Character == character
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

local function RunRespawnRoute(character)

    if RespawnRouteRunning then
        return
    end

    RespawnRouteRunning = true
    RespawnRouteActive = true

    -- Immediately wipe combat state.
    ResetCombat()

    local humanoid =
        character:WaitForChild(
            "Humanoid",
            10
        )

    local root =
        character:WaitForChild(
            "HumanoidRootPart",
            10
        )

    if not humanoid
        or not root
    then

        RespawnRouteActive = false
        RespawnRouteRunning = false

        return
    end

    -- Give the new character a moment to fully load.
    task.wait(1)

    if humanoid.Health <= 0 then

        RespawnRouteActive = false
        RespawnRouteRunning = false

        return
    end

    -- =====================================================
    -- ROUTE OWNS MOVEMENT FROM HERE
    -- =====================================================

    for _, position in ipairs(Route) do

        if not WalkToRoutePoint(
            character,
            humanoid,
            root,
            position
        ) then

            RespawnRouteRunning = false

            return
        end
    end

    -- =====================================================
    -- ROUTE FINISHED
    -- =====================================================

    StopCharacter(
        humanoid,
        root
    )

    -- Fresh combat state after reaching main area.
    ResetCombat()

    RespawnRouteActive = false
    RespawnRouteRunning = false

end

-- =========================================================
-- DEATH / CHARACTER DETECTION
-- =========================================================

local function SetupCharacter(character)

    local humanoid =
        character:WaitForChild(
            "Humanoid",
            10
        )

    if not humanoid then
        return
    end

    -- Detect death BEFORE the new character appears.
    humanoid.Died:Connect(function()

        -- Immediately lock movement to respawn system.
        RespawnRouteActive = true

        -- Kill every old combat state.
        ResetCombat()

    end)
end

-- Setup current character.
if Player.Character then
    SetupCharacter(
        Player.Character
    )
end

-- =========================================================
-- CHARACTER ADDED
-- =========================================================

Player.CharacterAdded:Connect(function(character)

    SetupCharacter(character)

    -- Only run the route if at least one automation
    -- system is enabled.
    if FireMageEnabled
        or FireBruteEnabled
    then

        task.spawn(function()

            -- Wait for character parts.
            local humanoid =
                character:WaitForChild(
                    "Humanoid",
                    10
                )

            local root =
                character:WaitForChild(
                    "HumanoidRootPart",
                    10
                )

            if not humanoid or not root then
                return
            end

            RunRespawnRoute(character)

        end)

    else

        -- If automation is off, don't leave the route lock on.
        RespawnRouteActive = false
        RespawnRouteRunning = false

    end
end)

-- =========================================================
-- UI
-- =========================================================

Tab:CreateToggle({
    Name = "Fire Mage [ BOSS ]",
    CurrentValue = false,
    Flag = "FireMageEnabled",

    Callback = function(Value)

        FireMageEnabled = Value

        if Value then

            -- If we're currently on the respawn route,
            -- the route stays in control.
            if not RespawnRouteActive then
                StartFireMageController()
            end

        else

            ResetFireMage()

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
            AttackDistance = number
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

            DodgeMin = number

            if DodgeMax < DodgeMin then
                DodgeMax = DodgeMin
            end
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
                math.max(
                    number,
                    DodgeMin
                )
        end
    end
})

Tab:CreateToggle({
    Name = "FireBrute [ MOBS ]",
    CurrentValue = false,
    Flag = "FireBruteEnabled",

    Callback = function(Value)

        FireBruteEnabled = Value

        if Value then

            if not RespawnRouteActive then
                StartFireBruteController()
            end

        else

            ResetFireBrute()

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
            SpinSpeed = number
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
            StopDistance = number
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
            WalkAwayDistance = number
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
            and number > 0
        then
            TargetTimeout = number
        end
    end
})

print("Fire Auto loaded.")
