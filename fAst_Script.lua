-- ================= [ ระบบ Heartbeat ตรวจจับผู้ใช้ ] =================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local SERVER_URL = "https://heartbeat-server-h5r4.onrender.com/api/heartbeat"
local INTERVAL = 30 -- ส่งสัญญาณทุก 30 วินาที

-- เช็คอุปกรณ์
local function getDevice()
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return "Mobile"
    elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
        return "Console"
    else
        return "PC"
    end
end

-- เช็คตัวรัน
local function getExecutor()
    local identify = identifyexecutor or getexecutorname
    if identify then
        return tostring(identify())
    end
    return "Unknown"
end

local sessionId = HttpService:GenerateGUID(false)
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

local function sendPing()
    if not httpRequest then return end

    local execName = getExecutor()
    local payload = {
        sessionId = sessionId,
        userId = player.UserId,
        username = player.Name,
        device = getDevice(),
        executor = execName,
        isDelta = (string.find(string.lower(execName), "delta") ~= nil)
    }

    pcall(function()
        httpRequest({
            Url = SERVER_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- ส่ง Ping ครั้งแรกทันที
task.spawn(sendPing)

-- วนลูปส่งต่อเนื่อง
task.spawn(function()
    while true do
        task.wait(INTERVAL)
        sendPing()
    end
end)
-- ==============================================================

-- [วางโค้ดหลักของคุณต่อจากตรงนี้ได้เลย]
return(function(X9SjE, ...)
local BxreFQ = {"22w";"VKHFA8Bd2lGH6g3MP";"Wl3eXtKfx8b";"Vi9L30rS";"fNY6yf";"HnI";"TyzIJ2";"mkUAhAsAW5QI3";"FzxNAJU";"vqutSADjRIJCHsE9";"Vh8q";"mBZz8Y9Ayb";"G8dakcr9Sf0j";"hgh0Ip546IYzj2"}
local ThygiHRq = function(...)
-- Advanced Lua example with multiple functions
local config = {
    debug = true,
    version = loadstring(base64decode("MS4wLjA="))(),
    author = loadstring(base64decode("THVhRGV2ZWxvcGVy"))()
}

function calculate(6mMrnpik, y)
    local sum = 6mMrnpik + y
    local product = 6mMrnpik * y
    local average = sum / 2
    
    if config.debug then
        print(loadstring(base64decode("Q2FsY3VsYXRpb24gZGVidWc6"))())
        print(loadstring(base64decode("U3VtOiA="))() .. sum)
        print(loadstring(base64decode("UHJvZHVjdDog"))() .. product)
        print(loadstring(base64decode("QXZlcmFnZTog"))() .. average)
    end
    
    return {sum = sum, product = product, average = average}
end

function processTable(t)
    local result = {}
    for key, value in pairs(t) do
        if type(value) == loadstring(base64decode("c3RyaW5n"))() then
            result[key] = string.upper(value)
        elseif type(value) == loadstring(base64decode("bnVtYmVy"))() then
            result[key] = value * 2
        else
            result[key] = value
        end
    end
    return result
end

-- Main execution
local data = {name = loadstring(base64decode("dGVzdA=="))(), count = 5, active = true}
local processed = processTable(data)

local calculations = calculate(10, 20)
print(loadstring(base64decode("RmluYWwgc3VtOiA="))() .. calculations.sum)
end
8nd5Leeo(T3SD5)
end)(...)
