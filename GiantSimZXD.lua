local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "Fire Mage + FireBrute",
    LoadingTitle = "Fire Mage + FireBrute",
    LoadingSubtitle = "Boss + Mob Automation",
    ConfigurationSaving = {
        Enabled = false
    }
})

local Tab = Window:CreateTab("Main")

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local FireMageEnabled = false
local FireBruteEnabled = false

local AttackDistance = 1
local DodgeMin = 1.5
local DodgeMax = 3

local SpinSpeed = 360
local TargetTimeout = 5
local StopDistance = 5
local WalkAwayDistance = 15

--------------------------------------------------
-- GLOBAL MOVEMENT LOCK
--------------------------------------------------

local RespawnRouteActive = false

--------------------------------------------------
-- FIRE MAGE STATE
--------------------------------------------------

local FireMageTarget = nil
local FireMageDodgeSide = 1
local FireMageNextDodgeTime = 0

--------------------------------------------------
-- FIRE BRUTE STATE
--------------------------------------------------

local FireBruteTarget = nil
local FireBrutePreviousTarget = nil
local FireBruteState = "Find"
local FireBruteAwayPosition = nil
local FireBruteLockStartTime = 0

--------------------------------------------------
-- CHARACTER HELPERS
--------------------------------------------------

local function GetCharacter()
    return Player.Character
end

local function GetHumanoid()
    local character = GetCharacter()

    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function GetRoot()
    local character = GetCharacter()

    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------
-- MODEL HELPERS
--------------------------------------------------

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

--------------------------------------------------
-- FIRE MAGE FIND
--------------------------------------------------

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

--------------------------------------------------
-- FIRE MAGE DODGE POSITION
--------------------------------------------------

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

--------------------------------------------------
-- FIRE BRUTE FIND
--------------------------------------------------

local function GetNearestFireBrute(root, excludedTarget)
    local nearest = nil
    local nearestDistance = math.huge

    for _, obj in ipairs(workspace:GetDescendants()) do
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

--------------------------------------------------
-- FIRE BRUTE FACE TARGET
--------------------------------------------------

local function FaceTarget(root, target, deltaTime)
    if not target or not target.Parent then
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

    direction = direction.Unit

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

    look = look.Unit

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
                targetAngle - currentAngle
            ),
            math.cos(
                targetAngle - currentAngle
            )
        )

    if math.abs(difference)
        <= math.rad(3)
    then
        root.CFrame =
            CFrame.lookAt(
                root.Position,
                root.Position + direction
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

--------------------------------------------------
-- FIRE BRUTE WALK AWAY POSITION
--------------------------------------------------

local function GetWalkAwayPosition(root, target)
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
            Vector3.new(
                -root.CFrame.LookVector.X,
                0,
                -root.CFrame.LookVector.Z
            )
    end

    direction = direction.Unit

    return root.Position
        + direction * WalkAwayDistance
end

--------------------------------------------------
-- RESET FIRE MAGE
--------------------------------------------------

local function ResetFireMageState()
    FireMageTarget = nil
    FireMageDodgeSide = 1
    FireMageNextDodgeTime = 0
end

--------------------------------------------------
-- RESET FIRE BRUTE
--------------------------------------------------

local function ResetFireBruteState()
    FireBruteTarget = nil
    FireBrutePreviousTarget = nil
    FireBruteState = "Find"
    FireBruteAwayPosition = nil
    FireBruteLockStartTime = 0
end

--------------------------------------------------
-- STOP CURRENT COMBAT MOVEMENT
--------------------------------------------------

local function StopCombatMovement()
    local humanoid = GetHumanoid()
    local root = GetRoot()

    if humanoid and root then
        humanoid:Move(
            Vector3.zero,
            false
        )

        humanoid:MoveTo(
            root.Position
        )
    end
end

--------------------------------------------------
-- RESPAWN ROUTE
--------------------------------------------------

local Route = {
    Vector3.new(
        22853.3047,
        800.6317,
        -1905.5050
    ),

    Vector3.new(
        22661.3848,
        798.9913,
        -2012.9749
    ),

    Vector3.new(
        22673.7344,
        799.5940,
        -2129.7021
    )
}

--------------------------------------------------
-- WALK TO ROUTE POINT
--------------------------------------------------

local function WalkToRoutePoint(
    character,
    position
)
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
        and RespawnRouteActive
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

--------------------------------------------------
-- RUN RESPAWN ROUTE
--------------------------------------------------

local function RunRespawnRoute(character)
    if RespawnRouteActive then
        return
    end

    RespawnRouteActive = true

    --------------------------------------------------
    -- HARD RESET ALL COMBAT STATE
    --------------------------------------------------

    ResetFireMageState()
    ResetFireBruteState()

    --------------------------------------------------
    -- GIVE CHARACTER TIME TO LOAD
    --------------------------------------------------

    local humanoid =
        character:WaitForChild(
            "Humanoid"
        )

    local root =
        character:WaitForChild(
            "HumanoidRootPart"
        )

    task.wait(1)

    if Player.Character ~= character
        or humanoid.Health <= 0
    then
        RespawnRouteActive = false
        return
    end

    --------------------------------------------------
    -- ROUTE POINT 1
    --------------------------------------------------

    local reached =
        WalkToRoutePoint(
            character,
            Route[1]
        )

    if not reached then
        RespawnRouteActive = false
        return
    end

    --------------------------------------------------
    -- ROUTE POINT 2
    --------------------------------------------------

    reached =
        WalkToRoutePoint(
            character,
            Route[2]
        )

    if not reached then
        RespawnRouteActive = false
        return
    end

    --------------------------------------------------
    -- ROUTE POINT 3
    --------------------------------------------------

    reached =
        WalkToRoutePoint(
            character,
            Route[3]
        )

    if not reached then
        RespawnRouteActive = false
        return
    end

    --------------------------------------------------
    -- ROUTE FINISHED
    --------------------------------------------------

    humanoid:Move(
        Vector3.zero,
        false
    )

    humanoid:MoveTo(
        root.Position
    )

    --------------------------------------------------
    -- FRESH COMBAT STATES
    --------------------------------------------------

    ResetFireMageState()
    ResetFireBruteState()

    --------------------------------------------------
    -- GIVE ROUTE CONTROL BACK
    --------------------------------------------------

    RespawnRouteActive = false
end

--------------------------------------------------
-- FIRE MAGE CONTROLLER
--------------------------------------------------

local function StartFireMageController()
    task.spawn(function()

        while FireMageEnabled do

            --------------------------------------------------
            -- RESPAWN ROUTE HAS COMPLETE CONTROL
            --------------------------------------------------

            if RespawnRouteActive then
                ResetFireMageState()

                task.wait(0.1)
                continue
            end

            local character =
                GetCharacter()

            local humanoid =
                GetHumanoid()

            local root =
                GetRoot()

            if not character
                or not humanoid
                or not root
            then
                task.wait(0.1)
                continue
            end

            if humanoid.Health <= 0 then
                ResetFireMageState()

                task.wait(0.1)
                continue
            end

            --------------------------------------------------
            -- FIND FIRE MAGE
            --------------------------------------------------

            if not FireMageTarget
                or not FireMageTarget.Parent
            then
                FireMageTarget =
                    GetFireMage()

                if FireMageTarget then
                    FireMageNextDodgeTime = 0
                end
            end

            --------------------------------------------------
            -- FIRE MAGE MOVEMENT
            --------------------------------------------------

            if FireMageTarget
                and FireMageTarget.Parent
            then

                local distance =
                    GetDistanceToModel(
                        root,
                        FireMageTarget
                    )

                --------------------------------------------------
                -- WALK TO FIRE MAGE
                --------------------------------------------------

                if distance > AttackDistance then

                    humanoid:MoveTo(
                        GetModelCenter(
                            FireMageTarget
                        )
                    )

                --------------------------------------------------
                -- DODGE AROUND FIRE MAGE
                --------------------------------------------------

                else

                    if os.clock()
                        >= FireMageNextDodgeTime
                    then

                        if math.random(1, 2) == 1 then
                            FireMageDodgeSide = 1
                        else
                            FireMageDodgeSide = -1
                        end

                        local dodgeDelay =
                            math.random(
                                math.floor(
                                    DodgeMin * 100
                                ),
                                math.floor(
                                    DodgeMax * 100
                                )
                            ) / 100

                        FireMageNextDodgeTime =
                            os.clock()
                            + dodgeDelay
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

        ResetFireMageState()
    end)
end

--------------------------------------------------
-- FIRE BRUTE CONTROLLER
--------------------------------------------------

local function StartFireBruteController()
    task.spawn(function()

        while FireBruteEnabled do

            --------------------------------------------------
            -- RESPAWN ROUTE HAS COMPLETE CONTROL
            --------------------------------------------------

            if RespawnRouteActive then
                ResetFireBruteState()

                task.wait(0.1)
                continue
            end

            local character =
                GetCharacter()

            local humanoid =
                GetHumanoid()

            local root =
                GetRoot()

            if not character
                or not humanoid
                or not root
            then
                task.wait(0.1)
                continue
            end

            if humanoid.Health <= 0 then
                ResetFireBruteState()

                task.wait(0.1)
                continue
            end

            --------------------------------------------------
            -- FIRE MAGE GETS MOVEMENT CONTROL
            --
            -- This prevents FireBrute from slowing down
            -- the walk toward FireMage.
            --------------------------------------------------

            if FireMageEnabled
                and GetFireMage()
            then
                ResetFireBruteState()

                task.wait(0.1)
                continue
            end

            --------------------------------------------------
            -- FIND FIRE BRUTE
            --------------------------------------------------

            if FireBruteState == "Find" then

                FireBruteTarget =
                    GetNearestFireBrute(
                        root,
                        FireBrutePreviousTarget
                    )

                if FireBruteTarget then
                    FireBruteState = "Spin"
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

            --------------------------------------------------
            -- TARGET EXISTS
            --------------------------------------------------

            if FireBruteTarget
                and FireBruteTarget.Parent
            then

                --------------------------------------------------
                -- SPIN
                --------------------------------------------------

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
                end

                --------------------------------------------------
                -- WALK TOWARD
                --------------------------------------------------

                if FireBruteState == "WalkToward" then

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

                        humanoid:MoveTo(
                            GetModelCenter(
                                FireBruteTarget
                            )
                        )
                    end
                end

                --------------------------------------------------
                -- WALK AWAY
                --------------------------------------------------

                if FireBruteState == "WalkAway" then

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

                        FireBruteAwayPosition =
                            nil

                        FireBruteLockStartTime =
                            os.clock()

                        FireBruteState =
                            "Lock"

                    else

                        humanoid:MoveTo(
                            FireBruteAwayPosition
                        )
                    end
                end

                --------------------------------------------------
                -- LOCK
                --------------------------------------------------

                if FireBruteState == "Lock" then

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
                        - FireBruteLockStartTime
                        >= TargetTimeout
                    then

                        FireBrutePreviousTarget =
                            FireBruteTarget

                        FireBruteTarget =
                            nil

                        FireBruteAwayPosition =
                            nil

                        FireBruteState =
                            "Find"
                    end
                end

            else

                FireBrutePreviousTarget =
                    FireBruteTarget

                FireBruteTarget =
                    nil

                FireBruteAwayPosition =
                    nil

                humanoid:Move(
                    Vector3.zero,
                    false
                )

                humanoid:MoveTo(
                    root.Position
                )

                FireBruteState =
                    "Find"
            end

            task.wait(0.1)
        end

        ResetFireBruteState()
    end)
end

--------------------------------------------------
-- CHARACTER / DEATH HANDLING
--------------------------------------------------

local function SetupCharacter(character)

    local humanoid =
        character:WaitForChild(
            "Humanoid"
        )

    character:WaitForChild(
        "HumanoidRootPart"
    )

    --------------------------------------------------
    -- DEATH
    --------------------------------------------------

    humanoid.Died:Connect(function()

        --------------------------------------------------
        -- HARD STOP EVERYTHING
        --------------------------------------------------

        ResetFireMageState()
        ResetFireBruteState()

        StopCombatMovement()

        --------------------------------------------------
        -- ROUTE WILL TAKE OVER ON RESPAWN
        --------------------------------------------------

        if FireMageEnabled
            or FireBruteEnabled
        then
            RespawnRouteActive = true
        else
            RespawnRouteActive = false
        end
    end)
end

--------------------------------------------------
-- CURRENT CHARACTER
--------------------------------------------------

if Player.Character then
    SetupCharacter(
        Player.Character
    )
end

--------------------------------------------------
-- RESPAWN
--------------------------------------------------

Player.CharacterAdded:Connect(
    function(character)

        SetupCharacter(character)

        --------------------------------------------------
        -- ONLY RUN ROUTE IF AUTOMATION IS ENABLED
        --------------------------------------------------

        if FireMageEnabled
            or FireBruteEnabled
        then

            task.spawn(function()
                RunRespawnRoute(character)
            end)

        else

            RespawnRouteActive = false
        end
    end
)

--------------------------------------------------
-- UI
--------------------------------------------------

Tab:CreateToggle({
    Name = "Fire Mage [ BOSS ]",
    CurrentValue = false,
    Flag = "FireMage",
    Callback = function(Value)

        FireMageEnabled = Value

        if not Value then
            ResetFireMageState()
            return
        end

        StartFireMageController()
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

            DodgeMax = number

            if DodgeMax < DodgeMin then
                DodgeMax = DodgeMin
            end
        end
    end
})

Tab:CreateToggle({
    Name = "FireBrute [ MOBS ]",
    CurrentValue = false,
    Flag = "FireBrute",
    Callback = function(Value)

        FireBruteEnabled = Value

        if not Value then
            ResetFireBruteState()
            return
        end

        StartFireBruteController()
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
            TargetTimeout = number
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
