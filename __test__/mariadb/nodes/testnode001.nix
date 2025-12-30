{ config, pkgs, lib, ... }: {
  # Enable MariaDB standalone instance using native NixOS service
  config.services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    
    settings = {
      mysqld = {
        bind-address = "127.0.0.1";
        port = 3306;
      };
    };

    # Create initial database
    initialDatabases = [
      { name = "testdb"; }
    ];

    # Create test user with access to testdb
    ensureUsers = [
      {
        name = "testuser";
        ensurePermissions = {
          "testdb.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  # Open firewall for MariaDB (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 3306 ];
}
