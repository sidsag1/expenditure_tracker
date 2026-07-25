import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/transaction.dart';
import 'models/account.dart';
import 'database/database_helper.dart';
import 'services/auth_service.dart';
import 'services/sms_service.dart';
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
  
  // Initialize database and services. DatabaseHelper._createDatabase already
  // seeds the predefined categories on first create; a second seed step here
  // used to duplicate that (see Category.predefinedCategories for the single
  // source of truth).
  await DatabaseHelper.instance.database;
  await AuthService().init();
  await SMSService().init();

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
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/splash':
            return MaterialPageRoute(builder: (_) => const SplashScreen());
          case '/onboarding':
            return MaterialPageRoute(builder: (_) => const OnboardingScreen());
          case '/pin_setup':
            return MaterialPageRoute(
              builder: (context) => PinSetupScreen(
                isFirstTime: true,
                onComplete: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('has_seen_onboarding', true);
                  if (context.mounted) {
                    Navigator.of(context)
                        .pushReplacementNamed('/sms_permission');
                  }
                },
              ),
            );
          case '/pin_entry':
            return MaterialPageRoute(
              builder: (context) => PinEntryScreen(
                onSuccess: () {
                  Navigator.of(context).pushReplacementNamed('/dashboard');
                },
              ),
            );
          case '/sms_permission':
            return MaterialPageRoute(
              builder: (context) => SMSPermissionScreen(
                onPermissionGranted: () {
                  Navigator.of(context).pushReplacementNamed('/accounts');
                },
                onPermissionDenied: () {
                  Navigator.of(context).pushReplacementNamed('/accounts');
                },
              ),
            );
          case '/dashboard':
            return MaterialPageRoute(builder: (_) => const DashboardScreen());
          case '/accounts':
            return MaterialPageRoute(builder: (_) => const AccountManagementScreen());
          case '/add_account':
            return MaterialPageRoute(builder: (_) => const AddAccountScreen());
          case '/account_detail':
            final account = settings.arguments as Account?;
            return MaterialPageRoute(
              builder: (_) => AccountDetailScreen(
                account: account ?? Account(
                  id: 1,
                  accountType: 'bank_account',
                  bankName: 'ICICI',
                  accountNumber: 'XX1234',
                  accountName: 'Primary Account',
                  currentBalance: 50000.0,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              ),
            );
          case '/transactions':
            return MaterialPageRoute(builder: (_) => const TransactionsScreen());
          case '/add_transaction':
            final transaction = settings.arguments as Transaction?;
            return MaterialPageRoute(
              builder: (_) => AddTransactionScreen(
                transaction: transaction,
              ),
            );
          case '/reports':
            return MaterialPageRoute(builder: (_) => const ReportsScreen());
          default:
            return MaterialPageRoute(builder: (_) => const SplashScreen());
        }
      },
    );
  }
}
