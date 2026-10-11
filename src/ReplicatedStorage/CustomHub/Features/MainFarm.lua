local QuestService = require(script.Parent.Farm.QuestService)
local EnemyService = require(script.Parent.Farm.EnemyService)
local MovementService = require(script.Parent.Farm.MovementService)
local CombatService = require(script.Parent.Farm.CombatService)

local QUEST_DIAGNOSTIC_INTERVAL = 1
local MAX_QUEST_DIAGNOSTIC_REPORT_LENGTH = 1400

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

local function questDataSummary(label, snapshot)
    if type(snapshot) ~= "table" then
        return label .. ": unavailable"
    end
    return string.format(
        "%s: reader=%s Guide.Data=%s QuestData.present=%s type=%s Task.type=%s",
        label,
        tostring(snapshot.ReaderState),
        tostring(snapshot.GuideDataType),
        tostring(snapshot.QuestDataPresent),
        tostring(snapshot.QuestDataType),
        tostring(snapshot.TaskType)
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

function MainFarm:_LogQuestDataSnapshot(phase, questState, force)
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
        print(text)
    end)
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

function MainFarm:_MoveTo(destination, session, threshold)
    if not self.MovementService then
        return false
    end
    return self.MovementService:MoveTo(destination, {
        Speed = 190,
        Threshold = threshold,
        IsCurrent = function()
            return self:_IsCurrent(session)
        end,
    })
end

function MainFarm:_ClearTarget()
    local hadTarget = self.Target ~= nil or self.TargetName ~= nil
    if hadTarget then
        if self.EnemyService then
            self.EnemyService:RestoreTargetCollision()
        end
        if self.MovementService then
            self.MovementService:Cancel()
        end
    end
    self.Target = nil
    self.TargetName = nil
end

function MainFarm:_RequestQuest(candidate, session)
    local key = questKey(candidate)
    local now = os.clock()
    if self.QuestDiagnosticWaitKey and self.QuestDiagnosticWaitKey ~= key then
        self:_EndQuestDiagnosticWait("candidate_changed_before_confirmation", now)
    end
    if self.LastQuestAttemptKey == key then
        local elapsed = now - (self.LastQuestAttemptAt or 0)
        if elapsed < 8 then
            self:_SetStatus("Waiting for active quest confirmation", "warning")
            return
        end
        self:_EndQuestDiagnosticWait("cooldown_elapsed_without_active_state", now)
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
    local requested, result = self.QuestService:RequestStart(candidate)
    local requestDiagnostic = self.QuestService.LastStartDiagnostic
    if type(requestDiagnostic) == "table" then
        self.QuestDiagnosticReport.RequestStage = tostring(requestDiagnostic.Stage)
        self.QuestDiagnosticReport.PcallSucceeded = requestDiagnostic.PcallSucceeded
        self.QuestDiagnosticReport.ResultType = tostring(requestDiagnostic.ResultType)
        self.QuestDiagnosticReport.ResultSummary = tostring(requestDiagnostic.ResultSummary)
    end
    local stateReadOk, stateAfterRequest = pcall(function()
        return self.QuestService:GetActiveQuestState()
    end)
    if not stateReadOk then
        stateAfterRequest = "diagnostic_read_error"
    end
    self:_LogQuestDataSnapshot("post_request", stateAfterRequest, true)
    if stateAfterRequest == "active" then
        self:_EndQuestDiagnosticWait("active_state_observed", os.clock())
    end
    if not self:_IsCurrent(session) then
        return
    end
    if requested then
        self:_SetStatus(
            "Quest request sent; waiting for GuideModule.Data.QuestData.Task confirmation",
            "warning"
        )
    else
        self:_SetStatus("Quest request failed: " .. tostring(result), "error")
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
        self:_SetStatus("Character ready; reacquiring farm state", "info")
    end

    local questState, activeTarget = self.QuestService:GetActiveQuestState()
    if self.QuestDiagnosticWaitKey then
        self:_LogQuestDataSnapshot("confirmation_poll", questState, false)
        local now = os.clock()
        if questState == "active" then
            self:_LogQuestDataSnapshot("confirmation_poll", questState, true)
            self:_EndQuestDiagnosticWait("active_state_observed", now)
        elseif now - (self.QuestDiagnosticWaitStartedAt or now) >= 8 then
            self:_LogQuestDataSnapshot("confirmation_poll", questState, true)
            self:_EndQuestDiagnosticWait("cooldown_elapsed_without_active_state", now)
        end
    end
    if questState == "unknown" then
        self:_ClearTarget()
        self.MovementService:Cancel()
        self:_SetStatus(
            "Waiting: GuideModule.Data quest state is unavailable; quest is not assumed active",
            "warning"
        )
        return
    elseif questState == "active-unknown" then
        self:_ClearTarget()
        self.MovementService:Cancel()
        self:_SetStatus("Waiting: an active quest exists but its target is not exposed", "warning")
        return
    elseif questState == "none" then
        self:_ClearTarget()
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
            if self.PendingQuestKey and self.MovementService then
                self.MovementService:Cancel()
            end
            self.PendingQuestKey = candidateKey
            self.PendingQuestReachedAt = nil
        end
        local giverCFrame = typeof(giverPosition) == "CFrame"
            and giverPosition
            or CFrame.new(giverPosition)
        if (root.Position - giverCFrame.Position).Magnitude > 8 then
            self.PendingQuestReachedAt = nil
            self:_MoveTo(giverCFrame * CFrame.new(0, 4, 2), session, 8)
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
        self:_ClearTarget()
        self.TargetName = activeTarget
    end

    local target = self.EnemyService:FindNearest(activeTarget, root.Position)
    if not target then
        if self.Target then
            self:_ClearTarget()
        end
        local spawnPart = self.EnemyService:FindSpawn(activeTarget)
        if spawnPart then
            self:_MoveTo(spawnPart.CFrame * CFrame.new(0, 60, 0), session, 100)
            self:_SetStatus("Waiting near supported spawn: " .. activeTarget, "info")
        else
            self.MovementService:Cancel()
            self:_SetStatus(
                "Waiting for living " .. activeTarget .. " or a Workspace._WorldOrigin.EnemySpawns marker",
                "warning"
            )
        end
        return
    end

    if self.Target ~= target then
        self:_ClearTarget()
        self.Target = target
        self.TargetName = activeTarget
        self:_SetStatus("Target acquired: " .. activeTarget, "success")
    end
    if not self.EnemyService:IsAlive(target) then
        self:_ClearTarget()
        self:_SetStatus("Target died or became invalid; reacquiring", "info")
        return
    end

    self.EnemyService:PrepareTarget(target, root)
    local combatReady, combatError = self:_EnsureCombatService()
    if combatReady then
        local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
        local weaponCategory = farmSettings and farmSettings.WeaponCategory or "Melee"
        if weaponCategory == "Blox Fruit" then
            self:_SetStatus("Blox Fruit M1 is a separate BNN path and is not part of this batch", "warning")
        else
            local equipped, equipResult = self.CombatService:EquipWeapon(weaponCategory)
            if equipped then
                local attackIssued, attackResult = self.CombatService:AttackM1(
                    target,
                    30,
                    weaponCategory
                )
                if attackIssued then
                    self:_SetStatus("M1 request issued; server damage is not yet confirmed", "info")
                elseif attackResult ~= "M1 animation cooldown" then
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
            self:_MoveTo(targetRoot.CFrame * CFrame.new(7, 20, 0), session, 2.5)
            if (root.Position - targetRoot.Position).Magnitude >= 30 then
                self:_SetStatus("Approaching target: " .. activeTarget, "info")
            end
        end
    else
        self:_ClearTarget()
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
            self:_SetStatus("Main Farm step error: " .. tostring(err), "error")
        end
        task.wait(0.15)
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
    self.QuestDiagnosticWaitKey = nil
    self.QuestDiagnosticWaitStartedAt = nil
    self.QuestDiagnosticReport = nil
    self.LastQuestDiagnosticSignature = nil
    self.LastQuestDiagnosticAt = 0
    self.LastStatus = nil

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
    self.Running = true
    self.CombatDependencyAttempted = false
    self.CombatDependencyError = nil
    local session = self.Session
    self.Context.State:SetFeatureEnabled("farm.main", true)
    self:_SetStatus("Main Farm enabled; reading authoritative quest state", "success")
    task.spawn(self._Run, self, session)
    return true
end

function MainFarm:Stop()
    self.Session += 1
    self.Running = false
    self:_EndQuestDiagnosticWait("stopped_before_confirmation", os.clock())
    if self.MovementService then
        self.MovementService:Cancel()
    end
    if self.CombatService then
        self.CombatService:Cancel()
    end
    if self.EnemyService then
        self.EnemyService:RestoreTargetCollision()
    end
    self.Target = nil
    self.TargetName = nil
    self.PendingQuestKey = nil
    self.PendingQuestReachedAt = nil
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
