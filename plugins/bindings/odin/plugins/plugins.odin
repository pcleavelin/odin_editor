package editor_plugins

PluginInfo :: struct {
    name: string,
    identifier: string,
    version: PluginVersion,
}

PluginVersion :: struct {
    major: u32,
    minor: u32,
}

