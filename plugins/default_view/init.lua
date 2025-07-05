local M = {}

M.version = "0.1"
M.name = "Default_View"
M.namespace = "nl_spacegirl_plugin_Default"

M.BufferListPanel = {
    num_clicks = 0
}

M.SomeOtherPanel = {
    num_clicks_2 = 0
}

function M.BufferListPanel.new()
    local p = {}
    setmetatable(p, {__index = M.BufferListPanel})
    return p
end

function M.BufferListPanel:render(ctx)
    -- if UI.button(ctx, "Number of Clicks "..self.num_clicks).clicked then
    --     self.num_clicks = self.num_clicks + 1
    -- end
end

function M.SomeOtherPanel.new()
    local p = {}
    setmetatable(p, {__index = M.SomeOtherPanel})
    return p
end

function M.SomeOtherPanel:render(ctx)
    UI_New.open_element(ctx, "Number of Clicks", {
        dir = UI_New.LeftToRight,
        kind = {UI_New.Exact(128), UI_New.Exact(32)},
    })
    UI_New.close_element(ctx)

    UI_New.open_element(ctx, "Whatever man", {
            dir = UI_New.LeftToRight,
            kind = {UI_New.Fit, UI_New.Exact(32)},
        })
    UI_New.close_element(ctx)
end

function M.open_file_search_window()
    local input = {
        {Editor.Key.Enter, "Open File", function() Editor.log("this should open a file") end}
    }

    Editor.spawn_floating_window(input, function(ctx)
        UI.push_parent(ctx, UI.push_rect(ctx, "window", true, true, UI.Vertical, UI.Fill, UI.ChildrenSum))
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 1")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 2")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 3")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 4")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 5")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 6")
        UI.label(ctx, "eventually this will be a window where you can search through a bunch of files 7")
        UI.pop_parent(ctx)
    end)
end

function M.OnLoad()
    Editor.log("default view loaded")
    Editor.log(nl_spacegirl_plugin_Default_Legacy_View['namespace'])

    local a = M.BufferListPanel.new()
    local b = M.BufferListPanel.new()

    print(M.BufferListPanel)
    print(a)
    print(b)

    Editor.register_key_group({
        {Editor.Key.Space, "", {
            {Editor.Key.F, "Open File", M.open_file_search_window},
            {Editor.Key.J, "New Panel", function()
                Editor.run_command("nl.spacegirl.editor.core", "Open New Panel", "BufferListPanel")
            end},
            {Editor.Key.K, "Some Other Panel", function()
                Editor.run_command("nl.spacegirl.editor.core", "Open New Panel", "SomeOtherPanel")
            end}
        }},
    })

    Editor.register_panel("BufferList", "BufferListPanel")
    Editor.register_panel("aksjdhflkasjdf", "SomeOtherPanel")
end

function M.view_render(cx)
    UI.label(cx, "Look its a me, a plugin")
end

return M
