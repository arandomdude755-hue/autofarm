local QuestService = require(script.Parent.Farm.QuestService)
local EnemyService = require(script.Parent.Farm.EnemyService)
local MovementService = require(script.Parent.Farm.MovementService)
local CombatService = require(script.Parent.Farm.CombatService)

local QUEST_DIAGNOSTIC_INTERVAL = 1
local MAX_QUEST_DIAGNOSTIC_REPORT_LENGTH = 1400
local MAX_SPAWN_DIAGNOSTIC_REPORT_LENGTH = 1400
local NPC_SCAN_INTERVAL = 0.35
local SPAWN_SCAN_INTERVAL = 0.5
local SPAWN_LOAD_GRACE = 1
local SPAWN_CYCLE_RETRY_INTERVAL = 2
local MAX_EMPTY_SPAWN_CYCLES = 2

local MainFarm = {
    Running = false,
    Session = 0,
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
            "Candidate: quest=" .. tostring(report.CandidateQuestName)
                .. " id=" .. tostring(report.CandidateQuestId),
            "StartQuest: pcall_succeeded=" .. pcallOutcome,
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
            "Normal EnemySpawns marker: " .. tostring(report.NormalMarkerFound == true),
            "Hidden unparented marker: " .. tostring(report.HiddenMarkerFound == true)
                .. " (discovery_available="
                .. tostring(report.HiddenDiscoveryAvailable == true) .. ")",
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

function MainFarm:_ClearTarget(preserveMovement)
    local hadTarget = self.Target ~= nil or self.TargetName ~= nil
    if hadTarget then
        if self.EnemyService then
            self.EnemyService:RestoreTargetCollision()
        end
        if self.MovementService and not preserveMovement then
            self.MovementService:Cancel()
        end
    end
    self.Target = nil
    self.TargetName = nil
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
    self.SpawnCandidateDiagnostic = nil
    self.SpawnLoading = nil
    self.SpawnRetryAt = nil
    self.SpawnEmptyCycles = 0
    self.SpawnSearchExhausted = false
    self.NextSpawnSearchAt = 0
    self.NextEnemySearchAt = 0
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
    if self.LastQuestAttemptKey == key then
        local elapsed = now - (self.LastQuestAttemptAt or 0)
        if elapsed < 8 then
            self:_SetStatus(
                "Waiting for active quest confirmation; "
                    .. boundedReason(self.LastQuestStateReason),
                "warning"
            )
            return
        end
        self:_TimeoutQuestConfirmation(key, now)
        return
    end

    self.LastQuestAttemptKey = key
    self.LastQuestAttemptAt = now
    self.QuestDiagnosticWaitKey = key
    self.QuestDiagnosticWaitStartedAt = now
    self.QuestDiagnosticReport = {
        CandidateQuestName = diagnosticScalar(candidate.QuestName),
        CandidateQuestId = diagnosticScalar(candidate.Id),
        RequestStage = "pcall_not_reached",
        PcallSucceeded = nil,
        ResultType = "n/a",
        ResultSummary = "not returned",
    }
    self.PendingQuestTargetName = candidate.Mob
    self:_SetStatus(
        "Requesting quest: " .. tostring(candidate.QuestName) .. " (ID "
            .. tostring(candidate.Id) .. ")",
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
            self.PendingQuestTargetName = nil
            self.PendingQuestKey = nil
            self.PendingQuestReachedAt = nil
            self:_SetStatus(
                "Quest confirmed by " .. boundedReason(readerEvidence),
                "success"
            )
        else
            self:_EndQuestDiagnosticWait("active_state_target_mismatch", os.clock())
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
        self:_ResetSpawnSearch(nil)
        self:_SetStatus("Character ready; reacquiring farm state", "info")
    end

    local questState, activeTarget, readerEvidence = self.QuestService:GetActiveQuestState()
    self.LastQuestStateReason = readerEvidence
    if self.QuestDiagnosticWaitKey then
        self:_LogQuestDataSnapshot("confirmation_poll", questState, false, readerEvidence)
        local now = os.clock()
        if questState == "active" then
            self:_LogQuestDataSnapshot("confirmation_poll", questState, true, readerEvidence)
            if activeTarget == self.PendingQuestTargetName then
                self:_EndQuestDiagnosticWait("active_state_observed", now)
                self.TimedOutQuestKey = nil
                self.LastQuestAttemptKey = nil
                self.PendingQuestTargetName = nil
                self.PendingQuestKey = nil
                self.PendingQuestReachedAt = nil
                self:_SetStatus(
                    "Quest confirmed by " .. boundedReason(readerEvidence),
                    "success"
                )
            else
                self:_EndQuestDiagnosticWait("active_state_target_mismatch", now)
                self.PendingQuestTargetName = nil
                self.PendingQuestKey = nil
                self.PendingQuestReachedAt = nil
                self:_SetStatus(
                    "A different active quest target was observed; following its validated target",
                    "warning"
                )
            end
        elseif now - (self.QuestDiagnosticWaitStartedAt or now) >= 8 then
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
        self.PendingQuestTargetName = nil
        self.PendingQuestKey = nil
        self.PendingQuestReachedAt = nil
        self:_SetStatus(
            "Quest confirmed by " .. boundedReason(readerEvidence),
            "success"
        )
    end
    if questState == "unknown" then
        self:_ClearTarget(true)
        self:_SetStatus(
            "Waiting: no reliable active quest state; movement session held safely",
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
        if (root.Position - giverCFrame.Position).Magnitude > 8 then
            self.PendingQuestReachedAt = nil
            self:_MoveTo(giverCFrame * CFrame.new(0, 4, 2), session, 8, true)
            self:_SetStatus("Approaching quest giver: " .. tostring(candidate.Name), "info")
            return
        end
        if not self.PendingQuestReachedAt then
            self.PendingQuestReachedAt = os.clock()
            self:_SetStatus("At quest giver; waiting before quest request", "info")
            return
        elseif os.clock() - self.PendingQuestReachedAt < 2 then
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
            self:_SetStatus(
                "No living " .. activeTarget
                    .. " was found after two spawn cycles; continuing throttled scans of loaded NPCs",
                "warning"
            )
            return
        end
        if self.SpawnRetryAt and now < self.SpawnRetryAt then
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
    local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
    local weaponCategory = farmSettings and farmSettings.WeaponCategory or "Melee"
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
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
            if self.EnemyService then
                self.EnemyService:RestoreTargetCollision()
            end
            self.Target = nil
            self.TargetName = nil
            self:_SetStatus("Main Farm step error: " .. tostring(err), "error")
        end
        task.wait()
    end
end

function MainFarm:Initialize(context)
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
    self.TimedOutQuestKey = nil
    self.QuestTimeoutReason = nil
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
            self:_ClearTarget()
            self:_ResetSpawnSearch(nil)
        end)
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
    self.PendingQuestTargetName = nil
    self.PendingQuestKey = nil
    self.PendingQuestReachedAt = nil
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
    if self.EnemyService then
        self.EnemyService:RestoreTargetCollision()
        self.EnemyService:ClearIgnoredSpawns()
    end
    self.Target = nil
    self.TargetName = nil
    self.PendingQuestKey = nil
    self.PendingQuestReachedAt = nil
    self.PendingQuestTargetName = nil
    self.LastQuestAttemptKey = nil
    self.LastQuestAttemptAt = 0
    self.TimedOutQuestKey = nil
    self.QuestTimeoutReason = nil
    self.LastQuestStateReason = nil
    self:_ResetSpawnSearch(nil)
    self.QuestDiagnosticWaitKey = nil
    self.QuestDiagnosticWaitStartedAt = nil
    if self.Context and self.Context.State then
        self.Context.State:SetFeatureEnabled("farm.main", false)
    end
end

function MainFarm:Handle(actionId, payload)
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
