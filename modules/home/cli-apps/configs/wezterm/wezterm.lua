local wezterm = require 'wezterm'
local theme_name = 'Catppuccin Frappe'
local theme = wezterm.color.get_builtin_schemes()[theme_name]

local config = {
  color_scheme = theme_name,
  font = wezterm.font 'JetBrains Mono',
  font_size = 13,
  tab_bar_at_bottom = true,
  use_fancy_tab_bar = false,
  hide_tab_bar_if_only_one_tab = true,
  show_new_tab_button_in_tab_bar = false,
  window_decorations = "INTEGRATED_BUTTONS|RESIZE",
  prefer_to_spawn_tabs = true,
  initial_cols = 196,
  initial_rows = 55,
  scrollback_lines = 4500,
  window_padding = {
    top = 60,
    left = 0,
    bottom = 0,
    right = 0,
  },

  keys = {
    {
      key = 'k',
      mods = 'CMD',
      action = wezterm.action.ClearScrollback("ScrollbackAndViewport"),
    },
    {
      key = 'p',
      mods = 'CMD',
      action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'p',
      mods = 'CMD|SHIFT',
      action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'w',
      mods = 'CMD',
      action = wezterm.action.CloseCurrentPane { confirm = false },
    },
    {
      key = 'LeftArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Left',
    },
    {
      key = 'RightArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Right',
    },
    {
      key = 'UpArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Up',
    },
    {
      key = 'DownArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Down',
    },
    {
      key = 'LeftArrow',
      mods = 'ALT',
      action = wezterm.action.AdjustPaneSize { 'Left', 5 },
    },
    {
      key = 'RightArrow',
      mods = 'ALT',
      action = wezterm.action.AdjustPaneSize { 'Right', 5 },
    },
    {
      key = 'UpArrow',
      mods = 'ALT',
      action = wezterm.action.AdjustPaneSize { 'Up', 5 },
    },
    {
      key = 'DownArrow',
      mods = 'ALT',
      action = wezterm.action.AdjustPaneSize { 'Down', 5 },
    },
    {
      key = 'UpArrow',
      mods = 'CMD|SHIFT',
      action = wezterm.action.ScrollToBottom,
    },
    {
      key = 'DownArrow',
      mods = 'CMD|SHIFT',
      action = wezterm.action.ScrollToTop,
    },
    {
      key = 't',
      mods = 'CTRL',
      action = wezterm.action.PromptInputLine {
        description = 'Enter new name for tab',
        action = wezterm.action_callback(
          function(window, pane, line)
            if line then
              window:active_tab():set_title(line)
            end
          end
        ),
      },
    },
  },

  unix_domains = {
    {
      name = 'default',
    },
  },

  ssh_domains = {
    {
      name = 'nas',
      remote_address = 'nas',
    },
  },

  default_gui_startup_args = { 'connect', 'default' },
}


local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider

function tab_title(tab_info)
  local title = tab_info.tab_title
  if title and #title > 0 then
    return title
  end
  return 'Tab #' .. tab_info.tab_id
end

wezterm.on(
  'format-tab-title',
  function(tab, tabs, panes, config, hover, max_width)
    local edge_background = wezterm.color.parse(theme.tab_bar.background)
    local foreground = wezterm.color.parse(theme.tab_bar.active_tab.fg_color)
    local background

    if tab.is_active then
      background = wezterm.color.parse(theme.ansi[3])
    elseif hover then
      background = wezterm.color.parse(theme.brights[8])
    else
      background = wezterm.color.parse(theme.ansi[8])
    end

    local title = tab_title(tab)
    title = wezterm.truncate_right(title, max_width - 4)

    return {
      { Background = { Color = background } },
      { Foreground = { Color = edge_background } },
      { Text = SOLID_RIGHT_ARROW },
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = " " .. title .. " " },
      { Background = { Color = edge_background } },
      { Foreground = { Color = background } },
      { Text = SOLID_RIGHT_ARROW },
    }
  end
)

return config
