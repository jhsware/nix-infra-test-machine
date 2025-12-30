{ config, pkgs, lib, ... }: {
  # Enable PostgreSQL standalone instance using native NixOS service
  config.services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    enableTCPIP = true;
    
    authentication = ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            trust
      host    all             all             ::1/128                 trust
    '';

    settings = {
      listen_addresses = lib.mkForce "127.0.0.1";
    };

    # Create initial database
    ensureDatabases = [ "testdb" ];
  };

  # Open firewall for PostgreSQL (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 5432 ];
}
