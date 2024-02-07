print("Hello from lua from a file!")

local WindowOpen = false

function render_ui_window(ctx)
    if WindowOpen then
        canvas = UI.push_floating(ctx, "lua canvas", 0, 0)
        UI.push_parent(ctx, canvas)
            window = UI.push_rect(ctx, "fullscreen window", true, true, UI.Vertical, UI.Fill, UI.Fill)
            UI.push_parent(ctx, window)
                if UI.button(ctx, "Click me!").clicked then
                    print("you clicked me!")
                end
                if UI.button(ctx, "I am lua").clicked then
                    print("you clicked me!")
                end
                if UI.button(ctx, "This is another button").clicked then
                    print("you clicked me!")
                end
                if UI.button(ctx, "if the names of these are the same it will seg fault").clicked then
                    print("you clicked me!")
                end
                if UI.button(ctx, "Click me! 2").clicked then
                    print("you clicked me!")
                end
            UI.pop_parent(ctx)
        UI.pop_parent(ctx)
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
