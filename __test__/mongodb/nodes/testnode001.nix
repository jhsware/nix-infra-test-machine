{ config, pkgs, lib, ... }: {
  # Enable MongoDB standalone instance
  config.services.mongodb = {
    enable = true;
    package = pkgs.mongodb-ce;
    bind_ip = "127.0.0.1";
  };

  # Support packages for testing
  config.environment.systemPackages = with pkgs; [
    mongosh
  ];

  # Open firewall for MongoDB (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 27017 ];
}
