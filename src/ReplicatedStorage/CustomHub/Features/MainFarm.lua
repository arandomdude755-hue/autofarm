local QuestService = require(script.Parent.Farm.QuestService)
local EnemyService = require(script.Parent.Farm.EnemyService)
local MovementService = require(script.Parent.Farm.MovementService)
local CombatService = require(script.Parent.Farm.CombatService)

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
local FARM_STEP_INTERVAL = 0.1
local NPC_SCAN_INTERVAL = 0.15
local SPAWN_SCAN_INTERVAL = 1
local TIKI_EVENT_SCAN_INTERVAL = 1
local TIKI_ACTION_INTERVAL = 0.4
local TIKI_SKILL_HOLD_SECONDS = 0.5
local FARM_SKILL_SCAN_INTERVAL = 0.4
local FARM_SKILL_PREPARE_TIMEOUT = 1.2
local FARM_SKILL_UNAVAILABLE_RETRY = 10
local TIKI_LOAD_ITEM_RETRY_INTERVAL = 5
local SPAWN_LOAD_GRACE = 1
local SPAWN_CYCLE_RETRY_INTERVAL = 2
local MAX_EMPTY_SPAWN_CYCLES = 2

local MainFarm = {
    Running = false,
    Session = 0,
    AutoBusoGeneration = 0,
    Context = nil,
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

function MainFarm:_SetStatus(message, kind)
    local now = os.clock()
    if self.LastStatus == message and now - (self.LastStatusAt or 0) < 1.5 then
        return
    end
    self.LastStatus = message
    self.LastStatusAt = now
    if self.Context and self.Context.State then
        self.Context.State:SetStatus(message, kind)
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
    self.MovementService = MovementService.new(context.Compatibility, function(message, kind)
        self:_SetStatus(message, kind)
    end)
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

function MainFarm:CopyStatusReport()
    local text = self.LastQuestDiagnosticReportText
    if type(text) ~= "string" or text == "" then
        self:_SetStatus("No completed quest status report is available yet.", "warning")
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
        self:_SetStatus("Complete quest status report copied to clipboard.", "success")
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

function MainFarm:_MoveTo(destination, session, threshold, keepSession)
    if not self.MovementService then
        return false
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

function MainFarm:_TryStartFarmSkill(target, session, weaponCategory, farmSettings)
    if self.FarmSkillActive then
        return true
    end
    if not farmSettings or farmSettings.UseFarmSkills ~= true then
        self.FarmSkillPreparing = nil
        return false
    end

    local now = os.clock()
    if now < (self.NextFarmSkillScanAt or 0) then
        return self.FarmSkillPreparing ~= nil
            and now < self.FarmSkillPreparing.Deadline
    end
    self.NextFarmSkillScanAt = now + FARM_SKILL_SCAN_INTERVAL

    self.FarmSkillIgnoredTools = self.FarmSkillIgnoredTools or {}
    for toolName, retryAt in pairs(self.FarmSkillIgnoredTools) do
        if now >= retryAt then
            self.FarmSkillIgnoredTools[toolName] = nil
        end
    end

    local skill, skillError, preparingTool = self.CombatService:FindReadyFarmSkill(
        farmSettings,
        weaponCategory,
        self.FarmSkillIgnoredTools
    )
    if preparingTool then
        local preparation = self.FarmSkillPreparing
        if not preparation or preparation.ToolName ~= preparingTool.Name then
            preparation = {
                ToolName = preparingTool.Name,
                StartedAt = now,
                Deadline = now + FARM_SKILL_PREPARE_TIMEOUT,
            }
            self.FarmSkillPreparing = preparation
        end
        if now < preparation.Deadline then
            self:_SetStatus("Preparing skill controls for " .. preparingTool.Name, "info")
            return true
        end
        self.FarmSkillIgnoredTools[preparingTool.Name] = now + FARM_SKILL_UNAVAILABLE_RETRY
        self.FarmSkillPreparing = nil
        self.CombatService:EquipWeapon(weaponCategory)
        self:_SetStatus(
            "Skill controls did not load for " .. preparingTool.Name .. "; using M1",
            "warning"
        )
        return false
    end
    self.FarmSkillPreparing = nil
    if not skill then
        if skillError and skillError ~= "No selected skill is currently ready" then
            self:_SetStatus("Farm skills unavailable: " .. tostring(skillError), "warning")
        end
        return false
    end

    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    local generation = self.FarmSkillGeneration
    self.FarmSkillActive = true
    local originalCharacter = self.Character
    local combatService = self.CombatService
    local skillHold = tonumber(farmSettings.FarmSkillHoldSeconds) or 0.5
    if farmSettings.FarmSkillFastRelease == true then
        skillHold = 0.05
    end
    self:_SetStatus(
        "Using " .. skill.Category .. " " .. skill.Key .. " skill",
        "success"
    )
    task.spawn(function()
        local activated, activationResult = combatService:UseSkill(
            skill.Tool,
            skill.Key,
            target,
            skillHold,
            function()
                local currentSettings = self.Context and self.Context.Config
                    and self.Context.Config.FarmSettings
                return self:_IsCurrent(session)
                    and self.Target == target
                    and self.EnemyService:IsAlive(target)
                    and currentSettings
                    and currentSettings.UseFarmSkills == true
                    and currentSettings[skill.Setting] == true
            end
        )
        if self.FarmSkillGeneration == generation then
            self.FarmSkillActive = false
            self.NextFarmSkillScanAt = os.clock() + FARM_SKILL_SCAN_INTERVAL
            if activated and self:_IsCurrent(session) and self.Target == target then
                self:_SetStatus(
                    "Sent " .. skill.Category .. " " .. skill.Key .. " skill",
                    "success"
                )
            elseif not activated and self:_IsCurrent(session) and self.Target == target then
                self:_SetStatus("Farm skill was not sent: " .. tostring(activationResult), "warning")
            end
        end
        local currentCharacter = self.Context and self.Context.Compatibility
            and self.Context.Compatibility:GetCharacterParts()
        if originalCharacter and currentCharacter == originalCharacter
            and combatService == self.CombatService
        then
            local currentSettings = self.Context and self.Context.Config
                and self.Context.Config.FarmSettings
            combatService:EquipWeapon(currentSettings and currentSettings.WeaponCategory or weaponCategory)
        end
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
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        if not self:_TryStartFarmSkill(target, session, weaponCategory, farmSettings) then
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
            local targetOffset = weaponCategory == "Blox Fruit"
                and CFrame.new(-7, 20, 0)
                or CFrame.new(7, 20, 0)
            self:_MoveTo(targetRoot.CFrame * targetOffset, session, 2.5, true)
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
    if not self.PendingQuestReachedAt then
        if self.QuestDeferredForDialogue then
            self.PendingQuestReachedAt = os.clock() - 2
        else
            self.PendingQuestReachedAt = os.clock()
            self:_SetStatus("At mode quest giver; waiting before quest request", "info")
            return
        end
    elseif os.clock() - self.PendingQuestReachedAt < 2 then
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

function MainFarm:_EngageModeTarget(target, targetIsBoss, root, session)
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
            (targetIsBoss and "Live boss acquired: " or "Quest-family target acquired: ")
                .. target.Name,
            "success"
        )
    end

    self.EnemyService:PrepareTarget(target, root)
    self:_BringMobsIfEnabled(target, root, targetIsBoss)
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
    local weaponCategory = farmSettings and farmSettings.WeaponCategory or "Melee"
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        if not self:_TryStartFarmSkill(target, session, weaponCategory, farmSettings) then
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
            local targetOffset = weaponCategory == "Blox Fruit"
                and CFrame.new(-7, 20, 0)
                or CFrame.new(7, 20, 0)
            self:_MoveTo(targetRoot.CFrame * targetOffset, session, 2.5, true)
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
    local ownsGuitar = guitar ~= nil
    local ownershipError = nil
    if not ownsGuitar then
        ownsGuitar, ownershipError = compatibility:HasOwnedInventoryItem("Skull Guitar")
    end

    if ownsGuitar and not guitar then
        if now >= (self.NextTikiLoadItemAt or 0) then
            self.NextTikiLoadItemAt = now + TIKI_LOAD_ITEM_RETRY_INTERVAL
            local commF, remoteError = compatibility:GetCommF()
            if not commF then
                self:_SetStatus(
                    "Owned Skull Guitar is in inventory but cannot be loaded: " .. tostring(remoteError),
                    "warning"
                )
            else
                local requestOk, requestResult = pcall(function()
                    return commF:InvokeServer("LoadItem", "Skull Guitar")
                end)
                if requestOk then
                    self:_SetStatus("Loading owned Skull Guitar for the Tiki puzzle", "info")
                else
                    self:_SetStatus(
                        "Owned Skull Guitar load request failed: " .. tostring(requestResult),
                        "warning"
                    )
                end
            end
        end
        return true
    end

    if ownsGuitar and guitar then
        local tapped, tapResult = self.CombatService:TapSkullGuitar(targetPosition)
        if tapped then
            self:_SetStatus(
                "Sent owned Skull Guitar puzzle request; waiting for event update",
                "success"
            )
            return true
        elseif tapResult == "Skull Guitar is reloading" then
            ownershipError = "Skull Guitar is reloading"
        else
            ownershipError = "Skull Guitar unavailable for puzzle action: " .. tostring(tapResult)
        end
    end

    local skill, skillError = self.CombatService:FindReadyTikiSkill()
    if not skill then
        local reason = tostring(skillError)
        if ownershipError then
            reason = tostring(ownershipError) .. "; " .. reason
        elseif ownershipError ~= nil then
            reason = "Skull Guitar ownership could not be verified; " .. reason
        end
        self:_SetStatus("Tiki puzzle waiting for any ready skill: " .. reason, "info")
        return true
    end

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

    if (pivot.Position - root.Position).Magnitude > 10 then
        self:_MoveTo(pivot * CFrame.new(0, 0, 10), session, 2.5, true)
        self:_SetStatus("Approaching Tiki puzzle object", "info")
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

    if profile.TikiEventPhase == true and self.TikiPuzzleActive then
        if self:_StepTikiEventPhase(root, session) then
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

    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
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
        self:_EngageModeTarget(target, targetIsBoss, root, session)
        return
    end
    if profile.TikiEventPhase == true and self:_StepTikiEventPhase(root, session) then
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
        self.TikiPuzzleActive = false
        self.TikiPuzzleRestorePending = false
        self:_ResetSpawnSearch(nil)
        self:_SetStatus("Character ready; reacquiring farm state", "info")
    end

    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings or {}
    local farmMode = farmSettings.FarmMode or "Level Farm"
    local modeProfiles = farmSettings.FarmModeProfiles
    local farmModeProfile = type(modeProfiles) == "table" and modeProfiles[farmMode] or nil
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
        if not self.PendingQuestReachedAt then
            if self.QuestDeferredForDialogue then
                self.PendingQuestReachedAt = os.clock() - 2
            else
                self.PendingQuestReachedAt = os.clock()
                self:_SetStatus("At quest giver; waiting before quest request", "info")
                return
            end
        elseif os.clock() - self.PendingQuestReachedAt < 2 then
            return
        end
        if self:_HandleQuestDialogueRecovery(candidate, giverCFrame, root, session) then
            return
        end
        self:_RequestQuest(candidate, session)
        return
    end

    if self.TargetName ~= activeTarget then
        self:_ClearTarget(true)
        self:_ResetSpawnSearch(activeTarget)
        self.TargetName = activeTarget
    end

    local now = os.clock()
    local target
    if self.Target and self.TargetName == activeTarget and self.EnemyService:IsAlive(self.Target) then
        target = self.Target
    elseif now >= (self.NextEnemySearchAt or 0) then
        target = self.EnemyService:FindNearest(activeTarget, root.Position)
        self.NextEnemySearchAt = now + NPC_SCAN_INTERVAL
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
        self.TargetName = activeTarget
        self:_SetStatus("Target acquired: " .. activeTarget, "success")
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
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        if not self:_TryStartFarmSkill(target, session, weaponCategory, farmSettings) then
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
            local targetOffset = weaponCategory == "Blox Fruit"
                and CFrame.new(-7, 20, 0)
                or CFrame.new(7, 20, 0)
            self:_MoveTo(targetRoot.CFrame * targetOffset, session, 2.5, true)
            if (root.Position - targetRoot.Position).Magnitude >= 30 then
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
        local ok, err = pcall(self._Step, self, session)
        if not ok then
            if self.MovementService then
                self.MovementService:Cancel()
            end
            self.QuestDialogueRecovery = nil
            if self.EnemyService then
                self.EnemyService:RestoreTargetCollision()
            end
            self.Target = nil
            self.TargetName = nil
            self:_SetStatus("Main Farm step error: " .. tostring(err), "error")
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
    self.Session += 1
    self.Character = nil
    self.Target = nil
    self.TargetName = nil
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
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self.TikiPuzzleActive = false
    self.TikiPuzzleRestorePending = false
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
            self.Character = nil
            self.QuestDialogueRecovery = nil
            self.NextTikiEventScanAt = 0
            self.TikiEventActive = false
            self.TikiEventTarget = nil
            self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
            self.FarmSkillActive = false
            self.FarmSkillPreparing = nil
            self.FarmSkillIgnoredTools = {}
            self.TikiPuzzleActive = false
            self.TikiPuzzleRestorePending = false
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
            self.FarmSkillPreparing = nil
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

function MainFarm:Start()
    if self.Running then
        return true
    end
    local ready, setupError = self:_EnsureBaseServices()
    if not ready then
        self:_SetStatus("Main Farm unavailable: " .. tostring(setupError), "error")
        return false, setupError
    end

    self.Session += 1
    local collisionReady, collisionError = self.MovementService:SetFarmCollisionSuppression(true)
    if not collisionReady then
        self:_SetStatus("Main Farm collision setup failed: " .. tostring(collisionError), "error")
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
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
    self:_ResetSpawnSearch(nil)
    local session = self.Session
    self.Context.State:SetFeatureEnabled("farm.main", true)
    self:_SetStatus("Main Farm enabled; reading available quest state", "success")
    task.spawn(self._Run, self, session)
    return true
end

function MainFarm:Stop()
    self.Session += 1
    self.Running = false
    self:_EndQuestDiagnosticWait("stopped_before_confirmation", os.clock())
    if self.MovementService then
        self.MovementService:Cancel()
        self.MovementService:SetFarmCollisionSuppression(false)
    end
    if self.CombatService then
        self.CombatService:Cancel()
    end
    self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1
    self.FarmSkillActive = false
    self.FarmSkillPreparing = nil
    self.FarmSkillIgnoredTools = {}
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
end

function MainFarm:Handle(actionId, payload)
    if actionId == "farm.status.copy" then
        return self:CopyStatusReport()
    end
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
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
    if actionId == "farm.autoModeQuest" then
        if not farmSettings or type(payload) ~= "boolean" then
            self:_SetStatus("Auto quest setting is unavailable or invalid", "error")
            return false
        end
        farmSettings.AutoModeQuest = payload
        self:_SetStatus(
            "Auto quest for modes " .. (payload and "enabled" or "disabled"),
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
        self:_SetStatus("Main Farm stopped; movement and attack loop cancelled", "info")
    end
    return true
end

function MainFarm:Cleanup()
    self:Stop()
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
