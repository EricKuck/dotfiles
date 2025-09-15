local hyper = {"ctrl", "alt", "cmd", "shift"}

-- Reload automatically on config changes
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()
hs.alert.show("🔨🥄 config loaded")

-- Hotkeys
hs.hotkey.bind({"ctrl", "cmd"}, "h", hs.reload) -- Reload config
hs.hotkey.bind(hyper, "a", function() hs.eventtap.keyStroke({"ctrl", "cmd", "shift"}, "4") end) -- Screenshot
hs.hotkey.bind("cmd", "\\", function() hs.application.launchOrFocus("Bitwarden") end) -- Show bitwarden

-- Force paste
hs.hotkey.bind(hyper, "v", function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

-- Turn on/off office light when plugged/unplugged from dock
usbWatcher = hs.usb.watcher.new(function(data)
  if data.vendorName == "CalDigit, Inc" then
    if data.eventType == "added" then
      hs.execute("curl mqtt://192.168.1.2:1883/zigbee2mqtt/Office%20Desk%20Lamp/set --user $(cat /run/secrets/mqtt_creds) --request PUBLISH --data '{\"state\":\"ON\"}'")
    elseif data.eventType == "removed" then
      hs.execute("curl mqtt://192.168.1.2:1883/zigbee2mqtt/Office%20Desk%20Lamp/set --user $(cat /run/secrets/mqtt_creds) --request PUBLISH --data '{\"state\":\"OFF\"}'")
    end
  end
end)
usbWatcher:start()

-- Turn on/off camera lighting when camera turns on/off
function setLightState()
  local cameraInUse = false
  for k, camera in pairs(hs.camera.allCameras()) do
    if camera:isInUse() then
      cameraInUse = true
      break
    end
  end

  if (cameraInUse) then
    hs.execute("/run/current-system/sw/bin/litra on")
  else
    hs.execute("/run/current-system/sw/bin/litra off")
  end
end

function setupCameraPropertyWatcher(camera)
  if camera:isPropertyWatcherRunning() then
    camera:stopPropertyWatcher()
  end

  camera:setPropertyWatcherCallback(function(camera, property, scope, element)
    if camera:isInUse() then
      setLightState()
    else
      -- Handle the case where we're actually just switching cameras with a slight delay
      hs.timer.doAfter(0.5, setLightState)
    end
  end)
  camera:startPropertyWatcher()
end

for k, camera in pairs(hs.camera.allCameras()) do
  setupCameraPropertyWatcher(camera)
end

hs.camera.setWatcherCallback(function(camera, state)
  if state == "Added" then
    setupCameraPropertyWatcher(camera)
  end
  toggleLights()
end)
hs.camera.startWatcher()
