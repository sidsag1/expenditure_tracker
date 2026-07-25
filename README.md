# 📱 Expenditure Tracker

A Flutter-based Android application that automatically tracks expenditure from various financial sources (bank accounts, debit cards, credit cards, digital wallets) by parsing SMS messages from banks like ICICI, Kotak, and SBI.

## 🎯 Key Features
- **Smart SMS Parsing**: Automatically read and parse SMS messages from supported banks. Runs incrementally on an isolate for high performance.
- **Background Syncing**: Syncs new messages automatically in the background when the app resumes.
- **Account Management**: Add, edit, and manage bank accounts, debit cards, credit cards, and digital wallets.
- **Expense Categorization**: Tag and categorize expenses for better organization.
- **Visual Analytics**: Interactive pie charts and bar charts to track spending patterns using `fl_chart`.
- **Security**: PIN/Password protection for app access, with background re-locking and screenshot prevention (`FLAG_SECURE`).
- **Bank Support**: ICICI, Kotak, and SBI message parsing.

## 🏗️ Technical Architecture
- **Framework**: Flutter (Dart)
- **Database**: SQLite with `sqflite` package (highly optimized paginated queries)
- **Charts**: `fl_chart` for data visualization
- **Permissions**: `permission_handler` for SMS access
- **Security**: `flutter_secure_storage` for PIN management
- **Platform**: Android Only (Targeting SDK 36)

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (stable channel)
- Android SDK + a connected device or emulator (minSdk 24)

### Build for Android

```bash
flutter pub get
flutter run                # debug build on connected device/emulator
flutter build apk --debug  # debug APK
```

### Release Build
To build a signed release bundle/APK, you need to provide a `key.properties` file at `android/key.properties`:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=<alias>
storeFile=<path_to_keystore>
```

```bash
flutter build appbundle --release
flutter build apk --release
```

Notes:
- SMS parsing requires a real Android device — grant SMS permission on first launch.
- If `key.properties` is missing, the release build will fall back to using the debug keystore.

### Run tests

```bash
flutter test
```

## 🚧 Project Status

Rounds 1–6 of `docs/ENTERPRISE_READINESS_PLAN.md` (correctness, security, accounting, parser
robustness, performance) are implemented and covered by tests. Round 7 (UX/navigation) landed the
bottom-nav shell, account editing, and a Settings screen, but Settings' CSV export and privacy
policy/license links are still stubs, biometric unlock isn't wired into the actual unlock flow yet,
and the hardcoded-colors/deprecated-API accessibility pass (P5-6) and error-message cleanup (P5-7)
haven't started. Round 8 (release engineering) has a real application ID, release signing config,
and a minified/shrunk release build, but still needs a real keystore, launcher icon/splash, and
the Play Store listing assets before a store submission. See the plan doc for the current
per-item status.
