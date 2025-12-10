{ config, pkgs, lib, ... }: {
  # Enable podman for container runtime
  config.infrastructure.podman.enable = true;

  # Enable MongoDB standalone instance
  config.infrastructure.mongodb-4 = {
    enable = true;
    bindToIp = "127.0.0.1";
    bindToPort = 27017;
  };

  # Open firewall for MongoDB (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 27017 ];
}
