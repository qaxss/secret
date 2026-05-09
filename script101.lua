if not game:IsLoaded() then
    game.Loaded:Wait()
end

local lp = game:GetService("Players").LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()

local httpService = game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local vehicles = require(replicatedStorage.Modules.Vehicles)
local getVehicleSpawnData = require(replicatedStorage.Remotes.Vehicles.GetVehicleSpawnData)
local liveryDenialReasons = require(replicatedStorage.Modules.LiveryDenialReasons)

local zlibC = game:HttpGet("https://gist.githubusercontent.com/qaxss/612b10e367f3b6e5277fd57d890fab5c/raw/ca39100d27c6c7ba6964a2c7b6b49eb1fd60eeaf/gistfile1.txt")
local LibDeflate = loadstring(zlibC)()

local settings = {
    download = true,
    upload = false,
    robloxApiKey = nil,
    robloxId = nil,
    baseDownloadLocation = "asset taker/",
    cookie = nil,
    cookieValid = false,
    sendToWebhook = false,
    webhookURL = nil,
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

if not response then warn("Gay you arent in a private server") ; return end

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
    if not ok then
        notify("Cookie", "Request failed during cookie test")
        return false
    end
    if tostring(response.StatusCode) ~= "200" then
        return false
    end
    return true
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

local function getImage(imageId, folder, imageName)
    if not settings.cookieValid then
        notify("Image Failed", "No valid cookie for: " .. tostring(imageName))
        return false, "No valid cookie"
    end

    local ok, response = pcall(function()
        return request({
            Url = "https://assetdelivery.roblox.com/v1/asset/?id=" .. imageId,
            Method = "GET",
            Headers = { ["Cookie"] = settings.cookie }
        })
    end)

    if not ok then
        notify("Image Failed", "Request crashed for: " .. tostring(imageName))
        return false, "Request failed"
    end

    local data = response.Body
    local contentEncoding = response.Headers["Content-Encoding"] or response.Headers["content-encoding"]

    if contentEncoding == "gzip" then
        local decompressed, err = decompressGzip(data)
        if decompressed then
            data = decompressed
        else
            notify("Image Failed", "Decompression failed: " .. tostring(imageName) .. " - " .. tostring(err))
            return false, response, err
        end
    end

    local byte1, byte2, byte3, byte4 = data:byte(1, 4)
    if byte1 == 0x89 and byte2 == 0x50 and byte3 == 0x4E and byte4 == 0x47 then
        writefile(folder .. "/" .. imageName .. ".png", data)
        return true, data
    else
        writefile(folder .. "/" .. imageName .. ".txt", response.StatusCode .. "\n" .. response.Body)
        notify("Image Failed", "Not a PNG - saved as txt: " .. tostring(imageName) .. " (status " .. tostring(response.StatusCode) .. ")")
        return false, response
    end
end

local function webhookEnabled(option)
    return settings.sendToWebhook
        and settings.webhookURL
        and string.find(settings.webhookURL, "discord.com/api/webhooks/")
        and settings.webhook[option]
end

local function sendFileToDiscord(filename, content, webhook)
    notify("Webhook", "Sending file: " .. filename)
    local boundary = "----WebKitFormBoundary" .. httpService:GenerateGUID(false)
    local body = "--" .. boundary .. "\r\n"
        .. 'Content-Disposition: form-data; name="file"; filename="' .. filename .. '"\r\n'
        .. "Content-Type: text/plain\r\n\r\n"
        .. content .. "\r\n"
        .. "--" .. boundary .. "--\r\n"

    local success, response = pcall(function()
        return request({
            Url = webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
            Body = body
        })
    end)

    if not success then
        notify("Webhook Failed", "pcall crashed sending file: " .. filename)
        return
    end

    if response.StatusCode == 429 then
        notify("Webhook", "Rate limited, retrying: " .. filename)
        task.wait(5)
        local ok2, res2 = pcall(function()
            return request({
                Url = webhook,
                Method = "POST",
                Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                Body = body
            })
        end)
        if not ok2 or (res2.StatusCode ~= 200 and res2.StatusCode ~= 204) then
            notify("Webhook Failed", "Retry failed for: " .. filename .. " status: " .. tostring(ok2 and res2.StatusCode or "crash"))
        else
            notify("Webhook", "File sent after retry: " .. filename)
        end
    elseif response.StatusCode == 200 or response.StatusCode == 204 then
        notify("Webhook", "File sent: " .. filename)
    else
        notify("Webhook Failed", "Status " .. tostring(response.StatusCode) .. " for: " .. filename)
    end
end

local debounce = false
local function sendToDiscord(embed, images, webhook)
    repeat task.wait() until not debounce
    debounce = true

    local ok, err = pcall(function()
        local success, response = pcall(function()
            return request({
                Url = webhook,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = httpService:JSONEncode({ embeds = { embed } })
            })
        end)

        if not success then
            notify("Webhook Failed", "Embed request crashed: " .. tostring(embed.title))
            return
        end

        if response.StatusCode == 429 then
            notify("Webhook", "Rate limited on embed, retrying...")
            task.wait(5)
            pcall(function()
                request({
                    Url = webhook,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = httpService:JSONEncode({ embeds = { embed } })
                })
            end)
        elseif response.StatusCode ~= 200 and response.StatusCode ~= 204 then
            notify("Webhook Failed", "Embed status " .. tostring(response.StatusCode) .. " for: " .. tostring(embed.title))
        end

        task.wait()

        if #images > 0 then
            notify("Webhook", "Sending " .. #images .. " image(s) for: " .. tostring(embed.title))
            for i = 1, #images, 10 do
                local boundary = "----WebKitFormBoundary" .. httpService:GenerateGUID(false)
                local body = ""
                local endIndex = math.min(i + 9, #images)

                for j = i, endIndex do
                    local imageData = images[j].data
                    local fileName = images[j].name
                    body = body .. "--" .. boundary .. "\r\n"
                    body = body .. 'Content-Disposition: form-data; name="file' .. (j - i + 1) .. '"; filename="' .. fileName .. '"\r\n'
                    body = body .. "Content-Type: image/png\r\n\r\n"
                    body = body .. imageData .. "\r\n"
                end
                body = body .. "--" .. boundary .. "--\r\n"

                local imgOk, imgResponse = pcall(function()
                    return request({
                        Url = webhook,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                        Body = body
                    })
                end)

                if not imgOk then
                    notify("Webhook Failed", "Image batch " .. i .. " crashed")
                elseif imgResponse.StatusCode == 429 then
                    notify("Webhook", "Rate limited on images, retrying batch " .. i)
                    task.wait(5)
                    pcall(function()
                        request({
                            Url = webhook,
                            Method = "POST",
                            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                            Body = body
                        })
                    end)
                elseif imgResponse.StatusCode ~= 200 and imgResponse.StatusCode ~= 204 then
                    notify("Webhook Failed", "Image batch " .. i .. " status: " .. tostring(imgResponse.StatusCode))
                end

                if endIndex < #images then
                    task.wait(0.2)
                end
            end
        end
    end)

    if not ok then
        notify("Webhook Failed", "sendToDiscord crashed: " .. tostring(err))
    end

    debounce = false
end

local function getServerData()
    notify("Phase 1", "Fetching server data...")
    local ok, result = pcall(function()
        return replicatedStorage:WaitForChild("PrivateServers"):WaitForChild("GetSettings"):InvokeServer()
    end)
    if not ok then
        error("getServerData failed: " .. tostring(result))
    end
    local serverSettings = result
    notify("Phase 1", "Server data fetched OK")
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

local function makeLiveryTable(car, liveryData, carId)
    local liveryTable = {
        ["car"] = car.Name,
        ["carId"] = carId,
        ["liveryCount"] = #liveryData,
        ["liveries"] = {}
    }
    for _, livery in liveryData do
        local outLivery = {
            name = sanitize(tostring(livery.liveryName)),
            vehicleColor = tostring(getColor(livery.vehicleColor)),
            liveryColor = tostring(getColor(livery.liveryColor)),
            liveryTransparency = tostring(livery.liveryTransparency),
            ELS = {
                park = livery.ParkPatterns,
                stg1 = livery.Stage1Patterns,
                stg2 = livery.Stage2Patterns,
                stg3 = livery.Stage3Patterns,
                color = livery.ELSColor
            },
            approved = livery.isApproved == true and "Approved" or liveryDenialReasons[livery.isApproved],
            textures = {}
        }
        for side, id in livery.textureIds do
            outLivery.textures[side] = tostring(id)
        end
        table.insert(liveryTable.liveries, outLivery)
    end
    return liveryTable
end

local function makeLiveryEmbed(car, uniqueLivery, category)
    local embed = {
        title = car.Name,
        description = "",
        fields = {
            { name = "Team", value = categoryMap[category], inline = true },
            { name = "Name", value = "`" .. uniqueLivery.name .. "`", inline = true },
            { name = "Vehicle Color", value = "`" .. uniqueLivery.vehicleColor .. "`", inline = true },
            { name = "Livery Color", value = "`" .. uniqueLivery.liveryColor .. "`", inline = true },
            { name = "Livery Transparency", value = "`" .. uniqueLivery.liveryTransparency .. "`", inline = true },
            { name = "Approval Status", value = uniqueLivery.approved, inline = true },
            { name = "Server", value = serverName, inline = true },
            { name = "Join code", value = joinCode, inline = true }
        }
    }
    for side, id in uniqueLivery.textures do
        embed.description = embed.description .. side .. ": `" .. id .. "`\n"
    end
    return embed
end

local function getLiveryImages(textureIds, downloadLocation)
    local textureAmount = 0
    local passCount = 0
    for _, _ in textureIds do textureAmount += 1 end

    local images = {}
    for side, id in textureIds do
        task.spawn(function()
            local ok, response = getImage(id, downloadLocation, side)
            if ok then
                table.insert(images, { name = side .. ".png", data = response })
            else
                notify("Image Failed", "Texture failed: " .. tostring(side) .. " id: " .. tostring(id))
            end
            passCount += 1
        end)
        task.wait()
    end

    repeat task.wait() until passCount == textureAmount
    return images
end

local function formatLiveryData(car, liveryData, category)
    local livery = ""
    local carId = tonumber(car)
    local car = vehicles.GetCarById(categoryMap[category], tonumber(car))
    local liveryTable = makeLiveryTable(car, liveryData, carId)

    notify("Liveries", "Processing: " .. tostring(liveryTable.car) .. " (" .. liveryTable.liveryCount .. " liveries)")

    livery = livery
        .. string.format("%-22s %s\n", "Car:", liveryTable.car)
        .. string.format("%-22s %s\n", " Livery Count:", liveryTable.liveryCount)

    for key, uniqueLivery in liveryTable.liveries do
        local unique = ""
            .. string.format("%-22s %s\n", "  Name:", uniqueLivery.name)
            .. string.format("%-22s %s\n", "  Vehicle Color:", uniqueLivery.vehicleColor or "Unknown")
            .. string.format("%-22s %s\n", "  Livery Color:", uniqueLivery.liveryColor or "Unknown")
            .. string.format("%-22s %s\n", "  Livery Transparency:", uniqueLivery.liveryTransparency or "Unknown")
            .. string.format("%-22s %s\n", "  Approval Status:", uniqueLivery.approved or "Unknown")
        livery = livery .. unique
        livery = livery .. "  Texture Ids:\n"
        for side, id in uniqueLivery.textures do
            livery = livery .. string.format("    %-12s %s\n", side .. ":", id)
        end

        if settings.download then
            local downloadLocation
            local safeCar = sanitize(liveryTable.car)
            local safeCategory = sanitize(category)
            local safeLiveryName = sanitize(uniqueLivery.name)

            if liveryTable.liveryCount == 1 then
                downloadLocation = settings.baseDownloadLocation .. safeServerName .. "/" .. safeCategory .. "/liveries/" .. safeCar
            else
                downloadLocation = settings.baseDownloadLocation .. safeServerName .. "/" .. safeCategory .. "/liveries/" .. safeCar .. "/" .. safeLiveryName
            end

            local mkOk, mkErr = pcall(function()
                makefolder(downloadLocation)
                writefile(downloadLocation .. "/" .. safeLiveryName .. ".txt", unique)
            end)
            if not mkOk then
                notify("Liveries Failed", "Failed to save livery file: " .. tostring(mkErr))
            else
                notify("Liveries", "Saved: " .. uniqueLivery.name .. " (" .. safeCar .. ")")
            end

            local images = getLiveryImages(uniqueLivery.textures, downloadLocation)
            notify("Liveries", "Got " .. #images .. " texture(s) for: " .. uniqueLivery.name)
            local embed = makeLiveryEmbed(car, uniqueLivery, category)

            if webhookEnabled("sendLiveries") then
                notify("Webhook", "Sending livery embed: " .. uniqueLivery.name)
                sendToDiscord(embed, images, settings.webhookURL)
            end
        end

        if key > 0 and key ~= liveryTable.liveryCount then
            livery = livery .. "  " .. string.rep("-", 15) .. "\n"
        end
    end
    return livery .. "\n", liveryTable
end

local function outputLiveries(liveryTable)
    local liveryTables = {}
    local liveries = [[
  _     _                _           
 | |   (_)_   _____ _ __(_) ___  ___ 
 | |   | \ \ / / _ \ '__| |/ _ \/ __|
 | |___| |\ V /  __/ |  | |  __/\__ \
 |_____|_| \_/ \___|_|  |_|\___||___/

]]
    local liveryCopy = table.clone(liveryTable)
    for team, val in liveryCopy do
        local count = 0
        if type(val) == "table" then
            for _, _ in val do count += 1 end
        end
        if count > 0 then
            notify("Liveries", "Team: " .. tostring(team) .. " (" .. count .. " cars)")
            if settings.download then
                makefolder(settings.baseDownloadLocation .. safeServerName .. "/" .. sanitize(team))
            end
            liveries = liveries
                .. string.rep("=", 30) .. "\n"
                .. tostring(team) .. "\n"
                .. string.rep("=", 30) .. "\n"
            liveryTables[team] = {}
            if type(val) == "table" then
                for car, carData in val do
                    if #carData > 0 then
                        local ok, liveryString, liveryTable = pcall(function()
                            return formatLiveryData(car, carData, team)
                        end)
                        if not ok then
                            notify("Liveries Failed", "formatLiveryData crashed for car: " .. tostring(car) .. " - " .. tostring(liveryString))
                        else
                            liveries = liveries .. liveryString
                            table.insert(liveryTables[team], liveryTable)
                        end
                    end
                end
            end
        end
    end

    notify("Liveries", "Quitting job...")
    pcall(function()
        replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer("Quit")
        task.wait()
        replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer("Quit")
    end)
    notify("Liveries", "Done processing all liveries!")
    return liveries, liveryTables
end

local function getClosestCivilianSpawner()
    local closest, dist = nil, math.huge
    local playerLoc = game.Players.LocalPlayer.Character.WorldPivot.Position
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
    notify("Setup", "Getting civilian car...")
    local ok, err = pcall(function()
        local closest = getClosestCivilianSpawner()
        if not closest then
            error("No civilian spawner found")
        end
        local interaction = closest:WaitForChild("SpawnClicker", 2):WaitForChild("InteractionAttachment", 2)
        if not interaction then
            error("No interaction found on spawner")
        end

        local spawnCar = { "Falcon Traveller 2003", nil, false, interaction }
        local buyCar = {
            "Falcon Traveller 2003",
            Color3.new(0.05098039656877518, 0.4117647409439087, 0.6745098233222961)
        }

        char.HumanoidRootPart.Position = closest.WorldPivot.Position
        task.wait(0.2)
        replicatedStorage:WaitForChild("FE"):WaitForChild("BuyCar"):InvokeServer(unpack(buyCar))
        task.wait(0.2)
        replicatedStorage:WaitForChild("FE"):WaitForChild("SpawnCar"):FireServer(unpack(spawnCar))
    end)

    if not ok then
        notify("Setup Failed", "getCar crashed: " .. tostring(err))
        return false
    end

    notify("Setup", "Car spawned successfully")
    return true
end

local starter = nil
local function isPlayerInOwnCar()
    local seat = char.Humanoid.SeatPart
    if not seat then
        if os.time() - starter > 10 then
            notify("Setup", "Not in car after 10s, retrying...")
            getCar()
            starter = os.time()
        end
        return false
    else
        if seat.Parent:GetAttribute("Owner") == lp.Name then
            return true
        end
    end
    return false
end

local function findPlayerCar()
    for _, car in workspace.Vehicles:GetChildren() do
        if car:GetAttribute("Owner") == lp.Name then
            return car
        end
    end
end

local function getJob()
    notify("Phase 3", "Joining News Station Worker job...")
    local newsJoin = {
        "Start",
        workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker")
    }

    local wantedOk, wantedLevel = pcall(function()
        return game:GetService("ReplicatedStorage"):WaitForChild("FE"):WaitForChild("GetWantedLevel"):InvokeServer(game.Players.LocalPlayer)
    end)
    if not wantedOk then
        notify("Job Failed", "GetWantedLevel crashed: " .. tostring(wantedLevel))
        return
    end
    if wantedLevel ~= 0 then
        notify("Job Failed", "Player is wanted! Clear wanted level first.")
        return
    end

    if game:GetService("Players").LocalPlayer.Team ~= game.Teams.Civilian then
        notify("Job Failed", "Wrong team - must be Civilian!")
        return
    end

    if not getCar() then
        notify("Job Failed", "Failed to get a car")
    end

    task.wait(0.2)
    notify("Setup", "Waiting to get in car...")
    starter = os.time()
    repeat task.wait() until isPlayerInOwnCar()
    notify("Setup", "In car! Moving to job location...")

    local car = findPlayerCar()
    if not car then
        notify("Job Failed", "Could not find player car after spawning")
        return
    end

    local moveOk, moveErr = pcall(function()
        car:MoveTo(workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker"):WaitForChild("Main").Position)
    end)
    if not moveOk then
        notify("Job Failed", "Car MoveTo crashed: " .. tostring(moveErr))
        return
    end

    task.wait(1)

    local joinOk, joinTeam = pcall(function()
        return game:GetService("ReplicatedStorage"):WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer(unpack(newsJoin))
    end)
    if not joinOk then
        notify("Job Failed", "StartJob crashed: " .. tostring(joinTeam))
        return
    end

    if joinTeam ~= "Success" then
        notify("Job Failed", "StartJob returned: " .. tostring(joinTeam))
    else
        notify("Phase 3", "Job joined successfully!")
    end
end

local function getLiveries()
    getJob()
    notify("Phase 3", "Fetching livery data from server...")

    local ok, success, data = pcall(function()
        return getVehicleSpawnData:Call(
            "News Station Worker",
            workspace:WaitForChild("VehicleSpawners"):WaitForChild("NewsStationWorker_Spawners"):WaitForChild("Stand"):WaitForChild("SpawnClicker"):WaitForChild("InteractionAttachment")
        ):Await()
    end)

    if not ok then
        notify("Phase 3 Failed", "getVehicleSpawnData crashed: " .. tostring(success))
        return "", {}
    end

    if success then
        if data.liveries then
            notify("Phase 3", "Livery data received, processing...")
            return outputLiveries(data.liveries)
        else
            notify("Phase 3", "No liveries found on this server")
            return "", {}
        end
    else
        notify("Phase 3 Failed", "Failed to get livery data: " .. tostring(data))
        return "", {}
    end
end

local function outputServerInfo()
    local data = getServerData()
    notify("Phase 1", "Got server data: " .. tostring(data.name))

    local server = [[
  ____                             _        __       
 / ___|  ___ _ ____   _____ _ __  (_)_ __  / _| ___  
 \___ \ / _ \ '__\ \ / / _ \ '__| | | '_ \| |_ / _ \ 
  ___) |  __/ |   \ V /  __/ |    | | | | |  _| (_) |
 |____/ \___|_|    \_/ \___|_|    |_|_| |_|_|  \___/ 

]]
    server = server
        .. string.format("%-10s %s\n", "Name:", tostring(data.name))
        .. string.format("%-10s %s\n", "Join code:", tostring(data.code))
        .. string.format("%-10s %s\n", "Icon:", tostring(data.icon))
        .. "Teams:\n"
    for team, info in data.teams do
        server = server
            .. string.format("%-10s %s\n", " Team:", tostring(team))
            .. string.format("%-10s %s\n", "   Name:", tostring(info.Name))
            .. string.format("%-10s %s\n", "   Logo:", tostring(info.Logo))
    end
    server = server
        .. string.format("%-10s %s", "Rules:\n", tostring(data.rules))
        .. string.format("%-10s %s", "Description:\n", tostring(data.description))

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
        mainEmbed.description = mainEmbed.description
            .. string.format("%-10s %s\n", "**Team:**", tostring(team))
            .. string.format("%-10s %s\n", "  **Name:**", "`" .. tostring(info.Name) .. "`")
            .. string.format("%-10s %s\n", "  **Logo id:**", "`" .. tostring(info.Logo) .. "`")
    end

    local descEmbed = { title = data.name, description = "```" .. data.description .. "```" }
    local rulesEmbed = { title = data.name, description = "```" .. data.rules .. "```" }

    local images = {}
    if settings.download then
        makefolder(settings.baseDownloadLocation .. safeServerName)
        notify("Phase 1", "Downloading server logo...")

        local ok, img = getImage(data.icon, settings.baseDownloadLocation .. safeServerName, "logo")
        if ok then
            table.insert(images, { name = "logo.png", data = img })
            notify("Phase 1", "Server logo saved")
        else
            notify("Phase 1", "Failed to save server logo")
        end

        for team, info in data.teams do
            local safeTeam = sanitize(team)
            local safeName = sanitize(info.Name)
            local teamFolder = settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam
            makefolder(teamFolder)
            notify("Phase 1", "Downloading logo for team: " .. tostring(team))
            local ok2, img2 = getImage(info.Logo, teamFolder, safeName)
            if ok2 then
                table.insert(images, { name = safeName .. ".png", data = img2 })
                notify("Phase 1", "Team logo saved: " .. tostring(team))
            else
                notify("Phase 1", "Failed to save logo for: " .. tostring(team))
            end
        end
    end

    if webhookEnabled("sendServerInfo") then
        notify("Webhook", "Sending server info embed...")
        sendToDiscord(mainEmbed, {}, settings.webhookURL)
    end
    if webhookEnabled("sendDescription") then
        notify("Webhook", "Sending description embed...")
        sendToDiscord(descEmbed, {}, settings.webhookURL)
    end
    if webhookEnabled("sendRules") then
        notify("Webhook", "Sending rules embed...")
        sendToDiscord(rulesEmbed, images, settings.webhookURL)
    end

    notify("Phase 1", "Server info complete!")
    return server .. "\n\n", data.original
end

local function getUniforms()
    notify("Phase 2", "Starting uniform collection...")
    local uniformTable = {}
    local uniforms = [[
  _   _       _  __                          
 | | | |_ __ (_)/ _| ___  _ __ _ __ ___  ___ 
 | | | | '_ \| | |_ / _ \| '__| '_ ` _ \/ __|
 | |_| | | | | |  _| (_) | |  | | | | | \__ \
  \___/|_| |_|_|_|  \___/|_|  |_| |_| |_|___/
                                             
]]

    for _, team in replicatedStorage.ReplicatedState.Uniforms:GetChildren() do
        local safeTeam = sanitize(team.Name)
        notify("Phase 2", "Processing team: " .. team.Name)
        if settings.download then
            makefolder(settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam .. "/uniforms")
        end
        uniformTable[team.Name] = {}
        uniforms = uniforms
            .. string.rep("=", 30) .. "\n"
            .. team.Name .. "\n"
            .. string.rep("=", 30) .. "\n"
        local uniformCount = 0
        for _, uniform in team:GetChildren() do
            if uniform:FindFirstChild("CustomUniform") then
                uniformCount += 1
                local shirtId = extractId(tostring(uniform.Shirt.ShirtTemplate))
                local pantsId = extractId(tostring(uniform.Pants.PantsTemplate))
                uniformTable[team.Name][uniform.Name] = { shirt = shirtId, pants = pantsId }

                uniforms = uniforms
                    .. string.format("%-10s %s\n", "  Name:", tostring(uniform.Name))
                    .. string.format("%-10s %s\n", "    Shirt:", shirtId)
                    .. string.format("%-10s %s\n", "    Pants:", pantsId)

                notify("Phase 2", uniform.Name .. " | Shirt: " .. shirtId .. " | Pants: " .. pantsId)

                task.spawn(function()
                    local images = {}
                    if settings.download then
                        local safeName = sanitize(uniform.Name)
                        local uniformFolder = settings.baseDownloadLocation .. safeServerName .. "/" .. safeTeam .. "/uniforms/" .. safeName
                        local mkOk, mkErr = pcall(function() makefolder(uniformFolder) end)
                        if not mkOk then
                            notify("Phase 2 Failed", "makefolder crashed for uniform: " .. tostring(mkErr))
                            return
                        end

                        local a, img = getImage(shirtId, uniformFolder, "Shirt")
                        if a then
                            table.insert(images, { name = "shirt.png", data = img })
                            notify("Phase 2", "Shirt saved: " .. uniform.Name)
                        else
                            notify("Phase 2", "Shirt failed: " .. uniform.Name)
                        end

                        local b, img2 = getImage(pantsId, uniformFolder, "Pants")
                        if b then
                            table.insert(images, { name = "pants.png", data = img2 })
                            notify("Phase 2", "Pants saved: " .. uniform.Name)
                        else
                            notify("Phase 2", "Pants failed: " .. uniform.Name)
                        end
                    end

                    local embed = {
                        title = serverName,
                        fields = {
                            { name = "Team", value = tostring(team.Name), inline = true },
                            { name = "Name", value = tostring(uniform.Name), inline = true },
                            { name = "Shirt", value = "`" .. shirtId .. "`", inline = true },
                            { name = "Pants", value = "`" .. pantsId .. "`", inline = true }
                        }
                    }

                    if webhookEnabled("sendUniforms") then
                        notify("Webhook", "Sending uniform embed: " .. uniform.Name)
                        sendToDiscord(embed, images, settings.webhookURL)
                    end
                end)
            end
        end
        notify("Phase 2", "Team " .. team.Name .. " done: " .. uniformCount .. " uniforms")
    end

    notify("Phase 2", "All uniforms collected!")
    return uniforms, uniformTable
end

local function getELS()
    notify("Phase 4", "Fetching ELS data...")
    local ok, data = pcall(function()
        return replicatedStorage.FE.GetCustomELS:InvokeServer()
    end)
    if not ok then
        error("getELS failed: " .. tostring(data))
    end
    notify("Phase 4", "ELS data received!")
    return data
end

local function getMapTemplates()
    notify("Phase 5", "Fetching map templates...")
    local mapLayouts = {}
    local ok, err = pcall(function()
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
    end)
    if not ok then
        error("getMapTemplates failed: " .. tostring(err))
    end
    local count = 0
    for _ in mapLayouts do count += 1 end
    notify("Phase 5", "Map templates done: " .. count .. " layouts")
    return mapLayouts
end

local function takeAssets()
    notify("Starting", "Validating cookie...")
    if testCookie(settings.cookie) then
        settings.cookieValid = true
        notify("Starting", "Cookie valid! Starting...")
    else
        notify("Failed", "Invalid cookie - stopping!")
        return
    end

    local outputString = ""
    local outputTable = {}

    local mkOk, mkErr = pcall(function()
        makefolder(settings.baseDownloadLocation .. safeServerName)
    end)
    if not mkOk then
        notify("Failed", "Could not create base folder: " .. tostring(mkErr))
        return
    end

    -- Phase 1: Server Info
    if settings.webhook.sendServerInfo then
        local serverInfoOutput, serverSettings
        notify("Phase 1", "Collecting server info...")
        local ok1, err1 = pcall(function()
            serverInfoOutput, serverSettings = outputServerInfo()
        end)
        if not ok1 then
            notify("Phase 1 Failed", tostring(err1))
        else
            outputString = outputString .. serverInfoOutput
            outputTable.settings = table.clone(serverSettings)
        end
    end

    -- Phase 2: Uniforms
    if settings.webhook.sendUniforms then
        local uniformsOutput, uniformTable
        notify("Phase 2", "Collecting uniforms...")
        local ok2, err2 = pcall(function()
            uniformsOutput, uniformTable = getUniforms()
        end)
        if not ok2 then
            notify("Phase 2 Failed", tostring(err2))
        else
            outputString = outputString .. uniformsOutput
            outputTable.uniforms = table.clone(uniformTable)
        end
    end

    -- Phase 3: Liveries
    if settings.webhook.sendLiveries then
        local liveriesOutput, liveryTable
        notify("Phase 3", "Collecting liveries...")
        local ok3, err3 = pcall(function()
            liveriesOutput, liveryTable = getLiveries()
        end)
        if not ok3 then
            notify("Phase 3 Failed", tostring(err3))
        else
            outputString = outputString .. liveriesOutput
            outputTable.liveries = table.clone(liveryTable)
        end
    end

    -- Phase 4: ELS
    if settings.webhook.sendELS then
        local ELSTable
        notify("Phase 4", "Collecting ELS...")
        local ok4, err4 = pcall(function()
            ELSTable = getELS()
        end)
        if not ok4 then
            notify("Phase 4 Failed", tostring(err4))
        else
            outputTable.ELS = table.clone(ELSTable)
        end
    end

    -- Phase 5: Map Templates
    if settings.webhook.sendMapTemplates then
        notify("Phase 5", "Collecting map templates...")
        local ok5, err5 = pcall(function()
            outputTable.Map = getMapTemplates()
        end)
        if not ok5 then
            notify("Phase 5 Failed", tostring(err5))
        end
    end

    -- Save files
    notify("Saving", "Writing JSON and TXT files...")
    local saveOk, saveErr = pcall(function()
        writefile(
            settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. ".json",
            httpService:JSONEncode(outputTable)
        )
        writefile(
            settings.baseDownloadLocation .. safeServerName .. "/" .. safeServerName .. ".txt",
            outputString
        )
    end)
    if not saveOk then
        notify("Save Failed", "writefile crashed: " .. tostring(saveErr))
        return
    end
    notify("Saving", "Files written successfully!")

    -- Send files to Discord
    if settings.webhook.sendELS and outputTable.ELS then
        notify("Webhook", "Sending ELS file...")
        task.wait(1)
        sendFileToDiscord(safeServerName .. "_ELS.json", httpService:JSONEncode(outputTable.ELS), settings.webhookURL)
    end

    if settings.webhook.sendMapTemplates and outputTable.Map then
        notify("Webhook", "Sending Map Templates file...")
        task.wait(1)
        sendFileToDiscord(safeServerName .. "_MapTemplates.json", httpService:JSONEncode(outputTable.Map), settings.webhookURL)
    end

    if settings.webhook.sendFullOutput then
        notify("Webhook", "Sending full output file...")
        task.wait(1)
        sendFileToDiscord(safeServerName .. ".txt", outputString, settings.webhookURL)
    end

    notify("Done!", "All assets collected successfully!", 10)
    print("DONE")
end

-- ===== UI INITIALIZATION =====
-- This is the UI system - add it right at the end before the return statement
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local UIModule = {}
UIModule.selectedItems = {
    serverInfo = true,
    uniforms = true,
    liveries = true,
    els = true,
    mapLayout = true,
    descriptions = false,
    rules = false
}

local DROPDOWN_ITEMS = {
    { id = "serverInfo", label = "Server Info", description = "Server name, code, teams" },
    { id = "uniforms", label = "Uniforms", description = "Team uniforms (shirts, pants)" },
    { id = "liveries", label = "Liveries", description = "Vehicle liveries and textures" },
    { id = "els", label = "ELS Data", description = "Emergency lighting system data" },
    { id = "mapLayout", label = "Map Layout", description = "Map templates and props" },
    { id = "descriptions", label = "Descriptions", description = "Server descriptions" },
    { id = "rules", label = "Rules", description = "Server rules" }
}

local function createScreenGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AssetTakerUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    return screenGui
end

local function createMainPanel(screenGui)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainPanel"
    mainFrame.Size = UDim2.new(0, 450, 0, 600)
    mainFrame.Position = UDim2.new(0.5, -225, 0.5, -300)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame
    
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 50)
    titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Asset Taker - Select Items"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = titleBar
    
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.Size = UDim2.new(1, -20, 1, -130)
    scrollFrame.Position = UDim2.new(0, 10, 0, 60)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    scrollFrame.Parent = mainFrame
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 8)
    listLayout.Parent = scrollFrame
    
    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingLeft = UDim.new(0, 10)
    listPadding.PaddingRight = UDim.new(0, 10)
    listPadding.PaddingTop = UDim.new(0, 5)
    listPadding.Parent = scrollFrame
    
    local webhookLabel = Instance.new("TextLabel")
    webhookLabel.Name = "WebhookLabel"
    webhookLabel.Size = UDim2.new(1, -20, 0, 20)
    webhookLabel.Position = UDim2.new(0, 10, 1, -70)
    webhookLabel.BackgroundTransparency = 1
    webhookLabel.Text = "Webhook URL (Optional)"
    webhookLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
    webhookLabel.TextSize = 12
    webhookLabel.Font = Enum.Font.GothamBold
    webhookLabel.TextXAlignment = Enum.TextXAlignment.Left
    webhookLabel.Parent = mainFrame
    
    local webhookInput = Instance.new("TextBox")
    webhookInput.Name = "WebhookInput"
    webhookInput.Size = UDim2.new(1, -20, 0, 28)
    webhookInput.Position = UDim2.new(0, 10, 1, -50)
    webhookInput.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    webhookInput.BorderColor3 = Color3.fromRGB(50, 50, 70)
    webhookInput.BorderSizePixel = 1
    webhookInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    webhookInput.TextSize = 11
    webhookInput.Font = Enum.Font.Gotham
    webhookInput.PlaceholderText = "https://discord.com/api/webhooks/..."
    webhookInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    webhookInput.Parent = mainFrame
    
    local startButton = Instance.new("TextButton")
    startButton.Name = "StartButton"
    startButton.Size = UDim2.new(1, -20, 0, 40)
    startButton.Position = UDim2.new(0, 10, 1, -40)
    startButton.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
    startButton.BorderSizePixel = 0
    startButton.Text = "START COLLECTION"
    startButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    startButton.TextSize = 14
    startButton.Font = Enum.Font.GothamBold
    startButton.Parent = mainFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = startButton
    
    return mainFrame, scrollFrame, webhookInput, startButton
end

local function createCheckboxItem(parent, item, onToggle)
    local container = Instance.new("Frame")
    container.Name = item.id .. "_Container"
    container.Size = UDim2.new(1, -20, 0, 60)
    container.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    container.BorderSizePixel = 0
    container.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container
    
    local checkbox = Instance.new("Frame")
    checkbox.Name = "Checkbox"
    checkbox.Size = UDim2.new(0, 24, 0, 24)
    checkbox.Position = UDim2.new(0, 8, 0.5, -12)
    checkbox.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    checkbox.BorderSizePixel = 1
    checkbox.BorderColor3 = Color3.fromRGB(100, 100, 150)
    checkbox.Parent = container
    
    local checkCorner = Instance.new("UICorner")
    checkCorner.CornerRadius = UDim.new(0, 4)
    checkCorner.Parent = checkbox
    
    local checkmark = Instance.new("TextLabel")
    checkmark.Name = "Checkmark"
    checkmark.Size = UDim2.new(1, 0, 1, 0)
    checkmark.BackgroundTransparency = 1
    checkmark.Text = "✓"
    checkmark.TextColor3 = Color3.fromRGB(0, 200, 100)
    checkmark.TextSize = 18
    checkmark.Font = Enum.Font.GothamBold
    checkmark.Visible = true
    checkmark.Parent = checkbox
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 200, 0, 24)
    label.Position = UDim2.new(0, 40, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = item.label
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    
    local description = Instance.new("TextLabel")
    description.Name = "Description"
    description.Size = UDim2.new(1, -50, 0, 20)
    description.Position = UDim2.new(0, 40, 0, 28)
    description.BackgroundTransparency = 1
    description.Text = item.description
    description.TextColor3 = Color3.fromRGB(150, 150, 150)
    description.TextSize = 11
    description.Font = Enum.Font.Gotham
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextWrapped = true
    description.Parent = container
    
    local isChecked = true
    checkmark.Visible = isChecked
    
    local button = Instance.new("TextButton")
    button.Name = "ClickArea"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.Text = ""
    button.Parent = container
    
    button.MouseButton1Click:Connect(function()
        isChecked = not isChecked
        checkmark.Visible = isChecked
        checkbox.BackgroundColor3 = isChecked and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(50, 50, 70)
        onToggle(item.id, isChecked)
    end)
    
    button.MouseEnter:Connect(function()
        container.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    end)
    
    button.MouseLeave:Connect(function()
        container.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    end)
end

local function makeDraggable(frame)
    local dragging = false
    local dragStart
    local frameStart
    
    frame.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            frameStart = frame.Position
        end
    end)
    
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = frameStart + UDim2.new(0, delta.X, 0, delta.Y)
        end
    end)
end

-- Build the UI
local screenGui = createScreenGui()
local mainFrame, scrollFrame, webhookInput, startButton = createMainPanel(screenGui)

for _, item in ipairs(DROPDOWN_ITEMS) do
    createCheckboxItem(scrollFrame, item, function(id, checked)
        UIModule.selectedItems[id] = checked
    end)
end

webhookInput.FocusLost:Connect(function(enterPressed)
    if webhookInput.Text ~= "" then
        settings.sendToWebhook = true
        settings.webhookURL = webhookInput.Text
    else
        settings.sendToWebhook = false
    end
end)

startButton.MouseButton1Click:Connect(function()
    startButton.Text = "STARTING..."
    startButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    
    settings.webhook.sendServerInfo = UIModule.selectedItems.serverInfo
    settings.webhook.sendUniforms = UIModule.selectedItems.uniforms
    settings.webhook.sendLiveries = UIModule.selectedItems.liveries
    settings.webhook.sendELS = UIModule.selectedItems.els
    settings.webhook.sendMapTemplates = UIModule.selectedItems.mapLayout
    settings.webhook.sendDescription = UIModule.selectedItems.descriptions
    settings.webhook.sendRules = UIModule.selectedItems.rules
    
    print("configuration:", settings)
    takeAssets()
end)

makeDraggable(mainFrame)
