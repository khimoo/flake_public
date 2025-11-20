{ skk-dict, settings, config, pkgs, lib, kiro, ... }:

let
  # binName はオプション。指定がなければ pkg.pname を使う。
  createWaylandDesktopEntry = { pkg, desktopName, execArgs, binName ? null }:
    let
      originalDesktop = "${pkg}/share/applications/${desktopName}";
      originalContent = builtins.readFile originalDesktop;
      # 実際に使用する実行ファイル名を決定
      execCmd = if binName != null then binName else pkg.pname;
      newContent = pkgs.runCommand "modified-${desktopName}" {} ''
        echo "${originalContent}" > $out
        # Exec= 行を置換（%U を付与）
        sed -i 's|^Exec=.*|Exec=${execCmd} ${execArgs} %U|' $out
      '';
    in
      newContent;

  # オプション自動で追加
  waylandApps = [
    {
      pkg = pkgs.obsidian;
      desktopName = "obsidian.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      # binName を省略 → pkg.pname を使う
    }
    {
      pkg = pkgs.bitwarden;
      desktopName = "bitwarden.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      binName = "bitwarden"; # ここで明示的に上書き
    }
    {
      pkg = pkgs.teams-for-linux;
      desktopName = "teams-for-linux.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      # binName を省略
    }
    {
      pkg = pkgs.vscode;
      desktopName = "code.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      binName = "code";
    }
    {
      pkg = kiro.packages.${settings.system}.default;
      desktopName = "kiro.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
      binName = "kiro";
    }
    {
      pkg = pkgs.spotify;
      desktopName = "spotify.desktop";
      execArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3";
    }
  ];

  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.rust-analyzer; lsp = "rust_analyzer"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
    # 追加したいLSPをここに
  ];

  # GNOME拡張機能の一元管理リスト
  gnomeExtensionsList = with pkgs.gnomeExtensions; [
    clipboard-history
    extension-list
    kimpanel
    gsconnect
    paperwm
  ];

desktopEntries = builtins.listToAttrs
  (map
    (app: {
      name = ".local/share/applications/${app.desktopName}";
      value = {
        source = createWaylandDesktopEntry {
          pkg = app.pkg;
          desktopName = app.desktopName;
          execArgs = app.execArgs;
          # binName が定義されていればその値を渡し、なければ null を渡す
          binName = if builtins.hasAttr "binName" app then app.binName else null;
        };
      };
    })
    waylandApps);

inherit (config.lib.file) mkOutOfStoreSymlink;

in {
  nixpkgs.config.allowUnfree = true;

  # パッケージリスト
  home.packages = with pkgs; [
    curl
    tig
    wezterm
    gcc
    neofetch
    python3
    thunderbird
    slack
    zoom-us
    yt-dlp
    transcribe
    appimage-run
    code-cursor
    krita
    tdf
    typst
    libreoffice
    discord
    gh
    uv
    direnv

    # fonts
    ipafont
    ipaexfont
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    nerd-fonts.fira-code
  ] ++ gnomeExtensionsList
    ++ map (app: app.pkg) waylandApps
    ++ map (s: s.pkg) lspServers;

  # デスクトップファイル設定
  home.file = desktopEntries;

  fonts.fontconfig = { enable = true; };
  programs.nushell = {
    enable = true;
    environmentVariables = {
      EDITOR = "nvim";
      SKK_DICTIONARY_PATH = "${skk-dict}";
      NEOVIM_LSP_SERVERS = builtins.concatStringsSep "," (map (s: s.lsp) lspServers);
      CODELLDB_PATH = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
    };
    shellAliases = {
      ghcs = "gh copilot suggest";
      ghce = "gh copilot explain";
    };
  };
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      command_timeout = 1300;
      scan_timeout = 50;
      format = ''
        $all$nix_shell$nodejs$lua$golang$rust$php$git_branch$git_commit$git_state$git_status
        $username$hostname$directory'';
      character = {
        success_symbol = "[](bold green) ";
        error_symbol = "[✗](bold red) ";
      };
    };
  };
  programs.git = {
    lfs.enable = true;
    enable = true;
    userName = settings.gitUsername;
    userEmail = settings.gitUserEmail;
    extraConfig = { init.defaultBranch = "main"; };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  # install neovim!!!
  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
    withNodeJs = true;
    extraPackages = with pkgs; [
      deno
      ripgrep
      xclip
      nil  # 色んなところでflake.nixを書くので
      nixfmt-rfc-style
      vscode-extensions.vadimcn.vscode-lldb
      # tinymist # 個別のflake.nixを定義することにした
      # rust-analyzer # 個別のflake.nixを定義することにした
    ];
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];
  };

  xdg.configFile = {
    "nvim" = {
      source = mkOutOfStoreSymlink "${config.home.homeDirectory}/flakes/home-manager/nvim";
      recursive = true;
    };
    "wezterm/wezterm.lua".source = mkOutOfStoreSymlink "${config.home.homeDirectory}/flakes/home-manager/wezterm.lua";
  };
  home.stateVersion = "25.05";
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-skk
    ];
  };
  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (ext: ext.extensionUuid) gnomeExtensionsList;
      };
      "org/gnome/desktop/interface" = {
        accent-color = "blue";
        color-scheme = "prefer-dark";
        show-battery-percentage = true;
        toolkit-accessibility = false;
      };
    };
  };
}
