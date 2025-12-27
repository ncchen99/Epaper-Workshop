# LEGO E-Ink Camera Controller

A Flutter app for controlling an Arduino E-Paper (E-Ink) display with a **LEGO brick-style UI**.

![LEGO Style](assets/images/demo_1.png)

## Features

- 🧱 **LEGO Brick UI** - Plastic-like textures, studs, and raised shadows
- 📷 **Image Selection** - Choose from preset images or upload your own
- 🔌 **Arduino Integration** - REST API communication with E-Paper device
- ☁️ **Cloud Upload** - Upload images to Cloudflare R2
- 📊 **Status Logging** - Real-time status updates

## Quick Start

### 1. Install Dependencies

```bash
cd Flutter
flutter pub get
```

### 2. Run the App

```bash
flutter run
```

### 3. Configuration

Edit `lib/config.dart` to configure:

```dart
// Toggle mock mode
static const bool mockMode = true;  // false = real device

// Arduino device URL
static const String arduinoBaseUrl = 'http://epaper.local';

// R2 Cloud Storage
static const String r2PublicUrl = 'https://pub-xxx.r2.dev';
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── config.dart               # Configuration
├── theme/
│   └── lego_theme.dart       # LEGO design system
├── widgets/
│   ├── lego_card.dart        # Card with studs
│   ├── lego_button.dart      # Animated button
│   ├── lego_status_chip.dart # Status indicator
│   ├── lego_top_bar.dart     # App bar
│   ├── lego_image_tile.dart  # Image selection
│   └── lego_bottom_sheet.dart# Image source picker
├── providers/
│   ├── device_connection_provider.dart
│   ├── image_selection_provider.dart
│   └── log_provider.dart
├── services/
│   ├── arduino_service.dart  # REST API client
│   └── upload_service.dart   # R2 upload
└── screens/
    └── home_screen.dart      # Main screen
```

## Arduino API

The app communicates with the Arduino device via REST API:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/show?slot={1,2,3}` | GET | Display image from slot |
| `/api/update?slot={1,2,3}` | GET | Update from cloud & display |

## Mock Mode

When `mockMode = true`:
- No real network calls are made
- Simulated delays for realistic UX
- Perfect for UI development and demos

## Switching to Real Mode

1. Set `mockMode = false` in `config.dart`
2. Ensure Arduino device is on the same network
3. Verify `arduinoBaseUrl` is correct
4. (Optional) Configure R2 upload endpoint

## Dependencies

- `flutter_riverpod` - State management
- `dio` - HTTP client
- `image_picker` - Camera/gallery access
- `google_fonts` - LEGO-style typography

## License

MIT
