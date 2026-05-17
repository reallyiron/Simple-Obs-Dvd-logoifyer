local obs = obslua
local bit = require("bit")

math.randomseed(os.time())

local MAX_GLOBAL_SOURCES = 100
local global_targets = {}
local global_target_count = 1
local current_show_all = false

local function randomize_velocity()
    local angle = math.random() * math.pi * 2
    while math.abs(math.cos(angle)) < 0.2 or math.abs(math.sin(angle)) < 0.2 do
        angle = math.random() * math.pi * 2
    end
    return math.cos(angle), math.sin(angle)
end

for i = 1, MAX_GLOBAL_SOURCES do
    local vx, vy = randomize_velocity()
    global_targets[i] = {
        active = false,
        source_name = "",
        speed_x = 5.0,
        speed_y = 5.0,
        color_mode = 0,
        fixed_color = 4278190335,
        start_dir_x = 0,
        start_dir_y = 0,
        vel_x = vx,
        vel_y = vy,
        og_raw_x = 0,
        og_raw_y = 0,
        initialized = false,
        last_source = ""
    }
end

local function find_scene_item_recursive(scene, target_name)
    if not scene or not target_name or target_name == "" then return nil end
    local items = obs.obs_scene_enum_items(scene)
    if not items then return nil end
    
    local found = nil
    for _, item in ipairs(items) do
        local source = obs.obs_sceneitem_get_source(item)
        if source then
            local name = obs.obs_source_get_name(source)
            if name == target_name then
                found = item
                break
            end
            
            local unversioned_id = obs.obs_source_get_unversioned_id(source)
            if unversioned_id == "group" then
                local group_scene = obs.obs_group_from_source(source)
                if group_scene then
                    found = find_scene_item_recursive(group_scene, target_name)
                    if found then break end
                end
            end
        end
    end
    
    obs.sceneitem_list_release(items)
    return found
end

function script_description()
    return "DVD Bounce Effect Ultimate\n\nPure Script Properties edition for high-performance and stability. Control up to 100 bouncing sources globally."
end

function script_properties()
    local props = obs.obs_properties_create()
    
    local p_advanced = obs.obs_properties_add_bool(props, "g_advanced", "⚙️ Advanced Customization Mode")
    local p_show_all = obs.obs_properties_add_bool(props, "g_show_all", "Show Sources from ALL Scenes")
    local p_count = obs.obs_properties_add_int(props, "g_count", "Number of Target Sources", 1, MAX_GLOBAL_SOURCES, 1)
    
    local source_names = {}
    if current_show_all then
        local sources = obs.obs_enum_sources()
        if sources then
            for _, source in ipairs(sources) do
                table.insert(source_names, obs.obs_source_get_name(source))
            end
            obs.source_list_release(sources)
        end
    else
        local current_scene_source = obs.obs_frontend_get_current_scene()
        if current_scene_source then
            local scene = obs.obs_scene_from_source(current_scene_source)
            if scene then
                local function collect_names(s)
                    local items = obs.obs_scene_enum_items(s)
                    if items then
                        for _, item in ipairs(items) do
                            local src = obs.obs_sceneitem_get_source(item)
                            if src then
                                table.insert(source_names, obs.obs_source_get_name(src))
                                if obs.obs_source_get_unversioned_id(src) == "group" then
                                    local grp = obs.obs_group_from_source(src)
                                    if grp then collect_names(grp) end
                                end
                            end
                        end
                        obs.sceneitem_list_release(items)
                    end
                end
                collect_names(scene)
            end
            obs.obs_source_release(current_scene_source)
        end
    end

    local function refresh_ui(props, prop, settings)
        local count = obs.obs_data_get_int(settings, "g_count")
        local show_all = obs.obs_data_get_bool(settings, "g_show_all")
        local is_advanced = obs.obs_data_get_bool(settings, "g_advanced")
        global_target_count = count
        current_show_all = show_all
        
        local dyn_source_names = {}
        if show_all then
            local sources = obs.obs_enum_sources()
            if sources then
                for _, source in ipairs(sources) do
                    table.insert(dyn_source_names, obs.obs_source_get_name(source))
                end
                obs.source_list_release(sources)
            end
        else
            local current_scene_source = obs.obs_frontend_get_current_scene()
            if current_scene_source then
                local scene = obs.obs_scene_from_source(current_scene_source)
                if scene then
                    local function collect_names(s)
                        local items = obs.obs_scene_enum_items(s)
                        if items then
                            for _, item in ipairs(items) do
                                local src = obs.obs_sceneitem_get_source(item)
                                if src then
                                    table.insert(dyn_source_names, obs.obs_source_get_name(src))
                                    if obs.obs_source_get_unversioned_id(src) == "group" then
                                        local grp = obs.obs_group_from_source(src)
                                        if grp then collect_names(grp) end
                                    end
                                end
                            end
                            obs.sceneitem_list_release(items)
                        end
                    end
                    collect_names(scene)
                end
                obs.obs_source_release(current_scene_source)
            end
        end

        for i = 1, MAX_GLOBAL_SOURCES do
            local visible = (i <= count)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "g_active_" .. i), visible)
            
            local p_source_list = obs.obs_properties_get(props, "g_source_" .. i)
            obs.obs_property_set_visible(p_source_list, visible)
            obs.obs_property_list_clear(p_source_list)
            obs.obs_property_list_add_string(p_source_list, "", "")
            for _, name in ipairs(dyn_source_names) do
                obs.obs_property_list_add_string(p_source_list, name, name)
            end
            
            obs.obs_property_set_visible(obs.obs_properties_get(props, "g_speed_x_" .. i), visible)
            obs.obs_property_set_visible(obs.obs_properties_get(props, "g_speed_y_" .. i), visible)
            
            if visible and is_advanced then
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_auto_color_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_color_mode_" .. i), true)
                local cmode = obs.obs_data_get_int(settings, "g_color_mode_" .. i)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_fixed_color_" .. i), (cmode == 1))
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_x_" .. i), true)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_y_" .. i), true)
            elseif visible and not is_advanced then
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_auto_color_" .. i), true)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_color_mode_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_fixed_color_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_x_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_y_" .. i), false)
            else
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_auto_color_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_color_mode_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_fixed_color_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_x_" .. i), false)
                obs.obs_property_set_visible(obs.obs_properties_get(props, "g_dir_y_" .. i), false)
            end
        end
        return true
    end

    obs.obs_property_set_modified_callback(p_count, refresh_ui)
    obs.obs_property_set_modified_callback(p_show_all, refresh_ui)
    obs.obs_property_set_modified_callback(p_advanced, refresh_ui)
    
    for i = 1, MAX_GLOBAL_SOURCES do
        local p_active = obs.obs_properties_add_bool(props, "g_active_" .. i, "► Enable DVDifyer " .. i)
        
        local p_source = obs.obs_properties_add_list(props, "g_source_" .. i, "Select Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
        obs.obs_property_list_add_string(p_source, "", "")
        for _, name in ipairs(source_names) do
            obs.obs_property_list_add_string(p_source, name, name)
        end
        
        local p_sx = obs.obs_properties_add_float_slider(props, "g_speed_x_" .. i, "Horizontal Speed", 0.1, 50.0, 0.1)
        local p_sy = obs.obs_properties_add_float_slider(props, "g_speed_y_" .. i, "Vertical Speed", 0.1, 50.0, 0.1)
        
        local p_color = obs.obs_properties_add_bool(props, "g_auto_color_" .. i, "Auto Color Change")
        
        local p_cmode = obs.obs_properties_add_list(props, "g_color_mode_" .. i, "Color Behavior", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        obs.obs_property_list_add_int(p_cmode, "Random Colors on Hit", 0)
        obs.obs_property_list_add_int(p_cmode, "Fixed Custom Color", 1)
        obs.obs_property_list_add_int(p_cmode, "No Color Change", 2)
        obs.obs_property_set_modified_callback(p_cmode, refresh_ui)
        
        local p_fcolor = obs.obs_properties_add_color(props, "g_fixed_color_" .. i, "Select Target Color")
        
        local p_dir_x = obs.obs_properties_add_list(props, "g_dir_x_" .. i, "Start X Direction", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        obs.obs_property_list_add_int(p_dir_x, "Random", 0)
        obs.obs_property_list_add_int(p_dir_x, "Force Right", 1)
        obs.obs_property_list_add_int(p_dir_x, "Force Left", 2)
        
        local p_dir_y = obs.obs_properties_add_list(props, "g_dir_y_" .. i, "Start Y Direction", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        obs.obs_property_list_add_int(p_dir_y, "Random", 0)
        obs.obs_property_list_add_int(p_dir_y, "Force Down", 1)
        obs.obs_property_list_add_int(p_dir_y, "Force Up", 2)
        
        local visible = (i <= global_target_count)
        obs.obs_property_set_visible(p_active, visible)
        obs.obs_property_set_visible(p_source, visible)
        obs.obs_property_set_visible(p_sx, visible)
        obs.obs_property_set_visible(p_sy, visible)
        obs.obs_property_set_visible(p_color, visible)
        obs.obs_property_set_visible(p_cmode, false)
        obs.obs_property_set_visible(p_fcolor, false)
        obs.obs_property_set_visible(p_dir_x, false)
        obs.obs_property_set_visible(p_dir_y, false)
    end
    
    obs.obs_properties_add_button(props, "g_reset_btn", "Reset All Positions", function(properties, property)
        local current_scene_source = obs.obs_frontend_get_current_scene()
        if not current_scene_source then return true end
        local scene = obs.obs_scene_from_source(current_scene_source)
        if not scene then
            obs.obs_source_release(current_scene_source)
            return true
        end

        for i = 1, MAX_GLOBAL_SOURCES do
            local gd = global_targets[i]
            if gd.initialized and gd.source_name and gd.source_name ~= "" then
                local scene_item = find_scene_item_recursive(scene, gd.source_name)
                if scene_item then
                    local pos = obs.vec2()
                    pos.x = gd.og_raw_x
                    pos.y = gd.og_raw_y
                    obs.obs_sceneitem_set_pos(scene_item, pos)
                end
            end
        end
        obs.obs_source_release(current_scene_source)
        return true
    end)
    
    return props
end

function script_update(settings)
    global_target_count = obs.obs_data_get_int(settings, "g_count")
    if global_target_count < 1 then global_target_count = 1 end
    current_show_all = obs.obs_data_get_bool(settings, "g_show_all")
    local is_advanced = obs.obs_data_get_bool(settings, "g_advanced")
    
    for i = 1, MAX_GLOBAL_SOURCES do
        local gd = global_targets[i]
        gd.active = obs.obs_data_get_bool(settings, "g_active_" .. i)
        gd.source_name = obs.obs_data_get_string(settings, "g_source_" .. i)
        gd.speed_x = obs.obs_data_get_double(settings, "g_speed_x_" .. i)
        gd.speed_y = obs.obs_data_get_double(settings, "g_speed_y_" .. i)
        
        if is_advanced then
            gd.color_mode = obs.obs_data_get_int(settings, "g_color_mode_" .. i)
            gd.fixed_color = obs.obs_data_get_int(settings, "g_fixed_color_" .. i)
            gd.start_dir_x = obs.obs_data_get_int(settings, "g_dir_x_" .. i)
            gd.start_dir_y = obs.obs_data_get_int(settings, "g_dir_y_" .. i)
        else
            local auto_col = obs.obs_data_get_bool(settings, "g_auto_color_" .. i)
            gd.color_mode = auto_col and 0 or 2
            gd.start_dir_x = 0
            gd.start_dir_y = 0
        end
        
        if gd.last_source ~= gd.source_name then
            gd.initialized = false
            gd.last_source = gd.source_name
        end
    end
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "g_count", 1)
    obs.obs_data_set_default_bool(settings, "g_show_all", false)
    obs.obs_data_set_default_bool(settings, "g_advanced", false)
    
    for i = 1, MAX_GLOBAL_SOURCES do
        obs.obs_data_set_default_bool(settings, "g_active_" .. i, false)
        obs.obs_data_set_default_double(settings, "g_speed_x_" .. i, 5.0)
        obs.obs_data_set_default_double(settings, "g_speed_y_" .. i, 5.0)
        obs.obs_data_set_default_bool(settings, "g_auto_color_" .. i, true)
        obs.obs_data_set_default_int(settings, "g_color_mode_" .. i, 0)
        obs.obs_data_set_default_int(settings, "g_fixed_color_" .. i, 4278190335)
        obs.obs_data_set_default_int(settings, "g_dir_x_" .. i, 0)
        obs.obs_data_set_default_int(settings, "g_dir_y_" .. i, 0)
    end
end

local function main_bounce_loop()
    local has_globals = false
    for i = 1, MAX_GLOBAL_SOURCES do
        if global_targets[i].active then has_globals = true; break end
    end
    
    if not has_globals then return end

    local current_scene_source = obs.obs_frontend_get_current_scene()
    if not current_scene_source then return end

    local scene = obs.obs_scene_from_source(current_scene_source)
    if not scene then
        obs.obs_source_release(current_scene_source)
        return
    end

    local canvas_w = 1920
    local canvas_h = 1080
    
    local ovi = obs.obs_video_info()
    obs.obs_get_video_info(ovi) 
    if ovi.base_width > 0 then canvas_w = ovi.base_width end
    if ovi.base_height > 0 then canvas_h = ovi.base_height end

    local scene_w = obs.obs_source_get_width(current_scene_source)
    local scene_h = obs.obs_source_get_height(current_scene_source)
    if scene_w > 0 then canvas_w = scene_w end
    if scene_h > 0 then canvas_h = scene_h end

    local bounce_tasks = {}

    for i = 1, MAX_GLOBAL_SOURCES do
        local gd = global_targets[i]
        if gd.active and gd.source_name and gd.source_name ~= "" then
            local scene_item = find_scene_item_recursive(scene, gd.source_name)
            if scene_item then
                local source = obs.obs_sceneitem_get_source(scene_item)
                if source then
                    table.insert(bounce_tasks, { data = gd, scene_item = scene_item, source = source })
                end
            end
        end
    end

    for _, task in ipairs(bounce_tasks) do
        local data = task.data
        local scene_item = task.scene_item
        local parent = task.source

        local current_pos = obs.vec2()
        obs.obs_sceneitem_get_pos(scene_item, current_pos)
        
        local current_scale = obs.vec2()
        obs.obs_sceneitem_get_scale(scene_item, current_scale)
        
        local bounds = obs.vec2()
        obs.obs_sceneitem_get_bounds(scene_item, bounds)
        local bounds_type = obs.obs_sceneitem_get_bounds_type(scene_item)
        
        local align = obs.obs_sceneitem_get_alignment(scene_item)
        if not align or align == 0 then align = 0 end

        local base_w = obs.obs_source_get_width(parent)
        local base_h = obs.obs_source_get_height(parent)
        
        local crop = obs.obs_sceneitem_crop()
        if crop then
            obs.obs_sceneitem_get_crop(scene_item, crop)
            base_w = base_w - crop.left - crop.right
            base_h = base_h - crop.top - crop.bottom
        end
        
        local item_w = math.abs(base_w * current_scale.x)
        local item_h = math.abs(base_h * current_scale.y)

        if bounds_type ~= 0 then 
            item_w = math.abs(bounds.x)
            item_h = math.abs(bounds.y)
        end

        local function has_flag(val, flag)
            if bit and bit.band then
                return bit.band(val, flag) == flag
            else
                return (math.floor(val / flag) % 2) == 1
            end
        end

        local origin_x = item_w / 2
        local origin_y = item_h / 2

        if has_flag(align, 1) then origin_x = 0
        elseif has_flag(align, 2) then origin_x = item_w end

        if has_flag(align, 4) then origin_y = 0
        elseif has_flag(align, 8) then origin_y = item_h end

        if not data.initialized then
            data.og_raw_x = current_pos.x
            data.og_raw_y = current_pos.y
            
            if data.start_dir_x == 1 then data.vel_x = math.abs(data.vel_x)
            elseif data.start_dir_x == 2 then data.vel_x = -math.abs(data.vel_x) end
            
            if data.start_dir_y == 1 then data.vel_y = math.abs(data.vel_y)
            elseif data.start_dir_y == 2 then data.vel_y = -math.abs(data.vel_y) end
            
            data.initialized = true
        end

        local tl_x = -origin_x
        local tl_y = -origin_y
        local tr_x = item_w - origin_x
        local tr_y = -origin_y
        local bl_x = -origin_x
        local bl_y = item_h - origin_y
        local br_x = item_w - origin_x
        local br_y = item_h - origin_y

        local rot = obs.obs_sceneitem_get_rot(scene_item)
        local rad = math.rad(rot)
        local cos_r = math.cos(rad)
        local sin_r = math.sin(rad)

        local function rot_pt(x, y)
            return x * cos_r - y * sin_r, x * sin_r + y * cos_r
        end

        local r1x, r1y = rot_pt(tl_x, tl_y)
        local r2x, r2y = rot_pt(tr_x, tr_y)
        local r3x, r3y = rot_pt(bl_x, bl_y)
        local r4x, r4y = rot_pt(br_x, br_y)

        local min_x = math.min(r1x, r2x, r3x, r4x)
        local max_x = math.max(r1x, r2x, r3x, r4x)
        local min_y = math.min(r1y, r2y, r3y, r4y)
        local max_y = math.max(r1y, r2y, r3y, r4y)
        
        local obj_w = max_x - min_x
        local obj_h = max_y - min_y

        local next_x = current_pos.x + (data.speed_x * data.vel_x)
        local next_y = current_pos.y + (data.speed_y * data.vel_y)
        local bounced = false

        if obj_w <= canvas_w then
            if (next_x + min_x) <= 0 then
                next_x = -min_x
                data.vel_x = math.abs(data.vel_x)
                bounced = true
            elseif (next_x + max_x) >= canvas_w then
                next_x = canvas_w - max_x
                data.vel_x = -math.abs(data.vel_x)
                bounced = true
            end
        else
            if (next_x + min_x) >= 0 then
                next_x = -min_x
                data.vel_x = -math.abs(data.vel_x)
                bounced = true
            elseif (next_x + max_x) <= canvas_w then
                next_x = canvas_w - max_x
                data.vel_x = math.abs(data.vel_x)
                bounced = true
            end
        end

        if obj_h <= canvas_h then
            if (next_y + min_y) <= 0 then
                next_y = -min_y
                data.vel_y = math.abs(data.vel_y)
                bounced = true
            elseif (next_y + max_y) >= canvas_h then
                next_y = canvas_h - max_y
                data.vel_y = -math.abs(data.vel_y)
                bounced = true
            end
        else
            if (next_y + min_y) >= 0 then
                next_y = -min_y
                data.vel_y = -math.abs(data.vel_y)
                bounced = true
            elseif (next_y + max_y) <= canvas_h then
                next_y = canvas_h - max_y
                data.vel_y = math.abs(data.vel_y)
                bounced = true
            end
        end

        current_pos.x = next_x
        current_pos.y = next_y
        obs.obs_sceneitem_set_pos(scene_item, current_pos)

        if bounced and data.color_mode ~= 2 then
            local color_filter = obs.obs_source_get_filter_by_name(parent, "DVD Color")
            
            if not color_filter then
                local f_settings = obs.obs_data_create()
                color_filter = obs.obs_source_create_private("color_filter_v2", "DVD Color", f_settings)
                obs.obs_source_filter_add(parent, color_filter)
                obs.obs_data_release(f_settings)
            end

            if color_filter then
                local final_color = 0xFFFFFFFF
                
                if data.color_mode == 0 then
                    local r = math.random(50, 255)
                    local g = math.random(50, 255)
                    local b = math.random(50, 255)
                    final_color = 4278190080 + (b * 65536) + (g * 256) + r
                elseif data.color_mode == 1 then
                    final_color = data.fixed_color
                end

                local c_settings = obs.obs_data_create()
                obs.obs_data_set_int(c_settings, "color_multiply", final_color)
                obs.obs_source_update(color_filter, c_settings)
                obs.obs_data_release(c_settings)
                obs.obs_source_release(color_filter)
            end
        end
    end

    obs.obs_source_release(current_scene_source)
end

obs.timer_add(main_bounce_loop, 16)
