if mods["ModuleInserter"] then

    data:extend({
        {
            type = "bool-setting",
            name = "pump-interface-with-module-inserter-mod",
            setting_type = "runtime-per-user",
            default_value = true
        }
    })
end
