local QuestService = require(script.Parent.Farm.QuestService)
local EnemyService = require(script.Parent.Farm.EnemyService)
local MovementService = require(script.Parent.Farm.MovementService)
local CombatService = require(script.Parent.Farm.CombatService)
local StackTaskQueue = require(script.Parent.Farm.StackTaskQueue)

local QUEST_DIAGNOSTIC_INTERVAL = 1
local MAX_QUEST_DIAGNOSTIC_REPORT_LENGTH = 1400
local MAX_SPAWN_DIAGNOSTIC_REPORT_LENGTH = 1400
local QUEST_CONFIRMATION_TIMEOUT = 8
local QUEST_START_RETRY_INTERVAL = 2
local MAX_QUEST_START_ATTEMPTS = 3
local QUEST_DIALOGUE_RETREAT_DISTANCE = 32
local QUEST_DIALOGUE_RETREAT_INCREMENT = 24
local QUEST_DIALOGUE_MAX_RETREAT_DISTANCE = 80
local QUEST_DIALOGUE_MOVE_RETRY_INTERVAL = 0.5
local MAX_QUEST_DIALOGUE_MOVE_FAILURES = 3
local QUEST_GIVER_REQUEST_DELAY = 2
local FARM_STEP_INTERVAL = 0.1
local NPC_SCAN_INTERVAL = 0.15
local DOUBLE_QUEST_SCAN_INTERVAL = 0.5
local DOUBLE_QUEST_MAX_FALLBACK_DISTANCE = 3000
local SPAWN_SCAN_INTERVAL = 1
local TIKI_EVENT_SCAN_INTERVAL = 1
local TIKI_ACTION_INTERVAL = 0.4
local TIKI_SKILL_HOLD_SECONDS = 0.5
local FARM_SKILL_SCAN_INTERVAL = 0.4
local FARM_SKILL_PREPARE_TIMEOUT = 1.2
local FARM_SKILL_UNAVAILABLE_RETRY = 10
local FARM_SKILL_ATTACK_POSITION_TOLERANCE = 6
local GUN_KNOCKBACK_HOLD_SECONDS = 0.3
local FARM_GUN_SWAP_SETTLE_SECONDS = 0.6
local TIKI_PUZZLE_ATTACK_RANGE = 8
local TIKI_LOAD_ITEM_RETRY_INTERVAL = 3
local SPAWN_LOAD_GRACE = 1
local SPAWN_CYCLE_RETRY_INTERVAL = 2
local MAX_EMPTY_SPAWN_CYCLES = 2
local STACK_TASK_LOAD_TIMEOUT = 8

local MainFarm = {
    Running = false,
    MainFarmEnabled = false,
    Session = 0,
    AutoBusoGeneration = 0,
    Context = nil,
    StackTaskQueue = nil,
    ActiveStackTask = nil,
    StackTaskStartedAt = 0,
    StackInterruptedFarm = false,
}

local function diagnosticScalar(value)
    local valueType = typeof(value)
    if type(value) == "string" then
        local text = value:gsub("[%c]", " ")
        if #text > 80 then
            text = text:sub(1, 77) .. "..."
        end
        return string.format("%q", text)
    end
    if type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    return "<" .. tostring(valueType) .. ">"
end

local function questKey(candidate)
    return tostring(candidate.QuestName) .. ":" .. tostring(candidate.Id)
end

local function horizontalUnitVector(vector)
    local horizontal = Vector3.new(vector.X, 0, vector.Z)
    if horizontal.Magnitude <= 0.01 then
        return nil
    end
    return horizontal.Unit
end

local function boundedReason(value)
    local text = tostring(value or "no validated active-quest signal observed")
        :gsub("[%c]", " ")
    if #text > 120 then
        text = text:sub(1, 117) .. "..."
    end
    return text
end

local function questDataSummary(label, snapshot)
    if type(snapshot) ~= "table" then
        return label .. ": unavailable"
    end
    return string.format(
        "%s: reader=%s Guide.Data=%s QuestData.present=%s type=%s Task.type=%s evidence=%s",
        label,
        tostring(snapshot.ReaderState),
        tostring(snapshot.GuideDataType),
        tostring(snapshot.QuestDataPresent),
        tostring(snapshot.QuestDataType),
        tostring(snapshot.TaskType),
        boundedReason(snapshot.ReaderEvidence)
    )
end

local function diagnosticSeaName(compatibility)
    local workspace = compatibility and compatibility.Workspace
    local mapReadOk, mapName = pcall(function()
        return workspace and workspace:GetAttribute("MAP")
    end)
    if mapReadOk then
        if mapName == "Sea1" then
            return "First Sea"
        elseif mapName == "Sea2" then
            return "Second Sea"
        elseif mapName == "Sea3" then
            return "Third Sea"
        end
    end
    if not compatibility then
        return "Unknown"
    end
    if type(compatibility.IsFirstSea) == "function" then
        local ok, isFirstSea = pcall(compatibility.IsFirstSea, compatibility)
        if ok and isFirstSea then
            return "First Sea"
        end
    end
    if type(compatibility.IsThirdSea) == "function" then
        local ok, isThirdSea = pcall(compatibility.IsThirdSea, compatibility)
        if ok and isThirdSea then
            return "Third Sea"
        end
    end
    return "Unknown"
end

function MainFarm:_SetStatus(message, kind, playerMessage)
    local now = os.clock()
    if self.LastStatus == message
        and self.LastStatusPlayerMessage == playerMessage
        and now - (self.LastStatusAt or 0) < 1.5
    then
        return
    end
    self.LastStatus = message
    self.LastStatusAt = now
    self.LastStatusPlayerMessage = playerMessage
    if self.Context and self.Context.State then
        self.Context.State:SetStatus(message, kind, playerMessage)
    end
end

function MainFarm:_EnsureBaseServices()
    if self.QuestService and self.EnemyService and self.MovementService then
        return true
    end

    local context = self.Context
    if not context or not context.Compatibility then
        return false, "Hub compatibility adapter is unavailable"
    end

    local questService, questError = QuestService.new(context.Compatibility)
    if not questService then
        return false, questError
    end
    self.QuestService = questService
    self.EnemyService = EnemyService.new(context.Compatibility)
    self.MovementService = context.MovementService or MovementService.new(
        context.Compatibility,
        function(message, kind)
            self:_SetStatus(message, kind)
        end
    )
    return true
end

function MainFarm:_EnsureCombatService()
    if self.CombatService then
        return true
    end
    if self.CombatDependencyAttempted then
        if os.clock() - (self.LastCombatDependencyAttemptAt or 0) < 5 then
            return false, self.CombatDependencyError
        end
    end
    self.CombatDependencyAttempted = true
    self.LastCombatDependencyAttemptAt = os.clock()
    local combatService, combatError = CombatService.new(
        self.Context.Compatibility,
        self.EnemyService
    )
    if not combatService then
        self.CombatDependencyError = combatError
        return false, combatError
    end
    self.CombatService = combatService
    return true
end

function MainFarm:_IsCurrent(session)
    return self.Running and self.Session == session
end

function MainFarm:_HasEnabledStackTasks()
    return self.StackTaskQueue ~= nil and self.StackTaskQueue:HasEnabledTasks()
end

function MainFarm:_GetStackTaskLabel(entry)
    if entry and entry.Kind == "CakePrince" then
        return "Cake Prince"
    elseif entry and entry.Kind == "Fruit" then
        return entry.Instance and entry.Instance.Name or "spawned fruit"
    end
    return "stack task"
end

function MainFarm:_BeginStackTask(entry)
    self.ActiveStackTask = entry
    self.StackTaskStartedAt = os.clock()
    self.StackInterruptedFarm = self.MainFarmEnabled == true

    self:_ClearTarget()
    if self.MovementService then
        self.MovementService:Cancel()
    end
    local teleportFeature = self.Context and self.Context.TeleportFeature
    if teleportFeature and teleportFeature.CancelFarmTravel then
        teleportFeature:CancelFarmTravel()
    end
    if self.CombatService then
        self.CombatService:Cancel()
    end
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillTarget = nil
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self.FarmGunToolSettleUntil = 0
    self.GunKnockbackHold = nil
    self:_ResetSpawnSearch(nil)

    if self.TikiPuzzleActive then
        self.TikiPuzzleActive = false
        self.TikiPuzzleRestorePending = true
    end

    self:_SetStatus(
        "Stack task started: " .. self:_GetStackTaskLabel(entry),
        "success"
    )
end

function MainFarm:_FinishStackTask(entry, reason, markCompleted)
    if self.StackTaskQueue then
        self.StackTaskQueue:Complete(entry, markCompleted)
    end
    self.ActiveStackTask = nil
    self.StackTaskStartedAt = 0
    self.StackInterruptedFarm = false
    self:_ClearTarget()
    if self.MovementService then
        self.MovementService:Cancel()
    end
    local teleportFeature = self.Context and self.Context.TeleportFeature
    if teleportFeature and teleportFeature.CancelFarmTravel then
        teleportFeature:CancelFarmTravel()
    end
    if self.CombatService then
        self.CombatService:Cancel()
    end
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillTarget = nil
    self.FarmSkillPreparing = nil
    self.GunKnockbackHold = nil

    if self.MainFarmEnabled then
        self:_SetStatus(
            "Stack task complete: " .. self:_GetStackTaskLabel(entry)
                .. "; resuming Main Farming",
            "success"
        )
    else
        self:_SetStatus(
            "Stack task complete: " .. self:_GetStackTaskLabel(entry),
            "success"
        )
    end
    if reason then
        self:_SetStatus(reason, "warning")
    end
end

function MainFarm:_StepStackTasks(session)
    local queue = self.StackTaskQueue
    if not queue or not queue:HasEnabledTasks() then
        return false
    end

    local entry = self.ActiveStackTask
    if entry and not queue:IsEnabled(entry) then
        self:_FinishStackTask(entry, "Stack task turned off", false)
        return true
    end
    if not entry then
        entry = queue:PopNext()
        if entry then
            self:_BeginStackTask(entry)
        end
    end

    if not entry then
        if self.MainFarmEnabled then
            return false
        end
        self:_SetStatus("Stack Farming is on; waiting for Cake Prince or a fruit", "info")
        return true
    end

    local compatibility = self.Context and self.Context.Compatibility
    local character, humanoid, root
    if compatibility then
        character, humanoid, root = compatibility:GetCharacterParts()
    end
    if not character or not humanoid or not root then
        if self.MovementService then
            self.MovementService:Cancel()
        end
        self:_SetStatus("Stack Farming is waiting for your character", "warning")
        return true
    end

    if self.TikiPuzzleRestorePending then
        self:_HoldPosition(session)
        self:_RestoreTikiFarmWeapon()
        self:_SetStatus("Stack Farming is preparing your farming weapon", "info")
        return true
    end

    local target = entry.Instance
    local workspaceService = compatibility.Workspace
    if not target or not target.Parent then
        self:_FinishStackTask(entry)
        return true
    end

    if entry.Kind == "CakePrince" then
        if not workspaceService or not target:IsDescendantOf(workspaceService) then
            self:_FinishStackTask(entry)
            return true
        end
        if not self.EnemyService:IsAlive(target) then
            if os.clock() - (self.StackTaskStartedAt or os.clock()) < STACK_TASK_LOAD_TIMEOUT then
                self:_HoldPosition(session)
                self:_SetStatus("Waiting for Cake Prince to load", "info")
            else
                self:_FinishStackTask(entry, "Cake Prince did not become available")
            end
            return true
        end

        self:_EngageModeTarget(target, true, root, session, "stack")
        if not self.EnemyService:IsAlive(target) then
            self:_FinishStackTask(entry)
        end
        return true
    elseif entry.Kind == "Fruit" then
        if not workspaceService or not target:IsDescendantOf(workspaceService) then
            self:_FinishStackTask(entry)
            return true
        end
        local handle = target:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then
            if os.clock() - (self.StackTaskStartedAt or os.clock()) < STACK_TASK_LOAD_TIMEOUT then
                self:_HoldPosition(session)
                self:_SetStatus("Waiting for the spawned fruit to load", "info")
            else
                self:_FinishStackTask(entry, "Spawned fruit could not be reached")
            end
            return true
        end

        local distance = (root.Position - handle.Position).Magnitude
        local moved, moveResult = self:_MoveTo(
            handle.CFrame,
            session,
            2.5,
            true,
            "spawned fruit"
        )
        if not moved then
            self:_SetStatus("Waiting to travel to spawned fruit: " .. tostring(moveResult), "warning")
        elseif distance <= 8 then
            self:_SetStatus("At spawned fruit; waiting for pickup", "info")
        else
            entry.NearbySince = nil
            self:_SetStatus("Traveling to spawned fruit", "info")
        end
        if distance <= 8 then
            entry.NearbySince = entry.NearbySince or os.clock()
            if os.clock() - entry.NearbySince >= 20 then
                self:_SetStatus("Fruit pickup is taking longer than expected; retrying", "warning")
            end
        end
        return true
    end

    self:_FinishStackTask(entry, "Unsupported stack task; continuing the queue")
    return true
end

function MainFarm:_LogQuestDataSnapshot(phase, questState, force, readerEvidence)
    pcall(function()
        local report = self.QuestDiagnosticReport
        if type(report) ~= "table" then
            return
        end

        local guide = self.QuestService and self.QuestService.Guide
        local guideData = type(guide) == "table" and guide.Data or nil
        local guideDataType = type(guideData)
        local questData = guideDataType == "table" and guideData.QuestData or nil
        local questDataType = type(questData)
        local taskType = questDataType == "table" and type(questData.Task) or "n/a"
        local questDataPresent = questData ~= nil
        local signature = table.concat({
            tostring(phase),
            tostring(guideDataType),
            questDataPresent and "present" or "nil",
            tostring(questDataType),
            tostring(taskType),
            tostring(questState),
            boundedReason(readerEvidence),
        }, "|")
        local now = os.clock()
        if not force
            and signature == self.LastQuestDiagnosticSignature
            and now - (self.LastQuestDiagnosticAt or 0) < QUEST_DIAGNOSTIC_INTERVAL
        then
            return
        end

        self.LastQuestDiagnosticSignature = signature
        self.LastQuestDiagnosticAt = now
        local snapshot = {
            ReaderState = tostring(questState),
            GuideDataType = tostring(guideDataType),
            QuestDataPresent = tostring(questDataPresent),
            QuestDataType = tostring(questDataType),
            TaskType = tostring(taskType),
            ReaderEvidence = boundedReason(readerEvidence),
        }
        report.LatestQuestData = snapshot
        if phase == "post_request" then
            report.PostRequestQuestData = snapshot
        end
    end)
end

function MainFarm:_PrintQuestDiagnosticReport(report, reason, elapsed)
    pcall(function()
        local pcallOutcome
        if type(report.PcallSucceeded) == "boolean" then
            pcallOutcome = tostring(report.PcallSucceeded)
                .. (report.PcallSucceeded and " (returned; acceptance not inferred)"
                    or " (call raised inside pcall)")
        else
            pcallOutcome = "not reached (stage=" .. tostring(report.RequestStage) .. ")"
        end

        local lines = {
            "===== [QuestDiagnostic] REPORT BEGIN =====",
            "Sea: " .. diagnosticSeaName(self.Context and self.Context.Compatibility),
            "Dialogue deferred: " .. tostring(report.DialogueDeferred == true),
            "Candidate: quest=" .. tostring(report.CandidateQuestName)
                .. " id=" .. tostring(report.CandidateQuestId),
            "StartQuest: pcall_succeeded=" .. pcallOutcome
                .. " attempts=" .. tostring(report.AttemptCount or 0),
            "Result: type=" .. tostring(report.ResultType)
                .. " summary=" .. tostring(report.ResultSummary),
            questDataSummary("QuestData after request", report.PostRequestQuestData),
            questDataSummary("QuestData at end", report.LatestQuestData),
            string.format(
                "Confirmation: %s; elapsed_seconds=%.2f",
                tostring(reason),
                math.max(0, elapsed)
            ),
            "===== [QuestDiagnostic] REPORT END =====",
        }
        local text = table.concat(lines, "\n")
        if #text > MAX_QUEST_DIAGNOSTIC_REPORT_LENGTH then
            local endMarker = "\n===== [QuestDiagnostic] REPORT END ====="
            text = text:sub(1, MAX_QUEST_DIAGNOSTIC_REPORT_LENGTH - #endMarker - 18)
                .. "\n...[truncated]" .. endMarker
        end

        self.LastQuestDiagnosticReportText = text
        local copied = false
        local clipboardCallOk = pcall(function()
            if type(setclipboard) == "function" then
                setclipboard(text)
                copied = true
            end
        end)
        if clipboardCallOk and copied then
            print("[QuestDiagnostic] Clipboard copy succeeded.")
        else
            print(text)
        end
    end)
end

function MainFarm:_BuildFarmMasteryDiagnosticReport()
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings or {}
    local category = farmSettings.MasteryCategory
    local lines = {
        "===== [FarmMasteryDiagnostic] REPORT BEGIN =====",
        "Enabled: " .. tostring(farmSettings.FarmMastery == true),
        "Method: " .. tostring(category),
        "Health threshold: " .. tostring(farmSettings.MasteryHealthPercent),
        "Status: " .. tostring(self.LastStatus or "unavailable"),
        "Status age: " .. string.format("%.2f", math.max(0, os.clock() - (self.LastStatusAt or os.clock()))),
        "Skill active: " .. tostring(self.FarmSkillActive == true),
        "Next skill scan in: "
            .. string.format("%.2f", math.max(0, (self.NextFarmSkillScanAt or 0) - os.clock())),
    }

    local target = self.Target
    if target then
        local healthPercent = "unavailable"
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.MaxHealth > 0 then
            healthPercent = string.format("%.1f%%", humanoid.Health / humanoid.MaxHealth * 100)
        end
        table.insert(lines, "Target: " .. target.Name .. "; health=" .. healthPercent)
    else
        table.insert(lines, "Target: none")
    end

    local playerRoot
    if self.Context and self.Context.Compatibility then
        local _, _, currentRoot = self.Context.Compatibility:GetCharacterParts()
        playerRoot = currentRoot
    end
    local attackCFrame = self:_GetFarmAttackPosition(target, category)
    local attackPosition = attackCFrame and attackCFrame.Position
    local playerDistance = playerRoot and attackPosition
        and (playerRoot.Position - attackPosition).Magnitude
    local movement = self.MovementService and self.MovementService.Active
    local movementGoalDistance = movement and movement.Goal and attackPosition
        and (movement.Goal.Position - attackPosition).Magnitude
    local inSkillPosition = target
        and playerRoot
        and self:_IsAtFarmAttackPosition(target, playerRoot, category)
        or false
    table.insert(
        lines,
        "Skill gate: in_attack_position=" .. tostring(inSkillPosition == true)
            .. "; player_distance=" .. (playerDistance and string.format("%.1f", playerDistance) or "n/a")
            .. "; tolerance=" .. tostring(FARM_SKILL_ATTACK_POSITION_TOLERANCE)
            .. "; movement_active=" .. tostring(movement ~= nil)
            .. "; movement_holding=" .. tostring(movement and movement.Holding or false)
            .. "; movement_goal_distance="
            .. (movementGoalDistance and string.format("%.1f", movementGoalDistance) or "n/a")
    )

    local preparation = self.FarmSkillPreparing
    if preparation then
        table.insert(
            lines,
            "Preparation: tool=" .. tostring(preparation.ToolName)
                .. "; deadline_remaining="
                .. string.format("%.2f", math.max(0, (preparation.Deadline or 0) - os.clock()))
        )
    else
        table.insert(lines, "Preparation: none")
    end
    local gunSettleRemaining = math.max(
        0,
        (self.FarmGunToolSettleUntil or 0) - os.clock()
    )
    if gunSettleRemaining > 0 then
        table.insert(
            lines,
            "Gun hotbar swap: settling; remaining="
                .. string.format("%.2f", gunSettleRemaining)
        )
    end

    if not self.CombatService then
        local servicesReady, servicesError = self:_EnsureBaseServices()
        if servicesReady then
            self:_EnsureCombatService()
        else
            table.insert(lines, "Combat service: unavailable; " .. tostring(servicesError))
        end
    end
    if self.CombatService then
        local masteryTool = category
            and self.CombatService:FindSkillWeapon(
                category,
                farmSettings.FarmMastery == true
            )
        local player = self.Context and self.Context.Compatibility
            and self.Context.Compatibility.Player
        local character = player and player.Character
        local backpack = player and player:FindFirstChild("Backpack")
        local toolParent = masteryTool and masteryTool.Parent == character
                and "Character"
            or (masteryTool and masteryTool.Parent == backpack and "Backpack")
            or (masteryTool and masteryTool.Parent and masteryTool.Parent.Name)
            or "none"
        table.insert(
            lines,
            "Mastery tool: " .. (masteryTool and masteryTool.Name or "none")
                .. "; parent=" .. tostring(toolParent)
                .. "; enabled=" .. tostring(masteryTool and masteryTool.Enabled)
        )
        if category == "Gun" then
            local gunParent = self.LastMasteryGunM1Tool
                and self.LastMasteryGunM1Tool.Parent
                and self.LastMasteryGunM1Tool.Parent.Name
                or "none"
            table.insert(
                lines,
                "Gun M1 last: " .. tostring(self.LastMasteryGunM1Result or "not attempted")
                    .. "; tool="
                    .. tostring(self.LastMasteryGunM1Tool and self.LastMasteryGunM1Tool.Name or "none")
                    .. "; parent=" .. tostring(gunParent)
                    .. "; age="
                    .. string.format(
                        "%.2f",
                        math.max(0, os.clock() - (self.LastMasteryGunM1At or os.clock()))
                    )
            )
        end
        local diagnosticOk, diagnostic = pcall(
            self.CombatService.BuildFarmSkillDiagnostic,
            self.CombatService,
            farmSettings,
            category,
            farmSettings.FarmMastery == true
        )
        table.insert(
            lines,
            diagnosticOk and diagnostic or ("Combat diagnostic failed: " .. tostring(diagnostic))
        )
    else
        table.insert(lines, "Combat service: unavailable")
    end

    table.insert(lines, "===== [FarmMasteryDiagnostic] REPORT END =====")
    local text = table.concat(lines, "\n")
    if #text > 6000 then
        text = text:sub(1, 5980) .. "\n...[truncated]"
    end
    return text
end

function MainFarm:_BuildTikiPuzzleDiagnosticReport()
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings or {}
    local lines = {
        "===== [TikiPuzzleDiagnostic] REPORT BEGIN =====",
        "Farm mode: " .. tostring(farmSettings.FarmMode),
        "Puzzle phase active: " .. tostring(self.TikiPuzzleActive == true),
        "Puzzle event visible: " .. tostring(self.TikiEventActive == true),
        "Attack policy: owned Skull Guitar is loaded and uses TAP only; otherwise use a ready skill",
        "Farm Mastery setting: " .. tostring(farmSettings.FarmMastery == true)
            .. " (independent; does not control Tiki puzzle attacks)",
        "Status: " .. tostring(self.LastStatus or "unavailable"),
        "Status age: " .. string.format("%.2f", math.max(0, os.clock() - (self.LastStatusAt or os.clock()))),
    }

    local target = self.TikiEventTarget
    local targetPosition
    if target then
        local pivotOk, pivot = pcall(function()
            if target:IsA("Model") then
                return target:GetPivot()
            elseif target:IsA("BasePart") then
                return target.CFrame
            end
            return nil
        end)
        if pivotOk and typeof(pivot) == "CFrame" then
            targetPosition = pivot.Position
        end
        table.insert(
            lines,
            "Puzzle object: " .. target.Name
                .. "; parent=" .. tostring(target.Parent and target.Parent.Name or "none")
                .. "; AlreadyDestroyedClient="
                .. tostring(target:GetAttribute("AlreadyDestroyedClient") == true)
        )
    else
        table.insert(lines, "Puzzle object: none")
    end

    local playerRoot
    if self.Context and self.Context.Compatibility then
        local _, _, currentRoot = self.Context.Compatibility:GetCharacterParts()
        playerRoot = currentRoot
    end
    local distance = playerRoot and targetPosition
        and (playerRoot.Position - targetPosition).Magnitude
    table.insert(
        lines,
        "Object distance: " .. (distance and string.format("%.1f", distance) or "n/a")
            .. "; movement_active=" .. tostring(
                self.MovementService and self.MovementService.Active ~= nil
            )
    )

    local combatReady = self.CombatService ~= nil
    if not combatReady then
        combatReady = self:_EnsureCombatService() == true
    end
    if combatReady and self.CombatService then
        local guitar = self.CombatService:FindToolByName("Skull Guitar")
        local guitarOwned, guitarOwnershipError
        if not guitar then
            guitarOwned, guitarOwnershipError =
                self.Context.Compatibility:HasOwnedInventoryItem("Skull Guitar")
        end
        local player = self.Context and self.Context.Compatibility
            and self.Context.Compatibility.Player
        local character = player and player.Character
        local backpack = player and player:FindFirstChild("Backpack")
        local parent = guitar and guitar.Parent == character and "Character"
            or (guitar and guitar.Parent == backpack and "Backpack")
            or (guitar and guitar.Parent and guitar.Parent.Name)
            or "none"
        table.insert(
            lines,
            "Skull Guitar: " .. tostring(guitar and guitar.Name or "not loaded")
                .. "; parent=" .. tostring(parent)
                .. "; enabled=" .. tostring(guitar and guitar.Enabled)
                .. "; stored_inventory_owned="
                .. tostring(guitar and true or (guitarOwnershipError and "unknown" or guitarOwned))
        )

        local readyOk, readySkill, readyError = pcall(
            self.CombatService.FindReadyTikiSkill,
            self.CombatService
        )
        table.insert(
            lines,
            readyOk and readySkill
                and ("Ready puzzle skill: " .. readySkill.Category .. " "
                    .. readySkill.Key .. "; tool=" .. readySkill.Tool.Name)
                or ("Ready puzzle skill: none; reason="
                    .. tostring(readyOk and readyError or readySkill))
        )
    else
        table.insert(lines, "Combat service: unavailable")
    end

    local action = self.LastTikiAction
    if action then
        table.insert(
            lines,
            "Last puzzle action: " .. tostring(action.Action)
                .. "; object=" .. tostring(action.ObjectName)
                .. "; current_object_match=" .. tostring(action.Target == target)
                .. "; tool=" .. tostring(action.ToolName)
                .. "; result=" .. tostring(action.Result)
                .. "; client_firing_state="
                .. tostring(action.ClientFiringState)
                .. "; age="
                .. string.format("%.2f", math.max(0, os.clock() - (action.At or os.clock())))
        )
    else
        table.insert(lines, "Last puzzle action: none")
    end

    table.insert(lines, "===== [TikiPuzzleDiagnostic] REPORT END =====")
    return table.concat(lines, "\n")
end

function MainFarm:CopyStatusReport()
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings
    local tikiDiagnostic = self.TikiPuzzleActive == true
    local masteryDiagnostic = farmSettings
        and farmSettings.FarmMastery == true
        or self.FarmSkillPreparing ~= nil
    local text
    if tikiDiagnostic then
        text = self:_BuildTikiPuzzleDiagnosticReport()
        self.LastTikiPuzzleDiagnosticReportText = text
    elseif masteryDiagnostic then
        text = self:_BuildFarmMasteryDiagnosticReport()
        self.LastFarmMasteryDiagnosticReportText = text
    else
        text = self.LastQuestDiagnosticReportText
    end

    local movementDiagnostic = self.MovementService
        and self.MovementService.LastStallDiagnostic
    local teleportFeature = self.Context and self.Context.TeleportFeature
    local travelMovementDiagnostic = teleportFeature
        and teleportFeature.MovementService
        and teleportFeature.MovementService.LastStallDiagnostic
    if travelMovementDiagnostic
        and (not movementDiagnostic or travelMovementDiagnostic.At > movementDiagnostic.At)
    then
        movementDiagnostic = travelMovementDiagnostic
    end
    local movementDiagnosticIncluded = false
    if movementDiagnostic
        and type(movementDiagnostic.Text) == "string"
        and movementDiagnostic.Text ~= ""
        and os.clock() - (movementDiagnostic.At or 0) <= 600
    then
        if type(text) == "string" and text ~= "" then
            text = text .. "\n\n" .. movementDiagnostic.Text
        else
            text = movementDiagnostic.Text
        end
        movementDiagnosticIncluded = true
    end

    local gatewayDiagnosticIncluded = false
    local gatewayDiagnostic = teleportFeature
        and teleportFeature.BuildGatewayDiagnosticReport
        and teleportFeature:BuildGatewayDiagnosticReport()
    if type(gatewayDiagnostic) == "string" and gatewayDiagnostic ~= "" then
        if type(text) == "string" and text ~= "" then
            text = text .. "\n\n" .. gatewayDiagnostic
        else
            text = gatewayDiagnostic
        end
        gatewayDiagnosticIncluded = true
    end

    local compatibility = self.Context and self.Context.Compatibility
    local titleDiagnosticIncluded = false
    local titleDiagnostic = compatibility
        and compatibility.BuildTitleAccessDiagnosticReport
        and compatibility:BuildTitleAccessDiagnosticReport()
    if type(titleDiagnostic) == "string" and titleDiagnostic ~= "" then
        if type(text) == "string" and text ~= "" then
            text = text .. "\n\n" .. titleDiagnostic
        else
            text = titleDiagnostic
        end
        titleDiagnosticIncluded = true
    end

    if type(text) ~= "string" or text == "" then
        self:_SetStatus("No status report is available yet.", "warning")
        return true
    end

    local copied = false
    local clipboardCallOk = pcall(function()
        if type(setclipboard) == "function" then
            setclipboard(text)
            copied = true
        end
    end)
    if clipboardCallOk and copied then
        local copiedMessage = "Complete quest status report copied to clipboard."
        if gatewayDiagnosticIncluded then
            copiedMessage = "Status report including gateway details copied to clipboard."
        elseif movementDiagnosticIncluded then
            copiedMessage = "Status report including movement-stall details copied to clipboard."
        elseif tikiDiagnostic then
            copiedMessage = "Tiki puzzle diagnostic copied to clipboard."
        elseif masteryDiagnostic then
            copiedMessage = "Farm Mastery diagnostic copied to clipboard."
        elseif titleDiagnosticIncluded then
            copiedMessage = "Status report including title-access diagnostics copied to clipboard."
        end
        self:_SetStatus(
            copiedMessage,
            "success"
        )
    else
        print(text)
        self:_SetStatus("Clipboard unavailable; complete report printed to output.", "warning")
    end
    return true
end

function MainFarm:_PrintSpawnDiagnosticReport(report)
    pcall(function()
        local selected
        if report.SelectedName then
            local distance = type(report.SelectedDistance) == "number"
                and report.SelectedDistance == report.SelectedDistance
                and report.SelectedDistance < math.huge
                and string.format("%.1f", report.SelectedDistance)
                or "n/a"
            selected = "source=" .. tostring(report.SelectedSource)
                .. " name=" .. diagnosticScalar(report.SelectedName)
                .. " distance=" .. distance
        else
            selected = "none"
        end

        local moveAccepted = report.MovementAccepted == nil
            and "not_called"
            or tostring(report.MovementAccepted == true)
        local availability = report.IsSpawnAvailable == nil
            and "not_called_no_candidate"
            or tostring(report.IsSpawnAvailable == true)
        local lines = {
            "===== [SpawnDiagnostic] REPORT BEGIN =====",
            "Target NPC: " .. diagnosticScalar(report.TargetName),
            "EnemySpawns container found: "
                .. tostring(report.EnemySpawnsContainerFound == true),
            "Normal EnemySpawns marker: " .. tostring(report.NormalMarkerFound == true),
            "Hidden unparented marker: " .. tostring(report.HiddenMarkerFound == true)
                .. " (discovery_available="
                .. tostring(report.HiddenDiscoveryAvailable == true)
                .. ", loading=" .. tostring(report.HiddenDiscoveryLoading == true)
                .. ", checked=" .. tostring(report.HiddenDiscoveryChecked == true) .. ")",
            "Selected candidate: " .. selected,
            "IsSpawnAvailable: " .. availability,
            "MovementService:MoveTo accepted=" .. moveAccepted
                .. " started_this_call=" .. tostring(report.MovementStarted == true)
                .. " result=" .. diagnosticScalar(report.MovementResult or "not_called"),
            "===== [SpawnDiagnostic] REPORT END =====",
        }
        local text = table.concat(lines, "\n")
        if #text > MAX_SPAWN_DIAGNOSTIC_REPORT_LENGTH then
            local endMarker = "\n===== [SpawnDiagnostic] REPORT END ====="
            text = text:sub(1, MAX_SPAWN_DIAGNOSTIC_REPORT_LENGTH - #endMarker - 18)
                .. "\n...[truncated]" .. endMarker
        end

        local copied = false
        local clipboardCallOk = pcall(function()
            if type(setclipboard) == "function" then
                setclipboard(text)
                copied = true
            end
        end)
        if clipboardCallOk and copied then
            print("[SpawnDiagnostic] Clipboard copy succeeded.")
        else
            print(text)
        end
    end)
end

function MainFarm:_RecordSpawnDiagnostic(
    targetName,
    discovery,
    candidate,
    isAvailable,
    movementAccepted,
    movementResult
)
    local report = type(discovery) == "table" and discovery or {}
    report.TargetName = targetName
    report.IsSpawnAvailable = isAvailable
    report.MovementAccepted = movementAccepted
    report.MovementResult = movementResult
    report.MovementStarted = movementAccepted == true
        and (
            movementResult == "moving"
            or movementResult == "retargeted"
            or (
                type(movementResult) == "string"
                and movementResult:sub(1, 10) == "moving to "
            )
        )
    if candidate and not report.SelectedName then
        local candidateNameOk, candidateName = pcall(function()
            return candidate.Name
        end)
        if candidateNameOk then
            report.SelectedName = candidateName
        end
    end

    local signature = table.concat({
        tostring(report.TargetName),
        tostring(report.NormalMarkerFound == true),
        tostring(report.HiddenMarkerFound == true),
        tostring(report.HiddenDiscoveryAvailable == true),
        tostring(report.SelectedSource),
        tostring(report.SelectedName),
        tostring(report.IsSpawnAvailable),
        tostring(report.MovementAccepted),
        tostring(report.MovementStarted),
        tostring(report.MovementResult),
    }, "|")
    if signature == self.LastSpawnDiagnosticSignature then
        return
    end
    self.LastSpawnDiagnosticSignature = signature
    self:_PrintSpawnDiagnosticReport(report)
end

function MainFarm:_EndQuestDiagnosticWait(reason, now)
    local key = self.QuestDiagnosticWaitKey
    if not key then
        return
    end

    pcall(function()
        local startedAt = self.QuestDiagnosticWaitStartedAt or now
        self:_PrintQuestDiagnosticReport(
            self.QuestDiagnosticReport or {},
            reason,
            math.max(0, now - startedAt)
        )
    end)
    self.QuestDiagnosticWaitKey = nil
    self.QuestDiagnosticWaitStartedAt = nil
    self.QuestDiagnosticReport = nil
end

function MainFarm:_MoveTo(destination, session, threshold, keepSession, label)
    if not self.MovementService then
        return false
    end
    local teleportFeature = self.Context and self.Context.TeleportFeature
    if teleportFeature and teleportFeature.MoveFarmTo then
        local routed, routeResult = teleportFeature:MoveFarmTo(destination, {
            Speed = 190,
            Threshold = threshold,
            KeepSession = keepSession == true,
            Label = label or "farm target",
            IsCurrent = function()
                return self:_IsCurrent(session)
            end,
        })
        if routed then
            return true, routeResult
        end
    end
    return self.MovementService:MoveTo(destination, {
        Speed = 190,
        Threshold = threshold,
        KeepSession = keepSession == true,
        IsCurrent = function()
            return self:_IsCurrent(session)
        end,
    })
end

function MainFarm:_HoldPosition(session)
    if not self.MovementService then
        return false, "Movement service is unavailable"
    end
    return self.MovementService:HoldPosition(function()
        return self:_IsCurrent(session)
    end)
end

function MainFarm:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)
    local key = questKey(candidate)
    local recovery = self.QuestDialogueRecovery
    if recovery and recovery.CandidateKey ~= key then
        self.QuestDialogueRecovery = nil
        self.MovementService:Cancel()
        recovery = nil
    end

    local dialogueOpen = self.QuestService:IsQuestGiverDialogueOpen()
    if not dialogueOpen then
        if recovery then
            self.QuestDialogueRecovery = nil
            self.QuestDeferredForDialogue = true
            self.PendingQuestReachedAt = os.clock() - 2
        end
        return false
    end

    if not recovery then
        local direction = horizontalUnitVector(root.Position - giverCFrame.Position)
        if not direction then
            direction = horizontalUnitVector(-root.CFrame.LookVector)
                or Vector3.new(1, 0, 0)
        end
        recovery = {
            CandidateKey = key,
            Direction = direction,
            RetreatDistance = QUEST_DIALOGUE_RETREAT_DISTANCE,
            NextMoveAt = 0,
            MoveFailures = 0,
        }
        self.QuestDialogueRecovery = recovery
    end

    self.QuestDeferredForDialogue = true
    self.PendingQuestReachedAt = nil
    if self.TimedOutQuestKey == key then
        self.TimedOutQuestKey = nil
        self.QuestTimeoutReason = nil
        self.LastQuestAttemptKey = nil
        self.LastQuestAttemptAt = 0
        self.QuestStartAttemptCount = 0
    end

    if recovery.MoveFailures >= MAX_QUEST_DIALOGUE_MOVE_FAILURES then
        self:_SetStatus(
            "Could not move away from quest dialogue; move away manually to retry",
            "warning"
        )
        return true
    end

    local offset = root.Position - giverCFrame.Position
    local currentDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    if currentDistance >= recovery.RetreatDistance - 3 then
        if recovery.RetreatDistance >= QUEST_DIALOGUE_MAX_RETREAT_DISTANCE then
            self:_SetStatus(
                "Quest dialogue is still open; move farther from the giver to retry",
                "warning"
            )
            return true
        end
        recovery.RetreatDistance = math.min(
            QUEST_DIALOGUE_MAX_RETREAT_DISTANCE,
            recovery.RetreatDistance + QUEST_DIALOGUE_RETREAT_INCREMENT
        )
    end

    local now = os.clock()
    if now >= (recovery.NextMoveAt or 0) then
        local giverPosition = giverCFrame.Position
        local retreatPosition = Vector3.new(
            giverPosition.X + recovery.Direction.X * recovery.RetreatDistance,
            root.Position.Y,
            giverPosition.Z + recovery.Direction.Z * recovery.RetreatDistance
        )
        local moveAccepted, moveResult = self:_MoveTo(
            CFrame.new(retreatPosition),
            session,
            4,
            true
        )
        recovery.NextMoveAt = now + QUEST_DIALOGUE_MOVE_RETRY_INTERVAL
        if moveAccepted then
            recovery.MoveFailures = 0
        else
            recovery.MoveFailures = recovery.MoveFailures + 1
        end
    end

    if recovery.MoveFailures >= MAX_QUEST_DIALOGUE_MOVE_FAILURES then
        self:_SetStatus(
            "Could not move away from quest dialogue; move away manually to retry",
            "warning"
        )
    else
        self:_SetStatus("Quest dialogue open; moving away to dismiss it", "info")
    end
    return true
end

function MainFarm:_ClearTarget(preserveMovement)
    local hadTarget = self.Target ~= nil or self.TargetName ~= nil
    if hadTarget then
        if self.EnemyService then
            self.EnemyService:RestoreTargetCollision(self.Target)
        end
        if self.MovementService and not preserveMovement then
            self.MovementService:Cancel()
        end
    end
    self.Target = nil
    self.TargetName = nil
    self.TargetIsBoss = nil
    self.GunKnockbackHold = nil
    self.DoubleQuestFallbackFor = nil
    self.DoubleQuestFallbackName = nil
    self.DoubleQuestScanTarget = nil
    self.NextDoubleQuestScanAt = 0
    if self.CombatService then
        self.CombatService:ClearFarmSkillAimTarget()
    end
end

function MainFarm:_ResetSpawnSearch(targetName)
    if self.SpawnSearchTarget ~= targetName then
        self.LastSpawnDiagnosticSignature = nil
    end
    if self.EnemyService then
        self.EnemyService:ClearIgnoredSpawns()
    end
    self.SpawnSearchTarget = targetName
    self.SpawnCandidate = nil
    self.SpawnCandidateTargetName = nil
    self.SpawnCandidateDiagnostic = nil
    self.SpawnLoading = nil
    self.SpawnRetryAt = nil
    self.SpawnEmptyCycles = 0
    self.SpawnSearchExhausted = false
    self.NextSpawnSearchAt = 0
    self.NextEnemySearchAt = 0
    self.ModeSpawnMarkersExhausted = false
end

function MainFarm:_TimeoutQuestConfirmation(key, now)
    if key ~= self.QuestDiagnosticWaitKey and key ~= self.LastQuestAttemptKey then
        return
    end
    local reason = boundedReason(self.LastQuestStateReason)
    self.TimedOutQuestKey = key
    self.QuestTimeoutReason = reason
    self:_EndQuestDiagnosticWait("cooldown_elapsed_without_active_state", now)
    self:_SetStatus(
        "Quest confirmation timed out after 8 seconds: " .. reason,
        "error"
    )
end

function MainFarm:_GetQuestGiverRequestDelay()
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings
    return farmSettings and farmSettings.InstantAcceptQuest == true
        and 0
        or QUEST_GIVER_REQUEST_DELAY
end

function MainFarm:_RequestQuest(candidate, session)
    local key = questKey(candidate)
    local now = os.clock()
    if self.QuestDiagnosticWaitKey and self.QuestDiagnosticWaitKey ~= key then
        self:_EndQuestDiagnosticWait("candidate_changed_before_confirmation", now)
    end
    if self.TimedOutQuestKey == key then
        self:_SetStatus(
            "Quest confirmation timed out: " .. boundedReason(self.QuestTimeoutReason)
                .. "; toggle Main Farm to retry",
            "error"
        )
        return
    end
    local isNewCandidate = self.LastQuestAttemptKey ~= key
    if isNewCandidate then
        self.LastQuestAttemptKey = key
        self.LastQuestAttemptAt = 0
        self.QuestStartAttemptCount = 0
        self.QuestDiagnosticWaitKey = key
        self.QuestDiagnosticWaitStartedAt = now
        self.LastQuestDiagnosticReportText = nil
        self.QuestDiagnosticReport = {
            CandidateQuestName = diagnosticScalar(candidate.QuestName),
            CandidateQuestId = diagnosticScalar(candidate.Id),
            DialogueDeferred = self.QuestDeferredForDialogue == true,
            RequestStage = "pcall_not_reached",
            PcallSucceeded = nil,
            ResultType = "n/a",
            ResultSummary = "not returned",
            AttemptCount = 0,
        }
        self.QuestDeferredForDialogue = false
        self.PendingQuestTargetName = candidate.Mob
    end

    local confirmationStartedAt = self.QuestDiagnosticWaitStartedAt or now
    if now - confirmationStartedAt >= QUEST_CONFIRMATION_TIMEOUT then
        self:_TimeoutQuestConfirmation(key, now)
        return
    end

    local attempts = self.QuestStartAttemptCount or 0
    if attempts >= MAX_QUEST_START_ATTEMPTS then
        self:_SetStatus(
            "Waiting for active quest confirmation; "
                .. boundedReason(self.LastQuestStateReason),
            "warning"
        )
        return
    end
    if attempts > 0 and now - (self.LastQuestAttemptAt or 0) < QUEST_START_RETRY_INTERVAL then
        self:_SetStatus(
            "Waiting for active quest confirmation; "
                .. boundedReason(self.LastQuestStateReason),
            "warning"
        )
        return
    end

    self.LastQuestAttemptAt = now
    self.QuestStartAttemptCount = attempts + 1
    self.QuestDiagnosticReport.AttemptCount = self.QuestStartAttemptCount
    self.PendingQuestTargetName = candidate.Mob
    self:_SetStatus(
        "Requesting quest: " .. tostring(candidate.QuestName) .. " (ID "
            .. tostring(candidate.Id) .. ", attempt "
            .. tostring(self.QuestStartAttemptCount) .. "/" .. tostring(MAX_QUEST_START_ATTEMPTS)
            .. ")",
        "info"
    )
    local requested = self.QuestService:RequestStart(candidate)
    local requestDiagnostic = self.QuestService.LastStartDiagnostic
    if type(requestDiagnostic) == "table" then
        self.QuestDiagnosticReport.RequestStage = tostring(requestDiagnostic.Stage)
        self.QuestDiagnosticReport.PcallSucceeded = requestDiagnostic.PcallSucceeded
        self.QuestDiagnosticReport.ResultType = tostring(requestDiagnostic.ResultType)
        self.QuestDiagnosticReport.ResultSummary = tostring(requestDiagnostic.ResultSummary)
    end
    local stateReadOk, stateAfterRequest, activeTargetAfterRequest, readerEvidence = pcall(function()
        return self.QuestService:GetActiveQuestState()
    end)
    if not stateReadOk then
        stateAfterRequest = "diagnostic_read_error"
        activeTargetAfterRequest = nil
        readerEvidence = "active quest state reader raised an error"
    end
    self.LastQuestStateReason = readerEvidence
    self:_LogQuestDataSnapshot("post_request", stateAfterRequest, true, readerEvidence)
    if stateAfterRequest == "active" then
        if activeTargetAfterRequest == candidate.Mob then
            self:_EndQuestDiagnosticWait("active_state_observed", os.clock())
            self.TimedOutQuestKey = nil
            self.LastQuestAttemptKey = nil
            self.LastQuestAttemptAt = 0
            self.QuestStartAttemptCount = 0
            self.PendingQuestTargetName = nil
            self.PendingQuestKey = nil
            self.PendingQuestReachedAt = nil
            self:_SetStatus(
                "Quest confirmed by " .. boundedReason(readerEvidence),
                "success"
            )
        else
            self:_EndQuestDiagnosticWait("active_state_target_mismatch", os.clock())
            self.LastQuestAttemptKey = nil
            self.LastQuestAttemptAt = 0
            self.QuestStartAttemptCount = 0
            self.PendingQuestTargetName = nil
            self.PendingQuestKey = nil
            self.PendingQuestReachedAt = nil
            self:_SetStatus(
                "A different active quest target was observed; following its validated target",
                "warning"
            )
        end
    end
    if not self:_IsCurrent(session) then
        return
    end
    if stateAfterRequest ~= "active" then
        local message = requested
            and "StartQuest call returned; waiting for state evidence (response is not acceptance)"
            or "StartQuest call raised; quest acceptance remains unconfirmed"
        self:_SetStatus(message, "warning")
    elseif activeTargetAfterRequest ~= candidate.Mob then
        self:_SetStatus(
            "A different active quest target was observed; following its validated target",
            "warning"
        )
    end
end

function MainFarm:_BringMobsIfEnabled(target, playerRoot, targetIsBoss)
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings
    if not farmSettings or farmSettings.BringMobs ~= true or targetIsBoss == true then
        return 0
    end
    return self.EnemyService:BringMatchingMob(
        target,
        playerRoot,
        farmSettings.BringMobCount
    )
end

function MainFarm:_GetFarmAttackPosition(target, weaponCategory)
    if not target then
        return nil
    end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return nil
    end

    local targetOffset = weaponCategory == "Blox Fruit"
        and CFrame.new(-7, 20, 0)
        or CFrame.new(7, 20, 0)
    return targetRoot.CFrame * targetOffset
end

function MainFarm:_MoveToFarmAttackPosition(
    target,
    weaponCategory,
    session,
    threshold,
    keepSession,
    allowRetargetDuringSkill
)
    local knockbackHold = self.GunKnockbackHold
    if knockbackHold then
        if knockbackHold.Target == target and os.clock() < knockbackHold.Until then
            local held = self:_HoldPosition(session)
            if held then
                return true, "holding briefly after Gun M1"
            end
            self.GunKnockbackHold = nil
        else
            self.GunKnockbackHold = nil
        end
    end
    if self.FarmSkillActive
        and self.FarmSkillTarget == target
        and not allowRetargetDuringSkill
    then
        return true, "holding position for active skill"
    end
    local destination = self:_GetFarmAttackPosition(target, weaponCategory)
    if not destination then
        return false, "target has no attack-position root"
    end
    return self:_MoveTo(destination, session, threshold, keepSession)
end

function MainFarm:_IsAtFarmAttackPosition(target, playerRoot, weaponCategory)
    if not target or not playerRoot then
        return false
    end
    local attackCFrame = self:_GetFarmAttackPosition(target, weaponCategory)
    if not attackCFrame then
        return false
    end
    local attackPosition = attackCFrame.Position
    if (playerRoot.Position - attackPosition).Magnitude > FARM_SKILL_ATTACK_POSITION_TOLERANCE then
        return false
    end

    local movement = self.MovementService and self.MovementService.Active
    -- Ordinary farm skills stay blocked during travel. The character's actual
    -- position is authoritative when movement holds a nearby, stale goal.
    if movement and movement.Holding ~= true then
        return false
    end
    return true
end

function MainFarm:_GetMasteryCategory(target, farmSettings, allowMastery)
    if allowMastery == false
        or not farmSettings
        or farmSettings.FarmMastery ~= true
    then
        return nil
    end
    local category = farmSettings.MasteryCategory
    if category ~= "Blox Fruit" and category ~= "Gun" then
        return nil
    end
    local humanoid = target and target:FindFirstChildOfClass("Humanoid")
    local health = humanoid and humanoid.Health
    local maxHealth = humanoid and humanoid.MaxHealth
    if type(health) ~= "number"
        or type(maxHealth) ~= "number"
        or maxHealth <= 0
    then
        return nil
    end
    local threshold = math.clamp(
        tonumber(farmSettings.MasteryHealthPercent) or 40,
        tonumber(farmSettings.MasteryHealthPercentMin) or 0,
        tonumber(farmSettings.MasteryHealthPercentMax) or 100
    )
    if (health / maxHealth) * 100 <= threshold then
        return category
    end
    return nil
end

function MainFarm:_SyncFarmSkillContext(
    target,
    weaponCategory,
    farmSettings,
    allowMastery,
    masteryCategory
)
    local masteryIsAllowed = farmSettings
        and farmSettings.FarmMastery == true
        and allowMastery ~= false
    local skillCategory = masteryCategory
    if not skillCategory and farmSettings and farmSettings.UseFarmSkills == true then
        skillCategory = weaponCategory
    end
    local contextWeaponCategory
    if not masteryCategory then
        contextWeaponCategory = weaponCategory
    end
    local selectedTool = skillCategory and self.CombatService
        and self.CombatService:FindSkillWeapon(skillCategory, true)
    local nextContext = {
        Target = target,
        WeaponCategory = contextWeaponCategory,
        FarmSkillsEnabled = masteryCategory == nil
            and farmSettings
            and farmSettings.UseFarmSkills == true,
        FarmMaterialsEnabled = farmSettings
            and farmSettings.FarmMaterialsEnabled == true,
        MasteryEnabled = masteryIsAllowed == true,
        MasteryMethod = masteryIsAllowed and farmSettings.MasteryCategory,
        MasteryThreshold = masteryIsAllowed and farmSettings.MasteryHealthPercent,
        AllowMastery = allowMastery ~= false,
        ActiveMasteryCategory = masteryCategory,
        SkillCategory = skillCategory,
        Tool = selectedTool,
        ToolParent = selectedTool and selectedTool.Parent,
    }
    local oldContext = self.FarmSkillContext
    local changed = not oldContext
        or oldContext.Target ~= nextContext.Target
        or oldContext.WeaponCategory ~= nextContext.WeaponCategory
        or oldContext.FarmSkillsEnabled ~= nextContext.FarmSkillsEnabled
        or oldContext.FarmMaterialsEnabled ~= nextContext.FarmMaterialsEnabled
        or oldContext.MasteryEnabled ~= nextContext.MasteryEnabled
        or oldContext.MasteryMethod ~= nextContext.MasteryMethod
        or oldContext.MasteryThreshold ~= nextContext.MasteryThreshold
        or oldContext.AllowMastery ~= nextContext.AllowMastery
        or oldContext.ActiveMasteryCategory ~= nextContext.ActiveMasteryCategory
        or oldContext.SkillCategory ~= nextContext.SkillCategory
        or oldContext.Tool ~= nextContext.Tool
        or oldContext.ToolParent ~= nextContext.ToolParent

    if changed then
        self.GunKnockbackHold = nil
        local gunToolChanged = nextContext.ActiveMasteryCategory == "Gun"
            and oldContext
            and (
                oldContext.ActiveMasteryCategory == "Gun"
                or oldContext.MasteryMethod == "Gun"
            )
            and (
                oldContext.Tool ~= nextContext.Tool
                or oldContext.ToolParent ~= nextContext.ToolParent
            )
        if gunToolChanged then
            self.FarmGunToolSettleUntil =
                os.clock() + FARM_GUN_SWAP_SETTLE_SECONDS
            if self.CombatService then
                self.CombatService:ResetGunM1Cooldown(nextContext.Tool)
            end
        end
        if self.FarmSkillActive and self.CombatService then
            self.CombatService:Cancel()
        end
        self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
        self.FarmSkillActive = false
        self.FarmSkillTarget = nil
        self.FarmSkillPreparing = nil
        self.FarmSkillIgnoredTools = {}
        self.NextFarmSkillScanAt = 0
        if self.CombatService then
            self.CombatService:ClearFarmSkillAimTarget()
        end
    end
    self.FarmSkillContext = nextContext
    return changed
end

function MainFarm:_TryStartFarmSkill(
    target,
    session,
    weaponCategory,
    farmSettings,
    playerRoot,
    allowMastery
)
    local masteryEnabled = farmSettings
        and farmSettings.FarmMastery == true
        and allowMastery ~= false
    local masteryCategory = self:_GetMasteryCategory(target, farmSettings, allowMastery)
    self:_SyncFarmSkillContext(
        target,
        weaponCategory,
        farmSettings,
        allowMastery,
        masteryCategory
    )
    local masteryGunM1Result
    local masteryGunM1Error
    local masteryFruitM1Result
    local masteryFruitM1Error
    local function tryMasteryGunM1()
        if masteryCategory ~= "Gun" or not self.CombatService then
            return
        end
        local equippedGun = self.CombatService:FindEquippedWeapon("Gun")
        if equippedGun then
            local inputSent, inputResult, shotStateChanged =
                self.CombatService:AttackGunM1(target, equippedGun)
            if inputSent then
                masteryGunM1Result = inputResult
                if shotStateChanged then
                    local now = os.clock()
                    local activeHold = self.GunKnockbackHold
                    if not activeHold
                        or activeHold.Target ~= target
                        or now >= activeHold.Until
                    then
                        self.GunKnockbackHold = {
                            Target = target,
                            Until = now + GUN_KNOCKBACK_HOLD_SECONDS,
                        }
                    end
                end
            elseif inputResult ~= "Gun is reloading"
                and inputResult ~= "Gun M1 is cooling down"
                and inputResult ~= "Selected mastery Gun is no longer equipped"
                and inputResult ~= "Gun M1 weapon did not equip"
            then
                masteryGunM1Error = inputResult
            end
            self.LastMasteryGunM1Tool = equippedGun
            self.LastMasteryGunM1Result = inputResult
            self.LastMasteryGunM1At = os.clock()
        else
            self.LastMasteryGunM1Tool = nil
            self.LastMasteryGunM1Result = "Waiting for the selected Gun to equip"
            self.LastMasteryGunM1At = os.clock()
        end
    end
    local function tryMasteryFruitM1()
        if masteryCategory ~= "Blox Fruit" or not self.CombatService then
            return
        end
        -- Resolve only the selected hotbar fruit, never stored inventory.
        local fruitTool = self.CombatService:FindSkillWeapon("Blox Fruit", true)
        if not fruitTool then
            return
        end
        local equippedFruit = self.CombatService:FindEquippedWeapon("Blox Fruit")
        if equippedFruit ~= fruitTool then
            local equipped, equipResult = self.CombatService:EquipTool(fruitTool)
            if not equipped then
                masteryFruitM1Error = tostring(equipResult)
                return
            end
            equippedFruit = self.CombatService:FindEquippedWeapon("Blox Fruit")
        end
        if equippedFruit ~= fruitTool then
            return
        end

        local callOk, inputSent, inputResult = pcall(
            self.CombatService.AttackM1,
            self.CombatService,
            target,
            70,
            "Blox Fruit",
            false,
            equippedFruit
        )
        if not callOk then
            masteryFruitM1Error = "Fruit M1 execution failed: " .. tostring(inputSent)
        elseif inputSent then
            masteryFruitM1Result = inputResult
        elseif inputResult ~= "Blox Fruit M1 is cooling down"
            and inputResult ~= "Selected mastery weapon is no longer equipped"
            and inputResult ~= "Selected fruit tool has no supported M1 remote"
            and inputResult ~= "Target is outside ClickM1 range"
        then
            masteryFruitM1Error = inputResult
        end
    end
    if self.FarmSkillActive then
        return true
    end

    local skillScanInterval = masteryCategory
        and FARM_STEP_INTERVAL
        or FARM_SKILL_SCAN_INTERVAL
    if masteryEnabled then
        local configuredCategory = farmSettings.MasteryCategory
        if configuredCategory ~= "Blox Fruit" and configuredCategory ~= "Gun" then
            self.FarmSkillPreparing = nil
            if self.CombatService then
                self.CombatService:ClearFarmSkillAimTarget()
            end
            self:_SetStatus("Farm Mastery needs a valid Blox Fruit or Gun method", "error")
            return true
        end
    end
    local skillCategory = masteryCategory or weaponCategory
    local ordinaryAtAttackPosition = masteryCategory ~= nil
        or self:_IsAtFarmAttackPosition(target, playerRoot, skillCategory)
    local shouldTrackSkillAim = masteryCategory ~= nil
        or (
            farmSettings
            and farmSettings.UseFarmSkills == true
            and ordinaryAtAttackPosition
        )
    if self.CombatService then
        if shouldTrackSkillAim then
            self.CombatService:SetFarmSkillAimTarget(target)
        else
            self.CombatService:ClearFarmSkillAimTarget()
        end
    end
    -- Ordinary farm skills wait for their attack position. Mastery follows the
    -- reference flow and may send a ready skill while approaching.
    if not ordinaryAtAttackPosition then
        self.FarmSkillPreparing = nil
        return false
    end
    if masteryCategory == nil
        and (not farmSettings or farmSettings.UseFarmSkills ~= true)
    then
        self.FarmSkillPreparing = nil
        return false
    end

    local now = os.clock()
    if masteryCategory == "Gun" and now < (self.FarmGunToolSettleUntil or 0) then
        self.FarmSkillPreparing = nil
        self:_SetStatus("Mastery waiting: Gun hotbar swap settling", "info")
        return true
    end
    if now < (self.NextFarmSkillScanAt or 0) then
        if masteryCategory then
            return true
        end
        return self.FarmSkillPreparing ~= nil
            and now < self.FarmSkillPreparing.Deadline
    end
    self.NextFarmSkillScanAt = now + skillScanInterval

    self.FarmSkillIgnoredTools = self.FarmSkillIgnoredTools or {}
    local skillIgnoredTools = self.FarmSkillIgnoredTools
    if masteryCategory then
        skillIgnoredTools = nil
    end
    for toolName, retryAt in pairs(self.FarmSkillIgnoredTools) do
        if now >= retryAt then
            self.FarmSkillIgnoredTools[toolName] = nil
        end
    end

    local skill, skillError, preparingTool = self.CombatService:FindReadyFarmSkill(
        farmSettings,
        skillCategory,
        skillIgnoredTools,
        masteryCategory
    )
    if preparingTool then
        -- A pending or inconsistent Skills row means no skill is ready to
        -- dispatch. Keep Gun Mastery progressing through M1 while that row
        -- resyncs; AttackGunM1 still enforces the game's Enabled/reload gates.
        if masteryCategory == "Gun" then
            tryMasteryGunM1()
            if masteryGunM1Result then
                self:_SetStatus(masteryGunM1Result, "info")
                return true
            elseif masteryGunM1Error then
                self:_SetStatus(
                    "Mastery Gun M1 unavailable: " .. tostring(masteryGunM1Error),
                    "warning"
                )
                return true
            end
        elseif masteryCategory == "Blox Fruit" then
            tryMasteryFruitM1()
            if masteryFruitM1Result then
                self:_SetStatus(masteryFruitM1Result, "info")
                return true
            elseif masteryFruitM1Error then
                self:_SetStatus(
                    "Mastery Fruit M1 unavailable: " .. tostring(masteryFruitM1Error),
                    "warning"
                )
                return true
            end
        end
        local preparation = self.FarmSkillPreparing
        if not preparation
            or preparation.Target ~= target
            or preparation.ToolName ~= preparingTool.Name
        then
            preparation = {
                Target = target,
                ToolName = preparingTool.Name,
                StartedAt = now,
                Deadline = now + FARM_SKILL_PREPARE_TIMEOUT,
            }
            self.FarmSkillPreparing = preparation
        end
        if now < preparation.Deadline then
            self:_SetStatus(
                masteryCategory and ("Preparing mastery skills: " .. tostring(skillError))
                    or ("Preparing skill controls for " .. preparingTool.Name),
                "info"
            )
            return true
        end
        if not masteryCategory then
            self.FarmSkillIgnoredTools[preparingTool.Name] =
                now + FARM_SKILL_UNAVAILABLE_RETRY
            self.FarmSkillPreparing = nil
            self.CombatService:EquipWeapon(weaponCategory)
            self:_SetStatus(
                "Skill controls did not load for " .. preparingTool.Name .. "; using M1",
                "warning"
            )
            return false
        end
        preparation.StartedAt = now
        preparation.Deadline = now + FARM_SKILL_PREPARE_TIMEOUT
        self:_SetStatus(
            "Mastery waiting: " .. tostring(skillError)
                .. "; retrying without re-equipping",
            "warning"
        )
        return true
    end
    self.FarmSkillPreparing = nil
    if not skill then
        if masteryCategory then
            if masteryCategory == "Gun" then
                tryMasteryGunM1()
            elseif masteryCategory == "Blox Fruit" then
                tryMasteryFruitM1()
            end
            if masteryGunM1Result then
                self:_SetStatus(masteryGunM1Result, "info")
            elseif masteryGunM1Error then
                self:_SetStatus(
                    "Mastery Gun M1 unavailable: " .. tostring(masteryGunM1Error),
                    "warning"
                )
            elseif masteryFruitM1Result then
                self:_SetStatus(masteryFruitM1Result, "info")
            elseif masteryFruitM1Error then
                self:_SetStatus(
                    "Mastery Fruit M1 unavailable: " .. tostring(masteryFruitM1Error),
                    "warning"
                )
                return true
            elseif skillError == "All selected skill keys are on cooldown" then
                self:_SetStatus("Mastery waiting: selected skills cooling down", "info")
            elseif skillError == "No selected skill keys are enabled" then
                self:_SetStatus("Mastery waiting: enable a selected skill key", "warning")
            elseif skillError
                and string.find(skillError, "No selected mastery skill is ready:", 1, true)
            then
                self:_SetStatus("Mastery waiting: " .. tostring(skillError), "info")
            elseif skillError then
                self:_SetStatus("Mastery skill lookup unavailable: " .. tostring(skillError), "warning")
            else
                self:_SetStatus("Mastery waiting: no selected skill is ready", "info")
            end
            return true
        end
        if skillError
            and skillError ~= "No selected skill keys are enabled"
            and skillError ~= "All selected skill keys are on cooldown"
        then
            self:_SetStatus("Farm skills unavailable: " .. tostring(skillError), "warning")
        end
        return false
    end

    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    local generation = self.FarmSkillGeneration
    self.FarmSkillActive = true
    self.FarmSkillTarget = target
    local originalCharacter = self.Character
    local combatService = self.CombatService
    local skillHold = tonumber(farmSettings.FarmSkillHoldSeconds) or 0.5
    if farmSettings.FarmSkillFastRelease == true then
        skillHold = 0.05
    end
    self:_SetStatus("Using " .. skill.Category .. " " .. skill.Key .. " skill", "success")
    local function runSkillAttempt()
        local callOk, activated, activationResult = pcall(function()
            return combatService:UseSkill(
                skill.Tool,
                skill.Key,
                target,
                skillHold,
                function()
                    local currentSettings = self.Context and self.Context.Config
                        and self.Context.Config.FarmSettings
                    local currentRoot
                    if self.Context and self.Context.Compatibility then
                        local _, _, characterRoot =
                            self.Context.Compatibility:GetCharacterParts()
                        currentRoot = characterRoot
                    end
                    return self:_IsCurrent(session)
                        and self.Target == target
                        and self.EnemyService:IsAlive(target)
                        and currentSettings
                        and currentSettings[skill.Setting] == true
                        and (
                            (masteryCategory
                                and currentSettings.FarmMastery == true
                                and self:_GetMasteryCategory(
                                    target,
                                    currentSettings,
                                    allowMastery
                                ) == masteryCategory)
                            or (
                                not masteryCategory
                                and currentSettings.FarmMaterialsEnabled ~= true
                                and currentSettings.UseFarmSkills == true
                                and self:_GetMasteryCategory(
                                    target,
                                    currentSettings,
                                    allowMastery
                                ) == nil
                            )
                        )
                        and (
                            masteryCategory ~= nil
                            or self:_IsAtFarmAttackPosition(
                                target,
                                currentRoot,
                                skillCategory
                            )
                        )
                end
            )
        end)
        if not callOk then
            return false, "Skill execution error: " .. tostring(activated)
        end
        return activated, activationResult
    end

    local function finishSkillAttempt(activated, activationResult)
        if self.FarmSkillGeneration == generation then
            self.FarmSkillActive = false
            if self.FarmSkillTarget == target then
                self.FarmSkillTarget = nil
            end
            self.NextFarmSkillScanAt = os.clock() + skillScanInterval
            if activated and self:_IsCurrent(session) and self.Target == target then
                self:_SetStatus(
                    "Sent " .. skill.Category .. " " .. skill.Key .. " key input",
                    "success"
                )
            elseif not activated and self:_IsCurrent(session) and self.Target == target then
                if masteryCategory then
                    self:_SetStatus(
                        "Mastery skill input failed: " .. tostring(activationResult),
                        "warning"
                    )
                else
                    self:_SetStatus(
                        "Farm skill was not sent: " .. tostring(activationResult),
                        "warning"
                    )
                end
            end
        end
        local currentCharacter = self.Context and self.Context.Compatibility
            and self.Context.Compatibility:GetCharacterParts()
        if originalCharacter and currentCharacter == originalCharacter
            and combatService == self.CombatService
            and not masteryCategory
        then
            local currentSettings = self.Context and self.Context.Config
                and self.Context.Config.FarmSettings
            local restoreCategory = currentSettings
                and currentSettings.WeaponCategory
                or weaponCategory
            local masteryCategoryNow = currentSettings
                and self:_GetMasteryCategory(target, currentSettings, allowMastery)
            if not masteryCategoryNow then
                combatService:EquipWeapon(restoreCategory)
            end
        end
    end

    -- Mastery only narrows the category and blocks unsafe fallback attacks;
    -- skill lookup, cooldown checks, aiming, input, and retries stay shared.
    task.spawn(function()
        finishSkillAttempt(runSkillAttempt())
    end)
    return true
end

function MainFarm:_StepAura(session, root)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    local radius = tonumber(farmSettings.AuraDistance) or 300
    local now = os.clock()
    local target = nil

    if self.Target and self.EnemyService:IsAlive(self.Target) then
        local targetRoot = self.Target:FindFirstChild("HumanoidRootPart")
        if targetRoot and (targetRoot.Position - root.Position).Magnitude <= radius then
            target = self.Target
        else
            self:_ClearTarget(true)
        end
    elseif self.Target or self.TargetName then
        self:_ClearTarget(true)
    end

    if not target and now >= (self.NextEnemySearchAt or 0) then
        target = self.EnemyService:FindNearestInRange(root.Position, radius)
        self.NextEnemySearchAt = now + NPC_SCAN_INTERVAL
    end

    if not target then
        self:_HoldPosition(session)
        self:_SetStatus(
            "Aura Farm waiting: no living enemy within " .. tostring(radius) .. " studs",
            "warning"
        )
        return
    end

    if self.Target ~= target then
        self:_ClearTarget()
        self.Target = target
        self.TargetName = target.Name
        self:_SetStatus("Aura target acquired: " .. target.Name, "success")
    end

    if not self.EnemyService:IsAlive(target) then
        self:_ClearTarget()
        self:_SetStatus("Aura target died or became invalid; reacquiring", "info")
        return
    end

    self.EnemyService:PrepareTarget(target, root)
    self:_BringMobsIfEnabled(target, root, false)
    local weaponCategory = farmSettings.WeaponCategory or "Melee"
    local masteryCategory = self:_GetMasteryCategory(target, farmSettings, true)
    local attackCategory = masteryCategory or weaponCategory
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        if not self:_TryStartFarmSkill(target, session, weaponCategory, farmSettings, root, true) then
            local equipped, equipResult = self.CombatService:EquipWeapon(weaponCategory)
            if equipped then
                local attackIssued, attackResult = self.CombatService:AttackM1(
                    target,
                    30,
                    weaponCategory,
                    farmSettings.AttackNoAnimation == true
                )
                if attackIssued then
                    self:_SetStatus("Aura M1 request issued; server damage is not yet confirmed", "info")
                else
                    self:_SetStatus("Aura combat waiting: " .. tostring(attackResult), "warning")
                end
            else
                self:_SetStatus("Aura combat waiting: " .. tostring(equipResult), "warning")
            end
        end
    else
        self:_SetStatus("Combat dependencies unavailable: " .. tostring(combatError), "error")
    end

    if self.EnemyService:IsAlive(target) then
        local targetRoot = target:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            self:_MoveToFarmAttackPosition(
                target,
                attackCategory,
                session,
                2.5,
                true,
                masteryCategory ~= nil
            )
            if (root.Position - targetRoot.Position).Magnitude >= 30 then
                self:_SetStatus("Approaching aura target: " .. target.Name, "info")
            end
        end
    else
        self:_ClearTarget()
        self:_SetStatus("Aura target died or became invalid; reacquiring", "info")
    end
end

function MainFarm:_StepModeQuestGiver(candidate, root, session)
    self:_ClearTarget(true)
    local giverPosition = candidate and candidate.Pos
    if typeof(giverPosition) ~= "Vector3" and typeof(giverPosition) ~= "CFrame" then
        self.MovementService:Cancel()
        self:_SetStatus("Selected mode quest giver has no usable position", "error")
        return
    end

    local candidateKey = questKey(candidate)
    if self.PendingQuestKey ~= candidateKey then
        self.PendingQuestKey = candidateKey
        self.PendingQuestReachedAt = nil
    end
    local giverCFrame = typeof(giverPosition) == "CFrame"
        and giverPosition
        or CFrame.new(giverPosition)
    if self.QuestDialogueRecovery
        and self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)
    then
        return
    end
    if (root.Position - giverCFrame.Position).Magnitude > 8 then
        if not self.QuestDeferredForDialogue then
            self.PendingQuestReachedAt = nil
        end
        self:_MoveTo(giverCFrame * CFrame.new(0, 4, 2), session, 8, true)
        self:_SetStatus("Approaching mode quest giver: " .. tostring(candidate.Name), "info")
        return
    end
    local requestDelay = self:_GetQuestGiverRequestDelay()
    if not self.PendingQuestReachedAt then
        if self.QuestDeferredForDialogue then
            self.PendingQuestReachedAt = os.clock() - 2
        elseif requestDelay == 0 then
            self.PendingQuestReachedAt = os.clock()
            self:_SetStatus("At mode quest giver; requesting quest immediately (RISK)", "warning")
        else
            self.PendingQuestReachedAt = os.clock()
            self:_SetStatus("At mode quest giver; waiting before quest request", "info")
            return
        end
    elseif os.clock() - self.PendingQuestReachedAt < requestDelay then
        return
    end
    if self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session) then
        return
    end
    self:_RequestQuest(candidate, session)
end

function MainFarm:_FindModeSpawn(targetNames, origin)
    local part, matchingMarkers, diagnostic, matchedTarget =
        self.EnemyService:FindSpawn(targetNames, origin)
    return part, matchedTarget, diagnostic, part ~= nil or matchingMarkers
end

function MainFarm:_EngageModeTarget(target, targetIsBoss, root, session, targetKind)
    if not self.EnemyService:IsAlive(target) then
        self:_ClearTarget()
        self:_SetStatus("Mode target died or became invalid; reacquiring", "info")
        return
    end

    if self.Target ~= target then
        self:_ClearTarget(true)
        self.Target = target
        self.TargetName = target.Name
        self.TargetIsBoss = targetIsBoss == true
        self.SpawnCandidate = nil
        self.SpawnCandidateTargetName = nil
        self.SpawnLoading = nil
        self.NextSpawnSearchAt = 0
        self:_SetStatus(
            (targetIsBoss and "Live boss acquired: "
                or targetKind == "material" and "Material target acquired: "
                or "Quest-family target acquired: ")
                .. target.Name,
            "success"
        )
    end

    self.EnemyService:PrepareTarget(target, root)
    self:_BringMobsIfEnabled(target, root, targetIsBoss)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
    local weaponCategory = farmSettings and farmSettings.WeaponCategory or "Melee"
    local masteryCategory = self:_GetMasteryCategory(
        target,
        farmSettings,
        targetIsBoss ~= true
    )
    local attackCategory = masteryCategory or weaponCategory
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        if not self:_TryStartFarmSkill(
            target,
            session,
            weaponCategory,
            farmSettings,
            root,
            targetIsBoss ~= true
        ) then
            local equipped, equipResult = self.CombatService:EquipWeapon(weaponCategory)
            if equipped then
                local attackIssued, attackResult = self.CombatService:AttackM1(
                    target,
                    30,
                    weaponCategory,
                    farmSettings and farmSettings.AttackNoAnimation == true
                )
                if attackIssued then
                    self:_SetStatus("M1 request issued; server damage is not yet confirmed", "info")
                else
                    self:_SetStatus("Combat waiting: " .. tostring(attackResult), "warning")
                end
            else
                self:_SetStatus("Combat waiting: " .. tostring(equipResult), "warning")
            end
        end
    else
        self:_SetStatus("Combat dependencies unavailable: " .. tostring(combatError), "error")
    end

    if self.EnemyService:IsAlive(target) then
        local targetRoot = target:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            self:_MoveToFarmAttackPosition(
                target,
                attackCategory,
                session,
                2.5,
                true,
                masteryCategory ~= nil
            )
            if (root.Position - targetRoot.Position).Magnitude >= 30 then
                self:_SetStatus("Approaching mode target: " .. target.Name, "info")
            end
        end
    else
        self:_ClearTarget(true)
        self:_SetStatus("Mode target died or became invalid; reacquiring", "info")
    end
end

function MainFarm:_RefreshTikiEventState(origin)
    local now = os.clock()
    if now < (self.NextTikiEventScanAt or 0) then
        return self.TikiEventActive == true, self.TikiEventTarget
    end
    self.NextTikiEventScanAt = now + TIKI_EVENT_SCAN_INTERVAL
    self.TikiEventActive = false
    self.TikiEventTarget = nil

    local workspace = self.Context.Compatibility.Workspace
    local map = workspace:FindFirstChild("Map")
    local outpost = map and map:FindFirstChild("TikiOutpost")
    local island = outpost and outpost:FindFirstChild("IslandModel")
    if not island then
        return false, nil
    end

    for index = 1, 4 do
        local eye = island:FindFirstChild("Eye" .. tostring(index), true)
        if not eye or not eye:IsA("BasePart") or eye.Transparency ~= 0 then
            return false, nil
        end
    end

    self.TikiEventActive = true
    local arena = island:FindFirstChild("EagleBossArena", true)
    if not arena then
        return true, nil
    end

    local nearestTarget = nil
    local nearestDistance = math.huge
    for _, eventObject in ipairs(arena:GetChildren()) do
        if eventObject.Name == "Tree"
            and eventObject:GetAttribute("AlreadyDestroyedClient") ~= true
        then
            local pivotOk, pivot = pcall(function()
                if eventObject:IsA("Model") then
                    return eventObject:GetPivot()
                elseif eventObject:IsA("BasePart") then
                    return eventObject.CFrame
                end
                return nil
            end)
            if pivotOk and typeof(pivot) == "CFrame" then
                local distance = (pivot.Position - origin).Magnitude
                if distance < nearestDistance then
                    nearestTarget = eventObject
                    nearestDistance = distance
                end
            end
        end
    end

    self.TikiEventTarget = nearestTarget
    return true, nearestTarget
end

function MainFarm:_RestoreTikiFarmWeapon()
    if not self.TikiPuzzleRestorePending then
        return true
    end

    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings or {}
    local category = farmSettings.WeaponCategory or "Melee"
    local combatReady, combatError = self:_EnsureCombatService()
    if not combatReady then
        self:_SetStatus(
            "Tiki phase ended; waiting to restore Farm Weapon: " .. tostring(combatError),
            "warning"
        )
        return false
    end
    local equipped, equipResult = self.CombatService:EquipWeapon(category)
    if not equipped then
        self:_SetStatus(
            "Tiki phase ended; waiting for Farm Weapon (" .. tostring(category) .. "): "
                .. tostring(equipResult),
            "warning"
        )
        return false
    end

    self.TikiPuzzleActive = false
    self.TikiPuzzleRestorePending = false
    self.NextTikiActionAt = 0
    self:_SetStatus("Tiki puzzle phase ended; restored Farm Weapon: " .. tostring(category), "success")
    return true
end

function MainFarm:_UseTikiPuzzleAction(eventTarget, targetPosition, session)
    local now = os.clock()
    if now < (self.NextTikiActionAt or 0) then
        return true
    end
    self.NextTikiActionAt = now + TIKI_ACTION_INTERVAL

    local combatReady, combatError = self:_EnsureCombatService()
    if not combatReady then
        self:_SetStatus("Tiki automation unavailable: " .. tostring(combatError), "warning")
        return true
    end

    local compatibility = self.Context.Compatibility
    local guitar = self.CombatService:FindToolByName("Skull Guitar")
    if not guitar then
        local ownsGuitar, ownershipError =
            compatibility:HasOwnedInventoryItem("Skull Guitar")
        if ownershipError then
            self.LastTikiAction = {
                At = now,
                Target = eventTarget,
                ObjectName = eventTarget and eventTarget.Name or "unknown",
                Action = "Waiting for Skull Guitar inventory check",
                ToolName = "Skull Guitar",
                Result = tostring(ownershipError),
                ClientFiringState = false,
            }
            self:_SetStatus(
                "Tiki puzzle waiting for Skull Guitar ownership check: " .. tostring(ownershipError),
                "warning"
            )
            return true
        end

        if ownsGuitar then
            if now >= (self.NextTikiLoadItemAt or 0) then
                self.NextTikiLoadItemAt = now + TIKI_LOAD_ITEM_RETRY_INTERVAL
                local commF, remoteError = compatibility:GetCommF()
                if not commF then
                    self.LastTikiAction = {
                        At = now,
                        Target = eventTarget,
                        ObjectName = eventTarget and eventTarget.Name or "unknown",
                        Action = "Loading owned Skull Guitar",
                        ToolName = "Skull Guitar",
                        Result = tostring(remoteError),
                        ClientFiringState = false,
                    }
                    self:_SetStatus(
                        "Owned Skull Guitar cannot be loaded: " .. tostring(remoteError),
                        "warning"
                    )
                else
                    local requestOk, requestResult = pcall(function()
                        return commF:InvokeServer("LoadItem", "Skull Guitar")
                    end)
                    self.LastTikiAction = {
                        At = now,
                        Target = eventTarget,
                        ObjectName = eventTarget and eventTarget.Name or "unknown",
                        Action = "Loading owned Skull Guitar",
                        ToolName = "Skull Guitar",
                        Result = requestOk and "LoadItem requested; waiting for tool"
                            or tostring(requestResult),
                        ClientFiringState = false,
                    }
                    if requestOk then
                        self:_SetStatus(
                            "Loading owned Skull Guitar for Tiki; waiting for it to appear",
                            "info"
                        )
                    else
                        self:_SetStatus(
                            "Owned Skull Guitar load request failed: " .. tostring(requestResult),
                            "warning"
                        )
                    end
                end
            else
                self:_SetStatus("Waiting for owned Skull Guitar to load", "info")
            end
            return true
        end
    end

    local tapStateChanged = false
    if guitar then
        local tapped, tapResult, shotStateChanged =
            self.CombatService:TapSkullGuitar(targetPosition)
        tapStateChanged = shotStateChanged == true
        self.LastTikiAction = {
            At = now,
            Target = eventTarget,
            ObjectName = eventTarget and eventTarget.Name or "unknown",
            Action = "Skull Guitar TAP",
            ToolName = guitar.Name,
            Result = tostring(tapResult),
            ClientFiringState = tapStateChanged,
        }
        if tapped and shotStateChanged == true then
            self:_SetStatus(
                "Sent owned Skull Guitar TAP; waiting for event update",
                "success"
            )
            return true
        elseif tapped then
            self:_SetStatus(
                "Skull Guitar TAP was attempted without firing-state confirmation; retrying TAP",
                "info"
            )
            return true
        elseif tapResult == "Skull Guitar is reloading" then
            self:_SetStatus("Equipped Skull Guitar is reloading; waiting to TAP again", "info")
        elseif tapResult == "Skull Guitar is cooling down" then
            self:_SetStatus("Equipped Skull Guitar is cooling down; waiting to TAP again", "info")
        else
            self:_SetStatus(
                "Equipped Skull Guitar TAP unavailable: " .. tostring(tapResult),
                "warning"
            )
        end
        return true
    end

    local skill, skillError = self.CombatService:FindReadyTikiSkill()
    if not skill then
        local reason = tostring(skillError)
        self.LastTikiAction = {
            At = now,
            Target = eventTarget,
            ObjectName = eventTarget and eventTarget.Name or "unknown",
            Action = "Waiting for ready puzzle skill",
            ToolName = "",
            Result = reason,
            ClientFiringState = tapStateChanged,
        }
        self:_SetStatus("Tiki puzzle waiting for any ready skill: " .. reason, "info")
        return true
    end

    self.LastTikiAction = {
        At = now,
        Target = eventTarget,
        ObjectName = eventTarget and eventTarget.Name or "unknown",
        Action = "Puzzle skill " .. skill.Category .. " " .. skill.Key,
        ToolName = skill.Tool and skill.Tool.Name or "none",
        Result = "dispatching",
        ClientFiringState = false,
    }
    local activated, activationResult = self.CombatService:UseSkill(
        skill.Tool,
        skill.Key,
        eventTarget,
        TIKI_SKILL_HOLD_SECONDS,
        function()
            return self:_IsCurrent(session)
                and self.TikiPuzzleActive == true
                and eventTarget.Parent ~= nil
                and eventTarget:GetAttribute("AlreadyDestroyedClient") ~= true
        end
    )
    self.LastTikiAction.Result = tostring(activationResult)
    if activated then
        self:_SetStatus(
            "Tiki puzzle: sent available " .. skill.Category .. " " .. skill.Key
                .. " skill key; waiting for event update",
            "success"
        )
    else
        self:_SetStatus("Tiki skill was not sent: " .. tostring(activationResult), "warning")
    end
    return true
end

function MainFarm:_StepTikiEventPhase(root, session)
    local eventActive, eventTarget = self:_RefreshTikiEventState(root.Position)
    if not eventActive then
        if self.TikiPuzzleActive then
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = true
        end
        if self.TikiPuzzleRestorePending then
            self:_HoldPosition(session)
            if self:_RestoreTikiFarmWeapon() then
                return false
            end
            return true
        end
        return false
    end
    self.TikiPuzzleActive = true
    self.TikiPuzzleRestorePending = false

    if self.Target then
        self:_ClearTarget()
    end
    if eventTarget and (
        eventTarget.Parent == nil
        or eventTarget:GetAttribute("AlreadyDestroyedClient") == true
    ) then
        self.NextTikiEventScanAt = 0
        self.TikiEventTarget = nil
        eventTarget = nil
    end

    if not eventTarget then
        self:_HoldPosition(session)
        self:_SetStatus(
            "Tiki event phase active; waiting for an available event object",
            "info"
        )
        return true
    end

    local pivotOk, pivot = pcall(function()
        if eventTarget:IsA("Model") then
            return eventTarget:GetPivot()
        elseif eventTarget:IsA("BasePart") then
            return eventTarget.CFrame
        end
        return nil
    end)
    if not pivotOk or typeof(pivot) ~= "CFrame" then
        self:_HoldPosition(session)
        self:_SetStatus("Tiki event object has no usable position; waiting safely", "warning")
        return true
    end

    local distance = (pivot.Position - root.Position).Magnitude
    if distance > TIKI_PUZZLE_ATTACK_RANGE then
        self:_MoveTo(pivot, session, 2.5, true)
        self:_SetStatus(
            "Approaching Tiki puzzle object (" .. string.format("%.1f", distance) .. " studs)",
            "info"
        )
    else
        self:_HoldPosition(session)
        self:_UseTikiPuzzleAction(eventTarget, pivot.Position, session)
    end
    return true
end

function MainFarm:_StepBossEventMode(
    session,
    root,
    farmMode,
    profile,
    questState,
    readerEvidence
)
    if type(profile) ~= "table" then
        self:_ClearTarget()
        self:_SetStatus("Unsupported farm mode: " .. tostring(farmMode), "error")
        return
    end

    local compatibility = self.Context.Compatibility
    local seaMethod = profile.Sea == "Second Sea" and "IsSecondSea"
        or profile.Sea == "Third Sea" and "IsThirdSea"
    local seaMethodAvailable = seaMethod and type(compatibility[seaMethod]) == "function"
    local inRequiredSea = false
    if seaMethodAvailable then
        local ok, result = pcall(compatibility[seaMethod], compatibility)
        inRequiredSea = ok and result == true
    end
    if not inRequiredSea then
        if self.TikiPuzzleActive then
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = true
        end
        if self.TikiPuzzleRestorePending then
            self:_HoldPosition(session)
            self:_RestoreTikiFarmWeapon()
        end
        self:_ClearTarget()
        self:_SetStatus(
            farmMode .. " requires " .. tostring(profile.Sea)
                .. "; switch seas manually. Cross-sea travel is not enabled.",
            "warning"
        )
        return
    end

    local level = self.QuestService:GetPlayerLevel()
    local minimumLevel = tonumber(profile.MinimumLevel)
    if not level or not minimumLevel then
        if self.TikiPuzzleActive then
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = true
        end
        if self.TikiPuzzleRestorePending then
            self:_HoldPosition(session)
            self:_RestoreTikiFarmWeapon()
        end
        self:_ClearTarget()
        self:_SetStatus("Mode level eligibility is unavailable", "error")
        return
    elseif level < minimumLevel then
        if self.TikiPuzzleActive then
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = true
        end
        if self.TikiPuzzleRestorePending then
            self:_HoldPosition(session)
            self:_RestoreTikiFarmWeapon()
        end
        self:_ClearTarget()
        self:_SetStatus(
            farmMode .. " requires level " .. tostring(minimumLevel)
                .. "; current level is " .. tostring(level),
            "warning"
        )
        return
    end

    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    if profile.TikiEventPhase == true then
        local now = os.clock()
        local bossTarget = nil
        local ignoreBoss = profile.IgnoreBossSetting
            and farmSettings[profile.IgnoreBossSetting] == true
        if not ignoreBoss and profile.BossName then
            if self.TargetIsBoss and self.EnemyService:IsAlive(self.Target) then
                bossTarget = self.Target
            elseif now >= (self.NextTikiBossSearchAt or 0) then
                self.NextTikiBossSearchAt = now + NPC_SCAN_INTERVAL
                bossTarget = self.EnemyService:FindNearest(profile.BossName, root.Position)
            end
        end

        if bossTarget then
            self.TikiEventComplete = true
            if self.TikiPuzzleActive then
                self.TikiPuzzleActive = false
                self.TikiPuzzleRestorePending = true
            end
            if self.TikiPuzzleRestorePending then
                self:_HoldPosition(session)
                if not self:_RestoreTikiFarmWeapon() then
                    return
                end
            end
            self:_EngageModeTarget(bossTarget, true, root, session)
            return
        end

        if not self.TikiEventComplete and self:_StepTikiEventPhase(root, session) then
            return
        end
    end

    local targetNames, targetError =
        self.QuestService:GetQuestTargets(profile.QuestPrefix, level)
    if type(targetNames) ~= "table" or #targetNames == 0 then
        self:_ClearTarget()
        self:_SetStatus(
            "Mode target lookup failed: " .. tostring(targetError),
            "error"
        )
        return
    end

    if farmSettings.AutoModeQuest == true then
        if questState == "unknown" or questState == "active-unknown" then
            self:_ClearTarget()
            self:_SetStatus(
                "Auto quest is waiting for a reliable quest state: "
                    .. boundedReason(readerEvidence),
                "warning"
            )
            return
        elseif questState == "none" then
            local candidate, selectionError = self.QuestService:SelectQuest(
                profile.QuestName,
                profile.QuestId,
                minimumLevel
            )
            if not candidate then
                self:_ClearTarget()
                self:_SetStatus(
                    "Mode quest selection unavailable: " .. tostring(selectionError),
                    "error"
                )
                return
            end
            self:_StepModeQuestGiver(candidate, root, session)
            return
        end
    end

    local searchKey = "mode:" .. farmMode
    if self.SpawnSearchTarget ~= searchKey then
        self:_ResetSpawnSearch(searchKey)
    end

    local now = os.clock()
    local target = nil
    local targetIsBoss = false
    if now >= (self.NextEnemySearchAt or 0) then
        local ignoreBoss = profile.IgnoreBossSetting
            and farmSettings[profile.IgnoreBossSetting] == true
        if profile.BossName and not ignoreBoss then
            target = self.EnemyService:FindNearest(profile.BossName, root.Position)
            targetIsBoss = target ~= nil
        end
        if not target then
            target = self.EnemyService:FindNearest(targetNames, root.Position)
        end
        self.NextEnemySearchAt = now + NPC_SCAN_INTERVAL
    elseif self.Target and self.EnemyService:IsAlive(self.Target) then
        target = self.Target
        targetIsBoss = self.TargetIsBoss == true
    end

    if target and targetIsBoss then
        if profile.TikiEventPhase == true then
            self.TikiEventComplete = true
            if self.TikiPuzzleActive then
                self.TikiPuzzleActive = false
                self.TikiPuzzleRestorePending = true
            end
        end
        self:_EngageModeTarget(target, targetIsBoss, root, session)
        return
    end
    if target then
        self:_EngageModeTarget(target, targetIsBoss, root, session)
        return
    end
    if self.Target then
        self:_ClearTarget(true)
    end

    if self.SpawnCandidate and not self.EnemyService:IsSpawnAvailable(
        self.SpawnCandidate,
        self.SpawnCandidateTargetName
    ) then
        self.SpawnCandidate = nil
        self.SpawnCandidateTargetName = nil
        self.SpawnLoading = nil
        self.NextSpawnSearchAt = 0
    end

    if now >= (self.NextSpawnSearchAt or 0) then
        local spawnPart, targetName, diagnostic, matchingMarkers =
            self:_FindModeSpawn(targetNames, root.Position)
        self.SpawnCandidate = spawnPart
        self.SpawnCandidateTargetName = targetName
        self.SpawnCandidateDiagnostic = diagnostic
        self.ModeSpawnMarkersExhausted = not spawnPart and matchingMarkers
        self.NextSpawnSearchAt = now + SPAWN_SCAN_INTERVAL
    end

    local spawnPart = self.SpawnCandidate
    local spawnTargetName = self.SpawnCandidateTargetName
    if spawnPart and spawnTargetName
        and self.EnemyService:IsSpawnAvailable(spawnPart, spawnTargetName)
    then
        local destination = spawnPart.CFrame * CFrame.new(0, 60, 0)
        self:_MoveTo(destination, session, 100, true)
        if (spawnPart.Position - root.Position).Magnitude <= 100 then
            if not self.SpawnLoading
                or self.SpawnLoading.TargetName ~= spawnTargetName
                or self.SpawnLoading.Part ~= spawnPart
            then
                self.SpawnLoading = {
                    TargetName = spawnTargetName,
                    Part = spawnPart,
                    ArrivedAt = now,
                }
            elseif now - self.SpawnLoading.ArrivedAt >= SPAWN_LOAD_GRACE then
                self.EnemyService:MarkSpawnIgnored(spawnPart, spawnTargetName)
                self.SpawnLoading = nil
                self.SpawnCandidate = nil
                self.SpawnCandidateTargetName = nil
                self.NextSpawnSearchAt = 0
                self.NextEnemySearchAt = 0
                self:_SetStatus(
                    "No living " .. spawnTargetName
                        .. " loaded at this marker; checking other mode targets",
                    "warning"
                )
                return
            end
            local elapsed = self.SpawnLoading and now - self.SpawnLoading.ArrivedAt or 0
            self:_SetStatus(
                "Waiting for " .. spawnTargetName .. " to load at spawn ("
                    .. tostring(math.max(0, math.ceil(SPAWN_LOAD_GRACE - elapsed)))
                    .. "s)",
                "info"
            )
        else
            if self.SpawnLoading and self.SpawnLoading.Part ~= spawnPart then
                self.SpawnLoading = nil
            end
            self:_SetStatus("Travelling to supported spawn for " .. spawnTargetName, "info")
        end
        return
    end

    if self.ModeSpawnMarkersExhausted then
        self:_HoldPosition(session)
        self.EnemyService:ClearIgnoredSpawns()
        self.SpawnCandidate = nil
        self.SpawnCandidateTargetName = nil
        self.SpawnLoading = nil
        self.ModeSpawnMarkersExhausted = false
        self.NextSpawnSearchAt = now + SPAWN_CYCLE_RETRY_INTERVAL
        self:_SetStatus("Mode spawn markers checked; retrying after a short pause", "warning")
        return
    end

    if self.SpawnCandidateDiagnostic
        and self.SpawnCandidateDiagnostic.HiddenDiscoveryLoading
    then
        self:_HoldPosition(session)
        self:_SetStatus("Checking hidden spawn markers in the background", "info")
        return
    end

    self:_HoldPosition(session)
    local bossText = profile.BossName
        and (" or live " .. profile.BossName)
        or ""
    self:_SetStatus(
        "No live quest-family target" .. bossText
            .. " or supported spawn marker is available",
        "warning"
    )
end

function MainFarm:_StepFarmMaterials(session, root)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    local materialNames = farmSettings.FarmMaterials
    local selectedMaterial = farmSettings.FarmMaterial
    local selectedIsValid = false
    if type(materialNames) == "table" then
        for _, materialName in ipairs(materialNames) do
            if materialName == selectedMaterial then
                selectedIsValid = true
                break
            end
        end
    end

    local function stopAndHold()
        self:_ClearTarget()
        self:_ResetSpawnSearch(nil)
        self:_HoldPosition(session)
    end

    if not selectedIsValid then
        stopAndHold()
        self:_SetStatus("Select a valid material before farming", "error")
        return
    end

    local materialTargets = farmSettings.FarmMaterialTargets
    local selectedTargets = type(materialTargets) == "table"
        and materialTargets[selectedMaterial]
        or nil
    if type(selectedTargets) ~= "table" then
        stopAndHold()
        self:_SetStatus("No enemy data is configured for " .. selectedMaterial, "error")
        return
    end

    local seaChecks = {
        { Index = 1, Name = "First Sea", Method = "IsFirstSea" },
        { Index = 2, Name = "Second Sea", Method = "IsSecondSea" },
        { Index = 3, Name = "Third Sea", Method = "IsThirdSea" },
    }
    local compatibility = self.Context.Compatibility
    local currentSeaIndex
    local currentSeaName
    local recognizedSeaCount = 0
    for _, sea in ipairs(seaChecks) do
        local check = compatibility and compatibility[sea.Method]
        if type(check) == "function" then
            local ok, isCurrentSea = pcall(check, compatibility)
            if ok and isCurrentSea == true then
                currentSeaIndex = sea.Index
                currentSeaName = sea.Name
                recognizedSeaCount += 1
            end
        end
    end
    if recognizedSeaCount ~= 1 then
        stopAndHold()
        self:_SetStatus(
            "Farm Materials is waiting for one recognized sea; cross-sea travel is disabled",
            "warning"
        )
        return
    end

    local targetNames = selectedTargets[currentSeaIndex]
    if type(targetNames) ~= "table" or #targetNames == 0 then
        local availableSeas = {}
        for _, sea in ipairs(seaChecks) do
            local names = selectedTargets[sea.Index]
            if type(names) == "table" and #names > 0 then
                table.insert(availableSeas, sea.Name)
            end
        end
        stopAndHold()
        self:_SetStatus(
            selectedMaterial .. " is not configured for " .. currentSeaName
                .. (#availableSeas > 0
                    and ("; available in " .. table.concat(availableSeas, ", "))
                    or "")
                .. ". Switch seas manually; cross-sea travel is disabled.",
            "warning"
        )
        return
    end

    local searchKey = "material:" .. tostring(currentSeaIndex) .. ":" .. selectedMaterial
    if self.SpawnSearchTarget ~= searchKey then
        self:_ClearTarget()
        self:_ResetSpawnSearch(searchKey)
    end

    local validTargetNames = {}
    for _, targetName in ipairs(targetNames) do
        if type(targetName) == "string" and targetName ~= "" then
            validTargetNames[targetName] = true
        end
    end
    if next(validTargetNames) == nil then
        stopAndHold()
        self:_SetStatus("No valid enemy names are configured for " .. selectedMaterial, "error")
        return
    end

    local now = os.clock()
    local target
    if self.Target then
        if self.EnemyService:IsAlive(self.Target)
            and validTargetNames[self.Target.Name] == true
        then
            target = self.Target
        else
            self:_ClearTarget()
        end
    end
    if not target and now >= (self.NextEnemySearchAt or 0) then
        target = self.EnemyService:FindNearest(targetNames, root.Position)
        self.NextEnemySearchAt = now + NPC_SCAN_INTERVAL
    end
    if target then
        self:_EngageModeTarget(target, false, root, session, "material")
        return
    end

    if self.SpawnCandidate and not self.EnemyService:IsSpawnAvailable(
        self.SpawnCandidate,
        self.SpawnCandidateTargetName
    ) then
        self.SpawnCandidate = nil
        self.SpawnCandidateTargetName = nil
        self.SpawnLoading = nil
        self.NextSpawnSearchAt = 0
    end

    if now >= (self.NextSpawnSearchAt or 0) then
        local spawnPart, targetName, diagnostic, matchingMarkers =
            self:_FindModeSpawn(targetNames, root.Position)
        self.SpawnCandidate = spawnPart
        self.SpawnCandidateTargetName = targetName
        self.SpawnCandidateDiagnostic = diagnostic
        self.ModeSpawnMarkersExhausted = not spawnPart and matchingMarkers
        self.NextSpawnSearchAt = now + SPAWN_SCAN_INTERVAL
    end

    local spawnPart = self.SpawnCandidate
    local spawnTargetName = self.SpawnCandidateTargetName
    if spawnPart and spawnTargetName
        and self.EnemyService:IsSpawnAvailable(spawnPart, spawnTargetName)
    then
        self:_MoveTo(spawnPart.CFrame * CFrame.new(0, 60, 0), session, 100, true)
        if (spawnPart.Position - root.Position).Magnitude <= 100 then
            if not self.SpawnLoading
                or self.SpawnLoading.TargetName ~= spawnTargetName
                or self.SpawnLoading.Part ~= spawnPart
            then
                self.SpawnLoading = {
                    TargetName = spawnTargetName,
                    Part = spawnPart,
                    ArrivedAt = now,
                }
            elseif now - self.SpawnLoading.ArrivedAt >= SPAWN_LOAD_GRACE then
                self.EnemyService:MarkSpawnIgnored(spawnPart, spawnTargetName)
                self.SpawnLoading = nil
                self.SpawnCandidate = nil
                self.SpawnCandidateTargetName = nil
                self.NextSpawnSearchAt = 0
                self.NextEnemySearchAt = 0
                self:_SetStatus(
                    "No living " .. spawnTargetName
                        .. " loaded at this marker; checking other material targets",
                    "warning"
                )
                return
            end
            local elapsed = self.SpawnLoading and now - self.SpawnLoading.ArrivedAt or 0
            self:_SetStatus(
                "Waiting for " .. spawnTargetName .. " to load at spawn ("
                    .. tostring(math.max(0, math.ceil(SPAWN_LOAD_GRACE - elapsed)))
                    .. "s)",
                "info"
            )
        else
            if self.SpawnLoading and self.SpawnLoading.Part ~= spawnPart then
                self.SpawnLoading = nil
            end
            self:_SetStatus("Travelling to supported spawn for " .. spawnTargetName, "info")
        end
        return
    end

    if self.ModeSpawnMarkersExhausted then
        self:_HoldPosition(session)
        self.EnemyService:ClearIgnoredSpawns()
        self.SpawnCandidate = nil
        self.SpawnCandidateTargetName = nil
        self.SpawnLoading = nil
        self.ModeSpawnMarkersExhausted = false
        self.NextSpawnSearchAt = now + SPAWN_CYCLE_RETRY_INTERVAL
        self:_SetStatus("Material spawn markers checked; retrying after a short pause", "warning")
        return
    end

    if self.SpawnCandidateDiagnostic
        and self.SpawnCandidateDiagnostic.HiddenDiscoveryLoading
    then
        self:_HoldPosition(session)
        self:_SetStatus("Checking hidden material spawn markers in the background", "info")
        return
    end

    self:_HoldPosition(session)
    self:_SetStatus(
        "No live " .. selectedMaterial .. " target or supported spawn marker is available",
        "warning"
    )
end

function MainFarm:_FindDoubleQuestFallback(activeTarget, root, now)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    if farmSettings.DoubleQuestEnabled ~= true then
        return nil
    end

    if self.DoubleQuestScanTarget ~= activeTarget then
        self.DoubleQuestScanTarget = activeTarget
        self.NextDoubleQuestScanAt = 0
    end
    if now < (self.NextDoubleQuestScanAt or 0) then
        return nil
    end
    self.NextDoubleQuestScanAt = now + DOUBLE_QUEST_SCAN_INTERVAL

    local candidate = self.QuestService:SelectPreviousLevelQuestTarget(activeTarget)
    if not candidate or type(candidate.Mob) ~= "string" or candidate.Mob == activeTarget then
        return nil
    end

    local target = self.EnemyService:FindNearest(candidate.Mob, root.Position)
    if not target or not self.EnemyService:IsAlive(target) then
        return nil
    end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot
        or (targetRoot.Position - root.Position).Magnitude > DOUBLE_QUEST_MAX_FALLBACK_DISTANCE
    then
        return nil
    end
    return target, candidate.Mob
end

function MainFarm:_Step(session)
    if not self:_IsCurrent(session) then
        return
    end

    local compatibility = self.Context.Compatibility
    local character, humanoid, root = compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
        if self.MovementService then
            self.MovementService:Cancel()
        end
        self:_ClearTarget()
        self:_SetStatus("Waiting for a living character and HumanoidRootPart", "warning")
        return
    end

    if self.Character ~= character then
        if self.MovementService then
            self.MovementService:Cancel()
        end
        if self.EnemyService then
            self.EnemyService:RestoreTargetCollision()
        end
        self.Character = character
        self.Target = nil
        self.TargetName = nil
        self.DoubleQuestFallbackFor = nil
        self.DoubleQuestFallbackName = nil
        self.DoubleQuestScanTarget = nil
        self.NextDoubleQuestScanAt = 0
        self.TikiPuzzleActive = false
        self.TikiPuzzleRestorePending = false
        self.TikiEventComplete = false
        self.NextTikiBossSearchAt = 0
        self:_ResetSpawnSearch(nil)
        self:_SetStatus("Character ready; reacquiring farm state", "info")
    end

    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    local farmMode = farmSettings.FarmMode
    local farmMaterialsEnabled = farmSettings.FarmMaterialsEnabled == true
    local modeProfiles = farmSettings.FarmModeProfiles
    local farmModeProfile = not farmMaterialsEnabled
        and type(modeProfiles) == "table"
        and type(farmMode) == "string"
        and modeProfiles[farmMode]
        or nil
    if type(farmModeProfile) ~= "table" or farmModeProfile.TikiEventPhase ~= true then
        self.TikiEventComplete = false
        self.NextTikiBossSearchAt = 0
    end
    if self.TikiPuzzleActive
        and (type(farmModeProfile) ~= "table" or farmModeProfile.TikiEventPhase ~= true)
    then
        self.TikiPuzzleActive = false
        self.TikiPuzzleRestorePending = true
    end
    if self.TikiPuzzleRestorePending then
        self:_HoldPosition(session)
        if not self:_RestoreTikiFarmWeapon() then
            return
        end
    end
    if farmMaterialsEnabled then
        self:_StepFarmMaterials(session, root)
        return
    end
    if type(farmMode) ~= "string" or farmMode == "" then
        if self.Target then
            self:_ClearTarget()
        end
        self:_HoldPosition(session)
        self:_SetStatus(
            "Choose a farm method to resume farming.",
            "warning",
            "Choose a farm method to resume farming."
        )
        return
    end
    if farmMode == "Aura Farm" then
        self:_StepAura(session, root)
        return
    end
    if farmMode ~= "Level Farm" and type(farmModeProfile) ~= "table" then
        self:_ClearTarget()
        self:_SetStatus("Unsupported farm mode: " .. tostring(farmMode), "error")
        return
    end

    local questState, activeTarget, readerEvidence = self.QuestService:GetActiveQuestState()
    self.LastQuestStateReason = readerEvidence
    if questState == "active" then
        self.QuestDeferredForDialogue = false
        if self.QuestDialogueRecovery then
            self.MovementService:Cancel()
            self.QuestDialogueRecovery = nil
            self.PendingQuestReachedAt = nil
        end
    end
    if self.QuestDiagnosticWaitKey then
        self:_LogQuestDataSnapshot("confirmation_poll", questState, false, readerEvidence)
        local now = os.clock()
        if questState == "active" then
            self:_LogQuestDataSnapshot("confirmation_poll", questState, true, readerEvidence)
            if activeTarget == self.PendingQuestTargetName then
                self:_EndQuestDiagnosticWait("active_state_observed", now)
                self.TimedOutQuestKey = nil
                self.LastQuestAttemptKey = nil
                self.LastQuestAttemptAt = 0
                self.QuestStartAttemptCount = 0
                self.PendingQuestTargetName = nil
                self.PendingQuestKey = nil
                self.PendingQuestReachedAt = nil
                self:_SetStatus(
                    "Quest confirmed by " .. boundedReason(readerEvidence),
                    "success"
                )
            else
                self:_EndQuestDiagnosticWait("active_state_target_mismatch", now)
                self.LastQuestAttemptKey = nil
                self.LastQuestAttemptAt = 0
                self.QuestStartAttemptCount = 0
                self.PendingQuestTargetName = nil
                self.PendingQuestKey = nil
                self.PendingQuestReachedAt = nil
                self:_SetStatus(
                    "A different active quest target was observed; following its validated target",
                    "warning"
                )
            end
        elseif self.QuestService:IsQuestGiverDialogueOpen() then
            self.QuestDiagnosticWaitStartedAt = nil
            self.LastQuestAttemptKey = nil
            self.LastQuestAttemptAt = 0
            self.QuestStartAttemptCount = 0
            self.QuestDeferredForDialogue = true
            self:_SetStatus(
                "Quest dialogue open; preparing recovery before requesting",
                "info"
            )
        elseif not self.QuestDiagnosticWaitStartedAt then
            self.QuestDiagnosticWaitStartedAt = now
        elseif now - self.QuestDiagnosticWaitStartedAt >= QUEST_CONFIRMATION_TIMEOUT then
            self:_LogQuestDataSnapshot("confirmation_poll", questState, true, readerEvidence)
            self:_TimeoutQuestConfirmation(self.QuestDiagnosticWaitKey, now)
        end
    end
    if questState == "active"
        and self.PendingQuestTargetName
        and activeTarget == self.PendingQuestTargetName
    then
        self.TimedOutQuestKey = nil
        self.QuestTimeoutReason = nil
        self.LastQuestAttemptKey = nil
        self.LastQuestAttemptAt = 0
        self.QuestStartAttemptCount = 0
        self.PendingQuestTargetName = nil
        self.PendingQuestKey = nil
        self.PendingQuestReachedAt = nil
        self:_SetStatus(
            "Quest confirmed by " .. boundedReason(readerEvidence),
            "success"
        )
    end
    if farmModeProfile then
        self:_StepBossEventMode(
            session,
            root,
            farmMode,
            farmModeProfile,
            questState,
            readerEvidence
        )
        return
    end
    if questState == "unknown" then
        self:_ClearTarget(true)
        self:_SetStatus(
            "Quest reader: " .. boundedReason(readerEvidence),
            "warning"
        )
        return
    elseif questState == "active-unknown" then
        self:_ClearTarget(true)
        self:_SetStatus(
            "Waiting: quest UI is active but its catalog target is unresolved; "
                .. boundedReason(readerEvidence),
            "warning"
        )
        return
    elseif questState == "none" then
        self:_ClearTarget(true)
        local candidate, selectionError = self.QuestService:SelectLevelQuest()
        if not candidate then
            self.MovementService:Cancel()
            self:_SetStatus("Quest selection unavailable: " .. tostring(selectionError), "error")
            return
        end

        local giverPosition = candidate.Pos
        if typeof(giverPosition) ~= "Vector3" and typeof(giverPosition) ~= "CFrame" then
            self.MovementService:Cancel()
            self:_SetStatus("Selected quest giver has no usable position", "error")
            return
        end
        local candidateKey = questKey(candidate)
        if self.PendingQuestKey ~= candidateKey then
            self.PendingQuestKey = candidateKey
            self.PendingQuestReachedAt = nil
        end
        local giverCFrame = typeof(giverPosition) == "CFrame"
            and giverPosition
            or CFrame.new(giverPosition)
        if self.QuestDialogueRecovery
            and self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session)
        then
            return
        end
        if (root.Position - giverCFrame.Position).Magnitude > 8 then
            if not self.QuestDeferredForDialogue then
                self.PendingQuestReachedAt = nil
            end
            self:_MoveTo(giverCFrame * CFrame.new(0, 4, 2), session, 8, true)
            self:_SetStatus("Approaching quest giver: " .. tostring(candidate.Name), "info")
            return
        end
        local requestDelay = self:_GetQuestGiverRequestDelay()
        if not self.PendingQuestReachedAt then
            if self.QuestDeferredForDialogue then
                self.PendingQuestReachedAt = os.clock() - 2
            elseif requestDelay == 0 then
                self.PendingQuestReachedAt = os.clock()
                self:_SetStatus("At quest giver; requesting quest immediately (RISK)", "warning")
            else
                self.PendingQuestReachedAt = os.clock()
                self:_SetStatus("At quest giver; waiting before quest request", "info")
                return
            end
        elseif os.clock() - self.PendingQuestReachedAt < requestDelay then
            return
        end
        if self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session) then
            return
        end
        self:_RequestQuest(candidate, session)
        return
    end

    local keepDoubleQuestFallback = farmSettings.DoubleQuestEnabled == true
        and self.DoubleQuestFallbackFor == activeTarget
        and self.TargetName == self.DoubleQuestFallbackName
        and self.Target ~= nil
        and self.EnemyService:IsAlive(self.Target)
    if self.TargetName ~= activeTarget and not keepDoubleQuestFallback then
        self:_ClearTarget(true)
        self:_ResetSpawnSearch(activeTarget)
        self.TargetName = activeTarget
    end

    local now = os.clock()
    local target
    local targetName = activeTarget
    local isDoubleQuestFallback = false
    if self.Target and self.TargetName == activeTarget and self.EnemyService:IsAlive(self.Target) then
        target = self.Target
    elseif now >= (self.NextEnemySearchAt or 0) then
        target = self.EnemyService:FindNearest(activeTarget, root.Position)
        if not target then
            if keepDoubleQuestFallback then
                target = self.Target
                targetName = self.DoubleQuestFallbackName
                isDoubleQuestFallback = true
            else
                target, targetName = self:_FindDoubleQuestFallback(activeTarget, root, now)
                isDoubleQuestFallback = target ~= nil
            end
        end
        self.NextEnemySearchAt = now + NPC_SCAN_INTERVAL
    elseif keepDoubleQuestFallback then
        target = self.Target
        targetName = self.DoubleQuestFallbackName
        isDoubleQuestFallback = true
    end
    if not target then
        if self.Target then
            self:_ClearTarget(true)
            self.TargetName = activeTarget
        end
        if self.SpawnSearchExhausted then
            self:_HoldPosition(session)
            self:_SetStatus(
                "No living " .. activeTarget
                    .. " was found after two spawn cycles; continuing throttled scans of loaded NPCs",
                "warning"
            )
            return
        end
        if self.SpawnRetryAt and now < self.SpawnRetryAt then
            self:_HoldPosition(session)
            self:_SetStatus(
                "No living " .. activeTarget .. " after checking known spawns; retrying shortly",
                "warning"
            )
            return
        elseif self.SpawnRetryAt then
            self.SpawnRetryAt = nil
            self.NextSpawnSearchAt = 0
        end

        local spawnPart = self.SpawnCandidate
        local spawnDiagnostic = self.SpawnCandidateDiagnostic
        local allSpawnsVisited = false
        if now >= (self.NextSpawnSearchAt or 0) then
            spawnPart, allSpawnsVisited, spawnDiagnostic =
                self.EnemyService:FindSpawn(activeTarget, root.Position)
            self.SpawnCandidate = spawnPart
            self.SpawnCandidateDiagnostic = spawnDiagnostic
            self.NextSpawnSearchAt = now + SPAWN_SCAN_INTERVAL
        end
        if spawnPart then
            local spawnAvailable =
                self.EnemyService:IsSpawnAvailable(spawnPart, activeTarget)
            if not spawnAvailable then
                self:_RecordSpawnDiagnostic(
                    activeTarget,
                    spawnDiagnostic,
                    spawnPart,
                    false,
                    nil,
                    "not_called_unavailable"
                )
                self.SpawnCandidate = nil
                self.SpawnLoading = nil
                self.NextSpawnSearchAt = 0
                self:_SetStatus(
                    "A matching enemy spawn marker is stale or ignored; rescanning",
                    "warning"
                )
                self:_HoldPosition(session)
                return
            end
            local spawnDestination = spawnPart.CFrame * CFrame.new(0, 60, 0)
            local movementAccepted, movementResult =
                self:_MoveTo(spawnDestination, session, 100, true)
            self:_RecordSpawnDiagnostic(
                activeTarget,
                spawnDiagnostic,
                spawnPart,
                true,
                movementAccepted,
                movementResult
            )
            if (spawnPart.Position - root.Position).Magnitude <= 100 then
                if not self.SpawnLoading
                    or self.SpawnLoading.TargetName ~= activeTarget
                    or self.SpawnLoading.Part ~= spawnPart
                then
                    self.SpawnLoading = {
                        TargetName = activeTarget,
                        Part = spawnPart,
                        ArrivedAt = now,
                    }
                elseif now - self.SpawnLoading.ArrivedAt >= SPAWN_LOAD_GRACE then
                    self.EnemyService:MarkSpawnIgnored(spawnPart, activeTarget)
                    self.SpawnLoading = nil
                    self.SpawnCandidate = nil
                    self.NextSpawnSearchAt = 0
                    self.NextEnemySearchAt = 0
                    self:_SetStatus(
                        "No living " .. activeTarget .. " loaded at this spawn; checking the next location",
                        "warning"
                    )
                    return
                end
                local elapsed = self.SpawnLoading and now - self.SpawnLoading.ArrivedAt or 0
                self:_SetStatus(
                    "Waiting for " .. activeTarget .. " to load at spawn ("
                        .. tostring(math.max(0, math.ceil(SPAWN_LOAD_GRACE - elapsed)))
                        .. "s)",
                    "info"
                )
            else
                if self.SpawnLoading and self.SpawnLoading.Part ~= spawnPart then
                    self.SpawnLoading = nil
                end
                self:_SetStatus("Travelling to supported spawn for " .. activeTarget, "info")
            end
        else
            self:_RecordSpawnDiagnostic(
                activeTarget,
                spawnDiagnostic,
                nil,
                nil,
                nil,
                "not_called_no_candidate"
            )
            if allSpawnsVisited then
                self.EnemyService:ClearIgnoredSpawns()
                self.SpawnCandidate = nil
                self.SpawnLoading = nil
                self.SpawnEmptyCycles = (self.SpawnEmptyCycles or 0) + 1
                if self.SpawnEmptyCycles >= MAX_EMPTY_SPAWN_CYCLES then
                    self.SpawnSearchExhausted = true
                    self.SpawnRetryAt = nil
                    self.NextSpawnSearchAt = math.huge
                    self:_SetStatus(
                        "No living " .. activeTarget
                            .. " after two spawn cycles; continuing throttled scans of loaded NPCs",
                        "warning"
                    )
                else
                    self.SpawnRetryAt = now + SPAWN_CYCLE_RETRY_INTERVAL
                    self.NextSpawnSearchAt = self.SpawnRetryAt
                    self:_SetStatus(
                        "No living " .. activeTarget
                            .. " at known spawns; retrying once after a short pause",
                        "warning"
                    )
                end
            elseif spawnDiagnostic and spawnDiagnostic.HiddenDiscoveryLoading then
                self.SpawnCandidate = nil
                self.SpawnLoading = nil
                self:_SetStatus("Checking hidden spawn markers in the background", "info")
            else
                self.SpawnCandidate = nil
                self.SpawnLoading = nil
                self:_SetStatus(
                    "No eligible " .. activeTarget
                        .. " is loaded and no matching Workspace._WorldOrigin.EnemySpawns marker is available",
                    "warning"
                )
            end
        end
        if not spawnPart then
            self:_HoldPosition(session)
        end
        return
    end

    if self.SpawnSearchTarget ~= activeTarget or self.SpawnSearchExhausted then
        self:_ResetSpawnSearch(activeTarget)
    end
    self.SpawnEmptyCycles = 0
    self.SpawnSearchExhausted = false
    self.SpawnCandidate = nil
    self.SpawnLoading = nil
    self.SpawnRetryAt = nil
    self.NextSpawnSearchAt = 0
    if self.Target ~= target then
        self:_ClearTarget(true)
        self.Target = target
        self.TargetName = targetName
        if isDoubleQuestFallback then
            self.DoubleQuestFallbackFor = activeTarget
            self.DoubleQuestFallbackName = targetName
            self:_SetStatus(
                "Double Quest: farming " .. targetName .. " while "
                    .. activeTarget .. " respawns",
                "info"
            )
        else
            self:_SetStatus("Target acquired: " .. activeTarget, "success")
        end
    end
    if not self.EnemyService:IsAlive(target) then
        self:_ClearTarget(true)
        self:_SetStatus("Target died or became invalid; reacquiring", "info")
        return
    end

    self.EnemyService:PrepareTarget(target, root)
    self:_BringMobsIfEnabled(target, root, false)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
    local weaponCategory = farmSettings and farmSettings.WeaponCategory or "Melee"
    local masteryCategory = self:_GetMasteryCategory(target, farmSettings, true)
    local attackCategory = masteryCategory or weaponCategory
    local combatReady, combatError = self:_EnsureCombatService()
    local skillHandling = false
    if combatReady then
        skillHandling = self:_TryStartFarmSkill(
            target,
            session,
            weaponCategory,
            farmSettings,
            root,
            true
        )
        if not skillHandling then
            local equipped, equipResult = self.CombatService:EquipWeapon(weaponCategory)
            if equipped then
                local attackIssued, attackResult = self.CombatService:AttackM1(
                    target,
                    30,
                    weaponCategory,
                    farmSettings and farmSettings.AttackNoAnimation == true
                )
                if attackIssued then
                    self:_SetStatus("M1 request issued; server damage is not yet confirmed", "info")
                else
                    self:_SetStatus("Combat waiting: " .. tostring(attackResult), "warning")
                end
            else
                self:_SetStatus("Combat waiting: " .. tostring(equipResult), "warning")
            end
        end
    else
        self:_SetStatus("Combat dependencies unavailable: " .. tostring(combatError), "error")
    end

    if self.EnemyService:IsAlive(target) then
        local targetRoot = target:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            self:_MoveToFarmAttackPosition(
                target,
                attackCategory,
                session,
                2.5,
                true,
                masteryCategory ~= nil
            )
            if not skillHandling
                and (root.Position - targetRoot.Position).Magnitude >= 30
            then
                self:_SetStatus("Approaching target: " .. activeTarget, "info")
            end
        end
    else
        self:_ClearTarget(true)
        self:_SetStatus("Target died or became invalid; reacquiring", "info")
    end
end

function MainFarm:_Run(session)
    while self:_IsCurrent(session) do
        local ok, err = pcall(function()
            if self:_StepStackTasks(session) then
                return
            end
            if self.MainFarmEnabled then
                self:_Step(session)
            else
                if self.MovementService then
                    self.MovementService:Cancel()
                end
                self:_SetStatus("Stack Farming is idle; waiting for an enabled task", "info")
            end
        end)
        if not ok then
            if self.MovementService then
                self.MovementService:Cancel()
            end
            if self.ActiveStackTask then
                local teleportFeature = self.Context and self.Context.TeleportFeature
                if teleportFeature and teleportFeature.CancelFarmTravel then
                    teleportFeature:CancelFarmTravel()
                end
            end
            self.QuestDialogueRecovery = nil
            if self.EnemyService then
                self.EnemyService:RestoreTargetCollision()
            end
            self.Target = nil
            self.TargetName = nil
            self.DoubleQuestFallbackFor = nil
            self.DoubleQuestFallbackName = nil
            self.DoubleQuestScanTarget = nil
            self.NextDoubleQuestScanAt = 0
            self:_SetStatus(
                (self.ActiveStackTask and "Stack Farming step error: " or "Main Farm step error: ")
                    .. tostring(err),
                "error"
            )
        end
        task.wait(FARM_STEP_INTERVAL)
    end
end

function MainFarm:_HasActiveBuso(character)
    if not character then
        return false
    end
    if character:FindFirstChild("HasBuso") then
        return true
    end
    for _, child in ipairs(character:GetChildren()) do
        if string.find(child.Name, "_BusoLayer", 1, true) then
            return true
        end
    end
    return false
end

function MainFarm:_SetAutoBuso(enabled, updateStatus)
    local farmSettings = self.Context and self.Context.Config
        and self.Context.Config.FarmSettings
    if not farmSettings or type(enabled) ~= "boolean" then
        self:_SetStatus("Auto Buso setting is unavailable or invalid", "error")
        return false
    end

    farmSettings.AutoBuso = enabled
    self.AutoBusoGeneration = (self.AutoBusoGeneration or 0) + 1
    local generation = self.AutoBusoGeneration
    if not enabled then
        if updateStatus ~= false then
            self:_SetStatus("Auto Buso disabled", "info")
        end
        return true
    end

    if updateStatus ~= false then
        self:_SetStatus("Auto Buso enabled; it will not purchase Haki", "success")
    end
    local runContext = self.Context
    task.spawn(function()
        while self.AutoBusoGeneration == generation
            and self.Context == runContext
            and farmSettings.AutoBuso == true
        do
            local compatibility = runContext.Compatibility
            local player = compatibility and compatibility.Player
            local character = player and player.Character
            if character and not self:_HasActiveBuso(character) then
                local commF, remoteError = compatibility:GetCommF()
                if self.Context ~= runContext or self.AutoBusoGeneration ~= generation then
                    break
                end
                if not commF then
                    self:_SetStatus("Auto Buso waiting: " .. tostring(remoteError), "warning")
                    task.wait(2)
                else
                    local invoked, invokeError = pcall(function()
                        return commF:InvokeServer("Buso")
                    end)
                    if not invoked
                        and self.Context == runContext
                        and self.AutoBusoGeneration == generation
                    then
                        self:_SetStatus(
                            "Auto Buso request failed: " .. tostring(invokeError),
                            "warning"
                        )
                    end
                    task.wait(2)
                end
            end
            task.wait(1)
        end
    end)
    return true
end

function MainFarm:Initialize(context)
    self.AutoBusoGeneration = (self.AutoBusoGeneration or 0) + 1
    self.Context = context
    self.Running = false
    self.MainFarmEnabled = false
    self.Session += 1
    self.ActiveStackTask = nil
    self.StackTaskStartedAt = 0
    self.StackInterruptedFarm = false
    if self.StackTaskQueue then
        self.StackTaskQueue:Cleanup()
    end
    self.StackTaskQueue = StackTaskQueue.new(
        context.Compatibility and context.Compatibility.Workspace
    )
    local stackQueueReady, stackQueueError = self.StackTaskQueue:Initialize()
    if not stackQueueReady then
        self.StackTaskQueue:Cleanup()
        self.StackTaskQueue = nil
        self:_SetStatus(
            "Stack Farming unavailable: " .. tostring(stackQueueError),
            "warning"
        )
    else
        local stackSettings = context.Config and context.Config.StackFarmSettings or {}
        self.StackTaskQueue:SetEnabled(
            "CakePrince",
            stackSettings.AutoAttackCakePrince == true
        )
        self.StackTaskQueue:SetEnabled(
            "Fruit",
            stackSettings.TeleportToFruit == true
        )
    end
    self.Character = nil
    self.Target = nil
    self.TargetName = nil
    self.DoubleQuestFallbackFor = nil
    self.DoubleQuestFallbackName = nil
    self.DoubleQuestScanTarget = nil
    self.NextDoubleQuestScanAt = 0
    self.QuestService = nil
    self.EnemyService = nil
    self.MovementService = nil
    self.CombatService = nil
    self.CombatDependencyAttempted = false
    self.CombatDependencyError = nil
    self.LastQuestAttemptKey = nil
    self.LastQuestAttemptAt = 0
    self.QuestStartAttemptCount = 0
    self.TimedOutQuestKey = nil
    self.QuestTimeoutReason = nil
    self.QuestDeferredForDialogue = false
    self.QuestDialogueRecovery = nil
    self.PendingQuestTargetName = nil
    self.LastQuestStateReason = nil
    self.QuestDiagnosticWaitKey = nil
    self.QuestDiagnosticWaitStartedAt = nil
    self.QuestDiagnosticReport = nil
    self.LastQuestDiagnosticSignature = nil
    self.LastQuestDiagnosticAt = 0
    self.SpawnCandidateDiagnostic = nil
    self.LastSpawnDiagnosticSignature = nil
    self.LastStatus = nil
    self.SpawnSearchTarget = nil
    self.SpawnCandidate = nil
    self.SpawnLoading = nil
    self.SpawnRetryAt = nil
    self.NextSpawnSearchAt = 0
    self.NextEnemySearchAt = 0
    self.NextTikiEventScanAt = 0
    self.TikiEventActive = false
    self.TikiEventTarget = nil
    self.NextFarmSkillScanAt = 0
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillTarget = nil
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self.FarmGunToolSettleUntil = 0
    self.GunKnockbackHold = nil
    self.TikiPuzzleActive = false
    self.TikiPuzzleRestorePending = false
    self.TikiEventComplete = false
    self.NextTikiBossSearchAt = 0
    self.NextTikiActionAt = 0
    self.NextTikiLoadItemAt = 0

    local player = context.Compatibility.Player
    if player then
        self.CharacterAddedConnection = player.CharacterAdded:Connect(function()
            if self.MovementService then
                self.MovementService:Cancel()
            end
            if self.EnemyService then
                self.EnemyService:RestoreTargetCollision()
            end
            if self.CombatService then
                self.CombatService:Cancel()
            end
            self.Target = nil
            self.TargetName = nil
            self.DoubleQuestFallbackFor = nil
            self.DoubleQuestFallbackName = nil
            self.DoubleQuestScanTarget = nil
            self.NextDoubleQuestScanAt = 0
            self.Character = nil
            self.QuestDialogueRecovery = nil
            self.NextTikiEventScanAt = 0
            self.TikiEventActive = false
            self.TikiEventTarget = nil
            self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
            self.FarmSkillActive = false
            self.FarmSkillTarget = nil
            self.FarmSkillPreparing = nil
            self.FarmSkillIgnoredTools = {}
            self.GunKnockbackHold = nil
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = false
            self.TikiEventComplete = false
            self.NextTikiBossSearchAt = 0
            self.NextTikiActionAt = 0
            self.NextTikiLoadItemAt = 0
            self:_ResetSpawnSearch(nil)
            self:_SetStatus("Character changed; farm session will reacquire after respawn", "warning")
        end)
        self.CharacterRemovingConnection = player.CharacterRemoving:Connect(function()
            if self.MovementService then
                self.MovementService:Cancel()
            end
            if self.CombatService then
                self.CombatService:Cancel()
            end
            self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
            self.FarmSkillActive = false
            self.FarmSkillTarget = nil
            self.FarmSkillPreparing = nil
            self.GunKnockbackHold = nil
            self.QuestDialogueRecovery = nil
            self:_ClearTarget()
            self:_ResetSpawnSearch(nil)
        end)
    end
    local farmSettings = context.Config and context.Config.FarmSettings
    if farmSettings and farmSettings.AutoBuso == true then
        self:_SetAutoBuso(true, false)
    end
    return true
end

function MainFarm:_StartWorker()
    if self.Running then
        return true
    end
    local ready, setupError = self:_EnsureBaseServices()
    if not ready then
        self:_SetStatus("Farm tasks unavailable: " .. tostring(setupError), "error")
        return false, setupError
    end

    self.Session += 1
    local collisionReady, collisionError = self.MovementService:SetFarmCollisionSuppression(true)
    if not collisionReady then
        self:_SetStatus("Farm task collision setup failed: " .. tostring(collisionError), "error")
        return false, collisionError
    end
    self.Running = true
    self.CombatDependencyAttempted = false
    self.CombatDependencyError = nil
    self.LastQuestAttemptKey = nil
    self.LastQuestAttemptAt = 0
    self.TimedOutQuestKey = nil
    self.QuestTimeoutReason = nil
    self.QuestDeferredForDialogue = false
    self.QuestDialogueRecovery = nil
    self.PendingQuestTargetName = nil
    self.PendingQuestKey = nil
    self.PendingQuestReachedAt = nil
    self.NextTikiEventScanAt = 0
    self.TikiEventActive = false
    self.TikiEventTarget = nil
    self.NextFarmSkillScanAt = 0
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillTarget = nil
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self.FarmGunToolSettleUntil = 0
    self.GunKnockbackHold = nil
    self.DoubleQuestFallbackFor = nil
    self.DoubleQuestFallbackName = nil
    self.DoubleQuestScanTarget = nil
    self.NextDoubleQuestScanAt = 0
    self:_ResetSpawnSearch(nil)
    local session = self.Session
    task.spawn(self._Run, self, session)
    return true
end

function MainFarm:Start()
    if self.MainFarmEnabled then
        return true
    end
    local teleportFeature = self.Context and self.Context.TeleportFeature
    if teleportFeature and teleportFeature:IsTraveling() then
        self.Context.State:SetStatus(
            "Auto Farm unavailable while travel is active.",
            "error",
            "Turn off Travel to Island or Travel to NPC before starting Auto Farm."
        )
        return false, "Manual travel is active"
    end
    local farmSettings = self.Context and self.Context.Config and self.Context.Config.FarmSettings
    if farmSettings
        and farmSettings.FarmMaterialsEnabled ~= true
        and (type(farmSettings.FarmMode) ~= "string" or farmSettings.FarmMode == "")
    then
        self.Context.State:SetStatus(
            "Choose a farm method before starting Auto Farm.",
            "warning",
            "Choose a farm method before turning on Start Farm."
        )
        return false, "Farm method must be selected"
    end
    local workerReady, workerError = self:_StartWorker()
    if not workerReady then
        return false, workerError
    end
    self.MainFarmEnabled = true
    self.Context.State:SetFeatureEnabled("farm.main", true)
    self:_SetStatus("Main Farm enabled; reading available quest state", "success")
    return true
end

function MainFarm:_StopWorker()
    if self.ActiveStackTask then
        self:_FinishStackTask(self.ActiveStackTask)
    end
    self.Session += 1
    self.Running = false
    self:_EndQuestDiagnosticWait("stopped_before_confirmation", os.clock())
    local teleportFeature = self.Context and self.Context.TeleportFeature
    if teleportFeature and teleportFeature.CancelFarmTravel then
        teleportFeature:CancelFarmTravel()
    end
    if self.MovementService then
        self.MovementService:Cancel()
        self.MovementService:SetFarmCollisionSuppression(false)
    end
    if self.CombatService then
        self.CombatService:Cancel()
    end
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillTarget = nil
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self.FarmGunToolSettleUntil = 0
    self.GunKnockbackHold = nil
    self.TikiEventComplete = false
    self.NextTikiBossSearchAt = 0
    if self.TikiPuzzleActive then
        self.TikiPuzzleActive = false
        self.TikiPuzzleRestorePending = true
    end
    if self.TikiPuzzleRestorePending then
        self:_RestoreTikiFarmWeapon()
    end
    if self.EnemyService then
        self.EnemyService:RestoreTargetCollision()
        self.EnemyService:ClearIgnoredSpawns()
        self.EnemyService:ClearTracking()
    end
    self.Target = nil
    self.TargetName = nil
    self.DoubleQuestFallbackFor = nil
    self.DoubleQuestFallbackName = nil
    self.DoubleQuestScanTarget = nil
    self.NextDoubleQuestScanAt = 0
    self.TargetIsBoss = nil
    self.NextTikiEventScanAt = 0
    self.TikiEventActive = false
    self.TikiEventTarget = nil
    self.NextTikiActionAt = 0
    self.NextTikiLoadItemAt = 0
    self.PendingQuestKey = nil
    self.PendingQuestReachedAt = nil
    self.PendingQuestTargetName = nil
    self.LastQuestAttemptKey = nil
    self.LastQuestAttemptAt = 0
    self.QuestStartAttemptCount = 0
    self.TimedOutQuestKey = nil
    self.QuestTimeoutReason = nil
    self.QuestDeferredForDialogue = false
    self.QuestDialogueRecovery = nil
    self.LastQuestStateReason = nil
    self:_ResetSpawnSearch(nil)
    self.QuestDiagnosticWaitKey = nil
    self.QuestDiagnosticWaitStartedAt = nil
    if self.Context and self.Context.State then
        self.Context.State:SetFeatureEnabled("farm.main", false)
    end
    return true
end

function MainFarm:Stop()
    self.MainFarmEnabled = false
    if self.Context and self.Context.State then
        self.Context.State:SetFeatureEnabled("farm.main", false)
    end

    if self:_HasEnabledStackTasks() then
        if not self.ActiveStackTask then
            self:_ClearTarget()
            if self.MovementService then
                self.MovementService:Cancel()
            end
            local teleportFeature = self.Context and self.Context.TeleportFeature
            if teleportFeature and teleportFeature.CancelFarmTravel then
                teleportFeature:CancelFarmTravel()
            end
            if self.CombatService then
                self.CombatService:Cancel()
            end
            self:_ResetSpawnSearch(nil)
        end
        self:_SetStatus("Main Farming is off; Stack Farming will continue", "info")
        return true
    end

    return self:_StopWorker()
end

function MainFarm:_SetStackTaskEnabled(kind, settingKey, label, payload)
    local stackSettings = self.Context
        and self.Context.Config
        and self.Context.Config.StackFarmSettings
    if not stackSettings or type(payload) ~= "boolean" then
        self:_SetStatus("Stack Farming setting is unavailable or invalid", "error")
        return false
    end
    if not self.StackTaskQueue then
        self:_SetStatus(
            "Stack Farming is unavailable because spawn detection could not start",
            "error",
            "Stack Farming could not start. Close and reopen the hub, then try again."
        )
        return false
    end
    if stackSettings[settingKey] == payload then
        return true
    end

    local teleportFeature = self.Context and self.Context.TeleportFeature
    if payload and teleportFeature and teleportFeature:IsTraveling() then
        self:_SetStatus(
            "Stack Farming unavailable while Travel is active",
            "error",
            "Turn off Travel to Island or Travel to NPC before starting Stack Farming."
        )
        return false
    end

    stackSettings[settingKey] = payload
    local queueReady, queueError = self.StackTaskQueue:SetEnabled(kind, payload)
    if not queueReady then
        stackSettings[settingKey] = not payload
        self:_SetStatus("Stack Farming setting error: " .. tostring(queueError), "error")
        return false
    end

    if payload then
        local workerReady, workerError = self:_StartWorker()
        if not workerReady then
            stackSettings[settingKey] = false
            self.StackTaskQueue:SetEnabled(kind, false)
            return false, workerError
        end
        self:_SetStatus("Stack task enabled: " .. label, "success")
        return true
    end

    if self.ActiveStackTask and self.ActiveStackTask.Kind == kind then
        self:_FinishStackTask(self.ActiveStackTask, "Stack task turned off", false)
    end
    if not self.MainFarmEnabled and not self:_HasEnabledStackTasks() then
        self:_StopWorker()
    else
        self:_SetStatus("Stack task disabled: " .. label, "info")
    end
    return true
end

function MainFarm:Handle(actionId, payload)
    if actionId == "farm.status.copy" then
        return self:CopyStatusReport()
    end
    if actionId == "stack.cakePrince.enabled" then
        return self:_SetStackTaskEnabled(
            "CakePrince",
            "AutoAttackCakePrince",
            "Auto Attack Cake Prince",
            payload
        )
    elseif actionId == "stack.fruit.enabled" then
        return self:_SetStackTaskEnabled(
            "Fruit",
            "TeleportToFruit",
            "Teleport To Fruit",
            payload
        )
    end
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
    if actionId == "farm.mastery.enabled" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Farm Mastery setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.FarmMastery = payload
        if payload and not self.Running then
            self:_SetStatus(
                "Farm Mastery enabled; turn on Start Farm to use it.",
                "warning",
                "Turn on Start Farm to use Farm Mastery."
            )
        else
            self:_SetStatus(
                "Farm Mastery " .. (payload and "enabled" or "disabled"),
                "success"
            )
        end
        return true
    end
    if actionId == "farm.mastery.category.select" then
        local methods = farmSettings and farmSettings.FarmMasteryMethods
        local selectedMethod
        if type(methods) == "table" and type(payload) == "string" then
            for _, method in ipairs(methods) do
                if method == payload then
                    selectedMethod = method
                    break
                end
            end
        end
        if not farmSettings or not selectedMethod then
            self:_SetStatus("Farm Mastery method is unavailable or invalid", "error")
            return false
        end
        farmSettings.MasteryCategory = selectedMethod
        self:_SetStatus("Mastery method: " .. selectedMethod, "success")
        return true
    end
    if actionId == "farm.mastery.healthPercent.set" then
        local selectedPercent = tonumber(payload)
        local minimum = farmSettings and tonumber(farmSettings.MasteryHealthPercentMin) or 0
        local maximum = farmSettings and tonumber(farmSettings.MasteryHealthPercentMax) or 100
        local step = farmSettings and tonumber(farmSettings.MasteryHealthPercentStep) or 1
        if not farmSettings
            or not selectedPercent
            or selectedPercent ~= selectedPercent
            or math.abs(selectedPercent) == math.huge
            or selectedPercent < minimum
            or selectedPercent > maximum
            or step <= 0
        then
            self:_SetStatus("Farm Mastery health threshold is invalid", "error")
            return false
        end
        farmSettings.MasteryHealthPercent = math.clamp(
            minimum + math.floor((selectedPercent - minimum) / step + 0.5) * step,
            minimum,
            maximum
        )
        self:_SetStatus(
            "Mastery health threshold: "
                .. tostring(farmSettings.MasteryHealthPercent)
                .. "%",
            "success"
        )
        return true
    end
    if actionId == "farm.settings.bringMobs" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Bring mobs setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.BringMobs = payload
        self:_SetStatus(
            "Bring mobs " .. (payload and "enabled" or "disabled"),
            "success"
        )
        return true
    end
    if actionId == "farm.bringMobCount.set" then
        if not farmSettings then
            self:_SetStatus("Farm settings are unavailable", "error")
            return false
        end
        local minimum = tonumber(farmSettings.BringMobCountMin) or 2
        local maximum = tonumber(farmSettings.BringMobCountMax) or 6
        local step = tonumber(farmSettings.BringMobCountStep) or 1
        if type(payload) ~= "number"
            or payload ~= payload
            or math.abs(payload) == math.huge
            or payload < minimum
            or payload > maximum
            or step <= 0
        then
            self:_SetStatus("Invalid Bring mob count", "error")
            return false
        end
        local selectedCount = minimum + math.floor((payload - minimum) / step + 0.5) * step
        farmSettings.BringMobCount = math.min(selectedCount, maximum)
        self:_SetStatus(
            "Bring mob count: " .. tostring(farmSettings.BringMobCount),
            "success"
        )
        return true
    end
    if actionId == "farm.settings.autoBuso" then
        return self:_SetAutoBuso(payload)
    end
    if actionId == "farm.skills.enabled" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Farm skills setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.UseFarmSkills = payload
        self:_SetStatus(
            "Farm combat skills " .. (payload and "enabled" or "disabled"),
            "success"
        )
        return true
    end
    if actionId == "farm.skills.fastRelease" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Fast skill release setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.FarmSkillFastRelease = payload
        self:_SetStatus(
            "Fast skill release " .. (payload and "enabled" or "disabled"),
            "success"
        )
        return true
    end
    if actionId == "farm.skills.holdSeconds.set" then
        local selectedDuration = tonumber(payload)
        if not farmSettings or not selectedDuration
            or selectedDuration ~= selectedDuration
            or math.abs(selectedDuration) == math.huge
            or selectedDuration < 0.05
            or selectedDuration > 5
        then
            self:_SetStatus("Skill hold duration is invalid", "error")
            return false
        end
        farmSettings.FarmSkillHoldSeconds =
            math.clamp(math.floor(selectedDuration * 20 + 0.5) / 20, 0.05, 5)
        self:_SetStatus(
            "Skill hold duration: " .. tostring(farmSettings.FarmSkillHoldSeconds) .. " sec",
            "success"
        )
        return true
    end
    local farmSkillToken, farmSkillKey = actionId:match(
        "^farm%.skills%.([%w]+)%.([ZXCVF])$"
    )
    if farmSkillToken then
        local allowedKeys = {
            Melee = { Z = true, X = true, C = true },
            Sword = { Z = true, X = true },
            Gun = { Z = true, X = true },
            BloxFruit = { Z = true, X = true, C = true, V = true, F = true },
        }
        local categoryKeys = allowedKeys[farmSkillToken]
        if not farmSettings or type(payload) ~= "boolean"
            or not categoryKeys or categoryKeys[farmSkillKey] ~= true
        then
            self:_SetStatus("Combat skill selection is unavailable or invalid", "error")
            return false
        end
        local settingName = "FarmSkill_" .. farmSkillToken .. "_" .. farmSkillKey
        farmSettings[settingName] = payload
        self:_SetStatus(
            farmSkillToken .. " " .. farmSkillKey .. " skill "
                .. (payload and "selected" or "unselected"),
            "success"
        )
        return true
    end
    if actionId == "farm.settings.instantQuest" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Instant quest acceptance setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.InstantAcceptQuest = payload
        self:_SetStatus(
            payload
                and "Instant quest acceptance on (RISK): a request may be too early."
                or "Instant quest acceptance off; waiting before requesting quests.",
            payload and "warning" or "success"
        )
        return true
    end
    if actionId == "farm.autoModeQuest" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Auto quest setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.AutoModeQuest = payload
        self:_SetStatus(
            "Auto quest Cake/Bones/Tyrant " .. (payload and "enabled" or "disabled"),
            "success"
        )
        return true
    end
    if actionId == "farm.doubleQuest" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Double Quest setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.DoubleQuestEnabled = payload
        self:_SetStatus(
            payload
                and "Double Quest on: farm nearby earlier-quest mobs while waiting; no quest credit."
                or "Double Quest disabled.",
            "success"
        )
        return true
    end
    if actionId == "farm.ignoreCakePrince" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Cake Prince boss setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.IgnoreCakePrince = payload
        self:_SetStatus(
            "Cake Prince boss " .. (payload and "ignored" or "enabled as a target"),
            "success"
        )
        return true
    end
    if actionId == "farm.mode.select" then
        if farmSettings and farmSettings.FarmMaterialsEnabled == true then
            self:_SetStatus(
                "Farm method locked to Farm Materials.",
                "warning",
                "Turn off Farm Materials to choose a different farm method."
            )
            return true
        end
        local selectedMode = nil
        for _, mode in ipairs(farmSettings and farmSettings.FarmModes or {}) do
            if mode == payload then
                selectedMode = mode
                break
            end
        end
        if not selectedMode then
            self:_SetStatus("Unsupported farm method: " .. tostring(payload), "error")
            return false
        end

        local restart = self.Running
        if restart then
            self:Stop()
        end
        farmSettings.FarmMode = selectedMode
        self:_SetStatus("Farm method: " .. selectedMode, "success")
        if restart then
            local started, startError = self:Start()
            if not started then
                self:_SetStatus("Could not restart farm: " .. tostring(startError), "error")
                return false
            end
        end
        return true
    end
    if actionId == "farm.material.select" then
        local selectedMaterial = nil
        for _, material in ipairs(farmSettings and farmSettings.FarmMaterials or {}) do
            if material == payload then
                selectedMaterial = material
                break
            end
        end
        if not farmSettings or not selectedMaterial then
            self:_SetStatus("Farm material is unavailable or invalid", "error")
            return false
        end
        farmSettings.FarmMaterial = selectedMaterial
        self:_SetStatus("Farm material: " .. selectedMaterial, "success")
        return true
    end
    if actionId == "farm.material.enabled" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Farm Materials setting is unavailable or invalid", "error")
            return false
        end
        local wasEnabled = farmSettings.FarmMaterialsEnabled == true
        farmSettings.FarmMaterialsEnabled = payload
        if payload and not self.Running then
            farmSettings.FarmMode = nil
            self:_SetStatus(
                "Farm Materials enabled; turn on Start Farm to run it.",
                "warning",
                "Turn on Start Farm to farm materials."
            )
        elseif payload then
            farmSettings.FarmMode = nil
            self:_SetStatus(
                "Farm Materials enabled; it takes priority over the selected farm method",
                "success"
            )
        elseif wasEnabled and self.Running then
            farmSettings.FarmMode = nil
            self:_SetStatus(
                "Farm Materials disabled; select a farm method to resume.",
                "warning",
                "Choose a farm method to resume farming."
            )
        elseif wasEnabled then
            farmSettings.FarmMode = nil
            self:_SetStatus(
                "Farm Materials disabled; choose a farm method before starting.",
                "warning",
                "Choose a farm method before turning on Start Farm."
            )
        else
            self:_SetStatus(
                "Farm Materials is already off.",
                "success"
            )
        end
        return true
    end
    if actionId == "farm.auraDistance.set" then
        if not farmSettings then
            self:_SetStatus("Farm settings are unavailable", "error")
            return false
        end
        local minimum = tonumber(farmSettings and farmSettings.AuraDistanceMin) or 0
        local maximum = tonumber(farmSettings and farmSettings.AuraDistanceMax) or 1000
        local step = tonumber(farmSettings and farmSettings.AuraDistanceStep) or 1
        if type(payload) ~= "number"
            or payload ~= payload
            or math.abs(payload) == math.huge
            or payload < minimum
            or payload > maximum
            or step <= 0
        then
            self:_SetStatus("Invalid Aura Farm distance", "error")
            return false
        end
        local selectedDistance = minimum + math.floor((payload - minimum) / step + 0.5) * step
        farmSettings.AuraDistance = math.min(selectedDistance, maximum)
        self:_SetStatus(
            "Aura distance: " .. tostring(farmSettings.AuraDistance) .. " studs",
            "success"
        )
        return true
    end
    if actionId ~= "farm.main" then
        return false
    end
    if payload == true then
        self:Start()
    else
        self:Stop()
        if not self:_HasEnabledStackTasks() then
            self:_SetStatus("Main Farming stopped; movement and attack loop cancelled", "info")
        end
    end
    return true
end

function MainFarm:Cleanup()
    self.MainFarmEnabled = false
    local stackSettings = self.Context
        and self.Context.Config
        and self.Context.Config.StackFarmSettings
    if stackSettings then
        stackSettings.AutoAttackCakePrince = false
        stackSettings.TeleportToFruit = false
    end
    if self.StackTaskQueue then
        self.StackTaskQueue:SetEnabled("CakePrince", false)
        self.StackTaskQueue:SetEnabled("Fruit", false)
    end
    self:_StopWorker()
    if self.StackTaskQueue then
        self.StackTaskQueue:Cleanup()
        self.StackTaskQueue = nil
    end
    self.AutoBusoGeneration = (self.AutoBusoGeneration or 0) + 1
    if self.CharacterAddedConnection then
        self.CharacterAddedConnection:Disconnect()
        self.CharacterAddedConnection = nil
    end
    if self.CharacterRemovingConnection then
        self.CharacterRemovingConnection:Disconnect()
        self.CharacterRemovingConnection = nil
    end
    self.QuestService = nil
    self.EnemyService = nil
    self.MovementService = nil
    self.CombatService = nil
    self.Context = nil
    return true
end

return MainFarm
