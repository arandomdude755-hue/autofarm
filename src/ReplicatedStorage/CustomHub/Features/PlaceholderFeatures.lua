local PlaceholderFeatures = {}

function PlaceholderFeatures:Initialize(_context)
    -- Placeholder actions remain isolated from the independently managed Main Farm.
    return true
end

function PlaceholderFeatures:Handle(actionId, payload, context)
    local state = context.State

    local messages = {
        ["player.status"] = "Player feature is a placeholder; no character data was read.",
    }
    local message = messages[actionId]
    if message then
        state:SetStatus(message, "success")
        return true
    end

    return false
end

function PlaceholderFeatures:Cleanup(_context)
    -- No placeholder action owns a background task.
end

return PlaceholderFeatures
