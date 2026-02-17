local RoundModel = {}
RoundModel.__index = RoundModel

function RoundModel.new(roundId, state, chooserUserId, scoresByUserId)
    local self = setmetatable({}, RoundModel)
    self.roundId = roundId
    self.state = state
    self.chooserUserId = chooserUserId
    self.chosenTokenIds = {}
    self.guessesByUserId = {}
    self.scoresByUserId = scoresByUserId or {}
    return self
end

function RoundModel:setState(state)
    self.state = state
end

function RoundModel:setChooserUserId(userId)
    self.chooserUserId = userId
end

function RoundModel:setChosenTokenIds(tokenIds)
    self.chosenTokenIds = tokenIds
end

function RoundModel:addGuess(userId, tokenId)
    local guesses = self.guessesByUserId[userId]
    if not guesses then
        guesses = {}
        self.guessesByUserId[userId] = guesses
    end
    table.insert(guesses, tokenId)
end

return RoundModel
