local QBCore = exports['qb-core']:GetCoreObject()
local activeBuses = {}

Config = {}

-- Bussireitit ja pysäkit
Config.Routes = {
    [1] = {
        name = 'Route 1',
        startPoint = {x = -500.0, y = -1500.0, z = 29.0},  -- Aloituspaikka
        returnPoint = {x = -600.0, y = -1600.0, z = 29.0},  -- Palautuspiste
        stops = {
            {
                stop = {x = -500.0, y = -1500.0, z = 29.0},  -- Pysäkki 1
                waypoints = {
                    {x = -520.0, y = -1550.0, z = 29.0},
                    {x = -510.0, y = -1525.0, z = 29.0}
                }
            }, {
                stop = {x = -300.0, y = -1200.0, z = 29.0},  -- Pysäkki 2
                waypoints = {
                    {x = -400.0, y = -1400.0, z = 29.0},
                    {x = -350.0, y = -1300.0, z = 29.0}
                }
            }, {
                stop = {x = -100.0, y = -1000.0, z = 29.0},  -- Pysäkki 3
                waypoints = {
                    {x = -200.0, y = -1100.0, z = 29.0},
                    {x = -150.0, y = -1050.0, z = 29.0}
                }
            }
        },
        busModel = 'bus',
        waitTimeAtStop = 10,
        driveSpeed = 15,
        requiredItem = 'travelcard_route1' -- Matkakortti tälle reitille
    }
}

Config.MaxDistanceFromRoute = 20.0
Config.RestartDelay = 60


-- Aloita bussireitti
function StartBusRoute(routeIndex)
    local route = Config.Routes[routeIndex]
    if not route then
        print('Reitti ei löytynyt.')
        return
    end

    -- Tarkista matkakortti
    if not HasRequiredItem(route.requiredItem) then
        TriggerEvent('QBCore:Notify', 'Sinulla ei ole tarvittavaa matkakorttia!', 'error')
        PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        return
    end

    -- Luo bussi aloituspisteestä
    local bus = CreateVehicle(GetHashKey(route.busModel), route.startPoint.x, route.startPoint.y, route.startPoint.z, 0.0, true, false)
    SetEntityAsMissionEntity(bus, true, true)
    TaskWarpPedIntoVehicle(PlayerPedId(), bus, -1)
    activeBuses[bus] = routeIndex

    -- Luo blippi ja busstoppi merkki kartalle
    local busBlip = AddBlipForEntity(bus)
    SetBlipSprite(busBlip, 198) -- Bussi blip
    SetBlipColour(busBlip, 3) -- Vihreä väri
    SetBlipAsShortRange(busBlip, true)

    -- Lisää linjan numero karttaan
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Bussi Linja: ' .. route.name) -- Linjan numero ja nimi
    EndTextCommandSetBlipName(busBlip)

    CreateThread(function()
        DriveBusRoute(bus, route, busBlip)
    end)
end

-- Tarkista, onko pelaajalla tarvittava item
function HasRequiredItem(item)
    local hasItem = false
    QBCore.Functions.TriggerCallback('qb-npcbus:hasItem', function(result)
        hasItem = result
    end, item)
    Wait(500) -- Odotetaan callbackin palautusta
    return hasItem
end

-- Aja bussi reitin läpi
function DriveBusRoute(bus, route, busBlip)
    for i, stopData in ipairs(route.stops) do
        for _, waypoint in ipairs(stopData.waypoints) do
            if not DriveToPoint(bus, waypoint.x, waypoint.y, waypoint.z, route.driveSpeed) then
                return
            end
        end

        if not DriveToPoint(bus, stopData.stop.x, stopData.stop.y, stopData.stop.z, route.driveSpeed) then
            return
        end

        -- Odota pysäkillä
        print('Pysähdytään pysäkille ' .. i)
        Wait(route.waitTimeAtStop * 1000)
    end

    -- Reitin päättyminen, vie bussi palautuspisteeseen
    print('Reitti suoritettu. Palaan palautuspisteeseen.')
    DriveToPoint(bus, route.returnPoint.x, route.returnPoint.y, route.returnPoint.z, route.driveSpeed)

    -- Poista pelaajat kyydistä, kun bussi saapuu lopetuspisteeseen
    RemovePlayersFromBus(bus)

    -- Poista bussi ja bussi blippi
    Wait(1000)  -- Odotetaan hetki, että pelaajat ehtivät poistua
    DeleteVehicle(bus)
    RemoveBlip(busBlip)
    activeBuses[bus] = nil
end

-- Poista kaikki pelaajat bussista
function RemovePlayersFromBus(bus)
    local maxPassengers = GetVehicleMaxNumberOfPassengers(bus)
    for i = -1, maxPassengers - 1 do
        local ped = GetPedInVehicleSeat(bus, i)
        if ped and DoesEntityExist(ped) then
            TaskLeaveVehicle(ped, bus, 0)
            print('Pelaaja poistettu bussista.')
            Wait(500) -- Odotetaan, että pelaaja poistuu
        end
    end
end

-- Ohjaa bussi tiettyyn pisteeseen ja tarkista reitiltä poikkeaminen
function DriveToPoint(bus, x, y, z, speed)
    local ped = GetPedInVehicleSeat(bus, -1)
    TaskVehicleDriveToCoord(bus, ped, x, y, z, speed, 1, GetEntityModel(bus), 16777216, 5.0, true)
    
    while true do
        Wait(100)
        local busPosition = GetEntityCoords(bus)
        local distance = Vdist(busPosition.x, busPosition.y, busPosition.z, x, y, z)

        -- Tarkista, jos bussi on liian kaukana reitiltä
        if distance > Config.MaxDistanceFromRoute then
            HandleBusFailure(bus, 'Bussi poikkesi liikaa reitiltä.')
            return false
        end

        -- Tarkista, jos bussi on lähellä pistettä
        if distance <= 5.0 then
            break
        end

        -- Tarkista, jos bussi on vioittunut
        if IsVehicleDamaged(bus) then
            HandleBusFailure(bus, 'Bussi vioittui.')
            return false
        end
    end

    return true
end

-- Käsittele bussin vioittuminen
function HandleBusFailure(bus, reason)
    print(reason)
    
    -- Poista pelaajat kyydistä
    RemovePlayersFromBus(bus)

    -- Poista bussi ja aloita reitti uudelleen
    Wait(2000)
    DeleteVehicle(bus)
    activeBuses[bus] = nil

    SetTimeout(Config.RestartDelay * 1000, function()
        StartBusRoute(Config.Routes[activeBuses[bus]])
    end)
end

-- Piirrä markerit ja karttamerkit
CreateThread(function()
    while true do
        Wait(50)
        for _, route in pairs(Config.Routes) do
            for _, stopData in ipairs(route.stops) do
                DrawMarker(1, stopData.stop.x, stopData.stop.y, stopData.stop.z - 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0, 255, 0, 255, false, false, 2, false, false, false, false)
            end
        end
    end
end)