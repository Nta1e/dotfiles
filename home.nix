{ pkgs, lib, config, sqlit, ... }:
let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
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
      export PATH="$HOME/.local/bin:$PATH"
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
        format = "[  $duration ]($style)";
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
      theme = "gruvbox_dark_hard";
      editor = {
        line-number = "relative";
        lsp.display-messages = true;
      };
      keys.normal = {
        space.space = "file_picker";
        space.q = ":q";
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
  home.shellAliases = {
    cd = "z";
    g = "git";
    cat = "bat";
    gc = "gitmoji commit";
    k = "kubecolor";
    switch = "sudo darwin-rebuild switch --flake ${dotfiles}#main";
    rshell = "source ~/.zshrc";
  };

  programs.direnv.nix-direnv.enable = true;

  programs.btop = {
    enable = true;
    settings = {
      # more settings here https://github.com/aristocratos/btop#btopconf-auto-generated-if-not-found
      vim_keys = true;
    };
  };

  programs.ghostty = {
    package = pkgs.ghostty-bin;
    enable = true;
    settings = {
      theme = "Gruvbox Dark Hard";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Nta1e";
      user.email = "shadikntale@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
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

    sqlit.packages.${pkgs.system}.default

    docker
    docker-compose
    docker-buildx
    colima
  
    yq
    uv
    nixd
    lefthook
    cocoapods

    rtk
    pgcli
    postgresql

  ];

}
