--control.lua

script.on_event({defines.events.on_player_selected_area},
   function (event)
      if event.item == 'pump-selection-tool' and #event.entities > 0 then
         local player = game.get_player(event.player_index)
             
         player.print("The selection");
      end
   end
)

script.on_event(defines.events.on_lua_shortcut, handle_shortcut)