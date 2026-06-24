<p align="center">
  <img src="assets/meccha-camouflage-banner.png" alt="Meccha Camouflage banner" width="100%" />
</p>

# Meccha Camouflage

Native runtime for MECCHA CHAMELEON.

## Download

Download the latest `meccha-camouflage.exe` from GitHub Releases:

- https://github.com/acentrist/MecchaCamouflage/releases/latest

The EXE is self-contained. It can be placed anywhere, including Downloads. It finds `PenguinHotel-Win64-Shipping.exe` by process name and extracts its embedded bridge DLL under `%LOCALAPPDATA%\MecchaCamouflage\runtime\`.

## Usage

1. Start MECCHA CHAMELEON.
2. Start `meccha-camouflage.exe`.
3. Press `F10` in game.

Runtime diagnostics are written to `%LOCALAPPDATA%\MecchaCamouflage\runtime\`.

## Development

The primary development environment is Windows with MSVC.

```bash
make build
make run
make probe
make copy-to-game
make package
```

Development defaults are defined at the top of `Makefile`:

- `GAME_ROOT`
- `NATIVE_APPLY_MODE`
- `DEV_PROBE_ARGS`
- `VERSION`

The managed Dumper7 SDK output is stored in `dumper-sdk/`. The Dumper-7 tool source is stored in `dumper-sdk/tool/`.
