{ config, pkgs, ... }:
let
  # Add variables here
in
{
  # This file contains common configuration across your entire fleet
  # of standalone machines.
  config.environment.systemPackages = with pkgs; [
    # Add some packages
    
  ];

  # Enable podman to run containers
  config.infrastructure.podman.enable = false;
}