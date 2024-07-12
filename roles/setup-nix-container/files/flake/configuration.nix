# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ 
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];
  
  networking.hostName = "{{ inventory_hostname }}";
  time.timeZone = "{{ timezone }}";

  environment.systemPackages = with pkgs; [
    python3
    ranger
    zsh
    oh-my-zsh
    btop

    # Is it neccessary to install this just for a nicer MOTD? .. Yes
    figlet
  ];

  users = {
    mutableUsers = false;
    defaultUserShell = pkgs.zsh;
    users.ansible = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      hashedPassword = "";
    };
  };

  # Enable passwordless sudo.
  security.sudo.extraRules = [
    {
      users = [ "ansible" ];
      commands = [
        { 
          command = "ALL" ;
          options= [ "NOPASSWD" ];
        }
      ];
    }
  ];

  system.userActivationScripts.zshrc = "touch .zshrc";

  programs.zsh = {
    enable = true;
    enableBashCompletion = true;
    ohMyZsh = {
      enable = true;
      theme = "bira";
    };

    promptInit = ''
      echo "$fg[red]$(figlet {{ inventory_hostname }} -f /etc/nixos/figlet-font.flf)"
      # TODO: Work out why this isn't being properly set in ZSH
      export HOST={{ inventory_hostname }}
    '';
  };

{% for userKeys in vault_pubkeys %}
  users.users.{{ userKeys.username }}.openssh.authorizedKeys.keys = [
  {% for key in userKeys.pubkeys %}
    "{{ key }}"
  {% endfor %}
  ];
{% endfor %}  

  services.openssh.enable = true;

  system.stateVersion = "23.11";
}