--data.lua

local pumpSelectionTool = table.deepcopy(data.raw["selection-tool"]["selection-tool"])

pumpSelectionTool.name = "pump-selection-tool"
pumpSelectionTool.icons= {
   {
      icon="__base__/graphics/icons/pumpjack.png",
      tint={r=1,g=0.5,b=1,a=1}
   },
}
pumpSelectionTool.selection_mode = {"any-entity"}
pumpSelectionTool.selection_cursor_box_type = "entity"
pumpSelectionTool.flags = {"only-in-cursor"}
pumpSelectionTool.entity_filters = {"crude-oil"}

-- no different ALT-behavior. Just copy it from the regular behavior
pumpSelectionTool.alt_selection_color = pumpSelectionTool.selection_color
pumpSelectionTool.alt_selection_cursor_box_type = pumpSelectionTool.selection_cursor_box_type
pumpSelectionTool.alt_selection_mode = pumpSelectionTool.selection_mode
pumpSelectionTool.alt_entity_filter_mode = pumpSelectionTool.entity_filter_mode
pumpSelectionTool.alt_entity_filters = pumpSelectionTool.entity_filters
pumpSelectionTool.alt_entity_type_filters = pumpSelectionTool.entity_type_filters
pumpSelectionTool.alt_tile_filter_mode = pumpSelectionTool.tile_filter_mode
pumpSelectionTool.alt_tile_filters = pumpSelectionTool.tile_filters


local pumpShortcut = table.deepcopy(data.raw["shortcut"]["give-blueprint"])
pumpShortcut.name = "pump-shortcut"
pumpShortcut.localised_name = nil
pumpShortcut.style = "green"
pumpShortcut.icon =
{
  filename = "__base__/graphics/icons/pumpjack.png",
  size = 32,
  scale = 1,
  mipmap_count = 4,
  flags = {"icon"}
}
pumpShortcut.item_to_create = "pump-selection-tool"

data:extend{
   pumpSelectionTool,
   pumpShortcut
}