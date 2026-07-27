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

    test('numeric month in dd-mm-yy date is parsed correctly, not defaulted to January',
        () async {
      // Regression test for a bug where _parseMonth only recognized month
      // *names* ('sep'), so a numeric month like '12' fell through to a
      // silent January fallback.
      final txn = await parser.parseSMS(
        'Your a/c no. XXXXX1234 is credited by Rs.5,000.00 on 09-12-25 by transfer.',
        'CBSSBI',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionDate, DateTime(2025, 12, 9));
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

  group('generic sign determination (P3-4)', () {
    test('"not credited" is not mis-signed as a credit by the bag-of-words '
        'contains("credited") check', () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 paid but not credited to beneficiary account XX1234 on 12-Jul-26. Please contact your branch.',
        'PNB',
      );

      expect(txn, isNull);
    });

    test('"not debited" is likewise not mis-signed as a debit', () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 was not debited from your account XX1234 on 12-Jul-26 due to a technical issue.',
        'PNB',
      );

      expect(txn, isNull);
    });

    test('a declined transaction is not recorded at all', () async {
      final txn = await parser.parseSMS(
        'Your card payment of Rs.500.00 on card XX1234 on 12-Jul-26 was declined due to insufficient funds.',
        'PNB',
      );

      expect(txn, isNull);
    });

    test('a refund is recorded as a credit, not a debit', () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 refund deposited to your account XX1234 on 12-Jul-26 for order 998877.',
        'PNB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 500.00);
    });

    test('a reversed payment is recorded as a credit', () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 debited earlier has been reversed to your account XX1234 on 12-Jul-26.',
        'PNB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
    });

    test('an ordinary debit alert is unaffected by the new sign checks',
        () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 debited from your account XX1234 on 12-Jul-26 towards UPI payment.',
        'PNB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
    });
  });

  group('merchant extraction (P3-2)', () {
    test(
        'a word containing "on" is not truncated by the old unanchored '
        'terminator (the "MONITOR" -> "M" regression)', () async {
      final txn = await parser.parseSMS(
        'Rs.500.00 debited from PNB Bank A/c XX1234 at MONITOR on 12-Jul-25. Ref No 123456.',
        'PNB',
      );

      expect(txn, isNotNull);
      expect(txn!.merchant, 'MONITOR');
    });

    test('"ONLINE" is not truncated to empty by the old terminator',
        () async {
      final txn = await parser.parseSMS(
        'Rs.250.00 debited from PNB Bank A/c XX1234 at ONLINE STORE on 12-Jul-25. Ref No 654321.',
        'PNB',
      );

      expect(txn, isNotNull);
      expect(txn!.merchant, 'ONLINE STORE');
    });

    test('a digits-only anchor match (a phone number, not a merchant) is discarded',
        () async {
      // "SMS BLOCK 340 to 9215676766" is dispute-line boilerplate, not a
      // payee -- the "to" anchor must not turn the phone number into a
      // "merchant".
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; VENDOR credited. UPI:528407948322. Call 18002662 for dispute. SMS BLOCK 340 to 9215676766.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.merchant, isNull);
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

    test(
        'a real debit alert containing "Do not share" and a "Know more" link '
        'still parses (P3-1: strong transaction signature overrides the '
        'broad marker list)', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX340 debited for Rs 1500.00 on 15-Jul-26 at BIG BAZAAR. Do not share your OTP/CVV with anyone. Know more at icicibank.com',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 1500.00);
      expect(txn.merchant, 'BIG BAZAAR');
    });

    test('an actual OTP delivery is rejected even if it reads like a strong signature',
        () async {
      // Contains an amount, an account token and a date, but is still just
      // an OTP -- the hard-veto list must win regardless of signature shape.
      final txn = await parser.parseSMS(
        'Your OTP for a card transaction of Rs 1500.00 on Account XX340 dated 15-Jul-26 is 445566. Do not share.',
        'ICICIB',
      );
      expect(txn, isNull);
    });

    test('monthly card statement notification is rejected', () async {
      // The amount quoted is the whole cycle's outstanding balance, i.e. the
      // sum of purchases already imported one by one from their own alerts --
      // importing it too booked a phantom expense every month, each roughly
      // the size of that month's real spending.
      final txn = await parser.parseSMS(
        'Statement for your ICICI Bank Credit Card XX4016 has been sent to '
        'sagar***@gmail.com. Total Amt Due Rs 77,368.67, Min Amt Due Rs 3,870.00, '
        'payable by 03-Aug-26.',
        'AD-ICICIT',
      );
      expect(txn, isNull);
    });

    test('statement notification is rejected on the statement wording alone',
        () async {
      // No 'amt due'/'payable by' to catch it, and it carries a full
      // transaction signature (amount + card token + the verb 'spent', plus
      // 'sent' from "has been sent to"), so only the statement check can
      // veto this one.
      final txn = await parser.parseSMS(
        'Statement for your ICICI Bank Credit Card XX4016 for Jul-26 has been '
        'sent to sagar***@gmail.com. You spent Rs 77,368.67 this cycle.',
        'AD-ICICIT',
      );
      expect(txn, isNull);
    });

    test('a real payment to a person is still parsed despite saying "sent to"',
        () async {
      // The statement veto is a conjunction for exactly this reason: 'sent'
      // and 'sent to' are ordinary transaction wording on their own.
      final txn = await parser.parseSMS(
        'Rs 500.00 sent to Ravi Kumar from your ICICI Bank Account XX340 on '
        '15-Jul-26. UPI:123456789.',
        'VM-ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 500.00);
    });

    test('a refund that mentions the statement it lands on is still parsed',
        () async {
      // Regression: an earlier, broader version of the statement veto keyed on
      // cycle-summary wording ('amt due', 'total due', 'payable by') and on
      // 'statement' near 'generated'. Refund alerts carry exactly that
      // phrasing, so every refund on the card stopped importing and the
      // account's income collapsed from ~18,500 to 2.
      final txn = await parser.parseSMS(
        'Rs 644.00 has been credited to your ICICI Bank Credit Card XX4016 on '
        '04-Sep-25 towards a refund. It will reflect in the statement generated '
        'for this cycle. Total Amt Due Rs 12,000.00, payable by 03-Oct-25.',
        'AD-ICICIT',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'credit');
      expect(txn.amount, 644.00);
    });

    test('a purchase that merely mentions the next statement is still parsed',
        () async {
      // 'statement' without any delivery marker is not a statement
      // notification -- plenty of genuine alerts refer to one in passing.
      final txn = await parser.parseSMS(
        'INR 2,082.60 spent using ICICI Bank Card XX4016 on 26-Jul-26 on AMAZON. '
        'This will appear in your next statement.',
        'AD-ICICIT',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 2082.60);
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
      expect(txn!.category, 'Uncategorized');
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

  group('unparseable dates', () {
    test('unrecognized month token falls back to receivedAt instead of fabricating January',
        () async {
      final receivedAt = DateTime(2026, 3, 5, 10, 30);
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Xyz-25; UPI:12345.',
        'VM-ICICIB',
        receivedAt: receivedAt,
      );

      expect(txn, isNotNull);
      expect(txn!.transactionDate, receivedAt);
    });

    test('far-future date (misparsed 2-digit year) falls back to receivedAt',
        () async {
      final receivedAt = DateTime(2026, 3, 5, 10, 30);
      final txn = await parser.parseSMS(
        'Rs. 250.00 debited from HDFC Bank A\\c XX9876 on 12/07/99 to VPA merchant@upi. Ref No: 987654321.',
        'HDFCBK',
        receivedAt: receivedAt,
      );

      expect(txn, isNotNull);
      expect(txn!.transactionDate, receivedAt);
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

  group('balance/limit extraction (P2-1)', () {
    test('ICICI account message: "Available Balance is Rs. X"', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Account XX340 credited:Rs. 2,45,687.00 on 30-Sep-25. Info NEFT-HSBCN52025093079143616-. Available Balance is Rs. 2,97,158.22.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 297158.22);
    });

    test('ICICI credit card message: "Avl Limit: INR X"', () async {
      final txn = await parser.parseSMS(
        'INR 630.00 spent using ICICI Bank Card XX4016 on 19-Oct-25 on INDIGO AIRLINE. Avl Limit: INR 1,45,739.72. If not you, call 1800 2662/SMS BLOCK 4016 to 9215676766.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 145739.72);
    });

    test('Kotak debit card message: "Avl bal Rs.X"', () async {
      final txn = await parser.parseSMS(
        'Rs.2000.00 spent via Kotak Debit Card XX7297 at PYU*SAFRESH TECHNOLOGY PR on 10/12/2025. Avl bal Rs.247.77 Not you?Tap https://kotak.com/KBANKT/Fraud',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 247.77);
    });

    test('HDFC message: "AVAILABLE LIMIT IS RS. X"', () async {
      final txn = await parser.parseSMS(
        'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 29393.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6955 ON 7-7-2026.YOUR AVAILABLE LIMIT IS RS. 686166.10',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 686166.10);
    });

    test('SBI message: "Avl Bal INR X"', () async {
      final txn = await parser.parseSMS(
        'Dear Customer, Your a/c no. XXXXXXXX5706 is credited by Rs.100000.00 on 09-12-25 by a/c linked to mobile 8XXXXXX522-SIDDHARTH SAGAR BAR (IMPS Ref no 534320026033). Avl Bal INR 4,56,789.00. If not done by you, call 1800111109. -SBI',
        'CBSSBI',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 456789.00);
    });

    test('a message with no balance/limit phrase leaves balanceAfter null',
        () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:12345.',
        'VM-ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, isNull);
    });
  });

  group('transfer detection (P2-2)', () {
    test('ICICI credit card BBPS payment is flagged as a transfer', () async {
      final txn = await parser.parseSMS(
        'Payment of Rs 70,000.00 has been received on your ICICI Bank Credit Card XX4016 through Bharat Bill Payment System on 09-DEC-25.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.isTransfer, isTrue);
    });

    test('HDFC "received towards your credit card" is flagged as a transfer',
        () async {
      final txn = await parser.parseSMS(
        'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 29393.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 6955 ON 7-7-2026.YOUR AVAILABLE LIMIT IS RS. 686166.10',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.isTransfer, isTrue);
    });

    test('HDFC "credited to your card" confirmation is flagged as a transfer',
        () async {
      final txn = await parser.parseSMS(
        'HDFC Bank Cardmember, Online Payment of Rs.29393 vide Ref# 188704527D5ME9D was credited to your card ending 6955 On 07/JUL/2026_value Date 07/JUL/2026',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.isTransfer, isTrue);
    });

    test('an ordinary merchant debit is never flagged as a transfer',
        () async {
      final txn = await parser.parseSMS(
        'Rs.499.00 spent via Kotak Debit Card XX1234 at SWIGGY on 12-Jul-25. Not you? Call 18602662666.',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.isTransfer, isFalse);
    });

    test(
        'a non-card BBPS utility bill payment is a genuine expense, not a '
        'transfer, even though it mentions BBPS', () async {
      // BBPS is also the rail banks use for ordinary bill payments
      // (electricity, gas, DTH) debited straight from a bank account. A bare
      // "bbps" substring match would wrongly exclude this from Total
      // Expenses; it must only be treated as a transfer when it's
      // specifically a payment received on a card.
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX340 debited for Rs 1,500.00 on 12-Jul-25; BSES RAJDHANI POWER BBPS credited. UPI:700000000001.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.isTransfer, isFalse);
    });
  });

  group('provenance fields', () {
    test('a parsed SMS transaction records source: sms', () async {
      final txn = await parser.parseSMS(
        'ICICI Bank Acct XX123 debited for Rs 1,500.00 on 30-Sep-25; UPI:12345.',
        'VM-ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.source, 'sms');
      expect(txn.rawMessageHash, isNotNull);
      expect(txn.rawMessageHash, hasLength(64)); // sha256 hex digest
    });
  });

  group('regex edge cases (codebase review fixes)', () {
    test('Kotak debit card amount with a space after Rs is parsed', () async {
      final txn = await parser.parseSMS(
        'Rs 499.00 spent via Kotak Debit Card XX1234 at SWIGGY on 12-Jul-25. Not you? Call 18602662666.',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.amount, 499.00);
      expect(txn.merchant, 'SWIGGY');
    });

    test('ICICI credit card amount with Rs (no dot) is parsed', () async {
      final txn = await parser.parseSMS(
        'Rs 630.00 spent using ICICI Bank Card XX4016 on 19-Oct-25 on INDIGO AIRLINE.',
        'ICICIB',
      );

      expect(txn, isNotNull);
      expect(txn!.amount, 630.00);
      expect(txn.accountType, 'credit_card');
    });

    test('SBI UPI debit with a currency prefix before the amount is parsed',
        () async {
      final txn = await parser.parseSMS(
        'A/C X1234 debited by Rs.500.00 on date 30Sep25 trf to AMAZON PAY Refno 601912345678',
        'CBSSBI',
      );

      expect(txn, isNotNull);
      expect(txn!.transactionType, 'debit');
      expect(txn.amount, 500.00);
      expect(txn.merchant, 'AMAZON PAY');
      expect(txn.transactionDate, DateTime(2025, 9, 30));
    });

    test('space-separated date ("30 Sep 25") is parsed, not defaulted to receivedAt',
        () async {
      final receivedAt = DateTime(2026, 1, 1);
      final txn = await parser.parseSMS(
        'Rs. 250.00 debited from HDFC Bank A/c XX9876 on 30 Sep 25 to VPA merchant@upi.',
        'HDFCBK',
        receivedAt: receivedAt,
      );

      expect(txn, isNotNull);
      expect(txn!.transactionDate, DateTime(2025, 9, 30));
    });

    test('"Avl Bal:" with a colon before the currency is still extracted',
        () async {
      final txn = await parser.parseSMS(
        'Rs.2000.00 spent via Kotak Debit Card XX7297 at SAFRESH on 10/12/2025. Avl Bal: Rs.247.77',
        'KOTAKB',
      );

      expect(txn, isNotNull);
      expect(txn!.balanceAfter, 247.77);
    });

    test('"Ref.No.123" with no whitespace around the dots is extracted',
        () async {
      final txn = await parser.parseSMS(
        'Rs. 250.00 debited from HDFC Bank A/c XX9876 on 12/07/25 to VPA merchant@upi. Ref.No.123456.',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.referenceNumber, '123456');
    });

    test('a hyphenated reference number is captured in full', () async {
      final txn = await parser.parseSMS(
        'Rs. 250.00 debited from HDFC Bank A/c XX9876 on 12/07/25 to VPA merchant@upi. Ref No: 123-456.',
        'HDFCBK',
      );

      expect(txn, isNotNull);
      expect(txn!.referenceNumber, '123-456');
    });

    test('"Payment request received" is a UPI collect request, not money '
        'actually received, and is rejected', () async {
      final txn = await parser.parseSMS(
        'Payment request received of Rs 500 from john@upi via PhonePe. Approve on your UPI app.',
        'PYTM',
      );

      expect(txn, isNull);
    });
  });
}
