# Agenix secrets configuration
#
# Usage:
#   agenix -e secrets/encryption-key.age

let
  user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf";
  user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp";

  allKeys = [
    user1
    user2
  ];
in
{
  # Symmetric encryption key for non-redistributable packages
  # Used to encrypt: TensorRT-RTX, Triton Container, etc.
  "encryption-key.age".publicKeys = allKeys;

  # R2 API credentials
  "r2-credentials.age".publicKeys = allKeys;

  # NVIDIA Developer credentials
  "nvidia-credentials.age".publicKeys = allKeys;
}
