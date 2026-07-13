local wezterm = require 'wezterm'
local config = {}

-- ベル時にトースト通知を表示
wezterm.on('bell', function(window, pane)
  window:toast_notification('Claude Code', 'Task completed', nil, 4000)
end)

-- Windows では WSL をデフォルトシェルにする
if wezterm.target_triple:find('windows') then
  config.default_domain = 'WSL:Ubuntu'
end

-- 見た目の設定
config.font_size = 12
config.color_scheme = 'Tokyo Night'
config.window_background_opacity = 0.9

-- スクロール行数
config.scrollback_lines = 10000
config.enable_scroll_bar = false

-- 起動時のウィンドウサイズ
config.initial_cols = 120
config.initial_rows = 30

-- 画像表示を有効化
config.enable_kitty_graphics = true

-- ベル音を有効化（Claudeが入力を求めたときに鳴る）
config.audible_bell = "SystemBeep"

-- 日本語入力（IME）の位置修正
config.use_ime = true
config.ime_preedit_rendering = "Builtin"

-- タブバーを表示
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

-- タブタイトルをカスタマイズ: ディレクトリ名 + 実行中コマンド
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local cwd = pane.current_working_dir
  local shell_title = pane.title or ''

  -- ディレクトリ名を取得
  local dir_name = ''
  if cwd then
    local path = cwd.file_path or tostring(cwd)
    dir_name = path:match('([^/]+)/?$') or path
  end

  -- シェルからのタイトル（コマンド名）を取得
  -- bashrcで「コマンド名」だけを設定するように変更
  local title = dir_name
  if shell_title ~= '' and shell_title ~= 'bash' and shell_title ~= dir_name then
    title = dir_name .. ' | ' .. shell_title
  end

  return {
    { Text = ' ' .. title .. ' ' },
  }
end)

-- タブ/ウィンドウを閉じるときの確認を無効化
config.window_close_confirmation = 'NeverPrompt'
config.skip_close_confirmation_for_processes_named = {
  'bash', 'sh', 'zsh', 'fish', 'tmux', 'nu', 'cmd.exe', 'pwsh.exe', 'powershell.exe',
  'wsl.exe', 'wslhost.exe', 'conhost.exe', 'node', 'claude',
}

-- alt screen（vim等）でのスクロール速度
config.alternate_buffer_wheel_scroll_speed = 1

-- キーバインド
config.keys = {
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'Enter', mods = 'ALT', action = wezterm.action.ToggleFullScreen },
}

-- マウス設定
local act = wezterm.action
config.mouse_bindings = {
  -- スクロール速度を固定（飛ぶ問題対策）
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'NONE',
    action = act.ScrollByLine(-3),
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'NONE',
    action = act.ScrollByLine(3),
  },
  -- 右クリック: 選択あり→コピー、なし→ペースト（Windows Terminal風）
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = wezterm.action_callback(function(window, pane)
      local has_selection = window:get_selection_text_for_pane(pane) ~= ''
      if has_selection then
        window:perform_action(act.CopyTo 'ClipboardAndPrimarySelection', pane)
        window:perform_action(act.ClearSelection, pane)
      else
        window:perform_action(act.PasteFrom 'Clipboard', pane)
      end
    end),
  },
  -- 中クリック無効化（誤操作防止）
  {
    event = { Down = { streak = 1, button = 'Middle' } },
    mods = 'NONE',
    action = act.Nop,
  },
}

return config
