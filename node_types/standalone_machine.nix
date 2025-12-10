{ config, pkgs, ... }:
let
  # Add variables here
in
{
  # This file contains common configuration across your entire fleet
  # of standalone machines.
  config.environment.systemPackages = with pkgs; [
    # Useful tools for debugging and administration
    htop
    curl
    wget
    netcat
    jq
  ];

  # Enable podman for container support (disabled by default)
  # Set to true in individual node configs or here for fleet-wide
  config.infrastructure.podman.enable = false;
}
