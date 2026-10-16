from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text(
    encoding="utf-8"
)
COMPATIBILITY = (
    ROOT / "src/ReplicatedStorage/CustomHub/Compatibility.lua"
).read_text(encoding="utf-8")
MAIN_FARM = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua"
).read_text(encoding="utf-8")
HOP = (
    ROOT / "src/ReplicatedStorage/CustomHub/Features/ServerHopService.lua"
).read_text(encoding="utf-8")
PERSISTENCE = (
    ROOT / "src/ReplicatedStorage/CustomHub/SettingsPersistence.lua"
).read_text(encoding="utf-8")
HUB = (ROOT / "src/ReplicatedStorage/CustomHub/init.lua").read_text(
    encoding="utf-8"
)


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")


require(
    "HopForEliteHunter = false" in CONFIG
    and "HopForBerries = false" in CONFIG
    and 'Action = "stack.hop.eliteHunter.enabled"' in CONFIG
    and 'Action = "stack.hop.berry.enabled"' in CONFIG
    and 'RequiredSea = 3' in CONFIG
    and 'Team = "Marines"' in CONFIG,
    "server hop options must default off and startup team must default to Marines",
)
require(
    'FindFirstChild("__ServerBrowser")' in COMPATIBILITY
    and "function Compatibility:GetPublicServers(cursor)" in COMPATIBILITY
    and "serverBrowser:InvokeServer(page)" in COMPATIBILITY
    and "local lastPage = 100" in COMPATIBILITY
    and "task.delay((page - firstPage) / 50" in COMPATIBILITY
    and "local deadline = os.clock() + 8" in COMPATIBILITY
    and "serverBrowser:InvokeServer(\"teleport\", jobId)" in COMPATIBILITY
    and "function Compatibility:TeleportToPublicServer(jobId)" in COMPATIBILITY
    and "TeleportToPlaceInstance" not in COMPATIBILITY
    and "playing < maxPlayers" in HOP
    and "not self:_IsVisited(jobId)" in HOP
    and "math.random(1, #candidates)" in HOP,
    "server hopping must use the game's server browser for listings and teleport handshakes",
)
require(
    "local PAGE_DELAY = 2" in HOP
    and "pause = 5" not in HOP,
    "server-list partial pages must retry safely without the old long paging pause",
)
require(
    "function SettingsPersistence:SetHopSession(session)" in PERSISTENCE
    and "function SettingsPersistence:GetHopSession()" in PERSISTENCE
    and "PendingJobId == currentJobId" in HOP
    and "function ServerHopService:ConsumeResume()" in HOP
    and "self.ResumeServerHop" in MAIN_FARM
    and "mainFarm.ResumePendingHop" in (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text(
        encoding="utf-8"
    ),
    "a saved hop preference alone must not restart hopping; only its pending teleport may resume",
)
require(
    'self.StackTaskQueue:SetEnabled("HopEliteHunter", hopEliteRequested)' in MAIN_FARM
    and 'self.StackTaskQueue:SetEnabled("HopBerry", hopBerryRequested)' in MAIN_FARM
    and "stackSettings.AutoEliteHunter ~= true" in MAIN_FARM
    and "stackSettings.AutoCollectBerries ~= true" in MAIN_FARM
    and "stackSettings[localSettingKey] ~= true" in MAIN_FARM
    and "localTaskEnabled = stackSettings[localSettingKey] == true" in MAIN_FARM
    and "hopService:Step()" in MAIN_FARM,
    "hop jobs must require their parent task and share its local queue behavior",
)
require(
    "MAX_PERSISTED_VISITED_SERVERS = 40" in HOP
    and "shortError(reason)" in HOP
    and "shortError(fetchError)" in HOP
    and "shortError(joinError)" in HOP,
    "hop should reduce pre-join persistence work and preserve the actual Roblox join/fetch errors",
)
require(
    'HOP_SESSION_FILE_PREFIX = SETTINGS_FOLDER .. "/hop_session_"' in PERSISTENCE
    and "self.HopPath = HOP_SESSION_FILE_PREFIX .. userIdText .. \".json\"" in PERSISTENCE
    and "self.Storage.Write,\n        self.HopPath,\n        content" in PERSISTENCE
    and "document.HopSession" not in PERSISTENCE,
    "hop progress must persist in a small dedicated file instead of rewriting all saved settings",
)
require(
    "function Compatibility:SelectTeamIfPrompted(teamName, timeoutSeconds)" in COMPATIBILITY
    and 'playerGui:FindFirstChild("Main (minimal)")' in COMPATIBILITY
    and 'playerGui:FindFirstChild("Main")' in COMPATIBILITY
    and "VirtualInputManager" in COMPATIBILITY
    and "button:Activate()" in COMPATIBILITY
    and "self.Compatibility:SelectTeamIfPrompted" in HUB,
    "startup team selection must handle both team-screen layouts without a game-specific remote",
)
require(
    HUB.index("SelectTeamIfPrompted")
    < HUB.index("self.FeatureManager:Initialize()"),
    "team selection must run before the hub interface is mounted",
)

print("PASS: Elite Hunter/berry hopping uses the game's server browser and its teleport handshake")
print("PASS: startup team selection defaults to Marines and runs before the hub UI")
