-- Game state machine with enter/exit callbacks

local stateMachine = {}

local currentState = nil
local states = {}

function stateMachine.register(name, state)
    states[name] = state
end

function stateMachine.switch(name, params)
    -- Call exit on current state
    if currentState and currentState.exit then
        currentState.exit()
    end

    -- Switch to new state
    currentState = states[name]

    -- Call enter on new state
    if currentState and currentState.enter then
        currentState.enter(params)
    end
end

function stateMachine.update(dt)
    if currentState and currentState.update then
        currentState.update(dt)
    end
end

function stateMachine.draw()
    if currentState and currentState.draw then
        currentState.draw()
    end
end

function stateMachine.keypressed(key)
    if currentState and currentState.keypressed then
        currentState.keypressed(key)
    end
end

function stateMachine.keyreleased(key)
    if currentState and currentState.keyreleased then
        currentState.keyreleased(key)
    end
end

function stateMachine.touchpressed(id, x, y)
    if currentState and currentState.touchpressed then
        currentState.touchpressed(id, x, y)
    end
end

function stateMachine.touchmoved(id, x, y)
    if currentState and currentState.touchmoved then
        currentState.touchmoved(id, x, y)
    end
end

function stateMachine.touchreleased(id, x, y)
    if currentState and currentState.touchreleased then
        currentState.touchreleased(id, x, y)
    end
end

function stateMachine.getCurrent()
    return currentState
end

return stateMachine
