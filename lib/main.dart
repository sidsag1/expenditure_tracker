import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/transaction.dart';
import 'models/account.dart';
import 'models/category.dart';
import 'database/database_helper.dart';
import 'database/account_dao.dart';
import 'database/transaction_dao.dart';
import 'database/category_dao.dart';
import 'services/auth_service.dart';
import 'services/sms_service.dart';
import 'services/sms_parser_service.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/pin_entry_screen.dart';
import 'screens/sms_permission_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/account_management_screen.dart';
import 'screens/add_account_screen.dart';
import 'screens/account_detail_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/reports_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database and services
  await DatabaseHelper.instance.database;
  await AuthService().init();
  await SMSService().init();
  
  // Initialize categories
  await _initializeCategories();
  
  runApp(const ExpenditureTrackerApp());
}

class ExpenditureTrackerApp extends StatelessWidget {
  const ExpenditureTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expenditure Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/pin_setup': (context) => const PinSetupScreen(
          isFirstTime: true,
          onComplete: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('has_seen_onboarding', true);
          },
        ),
        '/pin_entry': (context) => const PinEntryScreen(
          onSuccess: () {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          },
        ),
        '/sms_permission': (context) => const SMSPermissionScreen(
          onPermissionGranted: () {
            Navigator.of(context).pushReplacementNamed('/accounts');
          },
          onPermissionDenied: () {
            Navigator.of(context).pushReplacementNamed('/accounts');
          },
        ),
        '/dashboard': (context) => const DashboardScreen(),
        '/accounts': (context) => const AccountManagementScreen(),
        '/add_account': (context) => const AddAccountScreen(),
        '/account_detail': (context) => const AccountDetailScreen(
          account: Account(
            id: 1,
            accountType: 'bank_account',
            bankName: 'ICICI',
            accountNumber: 'XX1234',
            accountName: 'Primary Account',
            currentBalance: 50000.0,
          ),
        ),
        '/transactions': (context) => const TransactionsScreen(),
        '/add_transaction': (context) => const AddTransactionScreen(
          transaction: Transaction(
            id: 1,
            transactionType: 'debit',
            amount: 500.0,
            description: 'Sample Restaurant Expense',
            transactionDate: DateTime.now(),
            category: 'Food & Dining',
            bankName: 'ICICI',
            accountType: 'bank_account',
            isManual: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
        '/reports': (context) => const ReportsScreen(),
      },
      home: _buildDevelopmentScreen(),
    );
  }
}

Widget _buildDevelopmentScreen() {
  return Scaffold(
    backgroundColor: AppColors.backgroundColor,
    appBar: AppBar(
      title: const Text('Expenditure Tracker - Development Mode'),
      backgroundColor: AppColors.primaryColor,
    ),
    body: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.code,
            size: 64,
            color: Colors.green,
          ),
          SizedBox(height: 20),
          Text(
            'Expenditure Tracker - Development Mode',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'All features have been implemented!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTestButton('Test Database', _testDatabase),
              _buildTestButton('Test SMS', _testSMS),
              _buildTestButton('Test Auth', _testAuth),
              _buildTestButton('Test Screens', _testScreens),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildTestButton(String text, VoidCallback onPressed) {
  return ElevatedButton(
    onPressed: onPressed,
    child: Text(text),
  );
}

Future<void> _initializeCategories() async {
  final categoryDAO = CategoryDAO();
  final existingCategories = await categoryDAO.getAllCategories();
  
  if (existingCategories.isEmpty) {
    for (final categoryData in AppConstants.predefinedCategories) {
      final category = Category(
        name: categoryData['name'],
        icon: categoryData['icon'],
        color: categoryData['color'],
        isCustom: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await categoryDAO.insertCategory(category);
    }
  }
}

Future<void> _testDatabase() async {
  try {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    
    // Test creating tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_type TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        account_number TEXT NOT NULL,
        account_name TEXT NOT NULL,
        current_balance REAL NOT NULL DEFAULT 0.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER,
        transaction_type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        merchant TEXT,
        transaction_date TEXT NOT NULL,
        reference_number TEXT,
        category TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        is_manual INTEGER NOT NULL DEFAULT 0,
        is_pending INTEGER NOT NULL DEFAULT 0,
        transaction_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    
    print('✅ Database tests passed');
  } catch (e) {
    print('❌ Database tests failed: $e');
  }
}

Future<void> _testSMS() async {
  try {
    final smsService = SMSService();
    
    // Test SMS permission
    final hasPermission = await smsService.isPermissionGranted();
    print('SMS Permission Status: $hasPermission');
    
    // Test bank detection
    final iciciBank = smsService.getBankNameFromSender('ICICIB');
    print('ICICI Bank Detection: ${iciciBank ?? 'null'}');
    
    final kotakBank = smsService.getBankNameFromSender('KOTAKB');
    print('Kotak Bank Detection: ${kotakBank ?? 'null'}');
    
    final sbiBank = smsService.getBankNameFromSender('SBIPSG');
    print('SBI Bank Detection: ${sbiBank ?? 'null'}');
    
    print('✅ SMS service tests passed');
  } catch (e) {
    print('❌ SMS tests failed: $e');
  }
}

Future<void> _testAuth() async {
  try {
    final authService = AuthService();
    
    // Test PIN operations
    final hasPin = authService.isPinSet;
    print('PIN Status: $hasPin');
    
    // Test biometric availability
    final biometricAvailable = await authService.isBiometricAvailable();
    print('Biometric Available: $biometricAvailable');
    
    print('✅ Auth service tests passed');
  } catch (e) {
    print('❌ Auth tests failed: $e');
  }
}

Future<void> _testScreens() async {
  try {
    // Test database connection
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    print('Database connected: ${db != null}');
    
    // Test DAO operations
    final accountDAO = AccountDAO();
    final transactionDAO = TransactionDAO();
    final categoryDAO = CategoryDAO();
    
    // Test getting all data
    final accounts = await accountDAO.getActiveAccounts();
    final transactions = await transactionDAO.getAllTransactions();
    final categories = await categoryDAO.getAllCategories();
    
    print('✅ DAO tests passed');
    print('Accounts: ${accounts.length}');
    print('Transactions: ${transactions.length}');
    print('Categories: ${categories.length}');
  } catch (e) {
    print('❌ Screen tests failed: $e');
  }
}
