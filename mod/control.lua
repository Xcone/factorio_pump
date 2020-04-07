--control.lua

--player_index :: uint: The player doing the selection.
--surface :: LuaSurface: The surface selected.
--area :: BoundingBox: The area selected.
--item :: string: The item used to select the area.
--entities :: array of LuaEntity: The entities selected.
--tiles :: array of LuaTile: The tiles selected.
script.on_event({defines.events.on_player_selected_area},
   function (event)
      if event.item == 'pump-selection-tool' and #event.entities > 0 then
         local player = game.get_player(event.player_index)
         
         local count =0;
         for i, entity in ipairs(event.entities) do
            if can_place_pumpjack(event.surface, entity.position) then
               count = count + 1
            end
         end

         player.print(count);
      end
   end
)

script.on_event(defines.events.on_lua_shortcut, handle_shortcut)

function can_place_pumpjack(surface, position)
--name :: string: Name of the entity to check
--position :: Position: Where the entity would be placed
--direction :: defines.direction (optional): Direction the entity would be placed
--force :: ForceSpecification (optional): The force that would place the entity. If not specified, the enemy force is assumed.
--build_check_type :: defines.build_check_type (optional): What check type should be done.
--forced :: boolean (optional): If defines.build_check_type is "ghost_place" and this is true things that can be marked for deconstruction are ignored.
   return surface.can_place_entity(
      {
         name="pumpjack", 
         position=position, 
         direction=defines.direction.north, 
         force="player", 
         build_check_type=defines.build_check_type.ghost_place                  
      })
end