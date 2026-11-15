{ pkgs, ... }:
let
  maintenance = import ./bex-cache-maintenance { inherit pkgs; };
in
{
  home.packages = [ maintenance ];
  systemd.user.services.bex-cache-maintenance = {
    Unit.Description = "Expire unused Bex build outputs within a shared cache budget";
    Service = {
      Type = "oneshot";
      ExecStart = "${maintenance}/bin/bex-cache-maintenance";
      Nice = 10;
      TimeoutStartSec = "30min";
    };
  };
  systemd.user.timers.bex-cache-maintenance = {
    Unit.Description = "Maintain Bex build storage hourly";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
