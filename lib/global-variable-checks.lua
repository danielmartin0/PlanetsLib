
local Public = {}

--Run at beginning of every data cycle. Checks if commonly used global variables set by engine still exist. Used to enforce a certain level of code quality among all mods.
function Public.check_global_variables()
    if not helpers.compare_versions then
        error("Another mod has overridden the 'helpers' global variable. More info: https://lua-api.factorio.com/latest/classes/LuaHelpers.html")
    end
    


end

return Public