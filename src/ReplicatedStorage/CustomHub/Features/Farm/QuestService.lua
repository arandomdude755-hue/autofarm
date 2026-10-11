local QuestService = {}
QuestService.__index = QuestService

local excludedQuestNames = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

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
    if type(guideData) ~= "table" then
        return "unknown", nil
    end

    local questData = guideData.QuestData
    if questData == nil then
        return "none", nil
    end
    if type(questData) ~= "table" or type(questData.Task) ~= "table" then
        return "unknown", nil
    end

    local targetName = next(questData.Task)
    if type(targetName) ~= "string" then
        return "active-unknown", nil
    end
    return "active", targetName
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
    if type(candidate) ~= "table" or not candidate.QuestName or candidate.Id == nil then
        return false, "Quest candidate is incomplete"
    end

    local commF, remoteError = self.Compatibility:GetCommF()
    if not commF then
        return false, remoteError
    end
    local ok, result = pcall(function()
        return commF:InvokeServer("StartQuest", tostring(candidate.QuestName), candidate.Id)
    end)
    if not ok then
        return false, tostring(result)
    end

    -- BNN ignores this return value; acceptance is confirmed separately through QuestData.Task.
    return true, result
end

return QuestService
