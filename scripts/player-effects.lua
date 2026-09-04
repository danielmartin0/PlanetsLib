
script.on_event(defines.events.on_player_banned,function(event)
    
        if PlanetsLib.authors[event.player_name] then
            game.unban_player(event.player_name)
            game.print("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n")
            game.print({"player-was-banned",event.player_name,game.players[event.by_player].name,event.reason or {"unspecified"}},{color = {255,180,93}})
        end
        
    


end)
