-- JRS Stables | Wagons use the existing stable NPCs and menu in this resource.
Config.Wagons = {
    enabled = true,
    currencyType = 2, -- 0 cash, 1 gold, 2 both
    maxPlayerWagons = 5,
    maxWainwrightWagons = 10,
    wainwrightJob = 'wainwright',
    wainwrightGrade = 0,
    sellPrice = 0.70,
    shopDistance = 8.0,
    callEnabled = true,
    showNames = false, -- No floating name or health bar above a wagon.
    returnEnabled = true,
    callDistance = 100.0,
    seated = true,
    repairItem = 'hammer', -- Existing JRS item; one hammer repairs by the model's repairValue.
    repairUsage = 1,
    commands = { call = 'wagonEnter', returnWagon = 'wagonReturn', cargo = 'wagoncargo' },
    keys = { call = 0xF3830D8E, menu = 0x760A9C6F, brake = 0xF1301666 }, -- J spawn selected wagon; G menu; O brakes
    -- Server-side GrantWagon is only available to these resources.
    trustedGrantResources = { jrs_admin = true },
}
