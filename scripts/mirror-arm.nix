{
  writeShellApplication,
  rclone,
  wget,
  nix,
  perl,
}:
writeShellApplication {
  name = "mirror-arm-to-r2";

  runtimeInputs = [
    rclone
    wget
    nix
    perl
  ];

  text = builtins.readFile ./mirror-arm-to-r2.sh;
}
