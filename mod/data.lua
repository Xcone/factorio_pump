-- data.lua
local pumpSelectionTool = table.deepcopy(
                              data.raw["selection-tool"]["selection-tool"])

pumpSelectionTool.name = "pump-selection-tool"
pumpSelectionTool.icon = "__pump__/graphics/icons/pump_icon_32.png"
pumpSelectionTool.icon_size = 32
pumpSelectionTool.icon_mipmaps = 0
pumpSelectionTool.selection_mode = {"any-entity"}
pumpSelectionTool.selection_cursor_box_type = "entity"
pumpSelectionTool.flags = {"only-in-cursor", "spawnable"}
pumpSelectionTool.subgroup = "tool"
pumpSelectionTool.order = "c[automated-construction]-d[pump-selection-tool]"
pumpSelectionTool.entity_filters = {"crude-oil"}

-- no different ALT-behavior. Just copy it from the regular behavior
pumpSelectionTool.alt_selection_color = pumpSelectionTool.selection_color
pumpSelectionTool.alt_selection_cursor_box_type =
    pumpSelectionTool.selection_cursor_box_type
pumpSelectionTool.alt_selection_mode = pumpSelectionTool.selection_mode
pumpSelectionTool.alt_entity_filter_mode = pumpSelectionTool.entity_filter_mode
pumpSelectionTool.alt_entity_filters = pumpSelectionTool.entity_filters
pumpSelectionTool.alt_entity_type_filters =
    pumpSelectionTool.entity_type_filters
pumpSelectionTool.alt_tile_filter_mode = pumpSelectionTool.tile_filter_mode
pumpSelectionTool.alt_tile_filters = pumpSelectionTool.tile_filters

local pumpShortcut = table.deepcopy(data.raw["shortcut"]["give-blueprint"])
pumpShortcut.name = "pump-shortcut"
pumpShortcut.technology_to_unlock = nil
pumpShortcut.localised_name = nil
pumpShortcut.associated_control_input = nil
pumpShortcut.item_to_spawn = "pump-selection-tool"
pumpShortcut.style = "default"
pumpShortcut.icon = {
    filename = "__pump__/graphics/icons/pump_icon_32.png",
    priority = "extra-high-no-scale",
    size = 32,
    scale = 1,
    flags = {"icon"}
}
pumpShortcut.disabled_icon = {
    filename = "__pump__/graphics/icons/pump_icon_32_white.png",
    priority = "extra-high-no-scale",
    size = 32,
    scale = 1,
    flags = {"icon"}
}
pumpShortcut.small_icon = {
    filename = "__pump__/graphics/icons/pump_icon_24.png",
    priority = "extra-high-no-scale",
    size = 24,
    scale = 1,
    flags = {"icon"}
}
pumpShortcut.disabled_small_icon = {
    filename = "__pump__/graphics/icons/pump_icon_24_white.png",
    priority = "extra-high-no-scale",
    size = 24,
    scale = 1,
    flags = {"icon"}
}

data:extend{pumpSelectionTool, pumpShortcut}
