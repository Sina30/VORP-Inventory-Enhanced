local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, "version", 0)

Citizen.CreateThread(function()
    local link = "https://raw.githubusercontent.com/CodeRanchRed/versions/main/version.json?v=" .. os.time()
    PerformHttpRequest(link, function(err, text, headers)
        if err == 200 then
            local success, versionData = pcall(function()
                return json.decode(text)
            end)
            if success and versionData and versionData["vorp_inventory"] then
                local data = versionData["vorp_inventory"]
                local latestVersion = data.version
                local description = data.description
                local changelog = data.changelog or {}
                if currentVersion ~= latestVersion then
                    print("^0")
                    print("^3========================================^0")
                    print("^3["..resourceName.."] New Version Available!^0")
                    print("^7Current Version: ^1" .. currentVersion .. "^0")
                    print("^7Latest Version:  ^2" .. latestVersion .. "^0")
                    print("^0")
                    print("^7Changelog:^0")
                    for i, change in ipairs(changelog) do
                        print("^7  • " .. change .. "^0")
                    end
                    print("^3========================================^0")
                    print("^0")
                else
                    print("^2[vorp_inventory] You are using the latest version! (" .. currentVersion .. ")^0")
                end
            else
                print("^1[vorp_inventory] Failed to parse version data!^0")
            end
        else
            print("^1[vorp_inventory] Version check failed! (HTTP " .. tostring(err) .. ")^0")
        end
    end, "GET", "")
end)

