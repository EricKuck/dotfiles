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
hs.hotkey.bind('cmd', '\\', function() hs.application.launchOrFocus('Bitwarden') end)

-- Force paste
hs.hotkey.bind(hyper, "v", function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

-- Turn on/off office light when plugged/unplugged from dock
function dockCallback(data)
  if data.vendorName == "CalDigit, Inc" then
    if data.eventType == "added" then
      hs.execute("curl mqtt://192.168.1.2:1883/zigbee2mqtt/Office%20Desk%20Lamp/set --user $(cat /run/secrets/mqtt_creds) --request PUBLISH --data '{\"state\":\"ON\"}'")
    elseif data.eventType == "removed" then
      hs.execute("curl mqtt://192.168.1.2:1883/zigbee2mqtt/Office%20Desk%20Lamp/set --user $(cat /run/secrets/mqtt_creds) --request PUBLISH --data '{\"state\":\"OFF\"}'")
    end
  end
end

usbWatcher = hs.usb.watcher.new(dockCallback)
usbWatcher:start()

