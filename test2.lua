if not game:IsLoaded() then
    game.Loaded:Wait()
end

local lp = game:GetService("Players").LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local httpService = game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local players = game:GetService("Players")

local vehicles = require(replicatedStorage.Modules.Vehicles)
local getVehicleSpawnData = require(replicatedStorage.Remotes.Vehicles.GetVehicleSpawnData)
local liveryDenialReasons = require(replicatedStorage.Modules.LiveryDenialReasons)

local zlibC = game:HttpGet("https://gist.githubusercontent.com/qaxss/1db156969f3c5b9fef99ab0c2a631a23/raw/937ed62f816878d28cdb6ebe96bddc9250b74909/zlib.lua")
local LibDeflate = loadstring(zlibC)()

-- ============================================
-- CONFIGURATION
-- ============================================
local settings = {
    download = true,
    upload = false,
    robloxApiKey = nil,
    robloxId = nil,
    baseDownloadLocation = "asset_taker/",
    cookie = nil,
    cookieValid = false,
    sendToWebhook = false,
    webhookURL = nil,
    maxConcurrentDownloads = 75,        -- PARALLEL DOWNLOADS
    maxConcurrentWebhooks = 5,           -- PARALLEL WEBHOOKS
    batchWriteSize = 500,                -- DISK BATCH SIZE
    webhookQueueDelay = 0.05,            -- SECONDS
    webhookBatchSize = 10,               -- IMAGES PER WEBHOOK BATCH
    webhook = {
        sendServerInfo = true,
        sendDescription = true,
        sendRules = true,
        sendUniforms = true,
        sendLiveries = true,
        sendELS = true,
        sendMapTemplates = true,
        sendFullOutput = true,
    }
}

local categoryMap = {
    ["JobTrailers"] = "Job",
    ["Police"] = "Law",
    ["SheriffTrailers"] = "Law",
    ["DOT"] = "DOT",
    ["DOTTrailers"] = "DOT",
    ["FireTrailers"] = "Fire",
    ["Sheriff"] = "Law",
    ["Fire"] = "Fire",
    ["PoliceTrailers"] = "Law",
    ["Job"] = "Job"
}

local serverName, joinCode = nil, nil
local response, _ = pcall(function()
    serverName = replicatedStorage.PrivateServers.Info.ServerName.Value
    joinCode = replicatedStorage.PrivateServers.Info.Code.Value
end)

if not response then warn("Not in a private server") return end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local function sanitize(s)
    s = tostring(s):match("^%s*(.-)%s*$")
    s = s:gsub('[<>:"/\\|?*]', "_")
    return s
end

local safeServerName = sanitize(serverName)

local function notify(title, text, duration)
    duration = duration or 5
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration
        })
    end)
    print("[" .. title .. "] " .. text)
end

local function testCookie(cookie)
    local ok, response = pcall(function()
        return request({
            Url = "https://assetdelivery.roblox.com/v1/asset/?id=116800358210190",
            Method = "GET",
            Headers = { ["Cookie"] = cookie }
        })
    end)
    if not ok then return false end
    return tostring(response.StatusCode) == "200"
end

local function extractId(template)
    return template:match("%d+") or template
end

local function getColor(color)
    color = color:split(", ")
    local newColor = Color3.new(color[1], color[2], color[3])
    return newColor:ToHex()
end

local function decompressGzip(data)
    local byte1, byte2, byte3, byte4 = data:byte(1, 4)
    if byte1 == 0x89 and byte2 == 0x50 and byte3 == 0x4E and byte4 == 0x47 then
        return data
    end
    if data:byte(1) ~= 0x1F or data:byte(2) ~= 0x8B then
        return nil, "Not GZIP format"
    end
    local flags = data:byte(4)
    local pos = 11
    if bit32.band(flags, 0x04) ~= 0 then
        local xlen = data:byte(pos) + data:byte(pos + 1) * 256
        pos = pos + 2 + xlen
    end
    if bit32.band(flags, 0x08) ~= 0 then
        while data:byte(pos) ~= 0 do pos = pos + 1 end
        pos = pos + 1
    end
    if bit32.band(flags, 0x10) ~= 0 then
        while data:byte(pos) ~= 0 do pos = pos + 1 end
        pos = pos + 1
    end
    if bit32.band(flags, 0x02) ~= 0 then
        pos = pos + 2
    end
    local deflateData = data:sub(pos, #data - 8)
    local success, result = pcall(function()
        return LibDeflate.Deflate.Decompress(deflateData)
    end)
    if success and result then
        return result
    else
        return nil, "Decompression failed: " .. tostring(result)
    end
end

-- ============================================
-- PARALLEL DOWNLOAD SYSTEM (THE CORE UPGRADE)
-- ============================================
local activeDownloads = 0
local downloadQueue = {}
local downloadResults = {}
local downloadCallbacks = {}
local downloadIdCounter = 0

local function processDownloadQueue()
    while #downloadQueue > 0 and activeDownloads < settings.maxConcurrentDownloads do
        local task = table.remove(downloadQueue, 1)
        activeDownloads = activeDownloads + 1
        
        task.spawn(function()
            local ok, response = pcall(function()
                return request({
                    Url = "https://assetdelivery.roblox.com/v1/asset/?id=" .. task.imageId,
                    Method = "GET",
                    Headers = { ["Cookie"] = settings.cookie }
                })
            end)
            
            local result = {
                id = task.imageId,
                name = task.imageName,
                folder = task.folder,
                success = false,
                data = nil,
                error = nil
            }
            
            if ok then
                local data = response.Body
                local contentEncoding = response.Headers["Content-Encoding"] or response.Headers["content-encoding"]
                
                if contentEncoding == "gzip" then
                    local decompressed, err = decompressGzip(data)
                    if decompressed then
                        data = decompressed
                    else
                        result.error = "Decompression failed: " .. tostring(err)
                    end
                end
                
                local byte1, byte2, byte3, byte4 = data:byte(1, 4)
                if byte1 == 0x89 and byte2 == 0x50 and byte3 == 0x4E and byte4 == 0x47 then
                    result.success = true
                    result.data = data
                else
                    result.error = "Not a PNG (status " .. tostring(response.StatusCode) .. ")"
                end
            else
                result.error = "Request failed: " .. tostring(response)
            end
            
            downloadResults[task.callbackId] = result
            
            activeDownloads = activeDownloads - 1
            processDownloadQueue()
        end)
    end
end

local function downloadImageAsync(imageId, folder, imageName, callback)
    downloadIdCounter = downloadIdCounter + 1
    local callbackId = downloadIdCounter
    
    downloadCallbacks[callbackId] = callback
    
    table.insert(downloadQueue, {
        imageId = imageId,
        imageName = imageName,
        folder = folder,
        callbackId = callbackId
    })
    
    processDownloadQueue()
end

local function flushDownloadResults()
    local results = {}
    for id, result in pairs(downloadResults) do
        results[id] = result
        if downloadCallbacks[id] then
            downloadCallbacks[id](result)
            downloadCallbacks[id] = nil
        end
        downloadResults[id] = nil
    end
    return results
end

-- ============================================
-- PARALLEL WEBHOOK SYSTEM
-- ============================================
local webhookQueue = {}
local activeWebhooks = 0

local function sendWebhookAsync(webhookURL, data, isMultipart, boundary)
    while activeWebhooks >= settings.maxConcurrentWebhooks do
        task.wait(0.01)
    end
    activeWebhooks = activeWebhooks + 1
    
    task.spawn(function()
        local headers = {}
        if isMultipart then
            headers["Content-Type"] = "multipart/form-data; boundary=" .. boundary
        else
            headers["Content-Type"] = "application/json"
        end
        
        local ok, response = pcall(function()
            return request({
                Url = webhookURL,
                Method = "POST",
                Headers = headers,
                Body = data
            })
        end)
        
        activeWebhooks = activeWebhooks - 1
        
        if ok and (response.StatusCode == 429) then
            task.wait(5)
            pcall(function()
                request({
                    Url = webhookURL,
                    Method = "POST",
                    Headers = headers,
                    Body = data
                })
            end)
        end
    end)
end

local function queueWebhookMessage(webhookURL, embed, images)
    table.insert(webhookQueue, { url = webhookURL, embed = embed, images = images or {} })
end

task.spawn(function()
    while true do
        if #webhookQueue > 0 and activeWebhooks < settings.maxConcurrentWebhooks then
            local item = table.remove(webhookQueue, 1)
            
            -- Send embed
            local embedData = httpService:JSONEncode({ embeds = { item.embed } })
            sendWebhookAsync(item.url, embedData, false, nil)
            
            task.wait(0.1)
            
            -- Send images in parallel batches
            if #item.images > 0 then
                for i = 1, #item.images, settings.webhookBatchSize do
                    local boundary = "----WebKitFormBoundary" .. httpService:GenerateGUID(false)
                    local body = ""
                    local endIndex = math.min(i + settings.webhookBatchSize - 1, #item.images)
                    
                    for j = i, endIndex do
                        local img = item.images[j]
                        body = body .. "--" .. boundary .. "\r\n"
                        body = body .. 'Content-Disposition: form-data; name="file' .. (j - i + 1) .. '"; filename="' .. img.name .. '"\r\n'
                        body = body .. "Content-Type: image/png\r\n\r\n"
                        body = body .. img.data .. "\r\n"
                    end
                    body = body .. "--" .. boundary .. "--\r\n"
                    
                    sendWebhookAsync(item.url, body, true, boundary)
                    
                    if endIndex < #item.images then
                        task.wait(0.05)
                    end
                end
            end
        end
        task.wait(settings.webhookQueueDelay)
    end
end)

-- ============================================
-- MEMORY BUFFER SYSTEM (BULK DISK WRITES)
-- ============================================
local pendingWrites = {}
local pendingWriteCount = 0

local function queueWriteFile(path, content, isBinary)
    table.insert(pendingWrites, { path = path, content = content, binary = isBinary or false })
    pendingWriteCount = pendingWriteCount + 1
    
    if pendingWriteCount >= settings.batchWriteSize then
        flushWrites()
    end
end

local function flushWrites()
    if pendingWriteCount == 0 then return end
    
    local writes = pendingWrites
    pendingWrites = {}
    pendingWriteCount = 0
    
    task.spawn(function()
        for _, write in writes do
            local ok, err = pcall(function()
                writefile(write.path, write.content)
            end)
            if not ok then
                notify("Write Failed", "Could not write " .. write.path .. ": " .. tostring(err))
            end
        end
    end)
end

-- ============================================
-- STRING BUILDER SYSTEM
-- ============================================
local StringBuffer = {}
StringBuffer.__index = StringBuffer

function StringBuffer.new()
    return setmetatable({ lines = {} }, StringBuffer)
end

function StringBuffer:append(text)
    table.insert(self.lines, text)
end

function StringBuffer:appendLine(text)
    table.insert(self.lines, text .. "\n")
end

function StringBuffer:toString()
    return table.concat(self.lines)
end

-- ============================================
-- CORE FUNCTIONS (OPTIMIZED)
-- ============================================
local function getServerData()
    notify("Phase 1", "Fetching server data...")
    local ok, result = pcall(function()
        return replicatedStorage:WaitForChild("PrivateServers"):WaitForChild("GetSettings"):InvokeServer()
    end)
    if not ok then error("getServerData failed: " .. tostring(result)) end
    local serverSettings = result
    return {
        name = serverSettings.Data.Name,
        code = serverSettings.Data.CurrKey,
        icon = serverSettings.Data.IconId,
        rules = serverSettings.Data.Rules,
        description = serverSettings.Data.Description,
        teams = serverSettings.Data.CustomTeams,
        original = serverSettings
    }
end

local function outputServerInfo()
    local data = getServerData()
    local buffer = StringBuffer.new()
    
    buffer:appendLine("========================================")
    buffer:appendLine("SERVER INFORMATION")
    buffer:appendLine("========================================")
    buffer:appendLine(string.format("Name: %s", tostring(data.name)))
    buffer:appendLine(string.format("Join code: %s", tostring(data.code)))
    buffer:appendLine(string.format("Icon: %s", tostring(data.icon)))
    buffer:appendLine("Teams:")
    
    for team, info in data.teams do
        buffer:appendLine(string.format("  Team: %s", tostring(team)))
        buffer:appendLine(string.format("    Name: %s", tostring(info.Name)))
        buffer:appendLine(string.format("    Logo: %s", tostring(info.Logo)))
    end
    
    buffer:appendLine(string.format("Rules:\n%s", tostring(data.rules)))
    buffer:appendLine(string.format("Description:\n%s", tostring(data.description)))
    
    local mainEmbed = {
        title = data.name,
        description = "",
        fields = {
            { name = "Server name", value = tostring(data.name), inline = true },
            { name = "Server join code", value = tostring(data.code), inline = true },
            { name = "Server icon", value = "`" .. tostring(data.icon) .. "`", inline = true }
        }
    }
    
    for team, info in data.teams do
        mainEmbed.description = mainEmbed.description .. string.format("**Team:** %s\n  **Name:** `%s`\n  **Logo id:** `%s`\n", 
            tostring(team), tostring(info.Name), tostring(info.Logo))
    end
    
    local descEmbed = { title = data.name, description = "```" .. data.description .. "```" }
    local rulesEmbed = { title = data.name, description = "```" .. data.rules .. "```" }
    
    local images = {}
    
    if settings.download then
        makefolder(settings.baseDownloadLocation .. safeServerName)
        
        local logoPath = settings.baseDownloadLocation .. safeServerName .. "/logo.png"
        downloadImageAsync(data.icon, settings.baseDownloadLocation .. safeServerName, "logo", function(result)
            if result.success then
                queueWriteFile(logoPath, result.data, true)
                table.insert(images, { name = "logo.png", data = result.data })
            end
        end)
        
        for team, info in data.teams do
            local safeTeam = sanitize(team)
            local safeName = sanitize(info.Name)
            local teamFolder = settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam
            makefolder(teamFolder)
            
            local logoPath = teamFolder .. "/" .. safeName .. ".png"
            downloadImageAsync(info.Logo, teamFolder, safeName, function(result)
                if result.success then
                    queueWriteFile(logoPath, result.data, true)
                    table.insert(images, { name = safeName .. ".png", data = result.data })
                end
            end)
        end
    end
    
    flushDownloadResults()
    
    if settings.sendToWebhook and settings.webhookURL then
        if settings.webhook.sendServerInfo then
            queueWebhookMessage(settings.webhookURL, mainEmbed, {})
        end
        if settings.webhook.sendDescription then
            queueWebhookMessage(settings.webhookURL, descEmbed, {})
        end
        if settings.webhook.sendRules then
            queueWebhookMessage(settings.webhookURL, rulesEmbed, images)
        end
    end
    
    return buffer:toString(), data.original
end

-- ============================================
-- PARALLEL UNIFORM COLLECTION
-- ============================================
local function getUniforms()
    notify("Phase 2", "Starting uniform collection (PARALLEL MODE)...")
    local buffer = StringBuffer.new()
    local uniformTable = {}
    local downloadTasks = {}
    
    buffer:appendLine("\n========================================")
    buffer:appendLine("UNIFORMS")
    buffer:appendLine("========================================")
    
    for _, team in replicatedStorage.ReplicatedState.Uniforms:GetChildren() do
        local safeTeam = sanitize(team.Name)
        uniformTable[team.Name] = {}
        
        buffer:appendLine(string.rep("=", 30))
        buffer:appendLine(team.Name)
        buffer:appendLine(string.rep("=", 30))
        
        if settings.download then
            makefolder(settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam .. "/uniforms")
        end
        
        for _, uniform in team:GetChildren() do
            if uniform:FindFirstChild("CustomUniform") then
                local shirtId = extractId(tostring(uniform.Shirt.ShirtTemplate))
                local pantsId = extractId(tostring(uniform.Pants.PantsTemplate))
                local uniformName = uniform.Name
                
                uniformTable[team.Name][uniformName] = { shirt = shirtId, pants = pantsId }
                
                buffer:appendLine(string.format("  Name: %s", tostring(uniformName)))
                buffer:appendLine(string.format("    Shirt: %s", shirtId))
                buffer:appendLine(string.format("    Pants: %s", pantsId))
                
                if settings.download then
                    local safeName = sanitize(uniformName)
                    local uniformFolder = settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam .. "/uniforms/" .. safeName
                    makefolder(uniformFolder)
                    
                    local shirtPath = uniformFolder .. "/Shirt.png"
                    local pantsPath = uniformFolder .. "/Pants.png"
                    local images = {}
                    
                    downloadImageAsync(shirtId, uniformFolder, "Shirt", function(result)
                        if result.success then
                            queueWriteFile(shirtPath, result.data, true)
                            table.insert(images, { name = "shirt.png", data = result.data })
                        end
                    end)
                    
                    downloadImageAsync(pantsId, uniformFolder, "Pants", function(result)
                        if result.success then
                            queueWriteFile(pantsPath, result.data, true)
                            table.insert(images, { name = "pants.png", data = result.data })
                        end
                    end)
                    
                    local embed = {
                        title = serverName,
                        fields = {
                            { name = "Team", value = tostring(team.Name), inline = true },
                            { name = "Name", value = tostring(uniformName), inline = true },
                            { name = "Shirt", value = "`" .. shirtId .. "`", inline = true },
                            { name = "Pants", value = "`" .. pantsId .. "`", inline = true }
                        }
                    }
                    
                    if settings.sendToWebhook and settings.webhookURL and settings.webhook.sendUniforms then
                        queueWebhookMessage(settings.webhookURL, embed, images)
                    end
                end
            end
        end
    end
    
    flushDownloadResults()
    
    return buffer:toString(), uniformTable
end

-- ============================================
-- JOB AND CAR SETUP
-- ============================================
local function getClosestCivilianSpawner()
    local closest, dist = nil, math.huge
    local playerLoc = char.WorldPivot.Position
    for _, item in workspace:WaitForChild("VehicleSpawners"):GetChildren() do
        if item.Name == "Civilian_Spawners" and #item:GetChildren() > 0 then
            for _, spawner in item:GetChildren() do
                if #spawner:GetChildren() > 0 then
                    local a = playerLoc - spawner.WorldPivot.Position
                    if a.Magnitude < dist then
                        closest = spawner
                        dist = a.Magnitude
                    end
                end
            end
        end
    end
    return closest
end

local function getCar()
    local closest = getClosestCivilianSpawner()
    if not closest then return false end
    
    local interaction = closest:WaitForChild("SpawnClicker", 2):WaitForChild("InteractionAttachment", 2)
    if not interaction then return false end
    
    local spawnCar = { "Falcon Traveller 2003", nil, false, interaction }
    local buyCar = { "Falcon Traveller 2003", Color3.new(0.05098039656877518, 0.4117647409439087, 0.6745098233222961) }
    
    char.HumanoidRootPart.Position = closest.WorldPivot.Position
    task.wait(0.2)
    replicatedStorage:WaitForChild("FE"):WaitForChild("BuyCar"):InvokeServer(unpack(buyCar))
    task.wait(0.2)
    replicatedStorage:WaitForChild("FE"):WaitForChild("SpawnCar"):FireServer(unpack(spawnCar))
    
    return true
end

local function findPlayerCar()
    for _, car in workspace.Vehicles:GetChildren() do
        if car:GetAttribute("Owner") == lp.Name then
            return car
        end
    end
end

local function getJob()
    local newsJoin = { "Start", workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker") }
    
    local wantedLevel = replicatedStorage:WaitForChild("FE"):WaitForChild("GetWantedLevel"):InvokeServer(lp)
    if wantedLevel ~= 0 then
        notify("Job Failed", "Player is wanted!")
        return false
    end
    
    if lp.Team ~= game.Teams.Civilian then
        notify("Job Failed", "Wrong team!")
        return false
    end
    
    if not getCar() then
        notify("Job Failed", "Failed to get car")
        return false
    end
    
    task.wait(0.2)
    local car = findPlayerCar()
    if not car then return false end
    
    car:MoveTo(workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker"):WaitForChild("Main").Position)
    task.wait(1)
    
    local result = replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer(unpack(newsJoin))
    return result == "Success"
end

-- ============================================
-- PARALLEL LIVERY COLLECTION (MASSIVE SPEUP)
-- ============================================
local function formatLiveryDataParallel(car, liveryData, category)
    local carId = tonumber(car)
    local carInfo = vehicles.GetCarById(categoryMap[category], carId)
    local buffer = StringBuffer.new()
    local downloadTasks = {}
    local liveryEntries = {}
    
    buffer:appendLine(string.format("%-22s %s", "Car:", carInfo.Name))
    buffer:appendLine(string.format("%-22s %s", "Livery Count:", #liveryData))
    
    for _, livery in liveryData do
        local liveryEntry = {
            name = sanitize(tostring(livery.liveryName)),
            vehicleColor = getColor(livery.vehicleColor),
            liveryColor = getColor(livery.liveryColor),
            liveryTransparency = tostring(livery.liveryTransparency),
            approved = livery.isApproved == true and "Approved" or liveryDenialReasons[livery.isApproved],
            textures = {}
        }
        
        for side, id in livery.textureIds do
            liveryEntry.textures[side] = tostring(id)
        end
        
        table.insert(liveryEntries, liveryEntry)
        
        buffer:appendLine(string.format("  Name: %s", liveryEntry.name))
        buffer:appendLine(string.format("  Vehicle Color: %s", liveryEntry.vehicleColor))
        buffer:appendLine(string.format("  Livery Color: %s", liveryEntry.liveryColor))
        buffer:appendLine(string.format("  Livery Transparency: %s", liveryEntry.liveryTransparency))
        buffer:appendLine(string.format("  Approval Status: %s", liveryEntry.approved))
        buffer:appendLine("  Texture Ids:")
        
        for side, id in pairs(liveryEntry.textures) do
            buffer:appendLine(string.format("    %-12s %s", side .. ":", id))
        end
        
        if settings.download then
            local safeCar = sanitize(carInfo.Name)
            local safeCategory = sanitize(category)
            local safeLiveryName = sanitize(liveryEntry.name)
            local downloadLocation
            
            if #liveryData == 1 then
                downloadLocation = settings.baseDownloadLocation .. safeServerName .. "/" .. safeCategory .. "/liveries/" .. safeCar
            else
                downloadLocation = settings.baseDownloadLocation .. safeServerName .. "/" .. safeCategory .. "/liveries/" .. safeCar .. "/" .. safeLiveryName
            end
            
            makefolder(downloadLocation)
            
            local liveryText = string.format("Name: %s\nVehicle Color: %s\nLivery Color: %s\nLivery Transparency: %s\nApproval Status: %s\nTexture Ids:\n",
                liveryEntry.name, liveryEntry.vehicleColor, liveryEntry.liveryColor, liveryEntry.liveryTransparency, liveryEntry.approved)
            
            for side, id in pairs(liveryEntry.textures) do
                liveryText = liveryText .. string.format("  %s: %s\n", side, id)
            end
            
            queueWriteFile(downloadLocation .. "/" .. safeLiveryName .. ".txt", liveryText, false)
            
            local images = {}
            for side, id in pairs(liveryEntry.textures) do
                local imgPath = downloadLocation .. "/" .. side .. ".png"
                downloadImageAsync(id, downloadLocation, side, function(result)
                    if result.success then
                        queueWriteFile(imgPath, result.data, true)
                        table.insert(images, { name = side .. ".png", data = result.data })
                    end
                end)
            end
            
            local embed = {
                title = carInfo.Name,
                description = "",
                fields = {
                    { name = "Team", value = categoryMap[category], inline = true },
                    { name = "Name", value = "`" .. liveryEntry.name .. "`", inline = true },
                    { name = "Vehicle Color", value = "`" .. liveryEntry.vehicleColor .. "`", inline = true },
                    { name = "Livery Color", value = "`" .. liveryEntry.liveryColor .. "`", inline = true },
                    { name = "Livery Transparency", value = "`" .. liveryEntry.liveryTransparency .. "`", inline = true },
                    { name = "Approval Status", value = liveryEntry.approved, inline = true },
                    { name = "Server", value = serverName, inline = true },
                    { name = "Join code", value = joinCode, inline = true }
                }
            }
            
            for side, id in pairs(liveryEntry.textures) do
                embed.description = embed.description .. side .. ": `" .. id .. "`\n"
            end
            
            if settings.sendToWebhook and settings.webhookURL and settings.webhook.sendLiveries then
                queueWebhookMessage(settings.webhookURL, embed, images)
            end
        end
        
        buffer:appendLine("  " .. string.rep("-", 15))
    end
    
    return buffer:toString(), { car = carInfo.Name, liveries = liveryEntries }
end

local function getLiveries()
    if not getJob() then
        notify("Phase 3 Failed", "Could not start job")
        return "", {}
    end
    
    notify("Phase 3", "Fetching livery data (PARALLEL MODE)...")
    
    local interaction = workspace:WaitForChild("VehicleSpawners"):WaitForChild("NewsStationWorker_Spawners"):WaitForChild("Stand"):WaitForChild("SpawnClicker"):WaitForChild("InteractionAttachment")
    
    local ok, success, data = pcall(function()
        return getVehicleSpawnData:Call("News Station Worker", interaction):Await()
    end)
    
    if not ok or not success or not data.liveries then
        notify("Phase 3 Failed", "No liveries found")
        return "", {}
    end
    
    local buffer = StringBuffer.new()
    buffer:appendLine("\n========================================")
    buffer:appendLine("LIVERIES")
    buffer:appendLine("========================================")
    
    local liveryTable = {}
    
    for category, cars in pairs(data.liveries) do
        local count = 0
        for _, carData in pairs(cars) do
            if #carData > 0 then count = count + 1 end
        end
        
        if count > 0 then
            buffer:appendLine(string.rep("=", 30))
            buffer:appendLine(tostring(category))
            buffer:appendLine(string.rep("=", 30))
            
            liveryTable[category] = {}
            
            for carId, carData in pairs(cars) do
                if #carData > 0 then
                    local liveryString, liveryInfo = formatLiveryDataParallel(carId, carData, category)
                    buffer:append(liveryString)
                    table.insert(liveryTable[category], liveryInfo)
                end
            end
        end
    end
    
    pcall(function()
        replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer("Quit")
    end)
    
    flushDownloadResults()
    
    return buffer:toString(), liveryTable
end

-- ============================================
-- ELS AND MAP COLLECTION
-- ============================================
local function getELS()
    notify("Phase 4", "Fetching ELS data...")
    local ok, data = pcall(function()
        return replicatedStorage.FE.GetCustomELS:InvokeServer()
    end)
    if not ok then error("getELS failed: " .. tostring(data)) end
    
    if settings.sendToWebhook and settings.webhookURL and settings.webhook.sendELS then
        local elsJson = httpService:JSONEncode(data)
        queueWriteFile(settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. "_ELS.json", elsJson, false)
    end
    
    return data
end

local function getMapTemplates()
    notify("Phase 5", "Fetching map templates...")
    local mapLayouts = {}
    
    for _, template in workspace.MapLayouts:GetChildren() do
        local layoutName = template:GetAttribute("LayoutName")
        mapLayouts[layoutName] = {}
        for _, prop in template.Props:GetChildren() do
            table.insert(mapLayouts[layoutName], {
                name = prop:GetAttribute("PropName"),
                position = tostring(prop.WorldPivot)
            })
        end
    end
    
    if settings.sendToWebhook and settings.webhookURL and settings.webhook.sendMapTemplates then
        local mapJson = httpService:JSONEncode(mapLayouts)
        queueWriteFile(settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. "_MapTemplates.json", mapJson, false)
    end
    
    return mapLayouts
end

-- ============================================
-- MAIN EXECUTION
-- ============================================
local function takeAssets()
    notify("Starting", "Validating cookie...")
    if testCookie(settings.cookie) then
        settings.cookieValid = true
        notify("Starting", "Cookie valid! Starting parallel extraction...")
    else
        notify("Failed", "Invalid cookie - stopping!")
        return
    end
    
    local outputBuffer = StringBuffer.new()
    local outputTable = {}
    
    makefolder(settings.baseDownloadLocation .. safeServerName)
    
    -- Phase 1: Server Info
    local serverInfo, serverSettings = outputServerInfo()
    outputBuffer:append(serverInfo)
    outputTable.settings = serverSettings
    
    -- Phase 2: Uniforms
    local uniforms, uniformTable = getUniforms()
    outputBuffer:append(uniforms)
    outputTable.uniforms = uniformTable
    
    -- Phase 3: Liveries
    local liveries, liveryTable = getLiveries()
    outputBuffer:append(liveries)
    outputTable.liveries = liveryTable
    
    -- Phase 4: ELS
    outputTable.ELS = getELS()
    
    -- Phase 5: Map Templates
    outputTable.Map = getMapTemplates()
    
    -- Final flush and save
    notify("Saving", "Flushing all data to disk...")
    flushWrites()
    flushDownloadResults()
    
    local finalJson = httpService:JSONEncode(outputTable)
    local finalTxt = outputBuffer:toString()
    
    queueWriteFile(settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. ".json", finalJson, false)
    queueWriteFile(settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. ".txt", finalTxt, false)
    
    if settings.sendToWebhook and settings.webhookURL and settings.webhook.sendFullOutput then
        queueWriteFile(settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. "_full.txt", finalTxt, false)
    end
    
    flushWrites()
    
    notify("Done!", "All assets collected successfully in PARALLEL MODE!", 10)
    print("EXTRACTION COMPLETE")
end

-- ============================================
-- EXPORT
-- ============================================
return function(config)
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
    print("Configuration loaded - PARALLEL MODE ENABLED")
    print("Max Concurrent Downloads:", settings.maxConcurrentDownloads)
    print("Max Concurrent Webhooks:", settings.maxConcurrentWebhooks)
    print("Batch Write Size:", settings.batchWriteSize)
    takeAssets()
end
