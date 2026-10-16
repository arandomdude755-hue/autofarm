local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Compatibility = {}
Compatibility.__index = Compatibility

local TITLE_MENU_PROBE_TIMEOUT = 5
local TITLE_MENU_PROBE_INTERVAL = 0.05
local TITLE_MENU_CLOSE_GUARD_DURATION = 1.5
local TITLE_LOCKED_CONFIRMATION_DELAY = 0.25
local TITLE_STATE_CACHE_TTL = 5
local TITLE_STATE_UNKNOWN_CACHE_TTL = 1
local AUTO_EXECUTE_SOURCE_URL = "https://raw.githubusercontent.com/arandomdude755-hue/autofarm/dev/dist/customhub.bundle.lua"
local AUTO_EXECUTE_BUNDLE_PATH = "CustomHub/customhub.bundle.lua"
local AUTO_EXECUTE_ENABLED_KEY = "__CUSTOM_HUB_AUTO_EXECUTE"
local AUTO_EXECUTE_GENERATION_KEY = "__CUSTOM_HUB_AUTO_EXECUTE_GENERATION"

function Compatibility.new()
    return setmetatable({
        Player = Players.LocalPlayer,
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        RunService = RunService,
        CollectionService = CollectionService,
        HttpService = HttpService,
        NpcManager = nil,
        NpcCatalogNames = nil,
    }, Compatibility)
end

function Compatibility:_GetExecutorEnvironment()
    local getEnvironment
    pcall(function()
        getEnvironment = getgenv
    end)
    if type(getEnvironment) == "function" then
        local ok, environment = pcall(getEnvironment)
        if ok and type(environment) == "table" then
            return environment
        end
    end
    return _G
end

function Compatibility:_GetQueueOnTeleport()
    local environment = self:_GetExecutorEnvironment()
    local namespaces = { environment }
    if type(_G) == "table" and _G ~= environment then
        table.insert(namespaces, _G)
    end
    for _, namespaceName in ipairs({ "syn", "fluxus" }) do
        local namespace
        pcall(function()
            namespace = environment[namespaceName] or _G[namespaceName]
        end)
        if type(namespace) == "table" then
            table.insert(namespaces, namespace)
        end
    end

    for _, name in ipairs({
        "queue_on_teleport",
        "queueonteleport",
        "queueOnTeleport",
        "queue_on_tp",
    }) do
        for _, namespace in ipairs(namespaces) do
            local queueFunction
            pcall(function()
                queueFunction = namespace[name]
            end)
            if type(queueFunction) == "function" then
                return queueFunction, environment, name
            end
        end
    end
    return nil, environment, "queue-on-teleport API is unavailable"
end

function Compatibility:_FetchAutoExecuteSource(url)
    local httpOk, source = pcall(function()
        return game:HttpGet(url)
    end)
    if httpOk and type(source) == "string" and source ~= "" then
        return source, "game:HttpGet"
    end

    local lastError = httpOk and "HTTP response was empty" or tostring(source)
    local environment = self:_GetExecutorEnvironment()
    local namespaces = {}
    if type(environment) == "table" then
        table.insert(namespaces, environment)
    end
    if type(_G) == "table" and _G ~= environment then
        table.insert(namespaces, _G)
    end
    for _, namespaceName in ipairs({ "syn", "fluxus", "http" }) do
        local namespace
        pcall(function()
            namespace = environment[namespaceName] or _G[namespaceName]
        end)
        if type(namespace) == "table" then
            table.insert(namespaces, namespace)
        end
    end

    local candidates = {}
    local seen = {}
    for _, namespace in ipairs(namespaces) do
        for _, name in ipairs({ "request", "http_request" }) do
            local requestFunction
            pcall(function()
                requestFunction = namespace[name]
            end)
            if type(requestFunction) == "function" and not seen[requestFunction] then
                seen[requestFunction] = true
                table.insert(candidates, requestFunction)
            end
        end
    end

    for _, requestFunction in ipairs(candidates) do
        local requestOk, response = pcall(requestFunction, {
            Url = url,
            Method = "GET",
        })
        if requestOk then
            local body = type(response) == "string"
                and response
                or type(response) == "table"
                    and (response.Body or response.body)
            local status = type(response) == "table"
                and tonumber(response.StatusCode or response.Status or response.status_code)
            if type(body) == "string"
                and body ~= ""
                and (not status or status >= 200 and status < 300)
            then
                return body, "executor HTTP request"
            end
        else
            lastError = tostring(response)
        end

        local rawOk, rawResponse = pcall(requestFunction, url)
        if rawOk then
            local body = type(rawResponse) == "string"
                and rawResponse
                or type(rawResponse) == "table"
                    and (rawResponse.Body or rawResponse.body)
            if type(body) == "string" and body ~= "" then
                return body, "executor HTTP request"
            end
        else
            lastError = tostring(rawResponse)
        end
    end

    return nil, lastError
end

function Compatibility:_StageAutoExecuteBundle()
    local storage, storageError = self:GetLocalSettingsStorage()
    if not storage or type(storage.Write) ~= "function" then
        return false, storageError or "Local file APIs are unavailable"
    end

    local source, fetchError = self:_FetchAutoExecuteSource(AUTO_EXECUTE_SOURCE_URL)
    if type(source) ~= "string" or source == "" then
        return false, fetchError or "The bundle download was empty"
    end

    local writeOk, writeError = storage.Write(AUTO_EXECUTE_BUNDLE_PATH, source)
    if not writeOk then
        return false, writeError or "Could not save the local bundle copy"
    end
    return true
end

function Compatibility:SetAutoExecuteEnabled(enabled)
    if type(enabled) ~= "boolean" then
        return false, "Auto Execute setting is invalid"
    end

    local queueFunction, environment, apiName = self:_GetQueueOnTeleport()
    if type(environment) ~= "table" then
        return false, "Executor global environment is unavailable"
    end
    local generation
    local flagOk = pcall(function()
        generation = math.floor(
            tonumber(environment[AUTO_EXECUTE_GENERATION_KEY]) or 0
        ) + 1
        environment[AUTO_EXECUTE_GENERATION_KEY] = generation
        environment[AUTO_EXECUTE_ENABLED_KEY] = enabled
    end)
    if not flagOk then
        return false, "Executor could not save the Auto Execute state"
    end
    if not enabled then
        return true, "Auto Execute disabled; queued reloads will be skipped"
    end
    if type(queueFunction) ~= "function" then
        pcall(function()
            environment[AUTO_EXECUTE_ENABLED_KEY] = false
            environment[AUTO_EXECUTE_GENERATION_KEY] = generation + 1
        end)
        return false, apiName
    end

    local queuedSource = string.format([[
local sourceUrl = %q
local bundlePath = %q
local enabledKey = %q
local generationKey = %q
local expectedGeneration = %d
local environment
local getEnvironment = getgenv
pcall(function()
    if type(getEnvironment) == "function" then
        environment = getEnvironment()
    end
end)
if type(environment) ~= "table" then
    environment = _G
end
local autoExecuteEnabled = type(environment) == "table"
    and environment[enabledKey]
local currentGeneration = type(environment) == "table"
    and tonumber(environment[generationKey])
if autoExecuteEnabled == false
    or currentGeneration ~= nil and currentGeneration ~= expectedGeneration then
    return
end

task.spawn(function()
    local function waitFor(predicate, timeout)
        local deadline = os.clock() + timeout
        repeat
            local ok, result = pcall(predicate)
            if ok and result then
                return result
            end
            task.wait(0.25)
        until os.clock() >= deadline
        return nil
    end

    local function report(message, kind)
        warn("[Custom Hub Auto Execute] " .. message)
        local player = game:GetService("Players").LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        local hubGui = playerGui and playerGui:FindFirstChild("CustomHubShell")
        local notificationBridge = hubGui
            and hubGui:FindFirstChild("CustomHubNotificationBridge")
        if notificationBridge and notificationBridge:IsA("BindableFunction") then
            local notified = pcall(function()
                notificationBridge:Invoke(
                    "Auto Execute",
                    message,
                    kind or "info"
                )
            end)
            if notified then
                return
            end
        end

        local starterGui = game:GetService("StarterGui")
        for _ = 1, 20 do
            local shown = pcall(function()
                starterGui:SetCore("SendNotification", {
                    Title = "Custom Hub Auto Execute",
                    Text = message,
                    Duration = 8,
                })
            end)
            if shown then
                return
            end
            task.wait(0.25)
        end
    end

    if not waitFor(function()
        return game:IsLoaded()
    end, 120) then
        warn("[Custom Hub Auto Execute] Timed out waiting for the new game session.")
        return
    end

    local Players = game:GetService("Players")
    local player = waitFor(function()
        return Players.LocalPlayer
    end, 60)
    if not player then
        warn("[Custom Hub Auto Execute] LocalPlayer was unavailable.")
        return
    end

    local playerGui = waitFor(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end, 60)
    if not playerGui then
        warn("[Custom Hub Auto Execute] PlayerGui was unavailable.")
        return
    end

    local source
    local sourceKind
    local readFileFunction = readfile
    if type(readFileFunction) == "function" then
        local readOk, localSource = pcall(readFileFunction, bundlePath)
        if readOk and type(localSource) == "string" and localSource ~= "" then
            source = localSource
            sourceKind = "local bundle"
        end
    end

    if not source then
        local httpOk, httpSource = pcall(function()
            return game:HttpGet(sourceUrl)
        end)
        if httpOk and type(httpSource) == "string" and httpSource ~= "" then
            source = httpSource
            sourceKind = "URL"
        else
            local lastError = httpOk and "HTTP response was empty" or tostring(httpSource)
            local namespaces = {}
            if type(environment) == "table" then
                table.insert(namespaces, environment)
            end
            if type(_G) == "table" and _G ~= environment then
                table.insert(namespaces, _G)
            end
            for _, namespaceName in ipairs({ "syn", "fluxus", "http" }) do
                local namespace
                pcall(function()
                    namespace = environment[namespaceName] or _G[namespaceName]
                end)
                if type(namespace) == "table" then
                    table.insert(namespaces, namespace)
                end
            end

            local candidates = {}
            local seen = {}
            for _, namespace in ipairs(namespaces) do
                for _, name in ipairs({ "request", "http_request" }) do
                    local requestFunction
                    pcall(function()
                        requestFunction = namespace[name]
                    end)
                    if type(requestFunction) == "function"
                        and not seen[requestFunction]
                    then
                        seen[requestFunction] = true
                        table.insert(candidates, requestFunction)
                    end
                end
            end

            for _, requestFunction in ipairs(candidates) do
                local requestOk, response = pcall(requestFunction, {
                    Url = sourceUrl,
                    Method = "GET",
                })
                if requestOk then
                    local body = type(response) == "string"
                        and response
                        or type(response) == "table"
                            and (response.Body or response.body)
                    local status = type(response) == "table"
                        and tonumber(response.StatusCode or response.Status or response.status_code)
                    if type(body) == "string"
                        and body ~= ""
                        and (not status or status >= 200 and status < 300)
                    then
                        source = body
                        sourceKind = "executor HTTP request"
                        break
                    end
                else
                    lastError = tostring(response)
                end

                local rawOk, rawResponse = pcall(requestFunction, sourceUrl)
                if rawOk then
                    local body = type(rawResponse) == "string"
                        and rawResponse
                        or type(rawResponse) == "table"
                            and (rawResponse.Body or rawResponse.body)
                    if type(body) == "string" and body ~= "" then
                        source = body
                        sourceKind = "executor HTTP request"
                        break
                    end
                else
                    lastError = tostring(rawResponse)
                end
            end

            if not source then
                report("Could not download the bundle: " .. tostring(lastError))
                return
            end
        end
    end

    local function compile(sourceText)
        local compiler = loadstring
        if type(compiler) ~= "function" then
            return nil, "loadstring is unavailable"
        end
        local compileOk, chunk, compileError = pcall(compiler, sourceText)
        if not compileOk then
            return nil, tostring(chunk)
        end
        if type(chunk) ~= "function" then
            return nil, tostring(compileError or "The compiler returned no script")
        end
        return chunk
    end

    local chunk, compileError = compile(source)
    if not chunk and sourceKind == "local bundle" then
        local fetchOk, freshSource = pcall(function()
            return game:HttpGet(sourceUrl)
        end)
        if fetchOk and type(freshSource) == "string" and freshSource ~= "" then
            source = freshSource
            sourceKind = "URL"
            chunk, compileError = compile(source)
        else
            compileError = tostring(compileError)
                .. "; URL refresh failed: "
                .. tostring(freshSource)
        end
    end
    if not chunk then
        report("Could not compile the " .. tostring(sourceKind or "downloaded")
            .. " bundle: " .. tostring(compileError))
        return
    end

    if sourceKind == "URL" then
        pcall(function()
            if type(writefile) == "function" then
                writefile(bundlePath, source)
            end
        end)
    end

    local runOk, runError = pcall(chunk)
    if not runOk then
        report("Bundle execution failed: " .. tostring(runError), "error")
        return
    end

    local loadedGui = waitFor(function()
        local currentGui = player:FindFirstChildOfClass("PlayerGui")
        return currentGui and currentGui:FindFirstChild("CustomHubShell")
    end, 20)
    if loadedGui then
        report("Custom Hub loaded after teleport.")
    else
        report(
            "Bundle ran, but the hub window did not appear. Check executor errors.",
            "warning"
        )
    end
end)
]], AUTO_EXECUTE_SOURCE_URL, AUTO_EXECUTE_BUNDLE_PATH,
    AUTO_EXECUTE_ENABLED_KEY, AUTO_EXECUTE_GENERATION_KEY, generation)

    local queueOk, queueResult = pcall(queueFunction, queuedSource)
    if not queueOk or queueResult == false then
        pcall(function()
            environment[AUTO_EXECUTE_ENABLED_KEY] = false
            environment[AUTO_EXECUTE_GENERATION_KEY] = generation + 1
        end)
        return false, "The executor rejected the queued reload"
    end
    task.spawn(function()
        local staged, stageError = self:_StageAutoExecuteBundle()
        if not staged then
            warn(
                "[Custom Hub Auto Execute] Local bundle staging failed; "
                    .. "the queued loader will use its URL fallback: "
                    .. tostring(stageError)
            )
        end
    end)
    return true, "Auto Execute queued the current Custom Hub bundle after teleport"
end

function Compatibility:QueueAutoExecuteProbe()
    local queueFunction, _, apiName = self:_GetQueueOnTeleport()
    if type(queueFunction) ~= "function" then
        return false, apiName
    end

    local probeId = tostring(math.floor(os.clock() * 1000000))
    pcall(function()
        probeId = self.HttpService:GenerateGUID(false)
    end)

    local queuedSource = string.format([[
task.spawn(function()
    local function waitFor(predicate, timeout)
        local deadline = os.clock() + timeout
        repeat
            local ok, result = pcall(predicate)
            if ok and result then
                return result
            end
            task.wait(0.25)
        until os.clock() >= deadline
        return nil
    end

    if not waitFor(function()
        return game:IsLoaded()
    end, 120) then
        warn("[Custom Hub Queue Probe] Timed out waiting for the new game session. Probe: %s")
        return
    end

    local Players = game:GetService("Players")
    local player = waitFor(function()
        return Players.LocalPlayer
    end, 60)
    if not player then
        warn("[Custom Hub Queue Probe] LocalPlayer was unavailable. Probe: %s")
        return
    end

    local playerGui = waitFor(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end, 60)
    if not playerGui then
        warn("[Custom Hub Queue Probe] PlayerGui was unavailable. Probe: %s")
        return
    end

    local message = "Queued script ran after teleport. Probe: %s; API: %s"
    warn("[Custom Hub Queue Probe] " .. message)
    local starterGui = game:GetService("StarterGui")
    for _ = 1, 20 do
        local shown = pcall(function()
            starterGui:SetCore("SendNotification", {
                Title = "Custom Hub Queue Test",
                Text = message,
                Duration = 8,
            })
        end)
        if shown then
            return
        end
        task.wait(0.25)
    end
    warn("[Custom Hub Queue Probe] Could not display the confirmation notification.")
end)
]], probeId, probeId, probeId, probeId, apiName)

    local queueOk, queueResult = pcall(queueFunction, queuedSource)
    if not queueOk or queueResult == false then
        return false, "The executor rejected the queue test"
    end
    return true, apiName, probeId
end

function Compatibility:GetLocalSettingsStorage()
    local apiOk, api = pcall(function()
        return {
            Read = readfile,
            Write = writefile,
            Exists = isfile,
            IsFolder = isfolder,
            MakeFolder = makefolder,
        }
    end)
    if not apiOk or type(api) ~= "table"
        or type(api.Read) ~= "function"
        or type(api.Write) ~= "function"
    then
        return nil, "Local file APIs are unavailable"
    end

    return {
        Exists = type(api.Exists) == "function" and function(path)
            return api.Exists(path)
        end or nil,
        Read = function(path)
            return api.Read(path)
        end,
        Write = function(path, content)
            local folder = "CustomHub"
            if type(api.IsFolder) == "function" then
                local folderOk, exists = pcall(api.IsFolder, folder)
                if folderOk and not exists and type(api.MakeFolder) == "function" then
                    local makeOk, makeError = pcall(api.MakeFolder, folder)
                    if not makeOk then
                        local retryOk, existsAfter = pcall(api.IsFolder, folder)
                        if not retryOk or not existsAfter then
                            return false, tostring(makeError)
                        end
                    end
                end
            elseif type(api.MakeFolder) == "function" then
                pcall(api.MakeFolder, folder)
            end

            local writeOk, result = pcall(api.Write, path, content)
            if not writeOk then
                return false, tostring(result)
            end
            return true
        end,
    }
end

function Compatibility:GetNpcManager()
    if self.NpcManager then
        return self.NpcManager
    end
    local managerModule = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("NPCManager")
    if not managerModule or not managerModule:IsA("ModuleScript") then
        return nil, "NPCManager module is unavailable"
    end
    local ok, manager = pcall(require, managerModule)
    if not ok or type(manager) ~= "table"
        or type(manager.getNPCsByName) ~= "function"
    then
        return nil, "NPCManager lookup is unavailable: " .. tostring(manager)
    end
    self.NpcManager = manager
    return manager
end

function Compatibility:GetNpcCatalogNames()
    if self.NpcCatalogNames then
        return table.clone(self.NpcCatalogNames)
    end
    local managerModule = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("NPCManager")
    local npcListModule = managerModule
        and managerModule:FindFirstChild("NPCList")
    if not npcListModule or not npcListModule:IsA("ModuleScript") then
        return nil, "NPCManager.NPCList module is unavailable"
    end
    local ok, npcList = pcall(require, npcListModule)
    local list = ok and type(npcList) == "table" and npcList.List
    if type(list) ~= "table" then
        return nil, "NPCManager NPC list is unavailable: " .. tostring(npcList)
    end
    local names = {}
    for name in pairs(list) do
        if type(name) == "string" and name ~= "" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    self.NpcCatalogNames = names
    return table.clone(names)
end

function Compatibility:GetNpcModelsByName(name)
    if type(name) ~= "string" or name == "" then
        return {}, "NPC name is invalid"
    end
    local manager, managerError = self:GetNpcManager()
    if not manager then
        return {}, managerError
    end
    local ok, entries = pcall(manager.getNPCsByName, name)
    if not ok or type(entries) ~= "table" then
        return {}, ok and "NPCManager returned no entry list" or tostring(entries)
    end
    local models = {}
    local seen = {}
    for _, entry in ipairs(entries) do
        local stateOk, model = pcall(function()
            local modelState = entry and entry._modelState
            return modelState and modelState._instance
        end)
        if stateOk and model and typeof(model) == "Instance"
            and model:IsA("Model") and not seen[model]
        then
            seen[model] = true
            table.insert(models, model)
        end
    end
    return models
end

function Compatibility:GetPlayerGui()
    if not self.Player then
        return nil, "LocalPlayer is unavailable"
    end
    local playerGui = self.Player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil, "PlayerGui is unavailable"
    end
    return playerGui
end

function Compatibility:SelectTeamIfPrompted(teamName, timeoutSeconds)
    if teamName ~= "Marines" and teamName ~= "Pirates" then
        return false, "Unsupported team"
    end
    local player = self.Player
    if not player then
        return false, "LocalPlayer is unavailable"
    end

    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return false, "PlayerGui is unavailable"
    end

    local function activateButton(button)
        local fireSignal
        pcall(function()
            fireSignal = firesignal
        end)
        if type(fireSignal) == "function" then
            local activated = pcall(fireSignal, button.Activated)
            if activated then
                return true
            end
        end
        return pcall(function()
            button:Activate()
        end)
    end

    local timeout = math.clamp(tonumber(timeoutSeconds) or 20, 0, 30)
    local deadline = os.clock() + timeout
    local attempted = false
    local sawPrompt = false
    local nextButtonAttemptAt = 0
    while os.clock() <= deadline do
        if not game:IsLoaded() or not player:FindFirstChild("DataLoaded") then
            task.wait(0.1)
            continue
        end

        local main = playerGui:FindFirstChild("Main (minimal)")
        local chooseTeam = main and main:FindFirstChild("ChooseTeam")
        if not chooseTeam then
            main = playerGui:FindFirstChild("Main")
            chooseTeam = main and main:FindFirstChild("ChooseTeam")
        end
        local promptVisible = chooseTeam ~= nil and chooseTeam.Visible == true
        if player.Team and (not chooseTeam or not promptVisible) then
            return true, "Team selected"
        end

        if chooseTeam then
            sawPrompt = true
            local container = chooseTeam:FindFirstChild("Container")
            local teamCard = container and container:FindFirstChild(teamName)
            local frame = teamCard and teamCard:FindFirstChild("Frame")
            local button = frame and frame:FindFirstChild("TextButton")
            if not button then
                button = frame and frame:FindFirstChildWhichIsA("GuiButton", true)
            end
            if not button and teamCard then
                button = teamCard:FindFirstChildWhichIsA("GuiButton", true)
            end

            if button and os.clock() >= nextButtonAttemptAt then
                attempted = true
                nextButtonAttemptAt = os.clock() + 0.5
                activateButton(button)
            else
                task.wait(0.1)
            end
        else
            if player.Team then
                return true, "A team is already selected"
            end
            task.wait(0.1)
        end

        if player.Team and chooseTeam and not chooseTeam.Visible then
            return true, "Team selected"
        end
    end

    local main = playerGui:FindFirstChild("Main (minimal)")
        or playerGui:FindFirstChild("Main")
    local chooseTeam = main and main:FindFirstChild("ChooseTeam")
    if player.Team and (not chooseTeam or not chooseTeam.Visible) then
        return true, "A team is already selected"
    end
    if attempted then
        return false, "Could not confirm the " .. teamName .. " team selection"
    elseif sawPrompt then
        return false, "The team selection screen did not contain a usable button"
    end
    return false, "Team selection screen was not found after game data loaded"
end

function Compatibility:GetPublicServers(cursor)
    local serverBrowser = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not serverBrowser or not serverBrowser:IsA("RemoteFunction") then
        return nil, "The game's server browser remote is unavailable"
    end

    local firstPage = tonumber(cursor) or 1
    if firstPage % 1 ~= 0 or firstPage < 1 or firstPage > 100 then
        return nil, "Server browser page is invalid"
    end

    -- The reference hubs query all numbered pages concurrently. Stagger requests
    -- over two seconds so the search is fast without dumping 100 calls at once.
    local lastPage = 100
    local requestCount = lastPage - firstPage + 1
    local completed = 0
    local successful = 0
    local lastError = nil
    local serverData = {}
    local successfulPages = {}

    for page = firstPage, lastPage do
        task.delay((page - firstPage) / 50, function()
            local invokeOk, result = pcall(function()
                return serverBrowser:InvokeServer(page)
            end)
            if invokeOk and type(result) == "table" then
                successful += 1
                successfulPages[page] = true
                for jobId, info in pairs(result) do
                    if type(jobId) == "string" and type(info) == "table" then
                        serverData[jobId] = info
                    end
                end
            else
                lastError = invokeOk
                    and "The game's server browser returned an invalid page"
                    or tostring(result)
            end
            completed += 1
        end)
    end

    local deadline = os.clock() + 8
    while completed < requestCount and os.clock() < deadline do
        task.wait(0.05)
    end
    if successful == 0 then
        return nil, completed < requestCount
            and "The game's server browser scan timed out"
            or ("The game's server browser request failed: "
                .. tostring(lastError or "no usable pages returned"))
    end

    local maxPlayers = tonumber(self.Players and self.Players.MaxPlayers)
    if not maxPlayers or maxPlayers <= 0 then
        maxPlayers = 12
    end
    local servers = {}
    for jobId, info in pairs(serverData) do
        if type(jobId) == "string" and type(info) == "table" then
            local playing = tonumber(info.Count or info.playing)
            if playing then
                servers[#servers + 1] = {
                    id = jobId,
                    playing = playing,
                    maxPlayers = tonumber(info.MaxPlayers or info.maxPlayers)
                        or maxPlayers,
                }
            end
        end
    end
    local nextPage
    for page = firstPage, lastPage do
        if not successfulPages[page] then
            nextPage = page
            break
        end
    end
    return {
        Servers = servers,
        NextCursor = nextPage and tostring(nextPage) or nil,
    }
end

function Compatibility:TeleportToPublicServer(jobId)
    if type(jobId) ~= "string" or jobId == "" then
        return false, "Server id is unavailable"
    end
    if jobId == tostring(game.JobId) then
        return false, "This is already the current server"
    end

    local serverBrowser = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not serverBrowser or not serverBrowser:IsA("RemoteFunction") then
        return false, "The game's server browser remote is unavailable"
    end

    local teleportOk, result = pcall(function()
        return serverBrowser:InvokeServer("teleport", jobId)
    end)
    if not teleportOk then
        return false, tostring(result)
    end
    if result == false then
        return false, "The game's server browser rejected the destination"
    end
    return true
end

function Compatibility:GetUnparentedInstances()
    local getterOk, getter = pcall(function()
        return getnilinstances
    end)
    if not getterOk or type(getter) ~= "function" then
        return nil
    end

    local callOk, instances = pcall(getter)
    if not callOk or type(instances) ~= "table" then
        return nil
    end
    return instances
end

function Compatibility:GetGunShootFunction()
    if type(self.GunShootFunction) == "function"
        and type(self.GunShootTargetAssist) == "table"
        and type(self.GunShootTargetAssist.getTargetInfo) == "function"
    then
        return self.GunShootFunction, self.GunShootTargetAssist
    end

    local now = os.clock()
    if now < (self.GunShootNextScanAt or 0) then
        return nil, nil, self.GunShootResolveError or "Gun shoot function scan is cooling down"
    end
    self.GunShootNextScanAt = now + 2

    local getterOk, getGc = pcall(function()
        return getgc
    end)
    if not getterOk or type(getGc) ~= "function" then
        self.GunShootResolveError = "Executor getgc is unavailable"
        return nil, nil, self.GunShootResolveError
    end

    local debugOk, debugLibrary = pcall(function()
        return debug
    end)
    local getInfo = debugOk and debugLibrary and debugLibrary.getinfo
    local getConstants = debugOk and debugLibrary and debugLibrary.getconstants
    if type(getInfo) ~= "function" or type(getConstants) ~= "function" then
        self.GunShootResolveError = "Gun shoot function inspection is unavailable"
        return nil, nil, self.GunShootResolveError
    end

    local getGcOk, objects = pcall(getGc, false)
    if not getGcOk or type(objects) ~= "table" then
        self.GunShootResolveError = "Executor could not enumerate client functions"
        return nil, nil, self.GunShootResolveError
    end

    local isLuaClosure
    pcall(function()
        isLuaClosure = islclosure
    end)
    local getUpvalues
    pcall(function()
        getUpvalues = getupvalues
    end)

    local function hasRequiredConstants(constants)
        if type(constants) ~= "table" then
            return false
        end
        local foundShotsLeft = false
        local foundTotalShots = false
        for _, value in pairs(constants) do
            if value == "LocalShotsLeft" then
                foundShotsLeft = true
            elseif value == "LocalTotalShots" then
                foundTotalShots = true
            end
            if foundShotsLeft and foundTotalShots then
                return true
            end
        end
        return false
    end

    local function findTargetAssist(candidate)
        local values
        if type(getUpvalues) == "function" then
            local valuesOk, result = pcall(getUpvalues, candidate)
            if valuesOk and type(result) == "table" then
                values = result
            end
        end
        if not values and type(debugLibrary.getupvalue) == "function" then
            values = {}
            for index = 1, 40 do
                local valueOk, first, second =
                    pcall(debugLibrary.getupvalue, candidate, index)
                if not valueOk or first == nil then
                    break
                end
                table.insert(values, second ~= nil and second or first)
            end
        end
        for _, value in pairs(values or {}) do
            if type(value) == "table" then
                local targetInfo
                local readOk, result = pcall(rawget, value, "getTargetInfo")
                if readOk then
                    targetInfo = result
                end
                if type(targetInfo) == "function" then
                    return value
                end
            end
        end
        return nil
    end

    for _, candidate in pairs(objects) do
        if type(candidate) == "function" then
            local closureAllowed = true
            if type(isLuaClosure) == "function" then
                local closureOk, isClosure = pcall(isLuaClosure, candidate)
                closureAllowed = closureOk and isClosure == true
            end
            if closureAllowed then
                local infoOk, info = pcall(getInfo, candidate)
                local parameterCount = info
                    and (info.numparams or info.nparams)
                if infoOk and parameterCount == 2 then
                    local constantsOk, constants = pcall(getConstants, candidate)
                    if constantsOk and hasRequiredConstants(constants) then
                        local targetAssist = findTargetAssist(candidate)
                        if targetAssist then
                            self.GunShootFunction = candidate
                            self.GunShootTargetAssist = targetAssist
                            self.GunShootResolveError = nil
                            return candidate, targetAssist
                        end
                    end
                end
            end
        end
    end

    self.GunShootResolveError =
        "Could not find the client gun handler with a target lookup"
    return nil, nil, self.GunShootResolveError
end

function Compatibility:IsTouchEnabled()
    return UserInputService.TouchEnabled
end

function Compatibility:GetViewportSize()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(390, 844)
end

function Compatibility:GetCharacterParts()
    local character = self.Player and self.Player.Character
    if not character then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return character, humanoid, nil
    end
    return character, humanoid, root
end

function Compatibility:GetQuestModules()
    local questsModule = self.ReplicatedStorage:WaitForChild("Quests", 10)
    local guideModule = self.ReplicatedStorage:WaitForChild("GuideModule", 10)
    if not questsModule or not guideModule then
        return nil, nil, "BNN quest modules are unavailable"
    end

    local ok, quests = pcall(require, questsModule)
    if not ok or type(quests) ~= "table" then
        return nil, nil, "ReplicatedStorage.Quests did not return a quest table"
    end

    local guideOk, guide = pcall(require, guideModule)
    if not guideOk or type(guide) ~= "table" then
        return nil, nil, "GuideModule did not return a data table"
    end
    return quests, guide
end

function Compatibility:GetCommF()
    local remotes = self.ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        return nil, "ReplicatedStorage.Remotes.CommF_ is unavailable"
    end
    return commF
end

function Compatibility:CanSimulateTouch()
    local ok, touchFunction = pcall(function()
        return firetouchinterest
    end)
    return ok and type(touchFunction) == "function"
end

function Compatibility:TouchPart(touchingPart, targetPart, isCurrent)
    if not touchingPart or not touchingPart.Parent or not targetPart or not targetPart.Parent then
        return false, "Gateway touch parts are unavailable"
    end
    if type(isCurrent) == "function" and not isCurrent() then
        return false, "Gateway touch was cancelled"
    end
    local ok, touchFunction = pcall(function()
        return firetouchinterest
    end)
    if not ok or type(touchFunction) ~= "function" then
        return false, "This client cannot activate the map gateway touch trigger"
    end

    local began, beginError = pcall(touchFunction, touchingPart, targetPart, 0)
    if not began then
        return false, "Gateway touch could not begin: " .. tostring(beginError)
    end
    task.wait(0.15)
    if type(isCurrent) == "function" and not isCurrent() then
        pcall(touchFunction, touchingPart, targetPart, 1)
        return false, "Gateway touch was cancelled"
    end
    local ended, endError = pcall(touchFunction, touchingPart, targetPart, 1)
    if not ended then
        return false, "Gateway touch could not finish: " .. tostring(endError)
    end
    return true
end

function Compatibility:HasOwnedInventoryItem(itemName)
    local now = os.clock()
    self.OwnedInventoryCache = self.OwnedInventoryCache or {}
    if now - (self.OwnedInventoryCacheAt or 0) < 1
        and self.OwnedInventoryCache[itemName] ~= nil
    then
        return self.OwnedInventoryCache[itemName]
    end

    local itemServiceModule = self.ReplicatedStorage:FindFirstChild("ItemReplicationService")
    local itemConfigModule = self.ReplicatedStorage:FindFirstChild("ItemConfig")
    if not itemServiceModule or not itemConfigModule then
        return false, "Inventory lookup modules are unavailable"
    end

    local serviceOk, itemService = pcall(require, itemServiceModule)
    local configOk, itemConfig = pcall(require, itemConfigModule)
    if not serviceOk or type(itemService) ~= "table"
        or not configOk or type(itemConfig) ~= "table"
    then
        return false, "Inventory lookup modules could not be loaded"
    end

    local keys = itemService.KEYS
    local quantityKey = type(keys) == "table" and keys.QUANTITY
    if quantityKey == nil or type(itemService.GetItems) ~= "function"
        or type(itemConfig.match) ~= "function"
    then
        return false, "Inventory lookup APIs are unavailable"
    end

    local scanOk, found = pcall(function()
        for _, item in itemService:GetItems(quantityKey) do
            if item and item.Value and item.Value > 0 then
                local matchOk, itemDefinition = pcall(function()
                    return itemConfig.match(item.ItemId):unwrap()
                end)
                if matchOk and itemDefinition and itemDefinition.Display then
                    local display = itemDefinition.Display
                    local storageKey = itemDefinition.Index
                        and itemDefinition.Index.StorageKey
                    local resolvedName = display.Category == "Blox Fruit"
                            and (storageKey or display.Name)
                        or (display.Name or storageKey)
                    if resolvedName == itemName then
                        return true
                    end
                end
            end
        end
        return false
    end)
    if not scanOk then
        return false, "Inventory scan failed: " .. tostring(found)
    end

    self.OwnedInventoryCache[itemName] = found == true
    self.OwnedInventoryCacheAt = now
    return found == true
end

function Compatibility:GetInventoryMaterialCount(materialName)
    if type(materialName) ~= "string" or materialName == "" then
        return nil, "Material name is invalid"
    end

    local now = os.clock()
    self.InventoryMaterialCountCache = self.InventoryMaterialCountCache or {}
    local cached = self.InventoryMaterialCountCache[materialName]
    if cached and now < cached.ExpiresAt then
        return cached.Count
    end

    local itemServiceModule = self.ReplicatedStorage:FindFirstChild("ItemReplicationService")
    local itemConfigModule = self.ReplicatedStorage:FindFirstChild("ItemConfig")
    if not itemServiceModule or not itemConfigModule then
        return nil, "Inventory lookup modules are unavailable"
    end

    local serviceOk, itemService = pcall(require, itemServiceModule)
    local configOk, itemConfig = pcall(require, itemConfigModule)
    local keys = serviceOk and type(itemService) == "table" and itemService.KEYS
    local quantityKey = type(keys) == "table" and keys.QUANTITY
    if not serviceOk or type(itemService) ~= "table"
        or not configOk or type(itemConfig) ~= "table"
        or quantityKey == nil
        or type(itemService.GetItems) ~= "function"
        or type(itemConfig.match) ~= "function"
    then
        return nil, "Inventory lookup APIs are unavailable"
    end

    local scanOk, count = pcall(function()
        local total = 0
        for _, item in itemService:GetItems(quantityKey) do
            if item and tonumber(item.Value) and tonumber(item.Value) > 0 then
                local matchOk, itemDefinition = pcall(function()
                    return itemConfig.match(item.ItemId):unwrap()
                end)
                if matchOk and itemDefinition then
                    local display = itemDefinition.Display
                    local storageKey = itemDefinition.Index
                        and itemDefinition.Index.StorageKey
                    local debugLabel = itemDefinition.Index
                        and itemDefinition.Index.DebugLabel
                    local resolvedName = display
                        and (display.Name or storageKey)
                        or storageKey
                    if type(debugLabel) == "string" then
                        resolvedName = debugLabel:match("^(.-)%s*%[") or resolvedName
                    end
                    if resolvedName == materialName then
                        total += tonumber(item.Value)
                    end
                end
            end
        end
        return total
    end)
    if not scanOk then
        return nil, "Inventory material scan failed: " .. tostring(count)
    end

    self.InventoryMaterialCountCache[materialName] = {
        Count = count,
        ExpiresAt = now + 1,
    }
    return count
end

function Compatibility:GetUnlockedTitleCheck(titleName)
    if type(titleName) ~= "string" or titleName == "" then
        return nil, "title name is unavailable", false
    end

    local now = os.clock()
    self.TitleOwnershipCache = self.TitleOwnershipCache or {}
    local cache = self.TitleOwnershipCache[titleName]
    if cache and now < cache.ExpiresAt then
        return cache.Value, cache.Reason, false
    end

    local pending = self.TitleOwnershipPending
        and self.TitleOwnershipPending[titleName] == true
    return nil, pending and "title check pending" or "title state is unknown", pending
end

function Compatibility:BeginUnlockedTitleCheck(titleName)
    local state, reason, pending = self:GetUnlockedTitleCheck(titleName)
    if type(state) == "boolean" or pending then
        return state, reason, pending
    end

    local now = os.clock()
    local cache = self.TitleOwnershipCache and self.TitleOwnershipCache[titleName]
    if cache and now < cache.ExpiresAt then
        return nil, reason, false
    end

    self.TitleOwnershipPending = self.TitleOwnershipPending or {}
    self.TitleOwnershipPending[titleName] = true
    task.spawn(function()
        pcall(self.HasUnlockedTitle, self, titleName)
        if self.TitleOwnershipPending then
            self.TitleOwnershipPending[titleName] = nil
        end
    end)
    return nil, "title check pending", true
end

function Compatibility:HasUnlockedTitle(titleName)
    if type(titleName) ~= "string" or titleName == "" then
        return nil, "title name is unavailable"
    end

    local now = os.clock()
    self.TitleOwnershipCache = self.TitleOwnershipCache or {}
    local targetLower = string.lower(titleName)
    local cache = self.TitleOwnershipCache[titleName]
    if cache and now < cache.ExpiresAt then
        return cache.Value, cache.Reason
    end

    local function getMenuParts()
        local playerGui = self.Player and self.Player:FindFirstChildOfClass("PlayerGui")
        local titlesMenu = playerGui and playerGui:FindFirstChild("TitlesMenu")
        local root = titlesMenu and titlesMenu:FindFirstChild("ROOT")
        local frame = root and root:FindFirstChild("Frame")
        local content = frame and frame:FindFirstChild("content")
        local list = content and content:FindFirstChild("scrollingFrame")
        return titlesMenu, frame, list
    end

    local function readTitleState()
        local titlesMenu, frame, list = getMenuParts()
        if not titlesMenu then
            return nil, "TitlesMenu is unavailable", titlesMenu, frame, list
        end
        if not list then
            return nil, "title list is not populated", titlesMenu, frame, list
        end

        local row = list:FindFirstChild(titleName)
        if not row then
            for _, child in ipairs(list:GetChildren()) do
                if string.lower(tostring(child.Name)) == targetLower then
                    row = child
                    break
                end
            end
        end
        if not row or not row:IsA("GuiObject") then
            return nil, "title row is not present in the loaded list", titlesMenu, frame, list
        end
        if not row.Visible then
            return nil, "title row is hidden in the loaded list", titlesMenu, frame, list
        end

        local titleLabel = row:FindFirstChild("titleName", true)
        local titleText = titleLabel and titleLabel:IsA("TextLabel")
                and tostring(titleLabel.Text)
            or ""
        local titleTextLower = string.lower(titleText)
        local lockedImage = row:FindFirstChild("lockedImage", true)
        local isLocked = string.find(titleTextLower, "(locked)", 1, true) ~= nil
        if lockedImage and lockedImage:IsA("GuiObject") and lockedImage.Visible then
            isLocked = true
        end
        if isLocked then
            return false, "title row is marked locked", titlesMenu, frame, list
        end
        if titleTextLower ~= ""
            and string.find(titleTextLower, targetLower, 1, true)
        then
            return true, "unlocked title row is visible", titlesMenu, frame, list
        end
        return nil, "title row has no readable unlocked/locked marker", titlesMenu, frame, list
    end

    local function safeReadTitleState()
        local readOk, state, reason, titlesMenu, frame, list = pcall(readTitleState)
        if not readOk then
            return nil, "title UI scan failed: " .. tostring(state), nil, nil, nil
        end
        return state, reason, titlesMenu, frame, list
    end

    local state, reason, titlesMenu, frame = safeReadTitleState()
    local menuIsVisible = false
    pcall(function()
        menuIsVisible = titlesMenu.Enabled == true and frame and frame.Visible == true
    end)
    if state == true or (state == false and menuIsVisible) then
        self.TitleOwnershipCache[titleName] = {
            Value = state,
            Reason = reason,
            At = now,
            ExpiresAt = state == true
                    and math.huge
                or state == false
                    and now + TITLE_STATE_CACHE_TTL
                or now + TITLE_STATE_UNKNOWN_CACHE_TTL,
        }
        return state, reason
    end

    local openedForProbe = false
    local originalEnabled
    if titlesMenu and titlesMenu:IsA("LayerCollector") then
        originalEnabled = titlesMenu.Enabled
    end

    local frameConnections = {}
    local probeConnections = {}
    local watchedFrames = {}
    local probeFinished = false
    local lastCloseActivationAt = -math.huge
    local function activateMenuClose(activeFrame)
        if os.clock() - lastCloseActivationAt < 0.2 then
            return
        end
        lastCloseActivationAt = os.clock()
        pcall(function()
            if not activeFrame then
                local _, currentFrame = getMenuParts()
                activeFrame = currentFrame
            end
            local titleBar = activeFrame and activeFrame:FindFirstChild("title", true)
            local closeButton = titleBar and titleBar:FindFirstChild("close", true)
            if closeButton and closeButton:IsA("GuiButton") then
                closeButton:Activate()
            end
        end)
    end
    local function suppressProbeMenu(activateClose)
        pcall(function()
            local _, activeFrame = getMenuParts()
            if activeFrame and activeFrame:IsA("GuiObject") then
                if activateClose and activeFrame.Visible then
                    activateMenuClose(activeFrame)
                end
                activeFrame.Visible = false
            end
        end)
    end
    local function watchFrame(activeFrame)
        if not activeFrame or not activeFrame:IsA("GuiObject") or watchedFrames[activeFrame] then
            return
        end
        watchedFrames[activeFrame] = true
        local connectOk, connection = pcall(function()
            return activeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                pcall(function()
                    if openedForProbe and activeFrame.Visible then
                        if probeFinished then
                            activateMenuClose(activeFrame)
                        end
                        activeFrame.Visible = false
                    end
                end)
            end)
        end)
        if connectOk and connection then
            table.insert(frameConnections, connection)
        end
        if openedForProbe and activeFrame.Visible then
            activeFrame.Visible = false
        end
    end

    if not menuIsVisible then
        local openEvent = titlesMenu and titlesMenu:FindFirstChild("Open")
        if not openEvent or not openEvent:IsA("BindableEvent") then
            reason = "TitlesMenu.Open is unavailable"
            state = nil
        else
            if frame then
                watchFrame(frame)
            end
            local descendantConnection
            if titlesMenu then
                descendantConnection = titlesMenu.DescendantAdded:Connect(function(instance)
                    if instance.Name == "Frame"
                        and instance.Parent
                        and instance.Parent.Name == "ROOT"
                    then
                        pcall(watchFrame, instance)
                    end
                end)
            end
            if descendantConnection then
                table.insert(probeConnections, descendantConnection)
            end
            openedForProbe = true
            local fired, fireError = pcall(function()
                openEvent:Fire()
            end)
            if fired then
                task.wait(0.05)
                suppressProbeMenu()
            else
                openedForProbe = false
                state = nil
                reason = "TitlesMenu.Open failed: " .. tostring(fireError)
            end
        end
    end

    local function waitForTitleState()
        local deadline = os.clock() + TITLE_MENU_PROBE_TIMEOUT
        local lockedSeenAt
        repeat
            state, reason = safeReadTitleState()
            if state == true or (state == false and menuIsVisible) then
                break
            end
            if state == false then
                lockedSeenAt = lockedSeenAt or os.clock()
                if os.clock() - lockedSeenAt >= TITLE_LOCKED_CONFIRMATION_DELAY then
                    break
                end
            else
                lockedSeenAt = nil
            end
            if not openedForProbe and not menuIsVisible then
                break
            end
            if openedForProbe then
                suppressProbeMenu()
            end
            if os.clock() >= deadline then
                reason = "title list did not populate within "
                    .. tostring(TITLE_MENU_PROBE_TIMEOUT)
                    .. " seconds"
                break
            end
            task.wait(TITLE_MENU_PROBE_INTERVAL)
        until false
        return state, reason
    end
    local probeOk, probeState, probeReason = pcall(waitForTitleState)
    if probeOk then
        state, reason = probeState, probeReason
    else
        state = nil
        reason = "title menu probe failed: " .. tostring(probeState)
    end

    for _, connection in ipairs(probeConnections) do
        pcall(function()
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end)
    end
    if openedForProbe then
        probeFinished = true
        activateMenuClose(frame)
        suppressProbeMenu()
        pcall(function()
            if titlesMenu and originalEnabled ~= nil then
                titlesMenu.Enabled = originalEnabled
            end
        end)
        task.spawn(function()
            local deadline = os.clock() + TITLE_MENU_CLOSE_GUARD_DURATION
            repeat
                suppressProbeMenu(true)
                if titlesMenu and originalEnabled ~= nil then
                    pcall(function()
                        if titlesMenu.Enabled ~= originalEnabled then
                            titlesMenu.Enabled = originalEnabled
                        end
                    end)
                end
                task.wait(0.05)
            until os.clock() >= deadline
            openedForProbe = false
            for _, connection in ipairs(frameConnections) do
                pcall(function()
                    if connection and connection.Connected then
                        connection:Disconnect()
                    end
                end)
            end
        end)
    else
        for _, connection in ipairs(frameConnections) do
            pcall(function()
                if connection and connection.Connected then
                    connection:Disconnect()
                end
            end)
        end
    end

    now = os.clock()
    self.TitleOwnershipCache[titleName] = {
        Value = state,
        Reason = reason,
        At = now,
        ExpiresAt = state == true
                and math.huge
            or state == false
                and now + TITLE_STATE_CACHE_TTL
            or now + TITLE_STATE_UNKNOWN_CACHE_TTL,
    }
    return state, reason
end

function Compatibility:BuildTitleAccessDiagnosticReport()
    local targetTitle = "Liberator of the Sky"
    local targetLower = string.lower(targetTitle)
    local lines = {
        "===== [TitleAccessDiagnostic] REPORT BEGIN =====",
        "Target title: " .. targetTitle,
        "Purpose: locate title ownership data; no remotes are invoked",
    }
    local matchCount = 0
    local scanLimit = 3000
    local matchLimit = 30

    local function addMatch(sourceName, instance, valueDescription)
        if matchCount >= matchLimit then
            return
        end
        local path = "unknown path"
        pcall(function()
            path = instance:GetFullName()
        end)
        local className = "unknown class"
        pcall(function()
            className = instance.ClassName
        end)
        local visibility = ""
        pcall(function()
            if instance:IsA("GuiObject") then
                visibility = "; Visible=" .. tostring(instance.Visible)
            elseif instance:IsA("LayerCollector") then
                visibility = "; Enabled=" .. tostring(instance.Enabled)
            end
        end)
        lines[#lines + 1] = sourceName
            .. ": "
            .. path
            .. " ("
            .. className
            .. ")"
            .. (valueDescription and ("; value=" .. tostring(valueDescription)) or "")
            .. visibility
        matchCount += 1
    end

    local function scanRoot(sourceName, root, maxDescendants, includeTitleNames, includeAllText)
        if not root then
            lines[#lines + 1] = sourceName .. ": unavailable"
            return
        end
        local descendantsOk, descendants = pcall(root.GetDescendants, root)
        if not descendantsOk or type(descendants) ~= "table" then
            lines[#lines + 1] = sourceName .. ": descendants could not be read"
            return
        end
        local scanned = math.min(#descendants, tonumber(maxDescendants) or scanLimit)
        local relevantCount = 0
        for index = 1, scanned do
            local instance = descendants[index]
            local name = ""
            pcall(function()
                name = instance.Name
            end)
            local nameLower = string.lower(tostring(name))
            local valueText
            local isTextControl = false
            local valueOk = pcall(function()
                if instance:IsA("ValueBase") then
                    valueText = tostring(instance.Value)
                elseif instance:IsA("TextLabel")
                    or instance:IsA("TextButton")
                    or instance:IsA("TextBox")
                then
                    valueText = tostring(instance.Text)
                    isTextControl = true
                end
            end)
            if not valueOk then
                valueText = nil
            end
            local valueLower = type(valueText) == "string" and string.lower(valueText) or ""
            local exactTitleMatch = string.find(valueLower, targetLower, 1, true) ~= nil
            local exactTitleName = string.find(nameLower, targetLower, 1, true) ~= nil
            local titleNamed = includeTitleNames == true
                and string.find(nameLower, "title", 1, true) ~= nil
            local ownershipMarker = includeAllText == true
                and (
                    string.find(nameLower, "unlock", 1, true)
                    or string.find(nameLower, "owned", 1, true)
                    or string.find(nameLower, "claim", 1, true)
                    or string.find(nameLower, "equipped", 1, true)
                    or string.find(nameLower, "locked", 1, true)
                    or string.find(nameLower, "available", 1, true)
                )
            if titleNamed or exactTitleMatch or exactTitleName
                or (includeAllText == true and isTextControl)
                or ownershipMarker
            then
                relevantCount += 1
                addMatch(sourceName, instance, valueText)
            end

            local attributesOk, attributes = pcall(instance.GetAttributes, instance)
            if attributesOk and type(attributes) == "table" then
                for attributeName, attributeValue in pairs(attributes) do
                    local attributeNameLower = string.lower(tostring(attributeName))
                    local attributeText = tostring(attributeValue)
                    local attributeValueLower = string.lower(attributeText)
                    if (includeTitleNames == true
                            and string.find(attributeNameLower, "title", 1, true))
                        or string.find(attributeValueLower, targetLower, 1, true)
                    then
                        relevantCount += 1
                        addMatch(
                            sourceName .. " attribute " .. tostring(attributeName),
                            instance,
                            attributeText
                        )
                    end
                end
            end
        end
        lines[#lines + 1] = sourceName
            .. " scan: "
            .. tostring(scanned)
            .. " descendants; "
            .. tostring(relevantCount)
            .. " title-related matches"
            .. (#descendants > scanned and "; scan limit reached" or "")
    end

    local player = self.Player
    local playerData = player and player:FindFirstChild("Data")
    scanRoot("Player.Data", playerData, scanLimit, true, false)

    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
    local titlesMenu = playerGui and playerGui:FindFirstChild("TitlesMenu")
    local mainTitles = playerGui
        and playerGui:FindFirstChild("Main")
        and playerGui.Main:FindFirstChild("Titles")
    scanRoot("PlayerGui exact-title scan", playerGui, 10000, false, false)
    scanRoot("TitlesMenu", titlesMenu, 10000, true, true)
    local function describeGuiRoot(instance)
        if not instance then
            return "missing"
        end
        local state = instance.ClassName .. "; present"
        pcall(function()
            if instance:IsA("LayerCollector") then
                state ..= "; Enabled=" .. tostring(instance.Enabled)
            elseif instance:IsA("GuiObject") then
                state ..= "; Visible=" .. tostring(instance.Visible)
            end
        end)
        return state
    end
    lines[#lines + 1] = "TitlesMenu root: "
        .. describeGuiRoot(titlesMenu)
    lines[#lines + 1] = "Main.Titles root: "
        .. describeGuiRoot(mainTitles)

    local replicatedStorage = self.ReplicatedStorage
    local remoteCandidates = {}
    local moduleCandidates = {}
    if replicatedStorage then
        local descendantsOk, descendants = pcall(replicatedStorage.GetDescendants, replicatedStorage)
        if descendantsOk and type(descendants) == "table" then
            for index = 1, math.min(#descendants, scanLimit) do
                local instance = descendants[index]
                local nameLower = string.lower(tostring(instance.Name))
                if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
                    if string.find(nameLower, "title", 1, true) then
                        remoteCandidates[#remoteCandidates + 1] = instance:GetFullName()
                    elseif instance.Name == "CommF_" then
                        remoteCandidates[#remoteCandidates + 1] =
                            instance:GetFullName() .. " (generic remote; not invoked)"
                    end
                elseif instance:IsA("ModuleScript")
                    and string.find(nameLower, "title", 1, true)
                then
                    moduleCandidates[#moduleCandidates + 1] = instance:GetFullName()
                end
            end
        end
    end
    lines[#lines + 1] = "Title-related remotes: "
        .. (#remoteCandidates > 0 and table.concat(remoteCandidates, ", ") or "none found")
    lines[#lines + 1] = "Title-related modules: "
        .. (#moduleCandidates > 0 and table.concat(moduleCandidates, ", ") or "none found")
    local remotesFolder = replicatedStorage and replicatedStorage:FindFirstChild("Remotes")
    local commF = remotesFolder and remotesFolder:FindFirstChild("CommF_")
    lines[#lines + 1] = "Generic CommF_ remote: "
        .. (commF and (commF.ClassName .. "; present; not invoked") or "missing")

    local npcFolder = self.Workspace and self.Workspace:FindFirstChild("NPCs")
    local titleNpcs = {}
    for _, npc in ipairs(npcFolder and npcFolder:GetChildren() or {}) do
        if string.find(string.lower(npc.Name), "title", 1, true) then
            titleNpcs[#titleNpcs + 1] = npc.Name
        end
    end
    lines[#lines + 1] = "Title-related Workspace.NPCs: "
        .. (#titleNpcs > 0 and table.concat(titleNpcs, ", ") or "none found")
    if matchCount == 0 then
        lines[#lines + 1] = "Exact title text not found in the scanned Player.Data or PlayerGui entries."
    end
    lines[#lines + 1] = "Note: name/value matches are evidence only; they do not prove unlocked status."
    lines[#lines + 1] = "===== [TitleAccessDiagnostic] REPORT END ====="
    return table.concat(lines, "\n")
end

function Compatibility:GetCombatDependencies()
    local modules = self.ReplicatedStorage:FindFirstChild("Modules")
    local netModule = modules and modules:FindFirstChild("Net")
    local mouseModule = self.ReplicatedStorage:FindFirstChild("Mouse")
    local combatUtilModule = modules and modules:FindFirstChild("CombatUtil")
    if not netModule or not mouseModule or not combatUtilModule then
        return nil, "BNN melee dependency modules are unavailable"
    end

    local registerAttack = netModule:WaitForChild("RE/RegisterAttack", 10)
    if not registerAttack then
        return nil, "Modules.Net.RE/RegisterAttack is unavailable"
    end

    local mouseOk, mouse = pcall(require, mouseModule)
    local combatOk, combatUtil = pcall(require, combatUtilModule)
    local netOk, net = pcall(require, netModule)
    if not mouseOk or not combatOk or not netOk then
        return nil, "BNN melee dependency modules failed to load"
    end

    local hitOk, registerHit = pcall(function()
        return net:RemoteEvent("RegisterHit", true)
    end)
    if not hitOk or not registerHit then
        return nil, "Modules.Net RegisterHit dependency is unavailable"
    end

    return {
        Mouse = mouse,
        CombatUtil = combatUtil,
        Net = net,
        RegisterAttack = registerAttack,
        RegisterHit = registerHit,
    }
end

function Compatibility:IsThirdSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea3"
        or game.PlaceId == 100117331123089
        or game.PlaceId == 7449423635
end

function Compatibility:IsFirstSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea1"
        or game.PlaceId == 2753915549
        or game.PlaceId == 85211729168715
end

function Compatibility:IsSecondSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea2"
        or game.PlaceId == 4442272183
        or game.PlaceId == 79091703265657
end

return Compatibility
