import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'reports_screen.dart';
import 'account_management_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _pausedTime;
  // Tabs are built lazily, on first visit, rather than all five up front --
  // an eager IndexedStack instantiates every tab's State (and its initState
  // DB queries) immediately on app launch, firing 15+ concurrent SQLite
  // queries before the user has looked at anything but the Dashboard.
  final Set<int> _visitedIndices = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void clearCache() {
    setState(() {
      _visitedIndices.retainWhere((i) => i == _currentIndex);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final difference = DateTime.now().difference(_pausedTime!);
        if (difference.inMinutes >= 1) {
          // Lock the app after 1 minute in background. HomeShell's observer
          // stays registered even while another screen is pushed on top of
          // it, so a plain pushReplacementNamed would replace whatever
          // route happens to be topmost -- not HomeShell -- burying it (and
          // anything else on the stack) rather than actually locking the
          // app. Clear the whole stack down to just the lock screen instead.
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/pin_entry',
              (route) => false,
            );
          }
        }
        _pausedTime = null;
      }
    }
  }

  static const List<Widget Function()> _screenBuilders = [
    DashboardScreen.new,
    TransactionsScreen.new,
    ReportsScreen.new,
    AccountManagementScreen.new,
    SettingsScreen.new,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _screenBuilders.length; i++)
            _visitedIndices.contains(i)
                ? _screenBuilders[i]()
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _visitedIndices.add(index);
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1a1a2e),
        selectedItemColor: Colors.blue[400],
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Accounts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
