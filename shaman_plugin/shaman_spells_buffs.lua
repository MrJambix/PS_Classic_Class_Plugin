-- === Project Sylvanas Shaman Plugin ===
-- shaman_spells_buffs.lua
-- Contains all Shaman spell IDs (by rank), imbuement ranks, and buff IDs

local SPELLS = {}
SPELLS.Berserking           = { [1] = 20554 }
SPELLS.ChainLightning       = { [1]=421, [2]=930, [3]=2860, [4]=10605, [5]=25442 }
SPELLS.EarthShock           = { [1]=8042, [2]=8044, [3]=8045, [4]=10412, [5]=10413, [6]=10414, [7]=25454 }
SPELLS.FlameShock           = { [1]=8050, [2]=8052, [3]=8053, [4]=10447, [5]=10448, [6]=29228, [7]=25457 }
SPELLS.FrostShock           = { [1]=8056, [2]=8058, [3]=10472, [4]=10473, [5]=25464 }
SPELLS.LightningBolt        = { [1]=403, [2]=529, [3]=548, [4]=915, [5]=943, [6]=6041, [7]=10391, [8]=10392, [9]=15207, [10]=15208, [11]=25449 }
SPELLS.Purge                = { [1]=370, [2]=8012 }
SPELLS.LightningShield      = { [1]=324, [2]=325, [3]=905, [4]=945, [5]=8134, [6]=10431, [7]=10432, [8]=25469 }
SPELLS.AncestralSpirit      = { [1]=2008, [2]=20609, [3]=20610, [4]=20776 }
SPELLS.CureDisease          = { [1]=2870 }
SPELLS.CurePoison           = { [1]=526 }
SPELLS.NaturesSwiftness     = { [1]=16188 }
SPELLS.ChainHeal            = { [1]=1064, [2]=10622, [3]=10623, [4]=25423 }
SPELLS.BloodFury            = { [1]=20572, [2]=23230, [3]=23234 }
SPELLS.TremorTotem          = { [1]=8143 }

local rockbiter_ranks = {
    { spell = 10399, enchant = 503 },
    { spell = 8019,  enchant = 1   },
    { spell = 8018,  enchant = 6   },
    { spell = 8017,  enchant = 29  },
}
local windfury_ranks = {
    { spell = 8232, enchant = 283 },
}
local flametongue_ranks = {
    { spell = 8030, enchant = 3 },
    { spell = 8027, enchant = 4 },
    { spell = 8024, enchant = 5 },
}
local frostbrand_ranks = {
    { spell = 8033, enchant = 2 },
}

local SPELL_BUFFS = {
    Berserking = 26635,
    BloodFury = 23234,
    TremorTotem = 8143,
}

return {
    SPELLS = SPELLS,
    rockbiter_ranks = rockbiter_ranks,
    windfury_ranks = windfury_ranks,
    flametongue_ranks = flametongue_ranks,
    frostbrand_ranks = frostbrand_ranks,
    SPELL_BUFFS = SPELL_BUFFS,
}