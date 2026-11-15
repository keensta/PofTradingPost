local AnimalSpecies = {}

-- An ordered list so the dropdown order never changes between loads.
AnimalSpecies.List = {
    {
        name = "Rabbit",
        variants = {
            "Common Brown Rabbit",
            "Jackalope",
            "Rellekkan Cream Rabbit",
            "Piscatorian Cottontail Rabbit",
            "White Rabbit",
        },
    },
    {
        name = "Chicken",
        variants = {
            "Common White Hen",
            "Bandosian Bantam Hen",
            "Varrockian Red Hen",
            "Oomlie Hen",
            "Lizard Chicken",
            "Rooster",
        },
    },
    {
        name = "Sheep",
        variants = {
            "White Ewe",
            "White Ram",
            "Black Ewe",
            "Black Ram",
            "Summerdown Ewe",
            "Summerdown Ram",
            "Springsheared Ewe",
            "Springsheared Ram",
            "Winterwold Ewe",
            "Winterwold Ram",
            "Fallfaced Ewe",
            "Fallfaced Ram",
            "Golden Ewe",
            "Golden Ram",
        },
    },
    {
        name = "Cow",
        variants = {
            "Kandarin Cow",
            "Chocolate Cow",
            "Strawberry Cow",
            "Vanilla Cow",
            "Harlequin Cow",
            "Bull",
        },
    },
    {
        name = "Chinchompa",
        variants = {
            "Grey Chinchompa",
            "Golden Chinchompa",
            "Carnivorous Chinchompa",
            "Cobalt Chinchompa",
            "Viridian Chinchompa",
            "Azure Chinchompa",
            "Volatile Chinchompa",
            "Crimson Chinchompa",
            "Crystal Chinchompa",
        },
    },
    {
        name = "Spider",
        variants = {
            "Spirit Spider",
            "Night Spider",
            "Corpse Spider",
            "Fever Spider",
            "Giant Spider",
            "Ice Spider",
            "Araxyte Spider",
        },
    },
    {
        name = "Yak",
        variants = {
            "Fremennik Yak",
            "Sacred Yak",
            "Spirit Yak",
        },
    },
    {
        name = "Zygomite",
        variants = {
            "Gloomshroom Zygomite",
            "Zanarian Zygomite",
            "Daemoncap Zygomite",
            "Arcspore Zygomite",
            "Magical Zygomite",
        },
    },
    {
        name = "Dragon",
        variants = {
            "Green Dragon",
            "Royal Dragon",
        },
    },
}

-- Species names in display order.
function AnimalSpecies.getSpeciesNames()
    local names = {}
    for i, species in ipairs(AnimalSpecies.List) do names[i] = species.name end
    return names
end

function AnimalSpecies.getVariants(speciesName)
    for _, species in ipairs(AnimalSpecies.List) do
        if species.name == speciesName then return species.variants end
    end
    
    return {}
end

return AnimalSpecies