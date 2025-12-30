{ config, pkgs, lib, ... }: {
  # Create credentials file for MinIO
  config.environment.etc."minio/credentials".text = ''
    MINIO_ROOT_USER=testadmin
    MINIO_ROOT_PASSWORD=testpassword123
  '';

  # Enable MinIO standalone instance using native NixOS service
  config.services.minio = {
    enable = true;
    package = pkgs.minio;
    listenAddress = "127.0.0.1:9002";
    consoleAddress = "127.0.0.1:9003";
    dataDir = [ "/var/lib/minio/data" ];
    configDir = "/var/lib/minio/config";
    rootCredentialsFile = "/etc/minio/credentials";
    region = "us-east-1";
    browser = true;
  };

  # Install MinIO client and utilities for testing
  config.environment.systemPackages = with pkgs; [
    minio-client
    curl
    jq
  ];

  # Open firewall for MinIO (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 9002 9003 ];
}
