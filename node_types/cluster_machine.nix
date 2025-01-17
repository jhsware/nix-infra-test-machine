{ config, pkgs, ... }:
let
  # Add variables here
in
{
  config.environment.systemPackages = with pkgs; [
    # Add some packages
    
  ];

  # Enable podman to run containers
  config.infrastructure.podman.enable = false;
}