local BufferSearchOpen = false
local BufferSearchOpenElapsed = 0

local CurrentPreviewBufferIndex = Editor.get_current_buffer_index()
local BufferSearchIndex = 0

local SideBarWidth = 128

function buffer_list_iter()
    local idx = 0
    return function ()
        buffer_info = Editor.buffer_info_from_index(idx)
        idx = idx + 1

        return buffer_info, idx-1
    end
end

function centered(ctx, label, axis, width, height, body)
    UI.push_parent(ctx, UI.push_rect(ctx, label, false, false, UI.Horizontal, UI.Fill, UI.Fill))
        UI.spacer(ctx, "left spacer")
        UI.push_parent(ctx, UI.push_rect(ctx, "halfway centered", false, false, UI.Vertical, width, UI.Fill))
            UI.spacer(ctx, "top spacer")
            UI.push_parent(ctx, UI.push_rect(ctx, "centered container", false, false, axis, UI.Fill, height))
                body()
            UI.pop_parent(ctx)
            UI.spacer(ctx, "bottom spacer")
        UI.pop_parent(ctx)
        UI.spacer(ctx, "right spacer")
    UI.pop_parent(ctx)
end

function render_ui_window(ctx)
    current_buffer_index = Editor.get_current_buffer_index()

    numFrames = 7
    CurrentPreviewBufferIndex = current_buffer_index

    tabs = UI.push_rect(ctx, "tabs", false, false, UI.Vertical, UI.Exact(SideBarWidth), UI.Fill)
    UI.push_parent(ctx, tabs)
        UI.push_rect(ctx, "padded top open files", false, false, UI.Horizontal, UI.Fill, UI.Exact(8))
        UI.push_parent(ctx, UI.push_rect(ctx, "padded open files", false, false, UI.Horizontal, UI.Fill, UI.ChildrenSum))
            UI.push_rect(ctx, "padded top open files", false, false, UI.Horizontal, UI.Exact(8), UI.Fill)
            UI.label(ctx, "Open Files")
        UI.pop_parent(ctx)
        UI.push_rect(ctx, "padded bottom open files", false, false, UI.Horizontal, UI.Fill, UI.Exact(8))

        for buffer_info, i in buffer_list_iter() do
            button_container = UI.push_rect(ctx, "button container"..i, false, false, UI.Horizontal, UI.Fill, UI.ChildrenSum)
            UI.push_parent(ctx, button_container)
                flags = {"Clickable", "Hoverable", "DrawText"}
                if i == current_buffer_index then
                    table.insert(flags, 1, "DrawBackground")
                end

                if UI.advanced_button(ctx, " x ", flags, UI.FitText, UI.FitText).clicked then
                    print("hahah, you can't close buffers yet silly")
                end

                tab_button_interaction = UI.advanced_button(ctx, " "..buffer_info.file_path.." ", flags, UI.Fill, UI.FitText)
                if tab_button_interaction.clicked then
                    Editor.set_current_buffer_from_index(i)
                end
                if tab_button_interaction.hovering then
                    CurrentPreviewBufferIndex = i
                end
            UI.pop_parent(ctx)
        end
        UI.spacer(ctx, "below tabs spacer")

    UI.pop_parent(ctx)
    if UI.advanced_button(ctx, "side bar grab handle", {"DrawBorder", "Hoverable"}, UI.Exact(16), UI.Fill).dragging  then
        x,y = UI.get_mouse_pos(ctx)
        SideBarWidth = x-8

        -- TODO: use some math.max function
        if SideBarWidth < 128 then
            SideBarWidth = 128
        end
    end
    UI.buffer(ctx, CurrentPreviewBufferIndex)

    render_buffer_search(ctx)
end

function render_buffer_search(ctx)
    if BufferSearchOpen or BufferSearchOpenElapsed > 0 then
        if BufferSearchOpen and BufferSearchOpenElapsed < numFrames then
            BufferSearchOpenElapsed = BufferSearchOpenElapsed + 1
        elseif not BufferSearchOpen and BufferSearchOpenElapsed > 0 then
            BufferSearchOpenElapsed = BufferSearchOpenElapsed - 1
        end
    end

    if BufferSearchOpen or BufferSearchOpenElapsed > 0 then
        window_percent = 75
        if BufferSearchOpenElapsed > 0 then
            window_percent = ((BufferSearchOpenElapsed/numFrames) * 75)
        end

        UI.push_parent(ctx, UI.push_floating(ctx, "buffer search canvas", 0, 0))
            centered(ctx, "buffer search window", UI.Horizontal, UI.PercentOfParent(window_percent), UI.PercentOfParent(window_percent), (
                function ()
                    UI.push_parent(ctx, UI.push_rect(ctx, "window", true, true, UI.Horizontal, UI.Fill, UI.Fill))
                        UI.push_parent(ctx, UI.push_rect(ctx, "buffer list", false, false, UI.Vertical, UI.Fill, UI.Fill))
                            for buffer_info, i in buffer_list_iter() do
                                flags = {"DrawText"}

                                if i == BufferSearchIndex then
                                    table.insert(flags, 1, "DrawBorder")
                                end
                                interaction = UI.advanced_button(ctx, " "..buffer_info.file_path.." ", flags, UI.Fill, UI.FitText)
                            end
                        UI.pop_parent(ctx)
                        UI.buffer(ctx, BufferSearchIndex)
                    UI.pop_parent(ctx)
                end
            ))
        UI.pop_parent(ctx)
    end
end

function handle_buffer_input()
    -- print("you inputted into a buffer")
end

function OnInit()
    print("Main View plugin initialized")
    Editor.register_key_group({
        {Editor.Key.Space, "", {
            {Editor.Key.B, "Buffer Search", (
                function ()
                    BufferSearchOpen = true
                    BufferSearchIndex = 0
                end
            ),
            {
                {Editor.Key.Escape, "Close Window", (
                    function ()
                        Editor.request_window_close()
                        BufferSearchOpen = false
                    end
                )},
                {Editor.Key.Enter, "Switch to Buffer", (
                    function ()
                        Editor.set_current_buffer_from_index(BufferSearchIndex)
                        Editor.request_window_close()
                        BufferSearchOpen = false
                    end
                )},
                -- TODO: don't scroll past buffers
                {Editor.Key.K, "Move Selection Up", (function () BufferSearchIndex = BufferSearchIndex - 1 end)},
                {Editor.Key.J, "Move Selection Down", (function () BufferSearchIndex = BufferSearchIndex + 1 end)},
            }}
        }}
    })

    Editor.register_hook(Editor.Hook.OnDraw, render_ui_window)
    Editor.register_hook(Editor.Hook.OnBufferInput, handle_buffer_input)
end
