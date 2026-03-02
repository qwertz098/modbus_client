# Modbus TCP Test Client

A Flutter-based Android app for testing Modbus TCP communication with industrial devices.

## Features

- **Dynamic endpoint list** — Add/remove endpoints with the + button
- **Full Modbus TCP support** — FC01–04 (read), FC05/06 (write)
- **Data types** — BOOL, INT16, UINT16, INT32, UINT32, FLOAT32
- **Bit-level access** — Select individual bits (0–15) for BOOL types
- **Polling** — Manual read, or automatic at 500ms / 1s / 5s / 10s
- **Connection status** — Per-endpoint status indicator (grey/amber/green/red)
- **Byte order** — Global setting: Big-Endian, Little-Endian, Word-Swap
- **Profiles** — Save/load named configurations, auto-save on exit
- **Smart defaults** — New endpoints copy settings from the last row

## Setup & Build

### Prerequisites

- Flutter SDK ≥ 3.0 — [install guide](https://docs.flutter.dev/get-started/install)
- Android SDK (via Android Studio or command-line tools)

### Steps

```bash
# 1. Create Flutter scaffold
flutter create --org com.modbusclient modbus_tcp_client
cd modbus_tcp_client

# 2. Replace lib/ and pubspec.yaml with the provided source files
#    (copy the lib/ folder and pubspec.yaml from this package)

# 3. Install dependencies
flutter pub get

# 4. Run on connected device / emulator
flutter run

# 5. Build release APK
flutter build apk --release
```

The release APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

### Permissions

The app requires network access (INTERNET permission), which is included by default in Flutter Android projects. No additional manifest changes needed.

## Usage

### Endpoint Configuration

Each endpoint row defines one Modbus read/write operation:

| Field       | Description                            | Default       |
|-------------|----------------------------------------|---------------|
| IP Address  | Target device IP                       | 192.168.0.1   |
| Port        | Modbus TCP port                        | 502           |
| Unit ID     | Modbus slave unit identifier           | 3 (0x03)      |
| FC          | Function code (FC01–FC06)              | FC03          |
| Register    | Starting register address (decimal)    | 0             |
| Data Type   | BOOL, INT16, UINT16, INT32, UINT32, FLOAT32 | UINT16  |
| Bit         | Bit index 0–15 (BOOL only)            | 0             |

### Function Codes

| FC   | Operation              | Action         |
|------|------------------------|----------------|
| FC01 | Read Coils             | READ button    |
| FC02 | Read Discrete Inputs   | READ button    |
| FC03 | Read Holding Registers | READ button    |
| FC04 | Read Input Registers   | READ button    |
| FC05 | Write Single Coil      | WRITE button   |
| FC06 | Write Single Register  | WRITE button   |

### Polling

Use the segmented control at the top to select a polling interval, then press START. The app cycles through all read-type endpoints at the selected rate.

### Profiles

- **Auto-save**: Current configuration is automatically saved when modified and restored on app launch
- **Named profiles**: Tap the folder icon to save/load/delete named configurations

## Architecture

```
lib/
├── main.dart            App entry, theme, Provider setup
├── models.dart          Endpoint, Profile, enums
├── modbus_service.dart  Raw Modbus TCP protocol (dart:io Socket)
├── storage_service.dart SharedPreferences persistence
├── app_state.dart       ChangeNotifier state management
├── home_screen.dart     Main screen, polling bar, profile sheet
└── endpoint_card.dart   Endpoint card widget
```

The Modbus TCP implementation uses raw `dart:io` sockets with connection pooling per IP:port pair. No external Modbus library dependencies.

## License

MIT
