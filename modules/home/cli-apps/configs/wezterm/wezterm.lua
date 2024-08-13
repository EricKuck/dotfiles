local wezterm = require 'wezterm'
local act = wezterm.action
local theme_name = 'Catppuccin Frappe'
local theme = wezterm.color.get_builtin_schemes()[theme_name]
local tab_max_width = 20
local search_mode = nil
if wezterm.gui then
  search_mode = wezterm.gui.default_key_tables().search_mode
  table.insert(
    search_mode,
    { key = 'f', mods = 'CMD', action = act.CopyMode 'ClearPattern' }
  )
end

local config = {
  color_scheme = theme_name,
  colors = { split = theme.ansi[3] },
  font = wezterm.font 'JetBrains Mono',
  font_size = 13,
  tab_bar_at_bottom = true,
  use_fancy_tab_bar = false,
  tab_max_width = tab_max_width,
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

  key_tables = {
    search_mode = search_mode,
  },

  keys = {
    {
      key = 'f',
      mods = 'CMD|SHIFT',
      action = act.TogglePaneZoomState,
    },
    {
      key = 'f',
      mods = 'CMD',
      action = act.Search { CaseInSensitiveString = '' },
    },
    {
      key = 'k',
      mods = 'CMD',
      action = act.ClearScrollback("ScrollbackAndViewport"),
    },
    {
      key = 'p',
      mods = 'CMD',
      action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'p',
      mods = 'CMD|SHIFT',
      action = act.SplitVertical { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'w',
      mods = 'CMD',
      action = act.CloseCurrentPane { confirm = false },
    },
    {
      key = 'LeftArrow',
      mods = 'CMD',
      action = act.ActivatePaneDirection 'Left',
    },
    {
      key = 'RightArrow',
      mods = 'CMD',
      action = act.ActivatePaneDirection 'Right',
    },
    {
      key = 'UpArrow',
      mods = 'CMD',
      action = act.ActivatePaneDirection 'Up',
    },
    {
      key = 'DownArrow',
      mods = 'CMD',
      action = act.ActivatePaneDirection 'Down',
    },
    {
      key = 'LeftArrow',
      mods = 'ALT',
      action = act.AdjustPaneSize { 'Left', 5 },
    },
    {
      key = 'RightArrow',
      mods = 'ALT',
      action = act.AdjustPaneSize { 'Right', 5 },
    },
    {
      key = 'UpArrow',
      mods = 'ALT',
      action = act.AdjustPaneSize { 'Up', 5 },
    },
    {
      key = 'DownArrow',
      mods = 'ALT',
      action = act.AdjustPaneSize { 'Down', 5 },
    },
    {
      key = 'UpArrow',
      mods = 'CMD|SHIFT',
      action = act.ScrollToBottom,
    },
    {
      key = 'DownArrow',
      mods = 'CMD|SHIFT',
      action = act.ScrollToTop,
    },
    {
      key = 't',
      mods = 'CTRL',
      action = act.PromptInputLine {
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
  return 'Tab #' .. (tab_info.tab_index + 1)
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
    if tab.active_pane.is_zoomed then
      title = '[Z] ' .. title
    end

    local title_extra_width = 4 -- 2 spaces + 2 arrows
    local spacer = ''
    if tab.tab_index == 0 then
      spacer = '    '
      title_extra_width = title_extra_width + string.len(spacer)
    end

    title = ' ' .. wezterm.truncate_right(title, tab_max_width - title_extra_width) .. ' '

    return {
      { Background = { Color = edge_background } },
      { Foreground = { Color = theme.ansi[8] } },
      { Text = spacer },
      { Background = { Color = background } },
      { Foreground = { Color = edge_background } },
      { Text = SOLID_RIGHT_ARROW },
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = title },
      { Background = { Color = edge_background } },
      { Foreground = { Color = background } },
      { Text = SOLID_RIGHT_ARROW },
    }
  end
)

return config
