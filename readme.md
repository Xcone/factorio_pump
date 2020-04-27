# Factorio P.U.M.P.
This is a mod for [Factorio](https://factorio.com/).
Find it on the [mod page](https://mods.factorio.com/mod/pump)

# Why P.U.M.P.
Fluids and pipes are fun and all. But the more complex layout can be blueprinted and copied. Unfortunately, due to the random nature of how oil wells are found on the map, you're left with a significant chunk of manual labor for each oil field you claim. After a while placing pumpjacks gets old...

P.U.M.P. (Prevent Unwanted Manual Pump-placement) adds a selection-tool with which you can select oil wells, and then plans the layout of pumpjacks and pipes for you.

![](graphics/demo.gif)

## Alternative
I started this mod, because I thought this piece of tooling didn't exist. After release I learned I was beaten to it by [WellPlanner](https://mods.factorio.com/mod/WellPlanner), which released 2 months or so before mine. The WellPlanner mod is actually more feature complete. The primary difference between WellPlanner and P.U.M.P. is how to start the planner. P.U.M.P. uses a button on the shortcut bar, and WellPlanner uses a craftable planner, similar to a blueprint.

# Limitations
The mod attempts to split the field in smaller chunks until it is able to connect all the pumps in straight lines to any of the splits, or until the chunks are too small. Due to the nature of finding those splits, if the oil field is too tightly packed, or if obstructions (trees, rocks, water or other buildings) are in the way, P.U.M.P. might not be able to find a layout connecting all the pumpjacks in the selection. In which case P.U.M.P. will prompt it's not able to do its job.

Maybe I'll find the time to improve on that later. First, as this is my first mod, I'd like to see how getting a mod online works and all.

# Found a bug?
P.U.M.P. should store pump_planner_input.json in the script-output folder within the user folder. It'd be helpful if you could provide it to me. Note that the file will be replaced each time you make a selection. So double check the timestamp of the file if it was generated at the same time as the bug occurred.

# Todo/wishlist 
A list of things I may want to add to the mod:
- Add a setting to set a minimum distance to use underground pipe. Currently it is set to 2, but that just waste of materials in some cases. This should include the possibility to not use underground pipes at all.
- Add a (configurable) shortcut key
- Less hardcoded values
  - Pumpjack size
  - Pumpjack pipe output locations
  - Underground pipe distance  
- Support for Krastorio 2 [per request](https://mods.factorio.com/mod/pump/discussion/5ea215c45e07f1000cea5281).
- Fallback-routine to connect pumpjacks in another (more curvey) way, if P.U.M.P. was unable to do so with the straight segment splits.
- Support undo
