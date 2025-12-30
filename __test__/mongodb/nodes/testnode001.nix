{ config, pkgs, lib, ... }: {
  # Enable MongoDB standalone instance using native NixOS service
  config.services.mongodb = {
    enable = true;
    package = pkgs.mongodb-ce;
    bind_ip = "127.0.0.1";
    extraConfig = ''
      net.port: 27018
    '';
  };

  # Install mongosh for CLI access
  config.environment.systemPackages = with pkgs; [
    mongosh
  ];

  # Open firewall for MongoDB (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 27018 ];
}
