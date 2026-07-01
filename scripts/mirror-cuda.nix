{
  writeShellApplication,
  rclone,
  wget,
}:
writeShellApplication {
  name = "mirror-cuda-to-r2";

  runtimeInputs = [
    rclone
    wget
  ];

  text = builtins.readFile ./mirror-cuda-to-r2.sh;
}
