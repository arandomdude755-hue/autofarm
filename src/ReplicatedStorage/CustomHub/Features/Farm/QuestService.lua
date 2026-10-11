local QuestService = {}
QuestService.__index = QuestService

local MAX_TRACKED_QUEST_TEXT_LENGTH = 160
local MAX_TRACKED_QUEST_PROGRESS_LENGTH = 32
local MAX_MAIN_QUEST_TITLE_LENGTH = 160

local excludedQuestNames = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

local function diagnosticScalarRepresentation(value)
    local valueType = typeof(value)
    if type(value) == "string" then
        return string.format("<string length=%d>", #value)
    end

    if value == nil or type(value) == "boolean" then
        return tostring(value)
    end
    if type(value) == "number" then
        return "<number-redacted>"
    end
    return "<" .. tostring(valueType) .. ">"
end

local function usableTrackedQuestText(text, maxLength)
    if type(text) ~= "string" or #text == 0 or #text > maxLength then
        return nil
    end

    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function parseTrackedQuestProgress(text)
    if type(text) ~= "string" or #text > MAX_TRACKED_QUEST_PROGRESS_LENGTH then
        return nil
    end

    local currentText, totalText = text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
    if not currentText or not totalText then
        return nil
    end

    local current = tonumber(currentText)
    local total = tonumber(totalText)
    if not current or not total
        or current == math.huge
        or total == math.huge
        or total <= 0
        or current >= total
    then
        return nil
    end
    return current, total
end

local function titleContainsTarget(title, targetName)
    if type(title) ~= "string" or type(targetName) ~= "string" then
        return false
    end

    local titleWords = {}
    for word in title:lower():gmatch("[%w]+") do
        table.insert(titleWords, word)
    end
    local targetWords = {}
    for word in targetName:lower():gmatch("[%w]+") do
        table.insert(targetWords, word)
    end
    if #targetWords == 0 or #targetWords > #titleWords then
        return false
    end

    for startIndex = 1, #titleWords - #targetWords + 1 do
        local matches = true
        for offset, expected in ipairs(targetWords) do
            local actual = titleWords[startIndex + offset - 1]
            local finalWord = offset == #targetWords
            if actual ~= expected and not (finalWord and actual == expected .. "s") then
                matches = false
                break
            end
        end
        if matches then
            return true
        end
    end
    return false
end

local function parseMainQuestTitleProgress(title)
    if type(title) ~= "string" then
        return nil
    end
    local currentText, totalText = title:match("%((%d+)%s*/%s*(%d+)%)%s*$")
    local current = tonumber(currentText)
    local total = tonumber(totalText)
    if not current or not total or total <= 0 or current >= total then
        return nil
    end
    return current, total
end

local function findEligibleQuestTarget(self, guideData, targetName, progressTotal)
    local level = self:GetPlayerLevel()
    local npcList = type(guideData) == "table" and guideData.NPCList or nil
    if not level or type(npcList) ~= "table" or type(self.Quests) ~= "table" then
        return nil
    end

    for _, npcEntry in pairs(npcList) do
        if type(npcEntry) == "table" and not excludedQuestNames[npcEntry.InternalQuestName]
            and type(npcEntry.Levels) == "table"
        then
            local questGroup = self.Quests[npcEntry.InternalQuestName]
            if type(questGroup) == "table" then
                for questId, requiredLevel in pairs(npcEntry.Levels) do
                    local numericLevel = tonumber(requiredLevel)
                    local quest = questGroup[questId]
                    if numericLevel and numericLevel >= 0 and numericLevel <= level
                        and type(quest) == "table" and type(quest.Task) == "table"
                    then
                        local mobName, count = next(quest.Task)
                        local numericCount = tonumber(count)
                        if mobName == targetName and numericCount == progressTotal
                            and numericCount > 1
                        then
                            return mobName
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function findEligibleTargetFromTitle(self, guideData, title, progressTotal)
    local level = self:GetPlayerLevel()
    local npcList = type(guideData) == "table" and guideData.NPCList or nil
    if not level or type(npcList) ~= "table" or type(self.Quests) ~= "table" then
        return nil, "quest catalog or eligible NPC list is unavailable"
    end

    local bestTarget, bestLength, ambiguous = nil, 0, false
    for _, npcEntry in pairs(npcList) do
        if type(npcEntry) == "table"
            and not excludedQuestNames[npcEntry.InternalQuestName]
            and type(npcEntry.Levels) == "table"
        then
            local questGroup = self.Quests[npcEntry.InternalQuestName]
            if type(questGroup) == "table" then
                for questId, requiredLevel in pairs(npcEntry.Levels) do
                    local numericLevel = tonumber(requiredLevel)
                    local quest = questGroup[questId]
                    if numericLevel and numericLevel >= 0 and numericLevel <= level
                        and type(quest) == "table" and type(quest.Task) == "table"
                    then
                        for mobName, count in pairs(quest.Task) do
                            local numericCount = tonumber(count)
                            if type(mobName) == "string" and numericCount and numericCount > 1
                                and numericCount == progressTotal
                                and titleContainsTarget(title, mobName)
                            then
                                local nameLength = #mobName
                                if nameLength > bestLength then
                                    bestTarget, bestLength, ambiguous = mobName, nameLength, false
                                elseif nameLength == bestLength and bestTarget ~= mobName then
                                    ambiguous = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if ambiguous then
        return nil, "visible quest title matches multiple catalog targets"
    end
    if not bestTarget then
        return nil, "visible quest title does not map to a level-eligible catalog target"
    end
    return bestTarget
end

local function readTrackedQuestTarget(self, guideData)
    local ok, targetName = pcall(function()
        local compatibility = self.Compatibility
        if not compatibility or type(compatibility.GetPlayerGui) ~= "function" then
            return nil
        end

        local playerGui = compatibility:GetPlayerGui()
        local trackedQuestFrame = playerGui and playerGui:FindFirstChild("TrackedQuestFrame")
        if not trackedQuestFrame or not trackedQuestFrame:IsA("ScreenGui")
            or not trackedQuestFrame.Enabled
        then
            return nil
        end

        local frame = trackedQuestFrame:FindFirstChild("Frame")
        local header = frame and frame:FindFirstChild("header")
        local titleLabel = header and header:FindFirstChild("textLabel")
        local description = frame and frame:FindFirstChild("description")
        local progressLabel = frame and frame:FindFirstChild("progress")
        local title = titleLabel and usableTrackedQuestText(
            titleLabel.Text,
            MAX_TRACKED_QUEST_TEXT_LENGTH
        )
        local target = description and usableTrackedQuestText(
            description.Text,
            MAX_TRACKED_QUEST_TEXT_LENGTH
        )
        local progressText = progressLabel and progressLabel.Text
        if not title or not target then
            return nil
        end
        local progressCurrent, progressTotal = parseTrackedQuestProgress(progressText)
        if progressCurrent == nil or progressTotal == nil then
            return nil
        end

        return findEligibleQuestTarget(self, guideData, target, progressTotal)
    end)

    if not ok then
        return nil
    end
    return targetName
end

local function readFirstSeaQuestHud(self, guideData)
    local ok, state, targetName, reason = pcall(function()
        local compatibility = self.Compatibility
        if not compatibility or type(compatibility.GetPlayerGui) ~= "function" then
            return "unknown", nil, "PlayerGui reader is unavailable"
        end

        local playerGui = compatibility:GetPlayerGui()
        local main = playerGui and playerGui:FindFirstChild("Main")
        if not main then
            return "unknown", nil, "PlayerGui.Main is unavailable"
        end
        if main:IsA("ScreenGui") and not main.Enabled then
            return "unknown", nil, "PlayerGui.Main ScreenGui is disabled"
        end

        local questFrame = main:FindFirstChild("Quest")
        if not questFrame or not questFrame:IsA("GuiObject") then
            return "unknown", nil, "PlayerGui.Main.Quest is unavailable"
        end
        if not questFrame.Visible then
            return "none", nil, "PlayerGui.Main.Quest.Visible is false"
        end

        local container = questFrame:FindFirstChild("Container")
        local questTitle = container and container:FindFirstChild("QuestTitle")
        local titleLabel = questTitle and questTitle:FindFirstChild("Title")
        local titleIsText = titleLabel and (
            titleLabel:IsA("TextLabel")
                or titleLabel:IsA("TextButton")
                or titleLabel:IsA("TextBox")
        )
        if not titleIsText or not titleLabel.Visible
            or not container or (container:IsA("GuiObject") and not container.Visible)
            or not questTitle or (questTitle:IsA("GuiObject") and not questTitle.Visible)
        then
            return "active-unknown", nil, "visible quest panel has no visible readable title label"
        end

        local title = usableTrackedQuestText(titleLabel.Text, MAX_MAIN_QUEST_TITLE_LENGTH)
        if not title then
            return "active-unknown", nil, "visible quest panel title is empty or malformed"
        end
        local _, progressTotal = parseMainQuestTitleProgress(title)
        if not progressTotal then
            return "active-unknown", nil, "visible quest title has no valid incomplete current/total progress"
        end
        local mappedTarget, mappingError = findEligibleTargetFromTitle(
            self,
            guideData,
            title,
            progressTotal
        )
        if not mappedTarget then
            return "active-unknown", nil, mappingError
        end
        return "active", mappedTarget,
            "visible Main.Quest title/progress maps to the level-eligible quest catalog"
    end)

    if not ok then
        return "unknown", nil, "First Sea quest HUD read failed safely"
    end
    return state, targetName, reason
end

function QuestService.new(compatibility)
    local quests, guide, loadError = compatibility:GetQuestModules()
    if not quests then
        return nil, loadError
    end
    return setmetatable({
        Compatibility = compatibility,
        Player = compatibility.Player,
        Quests = quests,
        Guide = guide,
    }, QuestService)
end

function QuestService:GetPlayerLevel()
    local data = self.Player and self.Player:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    return level and tonumber(level.Value)
end

function QuestService:GetActiveQuestState()
    local guideData = self.Guide and self.Guide.Data
    local questData = type(guideData) == "table" and guideData.QuestData or nil
    if type(questData) == "table" and type(questData.Task) == "table" then
        local targetName = next(questData.Task)
        if type(targetName) == "string" and targetName ~= "" then
            return "active", targetName, "GuideModule.Data.QuestData.Task"
        end
    end

    local trackedTarget = readTrackedQuestTarget(self, guideData)
    if trackedTarget then
        return "active", trackedTarget, "TrackedQuestFrame title/target/progress mapped to quest catalog"
    end

    local firstSea = false
    if self.Compatibility and type(self.Compatibility.IsFirstSea) == "function" then
        local seaReadOk, isFirstSea = pcall(self.Compatibility.IsFirstSea, self.Compatibility)
        firstSea = seaReadOk and isFirstSea == true
    end
    if firstSea then
        local hudState, hudTarget, hudReason = readFirstSeaQuestHud(self, guideData)
        return hudState, hudTarget, hudReason
    end

    if type(guideData) ~= "table" then
        return "unknown", nil, "GuideModule.Data is unavailable"
    end
    if questData == nil then
        return "none", nil, "GuideModule.Data.QuestData is absent"
    end
    if type(questData) ~= "table" or type(questData.Task) ~= "table" then
        return "unknown", nil, "GuideModule.Data.QuestData.Task is not a table"
    end
    return "active-unknown", nil, "GuideModule exposes a quest record without a readable task"
end

function QuestService:SelectLevelQuest()
    local level = self:GetPlayerLevel()
    local guideData = self.Guide and self.Guide.Data
    local npcList = guideData and guideData.NPCList
    if not level or type(npcList) ~= "table" then
        return nil, "Player level or GuideModule.Data.NPCList is unavailable"
    end

    local bestLevel = 0
    local bestCandidate = nil
    for _, npcEntry in pairs(npcList) do
        if type(npcEntry) == "table" and not excludedQuestNames[npcEntry.InternalQuestName] then
            local questGroup = self.Quests[npcEntry.InternalQuestName]
            if type(npcEntry.Levels) == "table" and type(questGroup) == "table" then
                for questId, requiredLevel in pairs(npcEntry.Levels) do
                    local quest = questGroup[questId]
                    local numericLevel = tonumber(requiredLevel)
                    if type(quest) == "table"
                        and type(quest.Task) == "table"
                        and numericLevel
                        and numericLevel <= level
                        and numericLevel >= bestLevel
                    then
                        local mobName, count = next(quest.Task)
                        local numericCount = tonumber(count)
                        if type(mobName) == "string" and numericCount and numericCount > 1 then
                            bestCandidate = {
                                Level = numericLevel,
                                Name = npcEntry.NPCName,
                                QuestName = npcEntry.InternalQuestName,
                                Pos = npcEntry.Position,
                                Id = questId,
                                Mob = mobName,
                            }

                            local activeState, activeTarget = self:GetActiveQuestState()
                            local numericQuestId = tonumber(questId)
                            if activeState == "active"
                                and activeTarget == mobName
                                and numericQuestId
                                and numericQuestId > 1
                            then
                                local previousQuest = questGroup[numericQuestId - 1]
                                if previousQuest and type(previousQuest.Task) == "table" then
                                    for previousMob, previousCount in pairs(previousQuest.Task) do
                                        if previousMob ~= activeTarget
                                            and tonumber(previousCount)
                                            and tonumber(previousCount) > 1
                                        then
                                            bestCandidate.Mob = previousMob
                                            bestCandidate.Id = numericQuestId - 1
                                            break
                                        end
                                    end
                                end
                            end
                            bestLevel = numericLevel
                        end
                    end
                end
            end
        end
    end

    if not bestCandidate then
        return nil, "No eligible level-based quest candidate"
    end
    return bestCandidate
end

function QuestService:RequestStart(candidate)
    self.LastStartDiagnostic = {
        Stage = "pcall_not_reached",
        PcallSucceeded = nil,
        ResultType = "n/a",
        ResultSummary = "not returned",
    }
    if type(candidate) ~= "table" or not candidate.QuestName or candidate.Id == nil then
        self.LastStartDiagnostic.Stage = "candidate_invalid"
        return false, "Quest candidate is incomplete"
    end

    local commF, remoteError = self.Compatibility:GetCommF()
    if not commF then
        self.LastStartDiagnostic.Stage = "remote_unavailable"
        return false, remoteError
    end
    local ok, result = pcall(function()
        return commF:InvokeServer("StartQuest", tostring(candidate.QuestName), candidate.Id)
    end)
    pcall(function()
        self.LastStartDiagnostic = {
            Stage = "pcall_completed",
            PcallSucceeded = ok,
            ResultType = tostring(typeof(result)),
            ResultSummary = diagnosticScalarRepresentation(result),
        }
    end)
    if not ok then
        return false, tostring(result)
    end

    -- BNN ignores this return value; acceptance is confirmed separately through QuestData.Task.
    return true, result
end

return QuestService
