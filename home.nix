{ pkgs, lib, config, inputs, server, ... }:
let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  system = pkgs.stdenv.hostPlatform.system;
  brewPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";

  # figma-axi is not on npm (the other *-axi CLIs run via `npx -y` at call time)
  figma-axi = pkgs.buildNpmPackage {
    pname = "figma-axi";
    version = "0.1.0";
    src = inputs.figma-axi;
    npmDepsHash = "sha256-epzVGLzeshgOiFKU3pMExF+xRFm6IlCa1pwgWm8v+mU=";
  };

  # Docker: dangling images, stopped containers, build cache, anonymous volumes
  # (named volumes kept; skipped if colima is down). Then `mo clean`, which
  # prompts for sudo from a terminal but stays user-level under launchd.
  cleanup = pkgs.writeShellScript "cleanup" ''
    export PATH="${brewPrefix}/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    export DOCKER_HOST="unix://${config.home.homeDirectory}/.colima/default/docker.sock"
    echo "== $(date)"
    if [ -S "${config.home.homeDirectory}/.colima/default/docker.sock" ]; then
      ${pkgs.docker}/bin/docker system prune -f --volumes
    else
      echo "colima not running, skipping docker prune"
    fi
    mo clean
  '';
in
{
  home.username = "ntaleshadik";
  home.homeDirectory = "/Users/ntaleshadik";
  home.stateVersion = "22.05";

  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    defaultSopsFile = ./secrets.yaml;

    secrets = {
      b2_application_key_id = {
        path = "${config.sops.defaultSymlinkPath}/b2_application_key_id";
      };
      b2_application_key = {
        path = "${config.sops.defaultSymlinkPath}/b2_application_key";
      };
      aws_access_key_id = {
        path = "${config.sops.defaultSymlinkPath}/aws_access_key_id";
      };
      aws_secret_access_key = {
        path = "${config.sops.defaultSymlinkPath}/aws_secret_access_key";
      };
      digitalocean_token = {
        path = "${config.sops.defaultSymlinkPath}/digitalocean_token";
      };
      spaces_access_key_id = {
        path = "${config.sops.defaultSymlinkPath}/spaces_access_key_id";
      };
      spaces_secret_access_key = {
        path = "${config.sops.defaultSymlinkPath}/spaces_secret_access_key";
      };
      h_cloud_token = {
        path = "${config.sops.defaultSymlinkPath}/h_cloud_token";
      };
      figma_token = {
        path = "${config.sops.defaultSymlinkPath}/figma_token";
      };
      # Agent-only GitHub identity: fine-grained PAT for gh, dedicated key for git
      github_token = {
        path = "${config.sops.defaultSymlinkPath}/github_token";
      };
      github_ssh_key = {
        path = "${config.home.homeDirectory}/.ssh/agents_ed25519";
        mode = "0600";
      };
      kx_hcloud_kubeconfig = {
        path = "${config.home.homeDirectory}/.kube/configs/kx-hcloud.yaml";
      };
      kube_config = {
        path = "${config.home.homeDirectory}/.kube/config";
      };
    };
  };
  
  # https://github.com/malob/nixpkgs/blob/master/home/default.nix
  home.shell.enableShellIntegration = false;
  home.shell.enableZshIntegration = true;
  home.shell.enableBashIntegration = true;
  home.shell.enableNushellIntegration = true;
  home.shell.enableFishIntegration = false;
  programs.fish.enable = false;

  
  programs.zsh = {
    enable = true;
    autosuggestion = {
      enable = true;
    };
    syntaxHighlighting = {
      enable = true;
    };
    initContent = lib.mkOrder 1500 ''
      export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
      export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
      export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
      export KUBECONFIG="$HOME/.kube/configs/kx-hcloud.yaml:$HOME/.kube/config"

      export B2_APPLICATION_KEY_ID=$(cat ${config.sops.secrets.b2_application_key_id.path})
      export B2_APPLICATION_KEY=$(cat ${config.sops.secrets.b2_application_key.path})
      export AWS_ACCESS_KEY_ID=$(cat ${config.sops.secrets.aws_access_key_id.path})
      export AWS_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets.aws_secret_access_key.path})
      export DIGITALOCEAN_TOKEN=$(cat ${config.sops.secrets.digitalocean_token.path})
      export SPACES_ACCESS_KEY_ID=$(cat ${config.sops.secrets.spaces_access_key_id.path})
      export SPACES_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets.spaces_secret_access_key.path})
      export HCLOUD_TOKEN=$(cat ${config.sops.secrets.h_cloud_token.path})
      export FIGMA_TOKEN=$(cat ${config.sops.secrets.figma_token.path})
      export GH_TOKEN=$(cat ${config.sops.secrets.github_token.path})
      export TF_VAR_hcloud_token="$HCLOUD_TOKEN"

      export _ZO_DOCTOR=0
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      command_timeout = 2000;
      format = lib.concatStrings [
        " $directory"
        "$git_branch"
        "$git_status"
        "$fill"
        "$cmd_duration"
        "$kubernetes"
        "$all"
        "$line_break"
        "$character"
      ];
      character = {
        success_symbol = "[✔](bold green)";
        error_symbol = "[✗](bold red)";
      };
      directory = {
        truncation_length = 3;
      };
      fill = {
        symbol = " ";
      };
      package = {
        disabled = true;
      };
      kubernetes = {
        disabled = false;
        style = "bold yellow";
        format = "[$symbol$context( \\($namespace\\))]($style) ";
      };
      helm = {
        disabled = false;
        symbol = "⎈ ";
      };
      python = {
        symbol = " ";
      };
      golang = {
        symbol = " ";
      };
      nix_shell = {
        disabled = false;
        format = "via [$symbol$state( \\($name\\))]($style) ";
        symbol = "  ";
      };
      git_status = {
        staged = "[+](green)";
        untracked = "[?](red)";
        modified = "[*](yellow)";
      };
      cmd_duration = {
        min_time = 2000;
        format = "[  $duration ]($style)";
      };
    };
  };

  programs.kubecolor = {
    enable = true;
    settings = {
      kubectl = lib.getExe pkgs.kubectl;
      preset = "deuteranopia-dark";
    };
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
    vim-tmux-navigator
    gruvbox
  ];
  };
  
  programs.zoxide = {
    enable = true;
  };

  programs.nushell.enable = true;

  programs.helix = {
    enable = true;
    defaultEditor = true;
    ignores = [
      ".build/"
      "node_modules/"
      "!.gitignore"
    ];
    settings = {
      theme = "rose_pine_moon";
      editor = {
        line-number = "relative";
        lsp.display-messages = true;
      };
      keys.normal = {
        space.space = "file_picker";
        space.q = ":q";
        esc = [ "normal_mode" ":write" ];
      };
    };
  };
  
  programs.direnv = {
    enable = true;
  };
  
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
    };
  };
  # Claude Code behaviour toggles, as env vars rather than ~/.claude/settings.json
  # so Claude rewriting that file cannot regress them.
  home.sessionVariables = {
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
    CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
    CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
    CLAUDE_CODE_AUTO_COMPACT_WINDOW = "500000";
  };

  home.shellAliases = {
    cd = "z";
    g = "git";
    cat = "bat";
    gc = "gitmoji commit";
    k = "kubecolor";
    switch = "sudo darwin-rebuild switch --flake ${dotfiles}#${system} && sudo nix-collect-garbage --delete-older-than 7d";
    rshell = "source ~/.zshrc";
    cleanup = toString cleanup;
  };

  programs.direnv.nix-direnv.enable = true;

  # npm's default global prefix is the read-only nix store
  home.file.".npmrc".text = "prefix=${config.home.homeDirectory}/.npm-global\n";

  launchd.agents.weekly-cleanup = {
    enable = true;
    config = {
      ProgramArguments = [ (toString cleanup) ];
      StartCalendarInterval = [ { Weekday = 0; Hour = 10; Minute = 0; } ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/weekly-cleanup.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/weekly-cleanup.log";
    };
  };

  programs.btop = {
    enable = true;
    settings = {
      # more settings here https://github.com/aristocratos/btop#btopconf-auto-generated-if-not-found
      vim_keys = true;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Nta1e";
      user.email = "shadikntale@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      core.sshCommand = "ssh -i ${config.sops.secrets.github_ssh_key.path} -o IdentitiesOnly=yes";
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };    
  };

  programs.gh-dash = {
    enable = true;
    settings = {
      prSections = [
        {
          title = "My Pull Requests";
          filters = "is:open author:@me";
        }
        {
          title = "Needs My Review";
          filters = "is:open review-requested:@me";
        }
      ];
    };
  };

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig = {
      
    };
  };


  home.packages = with pkgs; [
    fzf
    kubectl
    kubernetes-helm
    talosctl
    terraform
    hcloud
    helm-ls
    kubie
    gitmoji-cli
    doctl
    # Secrets management
    age
    sops

    docker
    docker-compose
    docker-buildx
    colima
  
    nodejs
    yq
    uv
    nixd
    lefthook
    cocoapods

    # Agents and agent tooling
    rtk
    (pkgs.callPackage ./pkgs/pi { })
    figma-axi
    (pkgs.callPackage "${inputs.treehouse}/package.nix" { })
    jq

    pgcli
    postgresql

    nerd-fonts.hack
  ] ++ lib.optionals (!server) [
    # Heavy, uncached python/arrow build on x86_64-darwin; not needed headless
    inputs.sqlit.packages.${system}.default
  ];


  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";


  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";


  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Claude Code skills, pinned through the flake inputs so every Mac runs the
  # same version. Each is a directory holding SKILL.md.
  home.file.".claude/skills/lavish".source = "${inputs.lavish-axi}/skills/lavish";
  home.file.".claude/skills/quota-axi".source = "${inputs.quota-axi}/skills/quota-axi";
  home.file.".claude/skills/gh-axi".source = "${inputs.gh-axi}/skills/gh-axi";
  home.file.".claude/skills/figma-axi".source = "${inputs.figma-axi}/skills/figma-axi";


  # Seed the firstmate home (config/ and data/ are gitignored there and
  # firstmate curates them afterwards, so copy once rather than symlink).
  home.activation.firstmateSeed = lib.hm.dag.entryAfter ["writeBoundary"] ''
    fm=${config.home.homeDirectory}/workspace/firstmate
    if [ -d "$fm/bin" ]; then
      for f in $(cd ${dotfiles}/home/firstmate && find . -type f); do
        mkdir -p "$fm/$(dirname "$f")"
        [ -e "$fm/$f" ] || cp "${dotfiles}/home/firstmate/$f" "$fm/$f"
      done
    fi
  '';

  # ~/.claude/settings.json = repo baseline + this machine's overrides
  # (~/.claude/settings.machine.json, unmanaged). Claude Code writes to the
  # merged file directly, so anything it changed is kept in .prev on overwrite.
  home.activation.claudeSettings = lib.hm.dag.entryAfter ["linkGeneration"] ''
    base=${dotfiles}/home/.claude/settings.json
    machine=~/.claude/settings.machine.json
    out=~/.claude/settings.json
    mkdir -p ~/.claude
    [ -f "$machine" ] || echo '{}' > "$machine"
    merged=$(${pkgs.jq}/bin/jq -s -f ${dotfiles}/home/.claude/merge.jq "$base" "$machine")
    if [ -f "$out" ] && ! [ -L "$out" ] && [ "$(cat "$out")" != "$merged" ]; then
      cp "$out" "$out.prev"
      echo "claude: settings.json overwritten; previous copy in $out.prev" >&2
    fi
    rm -f "$out"
    printf '%s\n' "$merged" > "$out"
  '';
}
