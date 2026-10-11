local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomHub = require(ReplicatedStorage:WaitForChild("CustomHub"))

local hub = CustomHub.new()
local started, startError = hub:Start()
if not started then
    warn("[CustomHub] " .. tostring(startError))
end

script.Destroying:Connect(function()
    hub:Destroy()
end)
