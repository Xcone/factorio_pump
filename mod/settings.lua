if mods["ModuleInserterEx"] then

    data:extend({
        {
            type = "bool-setting",
            name = "pump-interface-with-module-inserter-mod",
            setting_type = "runtime-per-user",
            default_value = true
        }
    })
end

data:extend({
    {
        type = "bool-setting",
        name = "pump-ignore-research",
        setting_type = "runtime-per-user",
        default_value = false
    },
    {
        type = "bool-setting",
        name = "pump-always-show",
        setting_type = "runtime-per-user",
        default_value = true
    },

    {
        type = "int-setting",
        name = "pump-max-beacons-per-extractor",
        setting_type = "runtime-per-user",
        default_value = 4,
        minimum_value = 1,
        maximum_value = 8,        
    },
    {
        type = "int-setting",
        name = "pump-min-extractors-per-beacon",
        setting_type = "runtime-per-user",
        default_value = 1,
        minimum_value = 1,
        maximum_value = 8
    },
    {
        type = "int-setting",
        name = "pump-preferred-beacons-per-extractor",
        setting_type = "runtime-per-user",
        default_value = 1,
        minimum_value = 1,
        maximum_value = 8
    },
})
