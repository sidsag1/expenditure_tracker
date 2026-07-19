// Unit tests for SMSParserService.parseSMS.
//
// parseSMS is pure parsing logic (no database access), so it can run in the
// plain Dart test environment. Persistence paths (saveTransaction,
// isDuplicateTransaction) need sqflite and are exercised on-device instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/services/sms_parser_service.dart';

void main() {
  final parser = SMSParserService();

  group('sender identification', () {
    test('unknown sender returns null', () async {
      final txn = await parser.parseSMS(
        'Rs. 500.00 debited from your account on 12/07/26',
        'VM-UNKNWN',
      );
      expect(txn, isNull);
    });

    test('non-transactional message from a bank sender returns null',
        () async {
      final txn = await parser.parseSMS(
        'Dear Customer, your OTP for net banking login is 123456. Do not share it.',
        'VM-ICICIB',
      );
      expect(txn, isNull);
    });
  });

  group('ICICI messages', () {
    test('account debit is parsed with amount, date and type', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:12345. Call 18002662 for dispute.',
        'VM-ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 1500.00);
      expect(txn.bankName, 'ICICI');
      expect(txn.transactionDate, DateTime(2025, 9, 30));
      expect(txn.transactionId, isNotNull);
    });

    test('account credit is parsed as credit', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Account XX456 credited with Rs. 25,000.00 on 01-Oct-25. Info: SALARY.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 25000.00);
      expect(txn.transactionDate, DateTime(2025, 10, 1));
    });

    test('zero-amount message is rejected as invalid', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 0 on 30-Sep-25.',
        'VM-ICICIB',
      );
      expect(txn, isNull);
    });
  });

  group('Kotak messages', () {
    test('debit card spend is parsed with merchant', () async {
      final txn = await parser.parseSMS(
        'Rs.499.00 spent via Kotak Debit Card XX1234 at SWIGGY on 12-Jul-25. Not you? Call 18602662666.',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 499.00);
      expect(txn.merchant, 'SWIGGY');
      expect(txn.bankName, 'Kotak');
      expect(txn.transactionDate, DateTime(2025, 7, 12));
    });

    test('UPI sent is parsed as debit with recipient', () async {
      final txn = await parser.parseSMS(
        'Sent Rs.200.00 from Kotak Bank AC X1234 to john@upi on 12-07-25. UPI Ref 517276962160.',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 200.00);
      expect(txn.merchant, 'john@upi');
      expect(txn.referenceNumber, '517276962160');
    });
  });

  group('SBI messages', () {
    test('IMPS transfer is parsed with reference number', () async {
      final txn = await parser.parseSMS(
        'IMPS from Ac X9876 for Rs. 5,000.00 sent. Ref 601912345678 dt 01.12.25. If not done by you, call 1800111109.',
        'SBIINB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 5000.00);
      expect(txn.referenceNumber, '601912345678');
      expect(txn.bankName, 'SBI');
      expect(txn.transactionDate, DateTime(2025, 12, 1));
    });

    test('account credit is parsed as credit', () async {
      final txn = await parser.parseSMS(
        'Your a/c no. XXXXX1234 is credited by Rs.5,000.00 on 15-07-26 by transfer.',
        'CBSSBI',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 5000.00);
    });
  });

  group('generic parser (other banks and wallets)', () {
    test('HDFC debit is parsed with amount and date', () async {
      final txn = await parser.parseSMS(
        'Rs. 250.00 debited from HDFC Bank A/c XX9876 on 12/07/25 to VPA merchant@upi. Ref No: 987654321.',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 250.00);
      expect(txn.bankName, 'HDFC');
      expect(txn.transactionDate, DateTime(2025, 7, 12));
      expect(txn.referenceNumber, '987654321');
    });

    test('credited keyword produces a credit transaction', () async {
      final txn = await parser.parseSMS(
        'Your Axis Bank A/c XX1111 is credited with Rs. 10,000.00 on 01/07/2026.',
        'AXISBK',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 10000.00);
      expect(txn.bankName, 'Axis Bank');
    });

    test('wallet sender (Paytm) is recognised', () async {
      final txn = await parser.parseSMS(
        'Rs. 120.00 paid to Metro Card on 10/07/26 via Paytm Wallet.',
        'PYTM',
      );

      expect(txn, isNotNull);
      expect(txn!.bankName, 'Paytm');
      expect(txn.transactionType, 'debit');
      expect(txn.amount, 120.00);
    });

    test('message without an amount returns null', () async {
      final txn = await parser.parseSMS(
        'Your HDFC Bank account statement for June is ready.',
        'HDFCBK',
      );
      expect(txn, isNull);
    });
  });

  group('promotional and informational messages', () {
    test('loan/deal advertisement with an amount is rejected', () async {
      final txn = await parser.parseSMS(
        'Best Deal Alert!\n\nUnlock Loan of Rs. 520000 via PayZapp, on your HDFC Bank Credit Card x6955.\n\nKnow More: https://example.com/offer\nT&C',
        'HDFCBK',
      );
      expect(txn, isNull);
    });

    test('EMI due reminder is not treated as a debit', () async {
      final txn = await parser.parseSMS(
        'EMI of Rs 24688 for ICICI Bank Automobiles Loan XX9300 is due on 10-Jul-26. Please maintain sufficient funds in your linked Account XX4340 to avoid 5% per annum penal charges and Rs 500 bounce charges.',
        'VM-ICICIT',
      );
      expect(txn, isNull);
    });

    test('instant cash loan ad phrased as future credit is rejected',
        () async {
      final txn = await parser.parseSMS(
        'Instant Cash Alert! \nRs.879000 is ready to be credited to your Bank A/C without credit limit block: https://example.com/x - HDFC Bank',
        'HDFCBK',
      );
      expect(txn, isNull);
    });

    test('generic message with amount but no transaction verb is rejected',
        () async {
      final txn = await parser.parseSMS(
        'Get a personal loan of Rs. 500000 at just 10.5% interest with HDFC Bank!',
        'HDFCBK',
      );
      expect(txn, isNull);
    });

    test('credit card bill convert-to-EMI nudge is rejected', () async {
      final txn = await parser.parseSMS(
        'HDFC Bank Credit Card 6955 bill of Rs. 56539.2 can be paid in parts. Convert txns into EMIs. Check eligibility:https://hdfcbk.io/HDFCBK/s/epo4jBxl',
        'HDFCBK',
      );
      expect(txn, isNull);
    });
  });

  group('wallet messages (Blinkit)', () {
    final receivedAt = DateTime(2026, 7, 18, 14, 5);

    test('wallet payment is parsed as debit dated by SMS arrival', () async {
      final txn = await parser.parseSMS(
        'Payment of Rs. 273.00 from Blinkit Money Balance is successful. Updated balance: Rs. 1,390.00. Contact info@blinkit.com for queries. -blinkit',
        'JD-BLNKIT-S',
        receivedAt: receivedAt,
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 273.00);
      expect(txn.bankName, 'Blinkit');
      // Body carries no date, so the SMS timestamp is used
      expect(txn.transactionDate, receivedAt);
      expect(txn.category, 'Groceries');
    });

    test('wallet top-up is parsed as credit', () async {
      final txn = await parser.parseSMS(
        'Rs 255.00 added to your Blinkit Money account ending with 6522 successfully. Tap to view your balance : https://blinkit.link/blnkit/z/pg37wvh8 -blinkit',
        'JD-BLNKIT-S',
        receivedAt: receivedAt,
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 255.00);
      expect(txn.bankName, 'Blinkit');
      expect(txn.transactionDate, receivedAt);
    });
  });

  group('smart categorization', () {
    test('maps well-known merchants to spending categories', () {
      expect(parser.categorizeTransaction('paid at ZOMATO online order'),
          'Food & Dining');
      expect(parser.categorizeTransaction('spent on SWIGGY'), 'Food & Dining');
      expect(parser.categorizeTransaction('INDIGO AIRLINE ticket'), 'Travel');
      expect(parser.categorizeTransaction('AIR INDIA booking'), 'Travel');
      expect(parser.categorizeTransaction('spent at AMAZON FRESH'),
          'Groceries');
      expect(parser.categorizeTransaction('order from ZEPTO'), 'Groceries');
      expect(parser.categorizeTransaction('BLINKIT order'), 'Groceries');
      expect(parser.categorizeTransaction('BIGBASKET delivery'), 'Groceries');
      expect(parser.categorizeTransaction('purchase at AMAZON'), 'Shopping');
      expect(parser.categorizeTransaction('FLIPKART order'), 'Shopping');
      expect(parser.categorizeTransaction('NETFLIX subscription'),
          'Entertainment');
      expect(parser.categorizeTransaction('UBER trip'), 'Transportation');
      expect(parser.categorizeTransaction('PHARMEASY medicines'),
          'Health & Medical');
      expect(parser.categorizeTransaction('some unknown merchant'), isNull);
    });

    test('parsed card spend at a known merchant is auto-categorized',
        () async {
      final txn = await parser.parseSMS(
        'Rs.199 without OTP/PIN HDFC Bank Card x6955 At NETFLIX On 2026-06-13:08:56:40.Not U? Block&Reissue:Call 18002586161/SMS BLOCK CC 6955 to 7308080808',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.category, 'Entertainment');
    });

    test('credits are not auto-categorized as spending', () async {
      final txn = await parser.parseSMS(
        'Your Axis Bank A/c XX1111 is credited with Rs. 10,000.00 on 01/07/2026.',
        'AXISBK',
      );

      expect(txn, isNotNull);
      expect(txn!.category, 'uncategorized');
    });
  });

  group('real-world messages', () {
    test('ICICI UPI debit with dispute footer is parsed', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX340 debited for Rs 14.00 on 19-Jul-26; GANGA KUMAR YAD credited. UPI:620075350266. Call 18002662 for dispute. SMS BLOCK 340 to 9215676766.',
        'VM-ICICIT',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 14.00);
      expect(txn.bankName, 'ICICI');
      expect(txn.transactionDate, DateTime(2026, 7, 19));
    });

    test('HDFC card autopay (without OTP/PIN) is parsed as a debit', () async {
      final txn = await parser.parseSMS(
        'Rs.199 without OTP/PIN HDFC Bank Card x6955 At NETFLIX On 2026-06-13:08:56:40.Not U? Block&Reissue:Call 18002586161/SMS BLOCK CC 6955 to 7308080808',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 199.0);
      expect(txn.bankName, 'HDFC');
      expect(txn.transactionDate, DateTime(2026, 6, 13));
    });

    test('HDFC credit card payment received is parsed as a credit', () async {
      final txn = await parser.parseSMS(
        'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 29393.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6955 ON 7-7-2026.YOUR AVAILABLE LIMIT IS RS. 686166.10',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 29393.00);
      expect(txn.transactionDate, DateTime(2026, 7, 7));
    });

    test('HDFC duplicate confirmation SMS parses to the same day and amount',
        () async {
      final txn = await parser.parseSMS(
        'HDFC Bank Cardmember, Online Payment of Rs.29393 vide Ref# 188704527D5ME9D was credited to your card ending 6955 On 07/JUL/2026_value Date 07/JUL/2026',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 29393.00);
      expect(txn.transactionDate, DateTime(2026, 7, 7));
      expect(txn.referenceNumber, '188704527D5ME9D');
    });
  });

  group('transaction id generation', () {
    test('is deterministic for the same message and sender', () async {
      const message =
          'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:12345.';
      final a = await parser.parseSMS(message, 'VM-ICICIB');
      final b = await parser.parseSMS(message, 'VM-ICICIB');

      expect(a!.transactionId, b!.transactionId);
    });

    test('differs for different messages', () async {
      final a = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:11111.',
        'VM-ICICIB',
      );
      final b = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:22222.',
        'VM-ICICIB',
      );

      expect(a!.transactionId, isNot(b!.transactionId));
    });
  });

  group('amount parsing', () {
    test('handles Indian comma grouping', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 credited with Rs 1,23,456.78 on 01-Jan-26.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.amount, 123456.78);
    });
  });
}
