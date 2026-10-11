# CarRacers

3D arcade racing game made with Godot 4.3. Everything is built from code, so there are no external assets.

- Solo race or LAN multiplayer (host on one device, others join on the same Wi-Fi)
- Targets: Android (APK) and iPhone (IPA), built automatically by GitHub Actions
- Controls: W/S/A/D on keyboard, on-screen buttons on phones

## Run
Open the folder in Godot 4.3 and press F5.

## LAN play
Tap **Host LAN Game** on one device. Other devices on the same network see the game listed (UDP broadcast on port 24566) or can type the host IP. Game traffic uses ENet on UDP port 24565.

## Builds (GitHub Actions)
Push to `main` or run the workflows manually from the Actions tab:
- `Build Android APK`: debug-signed `CarRacers.apk`, ready to install.
- `Build iOS IPA (unsigned)`: `CarRacers-unsigned.ipa`. Sign and install it with your own tool (AltStore, Sideloadly, or Xcode with your Apple ID), or add your signing certificate and provisioning profile to the workflow.

## PS4 (planned, phase 2)
Godot cannot export to PS4. A separate PS4 client would need its own toolchain (for example the open-source OpenOrbis SDK) and would have to speak the same ENet protocol on port 24565. The network messages are in `scripts/net.gd` (`_state(pos, yaw, speed)`, plus a discovery packet `CARRACERS1|name`).
