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
        type = "bool-setting",
        name = "pump-use-plumber-pro",
        setting_type = "runtime-per-user",
        default_value = false
    },
})
