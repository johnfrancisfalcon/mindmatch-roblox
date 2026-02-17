local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local remoteNames = {
    "SubmitGuess",
    "SubmitChooserSelection",
    "UsePowerUp",
    "RoundStateUpdate",
    "RevealResults",
}

for _, remoteName in ipairs(remoteNames) do
    local remote = remotesFolder:FindFirstChild(remoteName)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = remoteName
        remote.Parent = remotesFolder
    end
end

print("✅ Remotes ensured")
