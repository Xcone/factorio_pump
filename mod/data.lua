--data.lua

local pumpSelectionTool = table.deepcopy(data.raw["selection-tool"]["selection-tool"])

pumpSelectionTool.name = "pump-selection-tool"
pumpSelectionTool.icons= {
   {
      icon="__base__/graphics/icons/pumpjack.png",
      tint={r=1,g=0.5,b=1,a=1}
   },
}
pumpSelectionTool.selection_mode = {"trees"}
pumpSelectionTool.alt_selection_mode = {"trees"}
pumpSelectionTool.selection_cursor_box_type = "entity"
pumpSelectionTool.flags = {"only-in-cursor"}

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