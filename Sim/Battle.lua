-- Always-running battle core from combat.js. The reference starts this animation
-- at load and steps it every 16 ms; its ship motion and death rolls consume the
-- shared simulation random stream, so the port keeps it even without a battle.
-- Drawing calls are omitted; framesDead still advances as in MoveShips.
-- Battles, honor and battle names (createBattle, checkForBattleEnd with an
-- active battle) belong to issue #15 and stop with an unported error.
local _, ns = ...
ns = ns or {}

local floor = math.floor
local Battle = {}

local WIDTH, HEIGHT = 310, 150
local GRID_WIDTH, GRID_HEIGHT = 31, 15
local INV_GRID_WIDTH = 1 / (WIDTH / GRID_WIDTH)
local INV_GRID_HEIGHT = 1 / (HEIGHT / GRID_HEIGHT)
local MAXSPEED = 2

Battle.initial = {
    battleWIDTH = WIDTH, battleHEIGHT = HEIGHT, battleLEFTSHIPS = 200, battleRIGHTSHIPS = 200,
    battleMAXSPEED = MAXSPEED, battleDEATH_THRESHOLD = 0.5,
    numShips = 0, numLeftShips = 0, numRightShips = 0,
    probeCombat = 0, probeCombatBaseRate = .15, attackSpeedFlag = 0, probeSpeed = 0,
    drifterCombat = 1.75, unitSize = 0, probeCount = 0, probesLostCombat = 0,
    drifterCount = 0, driftersKilled = 0, battleNameFlag = 0,
    -- The implicit global i: combat.js load runs for (i=0; i<battleNames.length; i++).
    i = 105,
}

-- new Ship(team): draw order and arithmetic follow combat.js lines 704-727.
local function newShip(S, team, draw)
    local ship = { alive = true, team = team, framesDead = 0, gx = 0, gy = 0 }
    if team == 0 then
        ship.x = (draw("combat.js:717:22") * 0.2) * S.battleWIDTH
        ship.y = draw("combat.js:718:21") * S.battleHEIGHT
        ship.vx = draw("combat.js:719:22") * S.battleMAXSPEED
        ship.vy = draw("combat.js:720:22") - 0.5
        ship.color = "#ffffff"
    else
        ship.x = (draw("combat.js:724:22") * 0.2 + 0.8) * S.battleWIDTH
        ship.y = draw("combat.js:725:21") * S.battleHEIGHT
        ship.vx = -1 * draw("combat.js:726:26") * S.battleMAXSPEED
        ship.vy = draw("combat.js:727:21") - 0.5
        ship.color = "#000000"
    end
    return ship
end

local function newGrid()
    local grid = {}
    for row = 0, GRID_HEIGHT - 1 do
        grid[row] = {}
        for col = 0, GRID_WIDTH - 1 do grid[row][col] = { ships = {}, numShips = 0 } end
    end
    return grid
end

-- battleRestart: alternate teams, starting with the right team.
function Battle.restart(S, draw)
    S.numLeftShips, S.numRightShips, S.numShips = 0, 0, 0
    S.ships = {}
    S.grid = newGrid()
    local leftShipTurn = false
    local i = 0
    while S.numLeftShips < S.battleLEFTSHIPS or S.numRightShips < S.battleRIGHTSHIPS do
        if leftShipTurn then
            S.ships[i + 1] = newShip(S, 0, draw)
            S.numLeftShips = S.numLeftShips + 1
            S.numShips = S.numShips + 1
            if S.numRightShips < S.battleRIGHTSHIPS then leftShipTurn = false end
        else
            S.ships[i + 1] = newShip(S, 1, draw)
            S.numRightShips = S.numRightShips + 1
            S.numShips = S.numShips + 1
            if S.numLeftShips < S.battleLEFTSHIPS then leftShipTurn = true end
        end
        i = i + 1
    end
end

local function updateGrid(S)
    local grid = S.grid
    for row = 0, GRID_HEIGHT - 1 do
        for col = 0, GRID_WIDTH - 1 do
            grid[row][col].ships = {}
            grid[row][col].numShips = 0
        end
    end
    for i = 1, S.numShips do
        local p = S.ships[i]
        if p.alive then
            p.gx = floor(p.x * INV_GRID_WIDTH)
            p.gy = floor(p.y * INV_GRID_HEIGHT)
            if p.gx < 0 then p.gx = 0 end
            if p.gy < 0 then p.gy = 0 end
            if p.gx > GRID_WIDTH - 1 then p.gx = GRID_WIDTH - 1 end
            if p.gy > GRID_HEIGHT - 1 then p.gy = GRID_HEIGHT - 1 end
            local cell = grid[p.gy][p.gx]
            cell.numShips = cell.numShips + 1
            cell.ships[cell.numShips] = p
        end
    end
    S.i = S.numShips -- UpdateGrid loops with the global i
end

local function findCentroid(S)
    local x, y, alive = 0, 0, 0
    for i = 1, S.numShips do
        local p = S.ships[i]
        if p.alive then
            x = x + p.x
            y = y + p.y
            alive = alive + 1
        end
    end
    x = ns.JSMath.div(x, alive)
    y = ns.JSMath.div(y, alive)
    x = (x * 0.8) + (S.battleWIDTH / 2 * 0.2)
    y = (y * 0.8) + (S.battleHEIGHT / 2 * 0.2)
    return x, y
end

local function moveSingleShip(S, p, cx, cy)
    p.vx = p.vx + (cx - p.x) * 0.001
    p.vy = p.vy + (cy - p.y) * 0.001
    local grid = S.grid
    local teammatesConsidered = 0
    for row = math.max(p.gy - 1, 0), math.min(p.gy + 2, GRID_HEIGHT) - 1 do
        for col = math.max(p.gx - 1, 0), math.min(p.gx + 2, GRID_WIDTH) - 1 do
            local ships = grid[row][col].ships
            if #ships >= 2 then
                for i = 1, #ships do
                    local other = ships[i]
                    if other.alive then
                        if other.team == p.team then
                            teammatesConsidered = teammatesConsidered + 1
                            if teammatesConsidered <= 3 then
                                p.vx = p.vx + other.vx * 0.01
                                p.vy = p.vy + other.vy * 0.01
                                p.vx = p.vx - (other.x - p.x) * .1
                                p.vy = p.vy - (other.y - p.y) * .1
                            end
                        else
                            p.vx = p.vx + other.vx * 0.2
                            p.vy = p.vy + other.vy * 0.2
                            p.vx = p.vx + (other.x - p.x) * 0.2
                            p.vy = p.vy + (other.y - p.y) * 0.2
                        end
                    end
                end
            end
        end
    end
    local max = S.battleMAXSPEED
    if math.abs(p.vx) > max then p.vx = p.vx < 0 and -max or max end
    if math.abs(p.vy) > max then p.vy = p.vy < 0 and -max or max end
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    if p.x > S.battleWIDTH then
        p.x = S.battleWIDTH
        p.vx = -max
    elseif p.x < 0 then
        p.x = 0
        p.vx = max
    end
    if p.y > S.battleHEIGHT then
        p.y = S.battleHEIGHT
        p.vy = -max
    elseif p.y < 0 then
        p.y = 0
        p.vy = max
    end
end

local function moveShips(S)
    local cx, cy = findCentroid(S)
    for i = 1, S.numShips do
        local p = S.ships[i]
        if not p.alive then
            if p.framesDead < 10 then p.framesDead = p.framesDead + 1 end
        else
            moveSingleShip(S, p, cx, cy)
        end
    end
end

local function checkForBattleEnd(S)
    if #S.battles > 0 then ns.Unported("checkForBattleEnd with an active battle", "#15") end
end

local function doCombat(S, draw)
    local pX = S.probeCombat * S.probeCombatBaseRate
    local dX = S.drifterCombat
    local ooda = 0
    if S.attackSpeedFlag == 1 then ooda = S.probeSpeed * .2 end
    local grid = S.grid
    for row = 0, GRID_HEIGHT - 1 do
        for col = 0, GRID_WIDTH - 1 do
            local cell = grid[row][col]
            if cell.numShips >= 2 then
                local left, right = 0, 0
                for i = 1, cell.numShips do
                    local p = cell.ships[i]
                    if p.alive then
                        if p.team == 0 then left = left + 1 else right = right + 1 end
                    end
                end
                if left ~= 0 and right ~= 0 then
                    for i = 1, cell.numShips do
                        local p = cell.ships[i]
                        local diceRoll
                        if p.team == 0 then
                            diceRoll = draw("combat.js:510:31") * dX * ((right / left) * .5)
                            S.battleDEATH_THRESHOLD = S.battleDEATH_THRESHOLD + ooda
                        else
                            diceRoll = ((draw("combat.js:515:33") * pX) + (S.probeCombat * .1)) * ((left / right) * .5)
                        end
                        if diceRoll > S.battleDEATH_THRESHOLD then
                            p.alive = false
                            if p.team == 0 then
                                S.numLeftShips = S.numLeftShips - 1
                                if S.unitSize > S.probeCount then S.unitSize = S.probeCount end
                                S.probeCount = S.probeCount - S.unitSize
                                S.probesLostCombat = S.probesLostCombat + S.unitSize
                            else
                                S.numRightShips = S.numRightShips - 1
                                if S.unitSize > S.drifterCount then S.unitSize = S.drifterCount end
                                S.drifterCount = S.drifterCount - S.unitSize
                                S.driftersKilled = S.driftersKilled + S.unitSize
                            end
                        end
                        S.battleDEATH_THRESHOLD = .5
                    end
                end
            end
        end
    end
    checkForBattleEnd(S)
end

-- The 16 ms Update callback: UpdateGrid, MoveShips, DoCombat.
function Battle.update(S, draw)
    updateGrid(S)
    moveShips(S)
    doCombat(S, draw)
end

ns.Battle = Battle
return Battle
