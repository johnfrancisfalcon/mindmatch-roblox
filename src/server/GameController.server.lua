local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Config = require(Shared:WaitForChild("Config"))
local RoundState = require(Shared:WaitForChild("RoundState"))
local RoundModel = require(Shared:WaitForChild("RoundModel"))

local roundStateUpdateRemote = Remotes:WaitForChild("RoundStateUpdate")
local revealResultsRemote = Remotes:WaitForChild("RevealResults")
local submitGuessRemote = Remotes:WaitForChild("SubmitGuess")
local submitChooserSelectionRemote = Remotes:WaitForChild("SubmitChooserSelection")

local scoresByUserId = {}
local currentState = RoundState.Lobby
local currentRound = RoundModel.new(0, RoundState.Lobby, nil, scoresByUserId)
local lastChooserUserId = nil
local tokenLookup = {}

for _, tokenId in ipairs(Config.TOKEN_POOL) do
    tokenLookup[tokenId] = true
end

local function shallowCopyArray(values)
    local out = {}
    for i = 1, #values do
        out[i] = values[i]
    end
    return out
end

local function shallowCopyMap(mapValue)
    local out = {}
    for key, value in pairs(mapValue) do
        out[key] = value
    end
    return out
end

local function formatStringArray(values)
    local fragments = {}
    for _, value in ipairs(values) do
        table.insert(fragments, value)
    end
    return "[" .. table.concat(fragments, ", ") .. "]"
end

local function formatNumberMap(mapValue)
    local fragments = {}
    for key, value in pairs(mapValue) do
        table.insert(fragments, string.format("%s=%s", tostring(key), tostring(value)))
    end
    table.sort(fragments)
    return "{" .. table.concat(fragments, ", ") .. "}"
end

local function broadcastState(stateName, timeRemaining)
    roundStateUpdateRemote:FireAllClients({
        roundId = currentRound.roundId,
        state = stateName,
        chooserUserId = currentRound.chooserUserId,
        timeRemaining = timeRemaining,
    })
end

local function setState(stateName, timeRemaining)
    currentState = stateName
    currentRound:setState(stateName)
    print(string.format("State -> %s", stateName))
    broadcastState(stateName, timeRemaining)
end

local function getPlayerCount()
    return #Players:GetPlayers()
end

local function getEligibleGuessersCount()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player.UserId ~= currentRound.chooserUserId then
            count += 1
        end
    end
    return count
end

local function ensureScore(player)
    if scoresByUserId[player.UserId] == nil then
        scoresByUserId[player.UserId] = 0
    end
end

local function removeScore(player)
    scoresByUserId[player.UserId] = nil
end

Players.PlayerAdded:Connect(function(player)
    ensureScore(player)
end)

Players.PlayerRemoving:Connect(function(player)
    removeScore(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    ensureScore(player)
end

local function waitForMinimumPlayers()
    while getPlayerCount() < Config.MIN_PLAYERS do
        task.wait(1)
    end
end

local function chooseNextChooserUserId()
    local players = Players:GetPlayers()
    if #players == 0 then
        return nil
    end

    if lastChooserUserId then
        table.sort(players, function(a, b)
            return a.UserId < b.UserId
        end)

        for index, player in ipairs(players) do
            if player.UserId == lastChooserUserId then
                local nextIndex = index + 1
                if nextIndex > #players then
                    nextIndex = 1
                end
                return players[nextIndex].UserId
            end
        end
    end

    local chooser = players[math.random(1, #players)]
    return chooser.UserId
end

local function isValidChooserSelection(selection)
    if typeof(selection) ~= "table" then
        return false
    end
    if #selection ~= 2 then
        return false
    end

    local firstToken = selection[1]
    local secondToken = selection[2]
    if typeof(firstToken) ~= "string" or typeof(secondToken) ~= "string" then
        return false
    end
    if firstToken == secondToken then
        return false
    end
    if not tokenLookup[firstToken] or not tokenLookup[secondToken] then
        return false
    end

    return true
end

local function isDuplicateGuess(userId, tokenId)
    local guesses = currentRound.guessesByUserId[userId]
    if not guesses then
        return false
    end
    for _, existing in ipairs(guesses) do
        if existing == tokenId then
            return true
        end
    end
    return false
end

submitChooserSelectionRemote.OnServerEvent:Connect(function(player, chosenTokenIds)
    if currentState ~= RoundState.Chooser then
        warn(string.format("Ignored chooser selection from %s: not in Chooser state", player.Name))
        return
    end
    if player.UserId ~= currentRound.chooserUserId then
        warn(string.format("Ignored chooser selection from %s: not current chooser", player.Name))
        return
    end
    if not isValidChooserSelection(chosenTokenIds) then
        warn(string.format("Ignored chooser selection from %s: invalid selection payload", player.Name))
        return
    end

    currentRound:setChosenTokenIds(shallowCopyArray(chosenTokenIds))
    print(string.format("Chooser selection accepted roundId=%d chooserUserId=%d tokens=%s,%s", currentRound.roundId, player.UserId, chosenTokenIds[1], chosenTokenIds[2]))
end)

submitGuessRemote.OnServerEvent:Connect(function(player, tokenId)
    if currentState ~= RoundState.Guess then
        warn(string.format("Ignored guess from %s: not in Guess state", player.Name))
        return
    end
    if player.UserId == currentRound.chooserUserId then
        warn(string.format("Ignored guess from %s: chooser cannot guess", player.Name))
        return
    end
    if typeof(tokenId) ~= "string" or not tokenLookup[tokenId] then
        warn(string.format("Ignored guess from %s: invalid token", player.Name))
        return
    end

    local guesses = currentRound.guessesByUserId[player.UserId]
    local guessCount = guesses and #guesses or 0
    if guessCount >= Config.MAX_GUESSES then
        warn(string.format("Ignored guess from %s: max guesses reached", player.Name))
        return
    end
    if isDuplicateGuess(player.UserId, tokenId) then
        warn(string.format("Ignored guess from %s: duplicate guess", player.Name))
        return
    end

    currentRound:addGuess(player.UserId, tokenId)
end)

local function computeRevealResults()
    local matchesByUserId = {}
    local chosenLookup = {}
    for _, tokenId in ipairs(currentRound.chosenTokenIds) do
        chosenLookup[tokenId] = true
    end

    for userId, guesses in pairs(currentRound.guessesByUserId) do
        local matches = 0
        for _, guessTokenId in ipairs(guesses) do
            if chosenLookup[guessTokenId] then
                matches += 1
            end
        end
        if matches > 2 then
            matches = 2
        end
        matchesByUserId[userId] = matches
        if matches == 2 then
            scoresByUserId[userId] = (scoresByUserId[userId] or 0) + 3
        elseif matches == 1 then
            scoresByUserId[userId] = (scoresByUserId[userId] or 0) + 1
        end
    end

    local zeroMatchers = 0
    local chooserUserId = currentRound.chooserUserId
    if chooserUserId then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId ~= chooserUserId then
                local matches = matchesByUserId[player.UserId] or 0
                if matches == 0 then
                    zeroMatchers += 1
                end
            end
        end
        scoresByUserId[chooserUserId] = (scoresByUserId[chooserUserId] or 0) + (2 * zeroMatchers)
    end

    return matchesByUserId
end

local function revealRound()
    local matchesByUserId = computeRevealResults()
    local payload = {
        roundId = currentRound.roundId,
        chooserUserId = currentRound.chooserUserId,
        chosenTokenIds = shallowCopyArray(currentRound.chosenTokenIds),
        scoresByUserId = shallowCopyMap(scoresByUserId),
        matchesByUserId = matchesByUserId,
    }
    print(string.format(
        "RevealResults payload roundId=%d chooserUserId=%s chosenTokenIds=%s scoresByUserId=%s matchesByUserId=%s",
        payload.roundId,
        tostring(payload.chooserUserId),
        formatStringArray(payload.chosenTokenIds),
        formatNumberMap(payload.scoresByUserId),
        formatNumberMap(payload.matchesByUserId)
    ))
    revealResultsRemote:FireAllClients(payload)
end

local function runRoundLoop()
    while true do
        setState(RoundState.Lobby, nil)
        waitForMinimumPlayers()

        local nextChooserUserId = chooseNextChooserUserId()
        currentRound = RoundModel.new(currentRound.roundId + 1, RoundState.Lobby, nextChooserUserId, scoresByUserId)
        lastChooserUserId = nextChooserUserId
        print(string.format("Chooser selected roundId=%d chooserUserId=%s eligibleGuessers=%d", currentRound.roundId, tostring(nextChooserUserId), getEligibleGuessersCount()))

        setState(RoundState.Chooser, Config.CHOOSER_DURATION)
        task.wait(Config.CHOOSER_DURATION)

        setState(RoundState.Guess, Config.GUESS_DURATION)
        task.wait(Config.GUESS_DURATION)

        setState(RoundState.Reveal, nil)
        revealRound()
        task.wait(2)

        setState(RoundState.End, Config.INTERMISSION_DURATION)
        task.wait(Config.INTERMISSION_DURATION)
    end
end

task.spawn(runRoundLoop)
