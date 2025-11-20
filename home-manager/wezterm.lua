-- https://qiita.com/sonarAIT/items/0571c869e5f9ab3be817
local wezterm = require 'wezterm'
local act = wezterm.action
local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

local handle = io.popen("which bash")
local bash_path = handle:read("*l")
handle:close()

mux_enable_ssh_agent = false
config.enable_wayland = false

-- 背景透過
config.window_background_opacity = 0.75

-- font
config.font_size = 13.0
config.font = wezterm.font 'FiraCode Nerd Font'

-- ime on
config.use_ime = true

-- タブがひとつの場合にタブバーを非表示
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false

-- タブバーの色を背景色に合わせる
config.window_background_gradient = {
  colors = { "#000000" },
}

-- タブバーの色を透過
 config.colors = {
   tab_bar = {
     inactive_tab_edge = "none",
   },
 }

-- 最初からフルスクリーンで起動
-- local mux = wezterm.mux
-- wezterm.on("gui-startup", function(cmd)
--   local tab, pane, window = mux.spawn_window(cmd or {})
--   window:gui_window():toggle_fullscreen()
-- end)

-- F11でフルスクリーン切り替え
config.keys = {
  {
    key = 'F11',
    mods = 'NONE',
    action = act.ToggleFullScreen,
  },
}

-- ctrl + マウスホイールでフォントサイズ変更
config.mouse_bindings = {
  -- Scrolling up while holding CTRL increases the font size
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'CTRL',
    action = act.IncreaseFontSize,
  },

  -- Scrolling down while holding CTRL decreases the font size
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'CTRL',
    action = act.DecreaseFontSize,
  },
}

-- ctrl + +_で背景透明度変更
current_opacity = config.window_background_opacity
function change_opacity(delta)
  return wezterm.action_callback(function(win, pane)
    local overrides = win:get_config_overrides() or {}
    local current_opacity = overrides.window_background_opacity
    local new_opacity = current_opacity + delta
    if new_opacity < 0.0 then
      new_opacity = 0.0
    elseif new_opacity > 1.0 then
      new_opacity = 1.0
    end
    overrides.window_background_opacity = new_opacity
    win:set_config_overrides(overrides)
  end)
end
table.insert(config.keys,
  {
    key = "=",
    mods = "CTRL",
    action = change_opacity(0.05),
  })
table.insert(config.keys,
  {
    key = "-",
    mods = "CTRL",
    action = change_opacity(-0.05),
  })
config.keys[#config.keys+1] = {
  key = "0",
  mods = "CTRL",
  action = wezterm.action_callback(function(win,pane)
    local overrides = win:get_config_overrides() or {}
    overrides.window_background_opacity = current_opacity
    win:set_config_overrides(overrides)
  end),
}

-- default_key_bindingsはオフ
config.disable_default_key_bindings = true

-- leaderキーはctrl + s
config.leader = { key="s", mods="CTRL", timeout_milliseconds=2000 }

-- leader + 0 で行頭に移動
config.keys[#config.keys+1] = {
  key = "0",
  mods = "LEADER",
  action = act.SendKey {
    key = "a",
    mods = "CTRL",
  },
}
-- leader + A で行末に移動
config.keys[#config.keys+1] = {
  key = "A",
  mods = "LEADER",
  action = act.SendKey {
    key = "e",
    mods = "CTRL",
  },
}
-- leader + d で先頭まで削除
config.keys[#config.keys+1] = {
  key = "d",
  mods = "LEADER",
  action = act.SendKey {
    key = "u",
    mods = "CTRL",
  },
}
-- leader + w で単語移動
config.keys[#config.keys+1] = {
  key = "w",
  mods = "LEADER",
  action = act.SendKey {
    key = "f",
    mods = "META",
  },
}
-- leader + W でワークスペース関連
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'W',
  action = act.ShowLauncherArgs { flags = 'WORKSPACES' , title = "Select workspace" },
}
-- leader + R でワークスペース名変更
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'R',
  action = act.PromptInputLine {
    description = '(wezterm) Set workspace title:',
    action = wezterm.action_callback(function(win,pane,line)
      if line then
        wezterm.mux.rename_workspace(
        wezterm.mux.get_active_workspace(),
        line
        )
      end
    end),
  },
}
-- leader + s で水平方向に分割
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 's',
  action = act.SplitVertical {
    domain = "CurrentPaneDomain",
  },
}
-- leader + v で垂直方向に分割
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'v',
  action = act.SplitHorizontal {
    domain = "CurrentPaneDomain",
  },
}
-- leader + q でペインリサイズ
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'q',
  action = act.ActivateKeyTable {
    name = "resize_pane",
    one_shot = false,
  },
}
-- leader + e でペイン位置変更(時計回り)
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'e',
  action = act.RotatePanes 'Clockwise',
}
-- leader + E でペイン位置変更(反時計回り)
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'E',
  action = act.RotatePanes 'CounterClockwise',
}
-- leader + hjkl でペイン移動
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'h',
  action = act.ActivatePaneDirection 'Left',
}
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'j',
  action = act.ActivatePaneDirection 'Down',
}
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'k',
  action = act.ActivatePaneDirection 'Up',
}
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'l',
  action = act.ActivatePaneDirection 'Right',
}
-- leader + c で新らしいタブを開く
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'c',
  action = act ({SpawnTab = "CurrentPaneDomain"}),
}
-- leader + n で次のタブへ
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'n',
  action = act ({ActivateTabRelative = 1}),
}
-- leader + shift + n で前のタブへ
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'N',
  action = act ({ActivateTabRelative = -1}),
}
-- leader + x でペインを閉じる
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'x',
  action = act.CloseCurrentPane {confirm = true},
}
-- leader + X でタブを閉じる
config.keys[#config.keys+1] = {
  mods = 'LEADER',
  key = 'X',
  action = act.CloseCurrentTab {confirm = true},
}

-- leader + y でcopy_mode起動
config.keys[#config.keys+1] = {
  key = "y",
  mods = "LEADER",
  action = act.ActivateCopyMode,
}
config.keys[#config.keys+1] = {
    key = 'P',
    mods = 'CTRL',
    action = wezterm.action.ActivateCommandPalette,
}
-- ctrl + shift + v でペースト
config.keys[#config.keys+1] = {
  key = "V",
  mods = "CTRL",
  action = act.PasteFrom "Clipboard",
}
-- config.keys[#config.keys+1] = {
--   key = "V",
--   mods = "CTRL",
--   action = act.PasteFrom "PrimarySelection",
-- }

-- キーテーブルたち
config.key_tables = {
  resize_pane = {
    { key = 'LeftArrow', action = act.AdjustPaneSize { 'Left', 1 } },
    { key = 'h', action = act.AdjustPaneSize { 'Left', 3 } },

    { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 1 } },
    { key = 'l', action = act.AdjustPaneSize { 'Right', 3 } },

    { key = 'UpArrow', action = act.AdjustPaneSize { 'Up', 1 } },
    { key = 'k', action = act.AdjustPaneSize { 'Up', 3 } },

    { key = 'DownArrow', action = act.AdjustPaneSize { 'Down', 1 } },
    { key = 'j', action = act.AdjustPaneSize { 'Down', 3 } },

    -- Cancel the mode by pressing escape
    { key = 'Escape', action = 'PopKeyTable' },
  },
  copy_mode = {
    { key = 'Tab', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
    {
      key = 'Tab',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveBackwardWord',
    },
    {
      key = 'Enter',
      mods = 'NONE',
      action = act.CopyMode 'MoveToStartOfNextLine',
    },
    {
      key = 'Escape',
      mods = 'NONE',
      action = act.Multiple {
        { CopyMode = 'Close' },
      },
    },
    {
      key = 'Space',
      mods = 'NONE',
      action = act.CopyMode { SetSelectionMode = 'Cell' },
    },
    {
      key = '$',
      mods = 'NONE',
      action = act.CopyMode 'MoveToEndOfLineContent',
    },
    {
      key = '$',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToEndOfLineContent',
    },
    { key = ',', mods = 'NONE', action = act.CopyMode 'JumpReverse' },
    { key = '0', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
    { key = ';', mods = 'NONE', action = act.CopyMode 'JumpAgain' },
    {
      key = 'F',
      mods = 'NONE',
      action = act.CopyMode { JumpBackward = { prev_char = false } },
    },
    {
      key = 'F',
      mods = 'SHIFT',
      action = act.CopyMode { JumpBackward = { prev_char = false } },
    },
    {
      key = 'G',
      mods = 'NONE',
      action = act.CopyMode 'MoveToScrollbackBottom',
    },
    {
      key = 'G',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToScrollbackBottom',
    },
    { key = 'H', mods = 'NONE', action = act.CopyMode 'MoveToViewportTop' },
    {
      key = 'H',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToViewportTop',
    },
    {
      key = 'L',
      mods = 'NONE',
      action = act.CopyMode 'MoveToViewportBottom',
    },
    {
      key = 'L',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToViewportBottom',
    },
    {
      key = 'M',
      mods = 'NONE',
      action = act.CopyMode 'MoveToViewportMiddle',
    },
    {
      key = 'M',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToViewportMiddle',
    },
    {
      key = 'O',
      mods = 'NONE',
      action = act.CopyMode 'MoveToSelectionOtherEndHoriz',
    },
    {
      key = 'O',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToSelectionOtherEndHoriz',
    },
    {
      key = 'T',
      mods = 'NONE',
      action = act.CopyMode { JumpBackward = { prev_char = true } },
    },
    {
      key = 'T',
      mods = 'SHIFT',
      action = act.CopyMode { JumpBackward = { prev_char = true } },
    },
    {
      key = 'V',
      mods = 'NONE',
      action = act.CopyMode { SetSelectionMode = 'Line' },
    },
    {
      key = 'V',
      mods = 'SHIFT',
      action = act.CopyMode { SetSelectionMode = 'Line' },
    },
    {
      key = '^',
      mods = 'NONE',
      action = act.CopyMode 'MoveToStartOfLineContent',
    },
    {
      key = '^',
      mods = 'SHIFT',
      action = act.CopyMode 'MoveToStartOfLineContent',
    },
    { key = 'b', mods = 'NONE', action = act.CopyMode 'MoveBackwardWord' },
    { key = 'b', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
    { key = 'b', mods = 'CTRL', action = act.CopyMode 'PageUp' },
    {
      key = 'c',
      mods = 'CTRL',
      action = act.Multiple {
        { CopyMode = 'Close' },
      },
    },
    {
      key = 'd',
      mods = 'CTRL',
      action = act.CopyMode { MoveByPage = 0.5 },
    },
    {
      key = 'e',
      mods = 'NONE',
      action = act.CopyMode 'MoveForwardWordEnd',
    },
    {
      key = 'f',
      mods = 'NONE',
      action = act.CopyMode { JumpForward = { prev_char = false } },
    },
    { key = 'f', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
    { key = 'f', mods = 'CTRL', action = act.CopyMode 'PageDown' },
    {
      key = 'g',
      mods = 'NONE',
      action = act.CopyMode 'MoveToScrollbackTop',
    },
    {
      key = 'g',
      mods = 'CTRL',
      action = act.Multiple {
        { CopyMode = 'Close' },
      },
    },
    { key = 'h', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
    { key = 'j', mods = 'NONE', action = act.CopyMode 'MoveDown' },
    { key = 'k', mods = 'NONE', action = act.CopyMode 'MoveUp' },
    { key = 'l', mods = 'NONE', action = act.CopyMode 'MoveRight' },
    {
      key = 'm',
      mods = 'ALT',
      action = act.CopyMode 'MoveToStartOfLineContent',
    },
    {
      key = 'o',
      mods = 'NONE',
      action = act.CopyMode 'MoveToSelectionOtherEnd',
    },
    {
      -- quick select
      key = 'q',
      mods = 'NONE',
      action = act.QuickSelect,
    },
    {
      key = 't',
      mods = 'NONE',
      action = act.CopyMode { JumpForward = { prev_char = true } },
    },
    {
      key = 'u',
      mods = 'CTRL',
      action = act.CopyMode { MoveByPage = -0.5 },
    },
    {
      key = 'v',
      mods = 'NONE',
      action = act.CopyMode { SetSelectionMode = 'Cell' },
    },
    {
      key = 'v',
      mods = 'CTRL',
      action = act.CopyMode { SetSelectionMode = 'Block' },
    },
    { key = 'w', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
    {
      key = 'y',
      mods = 'NONE',
      action = act.Multiple {
        { CopyTo = 'ClipboardAndPrimarySelection' },
        { CopyMode = 'Close' },
      },
    },
    { key = 'PageUp', mods = 'NONE', action = act.CopyMode 'PageUp' },
    { key = 'PageDown', mods = 'NONE', action = act.CopyMode 'PageDown' },
    {
      key = 'End',
      mods = 'NONE',
      action = act.CopyMode 'MoveToEndOfLineContent',
    },
    {
      key = 'Home',
      mods = 'NONE',
      action = act.CopyMode 'MoveToStartOfLine',
    },
    { key = 'LeftArrow', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
    {
      key = 'LeftArrow',
      mods = 'ALT',
      action = act.CopyMode 'MoveBackwardWord',
    },
    {
      key = 'RightArrow',
      mods = 'NONE',
      action = act.CopyMode 'MoveRight',
    },
    {
      key = 'RightArrow',
      mods = 'ALT',
      action = act.CopyMode 'MoveForwardWord',
    },
    { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'MoveUp' },
    { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'MoveDown' },
  },
}

return config
