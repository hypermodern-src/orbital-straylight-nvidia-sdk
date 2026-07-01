# Secrets Management with Agenix

This directory contains encrypted secrets managed by [agenix](https://github.com/ryantm/agenix).

## Setup

1. Enter the dev shell to get the `agenix` CLI:
   ```bash
   nix develop
   ```

## Usage

### Creating/Editing Secrets

```bash
# Edit encryption key (creates if doesn't exist)
agenix -e secrets/encryption-key.age

# Edit R2 credentials
agenix -e secrets/r2-credentials.age

# Edit NVIDIA credentials
agenix -e secrets/nvidia-credentials.age
```

### Adding New Users

Edit `secrets/secrets.nix` and add their SSH public key, then rekey:

```bash
agenix --rekey
```

## Secrets

- **encryption-key.age**: Symmetric key for encrypting non-redistributable packages (TensorRT-RTX,
  etc.)
- **r2-credentials.age**: Cloudflare R2 API credentials
- **nvidia-credentials.age**: NVIDIA Developer account credentials for automated downloads
