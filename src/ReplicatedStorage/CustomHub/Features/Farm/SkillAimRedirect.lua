local SkillAimRedirect = {}

local STATE_KEY = "__CustomHubSkillAimRedirectV1"

local function getSharedState()
    local environment = _G
    local getterOk, getEnvironment = pcall(function()
        return getgenv
    end)
    if getterOk and type(getEnvironment) == "function" then
        local environmentOk, executorEnvironment = pcall(getEnvironment)
        if environmentOk and type(executorEnvironment) == "table" then
            environment = executorEnvironment
        end
    end

    local stateOk, existingState = pcall(function()
        return environment[STATE_KEY]
    end)
    if stateOk and type(existingState) == "table" and existingState.Version == 1 then
        return existingState
    end

    local newState = {
        Version = 1,
        ActiveContext = nil,
        Installed = false,
        InstallError = nil,
    }
    pcall(function()
        environment[STATE_KEY] = newState
    end)
    return newState
end

local state = getSharedState()

local function clearExpiredContext()
    local context = state.ActiveContext
    if context and context.ExpiresAt and os.clock() > context.ExpiresAt then
        context.Active = false
        state.ActiveContext = nil
        return nil
    end
    return context
end

local function installNamecallHook()
    if state.Installed then
        return true
    end

    local getterOk, getRawMetatable = pcall(function()
        return getrawmetatable
    end)
    local readonlyOk, setReadonly = pcall(function()
        return setreadonly
    end)
    local closureOk, newClosure = pcall(function()
        return newcclosure
    end)
    local methodOk, getNamecallMethod = pcall(function()
        return getnamecallmethod
    end)
    if not getterOk or type(getRawMetatable) ~= "function"
        or not readonlyOk or type(setReadonly) ~= "function"
        or not closureOk or type(newClosure) ~= "function"
        or not methodOk or type(getNamecallMethod) ~= "function"
    then
        state.InstallError = "Executor remote-aim hooks are unavailable"
        return false, state.InstallError
    end

    local metatableOk, gameMetatable = pcall(getRawMetatable, game)
    if not metatableOk or type(gameMetatable) ~= "table"
        or type(gameMetatable.__namecall) ~= "function"
    then
        state.InstallError = "Game remote-aim hook target is unavailable"
        return false, state.InstallError
    end

    local oldNamecall = gameMetatable.__namecall
    local wrapperOk, replacement = pcall(newClosure, function(remote, ...)
        local context = clearExpiredContext()
        if context and context.Active then
            local currentMethodOk, currentMethod = pcall(getNamecallMethod)
            if currentMethodOk and currentMethod == "FireServer" then
                local nameOk, remoteName = pcall(function()
                    return remote.Name
                end)
                if nameOk and remoteName == "RemoteEvent" then
                    local arguments = table.pack(...)
                    if arguments.n == 1 then
                        local argument = arguments[1]
                        if typeof(argument) == "Vector3" then
                            arguments[1] = context.Position
                            return oldNamecall(
                                remote,
                                table.unpack(arguments, 1, arguments.n)
                            )
                        elseif typeof(argument) == "CFrame" then
                            arguments[1] = context.CFrame
                            return oldNamecall(
                                remote,
                                table.unpack(arguments, 1, arguments.n)
                            )
                        end
                    end
                end
            end
        end
        return oldNamecall(remote, ...)
    end)
    if not wrapperOk or type(replacement) ~= "function" then
        state.InstallError = "Could not create the skill aim redirect"
        return false, state.InstallError
    end

    local writable, writableError = pcall(setReadonly, gameMetatable, false)
    if not writable then
        state.InstallError = "Could not enable the skill aim redirect: "
            .. tostring(writableError)
        return false, state.InstallError
    end

    local assigned, assignError = pcall(function()
        gameMetatable.__namecall = replacement
    end)
    pcall(setReadonly, gameMetatable, true)
    if not assigned then
        state.InstallError = "Could not install the skill aim redirect: "
            .. tostring(assignError)
        return false, state.InstallError
    end

    state.Installed = true
    state.InstallError = nil
    return true
end

function SkillAimRedirect:Begin(targetPart)
    if not targetPart or not targetPart:IsA("BasePart") then
        return nil, "Skill aim target is unavailable"
    end
    if clearExpiredContext() then
        return nil, "Another skill aim redirect is already active"
    end

    local installed, installError = installNamecallHook()
    if not installed then
        return nil, installError
    end

    local context = {
        Active = true,
        ExpiresAt = os.clock() + 7,
    }
    state.ActiveContext = context
    local updated, updateError = self:Update(context, targetPart)
    if not updated then
        self:End(context)
        return nil, updateError
    end
    return context
end

function SkillAimRedirect:Update(context, targetPart)
    if not context or context.Active ~= true or state.ActiveContext ~= context then
        return false, "Skill aim redirect is no longer active"
    end
    if not targetPart or not targetPart:IsA("BasePart") or not targetPart.Parent then
        return false, "Skill aim target part is unavailable"
    end

    context.Position = targetPart.Position
    context.CFrame = targetPart.CFrame
    context.ExpiresAt = os.clock() + 7
    return true
end

function SkillAimRedirect:End(context)
    if not context then
        return
    end
    context.Active = false
    if state.ActiveContext == context then
        state.ActiveContext = nil
    end
end

return SkillAimRedirect
