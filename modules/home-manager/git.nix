{ settings, pkgs, ... }:

{
  programs = {
    lazygit = {
      enable = true;
      settings = {
        gui = {
          showIcons = true; # Nerd Fontのアイコンを表示
          theme = {
            lightTheme = false;
            activeBorderColor = [
              "green"
              "bold"
            ];
            inactiveBorderColor = [ "white" ];
          };
        };

        git = {
          # delta を lazygit 内のページャーとして使う設定
          pagers = [
            {
              pager = "delta --dark --paging=never";
              colorArg = "always";
            }
          ];
        };
      };
    };

    git = {
      enable = true;
      lfs.enable = true;

      settings = {
        user = {
          email = settings.gitUsername;
          name = settings.gitUserEmail;
        };

        init.defaultBranch = "main";
        merge.conflictstyle = "zdiff3";
      };
    };

    delta = {
      enable = true;
      options = {
        features = "side-by-side line-numbers decorations";
        side-by-side = true;
        line-numbers = true;
        navigate = true;
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
        };
      };
    };
  };
}
