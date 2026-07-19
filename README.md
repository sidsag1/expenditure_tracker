# 📱 Expenditure Tracker - Mobile App Design Document

## Project Overview
A Flutter-based Android application that automatically tracks expenditure from various financial sources (bank accounts, debit cards, credit cards, digital wallets) by parsing SMS messages from banks like ICICI, Kotak, and SBI.

## 🎯 Key Features
- **Account Management**: Add and manage bank accounts, debit cards, credit cards, and digital wallets
- **Smart SMS Parsing**: Automatically read and parse SMS messages from supported banks
- **Expense Categorization**: Tag and categorize expenses for better organization
- **Visual Analytics**: Reports and charts to track spending patterns
- **Security**: Password/PIN protection for app access
- **Bank Support**: ICICI, Kotak, and SBI message parsing

## 🏗️ Technical Architecture
- **Framework**: Flutter (Dart)
- **Database**: SQLite with sqflite package
- **Charts**: fl_chart for data visualization
- **Permissions**: permission_handler for SMS access
- **Security**: local_auth for biometric support
- **Platform**: Android (with potential iOS expansion)

## 📊 Project Progress Tracker

### Development Phases
- [x] **Phase 1: Project Setup & Foundation**
  - [x] Initialize Flutter project with Android configuration
  - [x] Set up project structure and folder organization
  - [x] Add required dependencies (SQLite, charts, permissions)
  - [x] Configure Android permissions for SMS reading

- [x] **Phase 2: Database & Data Models**
  - [x] Design SQLite database schema for accounts, transactions, categories
  - [x] Create data models for Account, Transaction, Category entities
  - [x] Implement database operations (CRUD)

- [x] **Phase 3: Authentication & Security**
  - [x] Create PIN/Password setup screen
  - [x] Implement authentication logic with local storage
  - [x] Add biometric authentication support

- [x] **Phase 4: Account Management UI**
  - [x] Create screens for adding bank accounts
  - [x] Build debit card, credit card, and wallet management screens
  - [x] Implement account validation and storage

- [x] **Phase 5: SMS Reading & Filtering**
  - [x] Implement SMS permission handling
  - [x] Create SMS reader service with bank number filtering
  - [x] Build SMS sync mechanism for new messages

- [x] **Phase 6: SMS Parsing Engine**
  - [x] Create regex patterns for ICICI bank messages (account & debit card)
  - [x] Build parser for ICICI credit card messages
  - [x] Implement Kotak bank message parsing
  - [x] Add SBI bank message parsing support
  - [x] Create transaction validation and duplicate detection

- [x] **Phase 7: Expense Management**
  - [x] Build expense categorization system
  - [x] Create tagging functionality for transactions
  - [x] Implement transaction editing and manual adjustments

- [x] **Phase 8: Reports & Analytics**
  - [x] Create spending reports (daily, monthly, yearly)
  - [x] Build visual charts using Flutter charts package
  - [x] Implement filtering and search functionality

- [x] **Phase 9: Main Dashboard**
  - [x] Design main dashboard with account overview
  - [x] Create navigation structure
  - [x] Implement real-time balance calculations

- [x] **Phase 10: Testing & Polish**
  - [x] Test SMS parsing accuracy with provided examples
  - [x] Performance optimization
  - [x] UI/UX improvements
  - [x] Final testing and bug fixes

## 📱 Supported Banks & SMS Formats

### ICICI Bank
- **Account Messages**: Credit/debit notifications with balance info
- **Debit Card**: Transaction alerts with merchant details
- **Credit Card**: Purchase notifications and payment confirmations

### Kotak Bank
- **Debit Card**: POS and online transaction alerts
- **UPI**: Money transfer notifications
- **Account**: IMPS and NEFT transaction details

### SBI Bank
- **Account**: IMPS transfer notifications
- **UPI**: Transaction alerts with reference numbers
- **Account**: Credit notifications with customer details

## 🔒 Security Features
- PIN/Password protection for app access
- Local data encryption for sensitive information
- Secure SMS permission handling
- Biometric authentication support (fingerprint/face unlock)

## 📈 Analytics & Reporting
- Daily, monthly, and yearly spending reports
- Visual charts showing expense trends
- Category-wise expense breakdown
- Balance tracking across all accounts
- Search and filter functionality

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (stable channel, Dart >= 3.10.4) with the Android toolchain (`flutter doctor` should show no Android issues)
- Android SDK + a connected device or emulator

### Build for Android

```bash
flutter pub get
flutter run                # debug build on connected device/emulator
flutter build apk --debug  # debug APK
flutter build apk --release  # release APK (build/app/outputs/flutter-apk/app-release.apk)
```

Notes:
- The release build currently signs with the debug key (fine for installing on your own phone). Set up a proper signing config in `android/app/build.gradle.kts` before any store release.
- SMS parsing requires a real Android device — grant SMS permission on first launch.

### Run tests

```bash
flutter test
```

## ✅ Project Status: **COMPLETED** (100%)

**All 10 phases have been successfully implemented!**

---

*This project has been developed as a comprehensive solution for automatic expense tracking through intelligent SMS parsing. The application is now fully functional and ready for deployment with the initial version.*
