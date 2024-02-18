local BufferSearchOpen = false
local BufferSearchOpenElapsed = 0

local CurrentPreviewBufferIndex = Editor.get_current_buffer_index()
local BufferSearchIndex = 0

local SideBarSmoothedWidth = 128
local SideBarWidth = 128
local SideBarClosed = false

local ActiveCodeView = nil
local CodeViews = {}

local MovingTab = nil
local MovingTabDest = nil

local LastMouseX = 0
local LastMouseY = 0

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

function lerp(from, to, rate)
    return (1 - rate) * from + rate*to
end

function remove_buffer_from_code_view(code_view_index, file_path)
    if code_view_index ~= nil and CodeViews[code_view_index] ~= nil then
        CodeViews[code_view_index].tabs[file_path] = nil
        k,v = pairs(CodeViews[code_view_index].tabs)(CodeViews[code_view_index].tabs)
        CodeViews[code_view_index].current_tab = k
    end
end

function add_buffer_to_code_view(code_view_index, file_path, buffer_index)
    if code_view_index == nil then
        code_view_index = 1
        ActiveCodeView = 1
    end

    -- A new code view is being created
    if CodeViews[code_view_index] == nil then
        CodeViews[code_view_index] = {}
        CodeViews[code_view_index].tabs = {}
        CodeViews[code_view_index].width = UI.Fill
    end

    ActiveCodeView = code_view_index

    CodeViews[code_view_index].tabs[file_path] = {}
    CodeViews[code_view_index].tabs[file_path].buffer_index = buffer_index
    CodeViews[code_view_index].current_tab = file_path
end

function ui_sidebar(ctx)
    SideBarSmoothedWidth = lerp(SideBarSmoothedWidth, SideBarWidth, 0.3)

    tabs, _ = UI.push_rect(ctx, "for some reason it chooses this as the parent", false, false, UI.Vertical, UI.Exact(SideBarSmoothedWidth), UI.Fill)
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
                    Editor.set_current_buffer_from_index(i)
                    add_buffer_to_code_view(ActiveCodeView+1, buffer_info.file_path, i)
                end

                tab_button_interaction = UI.advanced_button(ctx, " "..buffer_info.file_path.." ", flags, UI.Fill, UI.FitText)
                if tab_button_interaction.clicked then
                    Editor.set_current_buffer_from_index(i)
                    add_buffer_to_code_view(ActiveCodeView, buffer_info.file_path, i)
                end
                if tab_button_interaction.hovering then
                    CurrentPreviewBufferIndex = i
                end
            UI.pop_parent(ctx)
        end
        UI.spacer(ctx, "below tabs spacer")

    UI.pop_parent(ctx)
end

function ui_code_view(ctx, code_view_index)
    local code_view = CodeViews[code_view_index]
    local is_tab_dest = MovingTab ~= nil and ActiveCodeView ~= code_view_index

    code_view_rect, code_view_interaction = UI.push_rect(ctx, code_view_index.." code view", ActiveCodeView ~= code_view_index, true, UI.Vertical, code_view.width, UI.Fill)

    UI.push_parent(ctx, code_view_rect)
        tab_dest_flags = {}
        if is_tab_dest then tab_dest_flags = {"Hoverable"} end

        tab_dest_region, tab_dest_interaction = UI.push_box(ctx, "code view tab dest", tab_dest_flags, UI.Vertical, UI.Fill, UI.Fill)
        UI.push_parent(ctx, tab_dest_region)
            if is_tab_dest then
                if tab_dest_interaction.hovering then
                    MovingTabDest = code_view_index
                end
            end

            UI.push_parent(ctx, UI.push_rect(ctx, "tabs", false, false, UI.Horizontal, UI.Fill, UI.ChildrenSum))
                for k,v in pairs(code_view.tabs) do
                    show_border = k ~= code_view.current_tab
                    background = show_border
                    flags = {"Clickable", "DrawText"}
                    if show_border then
                        table.insert(flags, 1, "DrawBorder")
                        table.insert(flags, 1, "Hoverable")
                    end

                    UI.push_parent(ctx, UI.push_rect(ctx, k.." tab container", background, false, UI.Horizontal, UI.ChildrenSum, UI.ChildrenSum))
                        tab_button = UI.advanced_button(ctx, " "..k.." ", flags, UI.FitText, UI.Exact(32))
                        if tab_button.clicked or tab_button.dragging then
                            ActiveCodeView = code_view_index
                            code_view.current_tab = k

                            Editor.set_current_buffer_from_index(v["buffer_index"])
                        end

                        if tab_button.dragging then
                            if MovingTab == nil then
                                MovingTab = {}
                                MovingTab["code_view_index"] = code_view_index
                                MovingTab["tab"] = k
                            end

                            UI.push_parent(ctx, UI.push_floating(ctx, "dragging tab", x-(96/2), y-(32/2)))
                                UI.advanced_button(ctx, " "..k.." ", {"DrawText", "DrawBorder", "DrawBackground"}, UI.FitText, UI.Exact(32))
                            UI.pop_parent(ctx)
                        elseif MovingTab ~= nil and MovingTab["code_view_index"] == code_view_index and MovingTab["tab"] == k then
                            if MovingTabDest ~= nil then
                                add_buffer_to_code_view(MovingTabDest, k, v["buffer_index"])
                                remove_buffer_from_code_view(code_view_index, k)

                                MovingTabDest = nil
                            end

                            MovingTab = nil
                        end
                    UI.pop_parent(ctx)
                end
            UI.pop_parent(ctx)

            current_tab = code_view.current_tab
            if code_view.tabs[current_tab] ~= nil then
                buffer_index = code_view.tabs[current_tab].buffer_index

                UI.buffer(ctx, buffer_index)
            end

        UI.pop_parent(ctx)
    UI.pop_parent(ctx)

    return code_view_interaction
end

function render_ui_window(ctx)
    current_buffer_index = Editor.get_current_buffer_index()
    x,y = UI.get_mouse_pos(ctx)
    delta_x = LastMouseX - x
    delta_y = LastMouseY - y

    numFrames = 7
    CurrentPreviewBufferIndex = current_buffer_index

    if not SidebarClosed or SideBarSmoothedWidth > 2 then
        ui_sidebar(ctx)
    end
    if UI.advanced_button(ctx, "side bar grab handle", {"DrawBorder", "Hoverable"}, UI.Exact(16), UI.Fill).dragging then
        SideBarWidth = x-8

        if SideBarWidth < 32 then
            SidebarClosed = true
            SideBarWidth = 0
        elseif SideBarWidth > 128 then
            SidebarClosed = false
        end

        -- TODO: use some math.max function
        if not SidebarClosed and SideBarWidth < 128 then
            SideBarWidth = 128
        end
    end

    for k,v in ipairs(CodeViews) do
        code_view_interaction = ui_code_view(ctx, k)

        if next(CodeViews, k) ~= nil then
            interaction = UI.advanced_button(ctx, k.."code view grab handle", {"DrawBorder", "Hoverable"}, UI.Exact(16), UI.Fill)
            if interaction.dragging then
                local width = math.max(32, x - code_view_interaction.box_pos.x)
                v.width = UI.Exact(width)
            elseif interaction.clicked then
                v.width = UI.Fill
            end
        else
            v.width = UI.Fill
        end
    end

    for k,v in ipairs(CodeViews) do
        if next(v.tabs) == nil then
            table.remove(CodeViews, k)

            if ActiveCodeView > k then
                ActiveCodeView = ActiveCodeView - 1
            end
        end
    end

    render_buffer_search(ctx)

    LastMouseX = x
    LastMouseY = y
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
                        buffer_info = Editor.buffer_info_from_index(BufferSearchIndex)
                        add_buffer_to_code_view(ActiveCodeView, buffer_info.file_path, BufferSearchIndex)

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
