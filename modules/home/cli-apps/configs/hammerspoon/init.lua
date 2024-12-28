local hyper = {'ctrl', 'alt', 'cmd', 'shift'}

-- Reload automatically on config changes
hs.pathwatcher.new(os.getenv('HOME') .. '/.hammerspoon/', hs.reload):start()
hs.alert.show('🔨🥄 config loaded')
hs.hotkey.bind({'ctrl', 'cmd'}, 'h', hs.reload)

-- Launch/focus apps with one keystroke.
function launch(name, bundle)
    hs.application.launchOrFocus(name)
    hs.alert.showWithImage(name, hs.image.imageFromAppBundle(bundle), {atScreenEdge = 2}, 0.6)
 end

hs.hotkey.bind(hyper, 'a', function() launch('Android Studio', 'com.google.android.studio') end)
hs.hotkey.bind(hyper, 'b', function() launch('Arc', 'company.thebrowser.Browser') end)
hs.hotkey.bind(hyper, 'm', function() launch('Spotify', 'com.spotify.client') end)
hs.hotkey.bind(hyper, 's', function() launch('Slack', 'com.tinyspeck.slackmacgap') end)
hs.hotkey.bind(hyper, 't', function() launch('Ghostty', 'com.mitchellh.ghostty') end)

-- Force paste
hs.hotkey.bind(hyper, "v", function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

-- -- Pasteboard manager
-- ClipboardTool = hs.loadSpoon("ClipboardTool")
-- ClipboardTool.hist_size = 10
-- ClipboardTool.paste_on_select = true
-- ClipboardTool:start()
-- ClipboardTool:bindHotkeys({
--     toggle_clipboard = {{'cmd', 'shift'}, "v"}
-- })