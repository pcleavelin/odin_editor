local WindowOpen = true

function buffer_list_iter()
    local idx = 0
    return function ()
        buffer_info = Editor.buffer_info_from_index(idx)
        idx = idx + 1

        return buffer_info, idx-1
    end
end

function render_ui_window(ctx)
    if WindowOpen then
        current_buffer_index = Editor.get_current_buffer_index()

        tabs = UI.push_rect(ctx, "tabs", false, true, UI.Vertical, UI.ChildrenSum, UI.Fill)
        UI.push_parent(ctx, tabs)
            for buffer_info, i in buffer_list_iter() do
                button_container = UI.push_rect(ctx, "button container"..i, false, false, UI.Horizontal, UI.ChildrenSum, UI.ChildrenSum)
                UI.push_parent(ctx, button_container)
                    flags = {"Clickable", "Hoverable", "DrawText", "DrawBackground"}
                    if i ~= current_buffer_index then
                        table.insert(flags, 1, "DrawBorder")
                    end

                    if UI.advanced_button(ctx, " "..buffer_info.file_path.." ", flags, UI.PercentOfParent(25), UI.FitText).clicked then
                         Editor.set_current_buffer_from_index(i)
                    end
                    if UI.advanced_button(ctx, " x ", flags, UI.FitText, UI.FitText).clicked then
                        print("hahah, you can't close buffers yet silly")
                    end
                UI.pop_parent(ctx)
            end
        UI.pop_parent(ctx)

        -- if Tabs[CurrentTab] ~= nil then
        UI.buffer(ctx, current_buffer_index)
        -- else
        --     UI.push_parent(ctx, UI.push_centered(ctx, "centered no files open", false, false, UI.Vertical, UI.Fill, UI.Fill))
        --         if UI.button(ctx, "Open File").clicked then
        --             Tabs[CurrentTab] = {0, "main.odin"}
        --         end
        --     UI.pop_parent(ctx)
        -- end
    end
end

function handle_buffer_input()
    print("you inputted into a buffer")
end

function OnInit()
    print("Test lua plugin initialized")
    Editor.register_key_group({
        {Editor.Key.T, "Open Test UI", (
            function ()
                WindowOpen = not WindowOpen
            end
        )},
    })

    Editor.register_hook(Editor.Hook.OnDraw, render_ui_window)
    Editor.register_hook(Editor.Hook.OnBufferInput, handle_buffer_input)
end
