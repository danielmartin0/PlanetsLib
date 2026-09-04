if settings.startup["PlanetsLib-enable-lab-science-pack-preview-size-change"].value == true then
   for _,lab in pairs(data.raw.lab) do
        local max_count = 12
        local pack_count = 0
        for _,pack in pairs(lab.inputs) do
            pack_count = pack_count + 1
        end
        if pack_count >= max_count then
            --assert(lab.name ~= "cerys-lab")
            local icon_scaling = max_count/pack_count
            local left_top = lab.selection_box.left_top or lab.selection_box[1]
            local right_bottom = lab.selection_box.right_bottom or lab.selection_box[2]
            local x = math.abs(left_top[1] - right_bottom[1])
            local size_factor = 1
            if x then
                size_factor = math.sqrt(x / 3)
            end
            
            if not lab.icons_positioning then
            lab.icons_positioning = {
                --{inventory_index = defines.inventory.lab_modules, shift = {0, -0.9 * shift_factor}},
            }
            end
            --if not PlanetsLib.rro.contains(lab.icons_positioning,function(entry) return entry.inventory_index == defines.inventory.lab_input end) then
                table.insert(lab.icons_positioning,{inventory_index = defines.inventory.lab_input, shift = {0, 0.75*size_factor*(icon_scaling-1)}, max_icons_per_row = math.floor(6/math.sqrt(icon_scaling)), separation_multiplier = 1, scale = 0.9*size_factor*icon_scaling})
            --end
            
        end
    end 
end

