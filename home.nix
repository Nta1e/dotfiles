{ pkgs, lib, config, inputs, server, ... }:
let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  system = pkgs.stdenv.hostPlatform.system;
  brewPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";

  # Shared by zsh and bash login shells.
  shellExports = ''
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/workspace/odoo/tools/kx:$PATH"
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
    export KUBECONFIG="$HOME/.kube/configs/kx-hcloud.yaml"

    export B2_APPLICATION_KEY_ID=$(cat ${config.sops.secrets.b2_application_key_id.path})
    export B2_APPLICATION_KEY=$(cat ${config.sops.secrets.b2_application_key.path})
    export AWS_ACCESS_KEY_ID=$(cat ${config.sops.secrets.aws_access_key_id.path})
    export AWS_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets.aws_secret_access_key.path})
    export HCLOUD_TOKEN=$(cat ${config.sops.secrets.h_cloud_token.path})
    export FIGMA_TOKEN=$(cat ${config.sops.secrets.figma_token.path})
    export GH_TOKEN=$(cat ${config.sops.secrets.github_token.path})
  '' + lib.optionalString server ''
    export CLAUDE_CODE_OAUTH_TOKEN=$(cat ${config.sops.secrets.claude_oauth_token.path})
  '' + ''
    export TF_VAR_hcloud_token="$HCLOUD_TOKEN"
  '';

  # Telegram voice notes: whisper.cpp on the host CPU (OpenSuperWhisper's Intel
  # build returns garbage; Metal on the Intel GPU fails, hence -ng). About 11s
  # for a 17s note on the i9. Called by home/hermes/stt-host.sh over ssh.
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
    hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
  };
  hermesStt = pkgs.writeShellScriptBin "hermes-stt" ''
    exec ${pkgs.whisper-cpp}/bin/whisper-cli -ng -nt -np -m ${whisperModel} -f "$1" \
      --prompt "Odoo, ArgoCD, Argo, Krunchix, Hetzner, firstmate, crewmate, Postgres, Telegram, kubectl" 2>/dev/null
  '';

  # firstmate -> the captain's Telegram, as the Hermes bot. Firstmate cannot
  # reply to Telegram itself; a standing rule in its captain.md has it call
  # this on completion / captain-hold of tasks that arrived via Telegram.
  fmTg = pkgs.writeShellScriptBin "fm-tg" ''
    set -euo pipefail
    text="''${*:-$(cat)}"
    [ -n "$text" ] || { echo "fm-tg: nothing to send" >&2; exit 2; }
    token=$(cat ${config.sops.secrets.telegram_bot_token.path})
    chat=$(cut -d, -f1 ${config.sops.secrets.telegram_allowed_users.path})
    ${pkgs.curl}/bin/curl -sS -o /dev/null --fail-with-body \
      "https://api.telegram.org/bot$token/sendMessage" \
      --data-urlencode "chat_id=$chat" \
      --data-urlencode "text=$text" \
      --data-urlencode "disable_web_page_preview=true"
  '';

  # Named volume for /opt/data: a bind mount over virtiofs breaks sqlite WAL
  # and uid ownership. home/hermes is bind-mounted as a directory (a single-file
  # mount pins the inode and goes stale when git pull replaces the file);
  # seed.sh symlinks /opt/data/SOUL.md into it.
  #
  # One gateway serves both profiles (gateway.multiplex_profiles, set by
  # seed.sh): the default profile is the Telegram liaison, `ops`
  # (/opt/data/profiles/ops) is the Mattermost front door. A named profile
  # reads secrets only from its own .env, which seed.sh copies in from the
  # sops-rendered ~/.hermes/env-ops, so neither bot sees the other's token.
  # Attachments the captains post land in the ops document cache; that cache
  # is a symlink (seed.sh) to the host directory mounted here so `kx` on the
  # host can read the PDF the agent was handed.
  hermesCompose = pkgs.writeText "hermes-compose.yaml" (builtins.toJSON {
    services.hermes = {
      image = "nousresearch/hermes-agent";
      container_name = "hermes";
      command = [ "gateway" "run" ];
      env_file = [ "${config.home.homeDirectory}/.hermes/env" ];
      volumes = [
        "hermes-data:/opt/data"
        "${dotfiles}/home/hermes:/opt/dotfiles-hermes:ro"
        "${config.home.homeDirectory}/.hermes/ops-documents:/opt/host-documents"
        # see home/hermes/patches/README.md
        "${dotfiles}/home/hermes/patches/mattermost:/opt/hermes/plugins/platforms/mattermost:ro"
      ];
    };
    volumes.hermes-data = { };
  });

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
      h_cloud_token = {
        path = "${config.sops.defaultSymlinkPath}/h_cloud_token";
      };
      figma_token = {
        path = "${config.sops.defaultSymlinkPath}/figma_token";
      };
      # Agent GitHub identity: one classic PAT (repo, workflow, project,
      # read:org, packages) for gh, docker login to GHCR and the org project
      # board; fine-grained tokens cannot reach packages or org projects.
      # Git uses the dedicated key below.
      github_token = {
        path = "${config.sops.defaultSymlinkPath}/github_token";
      };
      github_ssh_key = {
        path = "${config.home.homeDirectory}/.ssh/agents_ed25519";
        mode = "0600";
      };
      # `claude setup-token`: long-lived, used headless on the server instead of
      # the Keychain login so the agents never wait on a relogin
      claude_oauth_token = {
        path = "${config.sops.defaultSymlinkPath}/claude_oauth_token";
      };
      kx_hcloud_kubeconfig = {
        path = "${config.home.homeDirectory}/.kube/configs/kx-hcloud.yaml";
      };
      # typesafe.ai (Jev): firstmate's typed dispatch resolver
      typesafe_api_key = { };
    } // lib.optionalAttrs server {
      # Hermes gateway (Telegram -> firstmate); see home/hermes/README.md
      telegram_bot_token = { };
      telegram_allowed_users = { };
      hermes_ssh_key = { };
      # Mattermost front door (`ops` profile); see home/hermes/ops/README.md
      mattermost_bot_token = { };
      mattermost_ops_users = { };
    };
    # firstmate's operator-owned .env (it never writes it): with the key
    # present, bin/fm-dispatch-resolve.sh picks the crewmate profile through
    # Jev instead of the LLM reading dispatch rules; absent = today's routing.
    templates = {
      "firstmate.env" = {
        path = "${config.home.homeDirectory}/workspace/firstmate/.env";
        content = ''
          TYPESAFE_API_KEY=${config.sops.placeholder.typesafe_api_key}
        '';
      };
    } // lib.optionalAttrs server {
    # Read host-side by docker-compose (env_file), so the container never
    # needs the sops dir mounted. ANTHROPIC_TOKEN = the claude setup-token:
    # Hermes routes as Claude Code, drawing on the Max plan's extra usage.
    "hermes.env" = {
      path = "${config.home.homeDirectory}/.hermes/env";
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.telegram_bot_token}
        TELEGRAM_ALLOWED_USERS=${config.sops.placeholder.telegram_allowed_users}
        ANTHROPIC_TOKEN=${config.sops.placeholder.claude_oauth_token}
        TERMINAL_SSH_HOST=host.docker.internal
        TERMINAL_SSH_USER=${config.home.username}
        TERMINAL_SSH_KEY=/opt/data/ssh/id_ed25519
        HERMES_LOCAL_STT_COMMAND=/opt/dotfiles-hermes/stt-host.sh {input_path} {output_dir}
      '';
    };
    # Copied into the ops profile by seed.sh (re-run it when these change).
    # Thread mode: every reply nests under the post that asked. Channels need
    # an @mention; DMs never do.
    "hermes-ops.env" = {
      path = "${config.home.homeDirectory}/.hermes/env-ops";
      content = ''
        MATTERMOST_URL=https://chat.krunchix.cafe
        MATTERMOST_TOKEN=${config.sops.placeholder.mattermost_bot_token}
        MATTERMOST_ALLOWED_USERS=${config.sops.placeholder.mattermost_ops_users}
        MATTERMOST_REPLY_MODE=thread
        MATTERMOST_REQUIRE_MENTION=true
        MATTERMOST_HOME_CHANNEL=bx8cps71sfriucrcswcmc3fixe
        HERMES_LOCAL_STT_COMMAND=/opt/dotfiles-hermes/stt-host.sh {input_path} {output_dir}
        ANTHROPIC_TOKEN=${config.sops.placeholder.claude_oauth_token}
        TERMINAL_SSH_HOST=host.docker.internal
        TERMINAL_SSH_USER=${config.home.username}
        TERMINAL_SSH_KEY=/opt/data/ssh/id_ed25519
        TERMINAL_ENV=ssh
      '';
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
    initContent = lib.mkOrder 1500 (shellExports + ''
      export _ZO_DOCTOR=0
    '');
  };

  # Same environment for `bash -l`: Hermes' ssh terminal backend and ad-hoc
  # `ssh host bash -lc ...` are bash, and kubectl/hcloud must not silently
  # fall back to other defaults there.
  programs.bash = {
    enable = true;
    profileExtra = shellExports;
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
    # Our checkouts load without `direnv allow`: firstmate's crewmates work in
    # fresh treehouse worktrees, each a new path, and a blocked .envrc leaves
    # them without the repo's devshell (odoo: python, ruff, just, pre-commit).
    # Trade-off accepted: any .envrc under these prefixes runs unreviewed.
    config.whitelist.prefix = [
      "${config.home.homeDirectory}/workspace"
      "${config.home.homeDirectory}/.treehouse"
    ];
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
    # unset LANG makes less (git's pager) print emoji as <F0><9F>.. escapes
    LANG = "en_US.UTF-8";
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
    CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
    CLAUDE_CODE_AUTO_COMPACT_WINDOW = "500000";
  } // lib.optionalAttrs server {
    # firstmate keeps its own memory (data/captain.md, data/learnings.md)
    CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
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
    (pkgs.callPackage ./pkgs/herdr { })
    rtk
    (pkgs.callPackage ./pkgs/pi { })
    figma-axi
    (pkgs.callPackage "${inputs.treehouse}/package.nix" { })
    jq

    pgcli
    postgresql
    poppler-utils # pdftotext, for `kx equity import`

    nerd-fonts.hack
  ] ++ lib.optionals (!server) [
    # Heavy, uncached python/arrow build on x86_64-darwin; not needed headless
    inputs.sqlit.packages.${system}.default
  ] ++ lib.optionals server [
    hermesStt
    fmTg
  ];


  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";


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


  # herdr server up at login so remote attaches and Hermes find it without a
  # terminal ever having been opened (the brew service did this before).
  # `herdr machine add` only accepts a server that is its own session leader
  # (getsid == getpid); launchd does not do that, so setsid it and forward
  # TERM so launchd can still stop it.
  launchd.agents.herdr = {
    enable = true;
    config = {
      ProgramArguments = [
        (toString (pkgs.writeShellScript "herdr-server" ''
          ${pkgs.util-linux}/bin/setsid ${config.home.profileDirectory}/bin/herdr server &
          trap 'kill -TERM $!' TERM INT
          wait
        ''))
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-server.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-server.log";
      EnvironmentVariables.PATH = "${config.home.profileDirectory}/bin:${brewPrefix}/bin:/usr/local/bin:/usr/bin:/bin";
    };
  };

  launchd.agents.colima = lib.mkIf server {
    enable = true;
    config = {
      ProgramArguments = [
        (toString (pkgs.writeShellScript "colima-agent" ''
          colima=${config.home.profileDirectory}/bin/colima
          # `start --foreground` exits at once if colima was started by hand,
          # which would make KeepAlive relaunch it every 10s. Hold until that
          # instance stops, then fail so launchd relaunches us to own it.
          if $colima status >/dev/null 2>&1; then
            while $colima status >/dev/null 2>&1; do sleep 30; done
            exit 1
          fi
          exec $colima start --foreground
        ''))
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/colima.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/colima.log";
      EnvironmentVariables.PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin";
    };
  };

  # Hermes runs in docker: upstream does not support macOS on Intel natively.
  # Its shell tool reaches this host over ssh (TERMINAL_SSH_* in hermes.env).
  launchd.agents.hermes = lib.mkIf server {
    enable = true;
    config = {
      ProgramArguments = [
        (toString (pkgs.writeShellScript "hermes-gateway" ''
          export DOCKER_HOST="unix://${config.home.homeDirectory}/.colima/default/docker.sock"
          until ${pkgs.docker}/bin/docker info >/dev/null 2>&1; do sleep 5; done
          exec ${pkgs.docker-compose}/bin/docker-compose -f ${hermesCompose} up --no-color
        ''))
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/hermes.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/hermes.log";
    };
  };

  # firstmate is a clone, not a package (the checkout is the agent home and
  # updates itself via /updatefirstmate), so clone once if absent, then seed
  # config/ and data/: gitignored there and curated by firstmate afterwards,
  # hence copied once rather than symlinked.
  home.activation.firstmateSeed = lib.hm.dag.entryAfter ["writeBoundary"] ''
    fm=${config.home.homeDirectory}/workspace/firstmate
    if [ ! -d "$fm/bin" ]; then
      mkdir -p "$(dirname "$fm")"
      ${pkgs.git}/bin/git clone --quiet https://github.com/kunchenguid/firstmate "$fm" || echo "firstmate: clone failed, seed skipped" >&2
    fi
    if [ -d "$fm/bin" ]; then
      for f in $(cd ${dotfiles}/home/firstmate && find . -type f); do
        mkdir -p "$fm/$(dirname "$f")"
        [ -e "$fm/$f" ] || cp "${dotfiles}/home/firstmate/$f" "$fm/$f"
      done
    fi
  '';

  # World-writable: the container's `hermes` uid is not ours on the virtiofs
  # mount, and the only thing in here is chat attachments.
  home.activation.hermesOpsDocuments = lib.mkIf server (lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p ${config.home.homeDirectory}/.hermes/ops-documents
    chmod 777 ${config.home.homeDirectory}/.hermes/ops-documents
  '');

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
