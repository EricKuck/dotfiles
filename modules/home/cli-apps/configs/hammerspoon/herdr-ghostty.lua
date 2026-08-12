local DEBUG = false
local log = hs.logger.new("herdr-router")

local GHOSTTY_PID_QUERY   = 'tell application "Ghostty" to get pid of focused terminal of selected tab of front window'
local GHOSTTY_TITLE_QUERY = 'tell application "Ghostty" to get name of focused terminal of selected tab of front window'

local function trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Locate the herdr binary: PATH first, then common install locations.
local function findHerdr()
    local out, ok = hs.execute("/usr/bin/env bash -lc 'command -v herdr' 2>/dev/null", true)
    if ok and out and tostring(out):match("herdr") then
        return trim(tostring(out))
    end
    local candidates = {
        "/Users/eric/.nix-profile/bin/herdr",
        "/opt/homebrew/bin/herdr",
        "/usr/local/bin/herdr",
        "/Users/eric/.local/bin/herdr",
    }
    for _, c in ipairs(candidates) do
        local t, ok2 = hs.execute("/bin/test -x " .. c .. " && echo yes", true)
        if ok2 and t and tostring(t):match("yes") then return c end
    end
    local glob, ok3 = hs.execute("/bin/ls -d /opt/homebrew/Cellar/herdr/*/bin/herdr 2>/dev/null | /usr/bin/tail -1", true)
    if ok3 and glob and tostring(glob):match("herdr") then
        return trim(tostring(glob))
    end
    return nil
end

local HERDR = findHerdr()

-- returns true/false; alerts in DEBUG mode so failures are visible
local function isHerdrForeground()
    -- attempt 1: exact foreground PID (Ghostty builds with pid support)
    local ok1, pidRes = hs.applescript.applescript(GHOSTTY_PID_QUERY)
    if ok1 and pidRes then
        local p = tostring(pidRes):match("^%d+$")
        if p then
            local out, psok = hs.execute("/bin/ps -p " .. p .. " -o comm=", true)
            if psok then
                local isHerdr = tostring(out):match("^herdr") ~= nil
                if DEBUG then hs.alert.show("cmd+? → " .. (isHerdr and "herdr (pid " .. p .. ")" or "other (pid " .. p .. ")")) end
                return isHerdr
            end
        end
    end

    -- attempt 2: terminal title is "herdr"
    local ok2, titleRes = hs.applescript.applescript(GHOSTTY_TITLE_QUERY)
    if ok2 and titleRes then
        local title = trim(tostring(titleRes))
        local isHerdr = title == "herdr" or title:match("^herdr[%s%.:%-—]") ~= nil
        if DEBUG then
            hs.alert.show("cmd+? → " .. (isHerdr and "herdr (title: '" .. title .. "')" or "other (title: '" .. title .. "')"))
        end
        return isHerdr
    end

    if DEBUG then hs.alert.show("herdr-router: both detections failed — check Automation permission & that Ghostty is frontmost") end
    return false
end

local function ghosttyNewTab()
    hs.applescript.applescript([[
        tell application "Ghostty"
            set w to front window
            new tab in w
        end tell]])
end

local function ghosttySplit(dir)
    hs.applescript.applescript(string.format([[
        tell application "Ghostty"
            set t to focused terminal of selected tab of front window
            split t direction %s
        end tell]], dir))
end

local function herdrCommand(action)
    if not HERDR then
        if DEBUG then hs.alert.show("herdr-router: herdr binary not found — routed to Ghostty instead") end
        return false
    end
    local cmd
    if action == "tab" then
        cmd = HERDR .. " tab create --focus"
    elseif action == "split-right" then
        cmd = HERDR .. " pane split --direction right --focus"
    else
        cmd = HERDR .. " pane split --direction down --focus"
    end
    hs.execute(cmd, true)
    return true
end

-- cmd+w in herdr: close the focused split if the tab has splits, else the tab.
local function herdrClose()
    if not HERDR then
        if DEBUG then hs.alert.show("herdr-close: herdr binary not found") end
        return
    end

    local out, ok = hs.execute(HERDR .. " tab list", true)
    if not ok or not out then
        if DEBUG then hs.alert.show("herdr-close: tab list failed") end
        return
    end
    local data = hs.json.decode(tostring(out))
    if not data or not data.result or not data.result.tabs then
        if DEBUG then hs.alert.show("herdr-close: bad tab list response") end
        return
    end

    local focused
    for _, t in ipairs(data.result.tabs) do
        if t.focused then focused = t; break end
    end
    if not focused then
        if DEBUG then hs.alert.show("herdr-close: no focused tab") end
        return
    end

    if focused.pane_count and focused.pane_count > 1 then
        -- close the focused split: find the UI-focused pane in this tab
        local pout, pok = hs.execute(HERDR .. " pane list", true)
        local pid
        if pok and pout then
            local pdata = hs.json.decode(tostring(pout))
            if pdata and pdata.result and pdata.result.panes then
                for _, p in ipairs(pdata.result.panes) do
                    if p.focused and p.tab_id == focused.tab_id then
                        pid = p.pane_id
                        break
                    end
                end
            end
        end
        if pid then
            if DEBUG then hs.alert.show("cmd+w → herdr: close split " .. pid) end
            hs.execute(HERDR .. " pane close " .. pid, true)
        elseif DEBUG then
            hs.alert.show("cmd+w → herdr: no focused pane in tab " .. focused.tab_id)
        end
    else
        if DEBUG then hs.alert.show("cmd+w → herdr: close tab " .. focused.tab_id) end
        hs.execute(HERDR .. " tab close " .. focused.tab_id, true)
    end
end

local function route(action)
    local ok, err = pcall(function()
        if isHerdrForeground() then
            herdrCommand(action)
        else
            if action == "tab" then
                ghosttyNewTab()
            else
                ghosttySplit(action == "split-right" and "right" or "down")
            end
        end
    end)
    if not ok then
        hs.alert.show("herdr-router ERROR: " .. tostring(err))
        log.e("route error: %s", tostring(err))
    end
end

-- macOS virtual key codes: T = 17, P = 35, W = 13
local T_KEY, P_KEY, W_KEY = 17, 35, 13

if _G.herdrGhosttyTap then _G.herdrGhosttyTap:stop() end

_G.herdrGhosttyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    local mods = e:getFlags()
    -- only cmd (optionally + shift), never ctrl/alt (keeps hyper combos intact)
    if not (mods.cmd and not mods.ctrl and not mods.alt) then return nil end

    local key = e:getKeyCode()

    -- cmd+w: consume ONLY when herdr is foreground; otherwise pass through so
    -- Ghostty closes split/tab/window natively.
    if key == W_KEY and not mods.shift then
        local app = hs.application.frontmostApplication()
        if not app or app:name() ~= "Ghostty" then return nil end
        if isHerdrForeground() then
            hs.timer.doAfter(0, herdrClose)
            return true
        end
        return nil
    end

    local action
    if key == T_KEY and not mods.shift then
        action = "tab"
    elseif key == P_KEY and not mods.shift then
        action = "split-right"
    elseif key == P_KEY and mods.shift then
        action = "split-down"
    end
    if not action then return nil end

    local app = hs.application.frontmostApplication()
    if not app or app:name() ~= "Ghostty" then return nil end

    -- consume the key and route (deferred so the eventtap stays responsive)
    hs.timer.doAfter(0, function() route(action) end)
    return true
end)

_G.herdrGhosttyTap:start()

if not _G.herdrGhosttyTap:isEnabled() then
    hs.alert.show("herdr-router: eventtap FAILED — grant Hammerspoon Accessibility permission (System Settings → Privacy & Security → Accessibility), then reload")
elseif DEBUG then
    hs.alert.show("herdr-router v6: loaded (herdr at " .. tostring(HERDR or "NOT FOUND") .. ")")
end
