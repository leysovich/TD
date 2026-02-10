local Config = {}

Config.StartMoney = 460
Config.BaseLives = 20
Config.Intermission = 10
Config.MaxTowersPerPlayer = 22
Config.SellRefundRate = 0.65
Config.WaveClearBonusBase = 20
Config.WaveClearBonusScale = 2.2

Config.Towers = {
    LaserTurret = {
        DisplayName = 'Laser Turret',
        TemplateName = 'LaserTurret',
        Cost = 145,
        Damage = 11,
        Range = 35,
        FireRate = 0.68,
        Color = Color3.fromRGB(0, 255, 204),
        Upgrades = {
            {Cost = 150, DamageMult = 1.55, RangeAdd = 4, FireRateMult = 0.90},
            {Cost = 260, DamageMult = 1.50, RangeAdd = 5, FireRateMult = 0.88},
            {Cost = 430, DamageMult = 1.55, RangeAdd = 6, FireRateMult = 0.86},
        },
    },

    FrostBeam = {
        DisplayName = 'Frost Beam',
        TemplateName = 'FrostBeam',
        Cost = 175,
        Damage = 7,
        Range = 38,
        FireRate = 0.42,
        SlowFactor = 0.55,
        SlowDuration = 1.6,
        Color = Color3.fromRGB(120, 200, 255),
        Upgrades = {
            {Cost = 155, DamageMult = 1.40, RangeAdd = 4, FireRateMult = 0.90, SlowFactorMult = 0.90, SlowDurationAdd = 0.35},
            {Cost = 265, DamageMult = 1.50, RangeAdd = 4, FireRateMult = 0.88, SlowFactorMult = 0.90, SlowDurationAdd = 0.45},
            {Cost = 420, DamageMult = 1.60, RangeAdd = 5, FireRateMult = 0.86, SlowFactorMult = 0.90, SlowDurationAdd = 0.55},
        },
    },

    MissilePod = {
        DisplayName = 'Missile Pod',
        TemplateName = 'MissilePod',
        Cost = 320,
        Damage = 42,
        Range = 52,
        FireRate = 1.60,
        SplashRadius = 12,
        Color = Color3.fromRGB(255, 180, 70),
        Upgrades = {
            {Cost = 300, DamageMult = 1.42, RangeAdd = 4, FireRateMult = 0.94, SplashRadiusAdd = 1},
            {Cost = 455, DamageMult = 1.52, RangeAdd = 5, FireRateMult = 0.90, SplashRadiusAdd = 2},
            {Cost = 700, DamageMult = 1.65, RangeAdd = 6, FireRateMult = 0.88, SplashRadiusAdd = 2},
        },
    },
}

Config.Waves = {
    {Count = 8,  HP = 34,   Speed = 9,  Reward = 4,  SpawnDelay = 0.95, Name = 'Probe Scouts',       EnemyType = 'Alien', TurnRate = 110},
    {Count = 10, HP = 44,   Speed = 10, Reward = 4,  SpawnDelay = 0.88, Name = 'Scout Push',         EnemyType = 'Alien', TurnRate = 115},
    {Count = 12, HP = 58,   Speed = 11, Reward = 5,  SpawnDelay = 0.82, Name = 'Fast Raiders',       EnemyType = 'Alien', TurnRate = 125},
    {Count = 8,  HP = 95,   Speed = 8,  Reward = 7,  SpawnDelay = 1.02, Name = 'Heavy Walkers',      EnemyType = 'Alien', TurnRate = 95},
    {Count = 1,  HP = 680,  Speed = 6,  Reward = 42, SpawnDelay = 0.60, Name = 'Alpha Strider',      EnemyType = 'Alien', TurnRate = 85},

    {Count = 14, HP = 82,   Speed = 10, Reward = 7,  SpawnDelay = 0.82, Name = 'Raider Screen',      EnemyType = 'Alien', TurnRate = 118},
    {Count = 14, HP = 145,  Speed = 9,  Reward = 8,  SpawnDelay = 0.88, Name = 'Armor Convoy',       EnemyType = 'Alien', TurnRate = 100},
    {Count = 20, HP = 120,  Speed = 12, Reward = 7,  SpawnDelay = 0.68, Name = 'Swarm Lanes',        EnemyType = 'Alien', TurnRate = 130},
    {Count = 2,  HP = 780,  Speed = 7,  Reward = 30, SpawnDelay = 1.10, Name = 'Twin Brutes',        EnemyType = 'Alien', TurnRate = 90},

    {Count = 20, HP = 140,  Speed = 11, Reward = 8,  SpawnDelay = 0.68, Name = 'Overrun Protocol',   EnemyType = 'Alien', TurnRate = 120},
    {Count = 18, HP = 190,  Speed = 9,  Reward = 9,  SpawnDelay = 0.82, Name = 'Siege Train',        EnemyType = 'Alien', TurnRate = 95},
    {Count = 1,  HP = 2300, Speed = 7,  Reward = 60, SpawnDelay = 0.55, Name = 'Titan Core',         EnemyType = 'Alien', TurnRate = 80},

    {Count = 26, HP = 210,  Speed = 11, Reward = 9,  SpawnDelay = 0.60, Name = 'Aftershock Swarm',   EnemyType = 'Alien', TurnRate = 120},
    {Count = 22, HP = 290,  Speed = 10, Reward = 10, SpawnDelay = 0.72, Name = 'War Columns',        EnemyType = 'Alien', TurnRate = 100},
    {Count = 1,  HP = 4200, Speed = 8,  Reward = 105, SpawnDelay = 0.50, Name = 'Overmind Apex',     EnemyType = 'Alien', TurnRate = 85},
}

return Config
