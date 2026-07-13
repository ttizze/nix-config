{
  inputs,
  username,
  overlay,
  allowUnfreePredicate,
  ...
}:
{
  imports = [ ../../modules/darwin/system.nix ];

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    overlays = [ overlay ];
    config.allowUnfreePredicate = allowUnfreePredicate;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = { inherit inputs username; };
    users.${username}.imports = [
      ../../home/tt/common.nix
      ../../home/tt/darwin.nix
    ];
  };
}
