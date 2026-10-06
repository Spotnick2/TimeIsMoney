-- Investment engine (main.js): deposits and withdrawals, stock purchases with
-- generated symbols, price updates, sales, the risk selector, engine upgrades and
-- the lifetime report. Extends Sim/Workshop.lua; source names and order preserved.
local _, ns = ...
ns = ns or {}

local JSMath, Workshop = ns.JSMath, ns.Workshop
local Game = Workshop.Game
local floor, ceil = math.floor, math.ceil
local pow = JSMath.pow
local MATH_E = JSMath.fromWords(0x4005BF0A, 0x8B145769) -- Math.E

local initial = {
    stockID = 0, investLevel = 0, investUpgradeCost = 100, stockGainThreshold = .5, ledger = 0,
}
for key, value in pairs(initial) do Workshop.initial[key] = value end
Workshop.arrays.alphabet = true
for _, id in ipairs({ "btnInvest", "btnWithdraw", "btnImproveInvestments" }) do
    Workshop.buttons[#Workshop.buttons + 1] = id
end
Workshop.setups[#Workshop.setups + 1] = function(_, S)
    S.alphabet = {}
    for i = 1, 26 do S.alphabet[i] = string.char(64 + i) end
end

-- Math.pow(base, Math.E) matches V8 for every base up to 967
-- (tests/reference/jsmath.test.cjs); beyond it JSMath.pow is a declared difference
-- (#24, docs/reference/WORKSHOP.md).

function Game:investUpgrade()
    local S = self.S
    -- The new cost uses base (investLevel + 1) after the level increment.
    S.yomi = S.yomi - S.investUpgradeCost
    S.investLevel = S.investLevel + 1
    S.stockGainThreshold = S.stockGainThreshold + .01
    S.investUpgradeCost = floor(pow(S.investLevel + 1, MATH_E) * 100)
    self:displayMessage("Investment engine upgraded, expected profit/loss ratio now " ..
        JSMath.toString(S.stockGainThreshold))
end

function Game:investDeposit()
    local S = self.S
    S.ledger = S.ledger - floor(S.funds)
    S.bankroll = floor(S.bankroll + S.funds)
    S.funds = 0
end

function Game:investWithdraw()
    local S = self.S
    S.ledger = S.ledger + S.bankroll
    S.funds = S.funds + S.bankroll
    S.bankroll = 0
end

function Game:generateSymbol()
    local S = self.S
    local ltrNum
    local x = self.draw("main.js:1558:18")
    if x <= .01 then
        ltrNum = 1
    elseif x <= .1 then
        ltrNum = 2
    elseif x <= .4 then
        ltrNum = 3
    else
        ltrNum = 4
    end
    local y = floor(self.draw("main.js:1569:29") * 26)
    local name = S.alphabet[y + 1]
    for _ = 1, ltrNum - 1 do
        local z = floor(self.draw("main.js:1573:33") * 26)
        name = name .. S.alphabet[z + 1]
    end
    return name
end

function Game:createStock(dollars)
    local S = self.S
    S.stockID = S.stockID + 1
    local sym = self:generateSymbol()
    local roll = self.draw("main.js:1502:21")
    local pri
    if roll > .99 then
        pri = ceil(self.draw("main.js:1504:32") * 3000)
    elseif roll > .85 then
        pri = ceil(self.draw("main.js:1506:32") * 500)
    elseif roll > .60 then
        pri = ceil(self.draw("main.js:1508:32") * 150)
    elseif roll > .20 then
        pri = ceil(self.draw("main.js:1510:32") * 50)
    else
        pri = ceil(self.draw("main.js:1512:32") * 15)
    end
    if pri > dollars then pri = ceil(dollars * roll) end
    local amt = floor(JSMath.div(dollars, pri))
    if amt > 1000000 then amt = 1000000 end
    S.stocks[#S.stocks + 1] = {
        id = S.stockID, symbol = sym, price = pri, amount = amt, total = pri * amt, profit = 0, age = 0,
    }
    S.portfolioSize = #S.stocks
    S.bankroll = S.bankroll - (pri * amt)
end

function Game:sellStock()
    local S = self.S
    S.bankroll = S.bankroll + S.stocks[1].total
    table.remove(S.stocks, 1)
    S.portfolioSize = #S.stocks
end

function Game:updateStocks()
    local S = self.S
    for i = 1, S.portfolioSize do
        local stock = S.stocks[i]
        stock.age = stock.age + 1
        if self.draw("main.js:1585:16") < .6 then
            local gain = true
            if self.draw("main.js:1587:18") > S.stockGainThreshold then gain = false end
            local currentPrice = stock.price
            local delta = ceil((self.draw("main.js:1592:37") * currentPrice) / (4 * S.riskiness))
            if gain then stock.price = stock.price + delta else stock.price = stock.price - delta end
            if stock.price == 0 and self.draw("main.js:1600:42") > .24 then stock.price = 1 end
            stock.total = stock.price * stock.amount
            if gain then
                stock.profit = stock.profit + (delta * stock.amount)
            else
                stock.profit = stock.profit - (delta * stock.amount)
            end
        end
    end
end

-- The 10 ms loop's lifetime report.
function Game:stockReport()
    local S = self.S
    S.stockReportCounter = S.stockReportCounter + 1
    if S.stockReportCounter >= 10000 then
        self:displayMessage("Lifetime investment revenue report: $" .. Workshop.formatWithCommas(S.ledger + S.portTotal))
        S.stockReportCounter = 0
    end
end

local clicks = Workshop.clicks
clicks.btnInvest = Game.investDeposit
clicks.btnWithdraw = Game.investWithdraw
clicks.btnImproveInvestments = Game.investUpgrade

return Workshop
