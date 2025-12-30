{ config, pkgs, lib, ... }: {
  # Enable Redis standalone instance using native NixOS service
  config.services.redis.package = pkgs.redis;
  
  config.services.redis.servers."" = {
    enable = true;
    bind = "127.0.0.1";
    port = 6380;
    databases = 16;
  };

  # Install redis-cli for CLI access
  config.environment.systemPackages = with pkgs; [
    redis
  ];

  # Open firewall for Redis (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 6380 ];
}
