local TaskCoordinator = {}
TaskCoordinator.__index = TaskCoordinator

local VALID_GROUPS = {
    MainFarm = true,
    Background = true,
    StackFarm = true,
    Protected = true,
}

function TaskCoordinator.new()
    return setmetatable({
        Current = nil,
        NextLeaseId = 0,
        Destroyed = false,
    }, TaskCoordinator)
end

-- Background work is normal Main Farming or user-directed Travel. Stack work
-- may pause either; Protected progression work may take over from Main Farming.
function TaskCoordinator:TryAcquire(owner, label, group, onPreempt)
    if self.Destroyed then
        return nil, "Task coordination has stopped"
    end
    if type(owner) ~= "string" or owner == "" then
        return nil, "Task owner is required"
    end
    if type(label) ~= "string" or label == "" then
        return nil, "Task label is required"
    end
    if not VALID_GROUPS[group] then
        return nil, "Unsupported task group"
    end

    local current = self.Current
    if current then
        if current.Owner == owner
            and current.Label == label
            and current.Group == group
        then
            return current
        end
        local canPreemptMainFarm = (
                group == "StackFarm" or group == "Protected"
            )
            and current.Group == "MainFarm"
        local canPreemptBackground = (
                group == "StackFarm" or group == "Protected"
            )
            and current.Group == "Background"
        if canPreemptMainFarm or canPreemptBackground then
            self.Current = nil
            if type(current.OnPreempt) == "function" then
                pcall(current.OnPreempt, group, label)
            end
        else
            return nil, current
        end
    end

    self.NextLeaseId += 1
    local lease = {
        Id = self.NextLeaseId,
        Owner = owner,
        Label = label,
        Group = group,
        OnPreempt = onPreempt,
    }
    self.Current = lease
    return lease
end

function TaskCoordinator:CanRunStack(stackLease)
    local current = self.Current
    if not current then
        return true
    end
    if current == stackLease
        or current.Group == "MainFarm"
        or current.Group == "Background"
    then
        return true
    end
    return false, current
end

function TaskCoordinator:GetCurrent()
    return self.Current
end

function TaskCoordinator:IsCurrent(lease)
    return lease ~= nil and self.Current == lease
end

function TaskCoordinator:Release(lease)
    if not lease or self.Current ~= lease then
        return false
    end
    self.Current = nil
    return true
end

function TaskCoordinator:Cleanup()
    self.Destroyed = true
    self.Current = nil
end

return TaskCoordinator
