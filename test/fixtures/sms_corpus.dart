// Real-world-shaped SMS corpus used to validate SMSParserService end-to-end
// (P3-4/P7-3).
//
// The original ten messages here used to live in
// lib/services/sms_service.dart as SMSService.getTestSMSMessages() -- a
// "test method to simulate SMS parsing (for development)" that shipped the
// developer's own real transaction data (merchant names, masked account
// numbers) inside every release build for no functional reason: nothing in
// lib/ ever called it outside manual development probing. Moved here
// (P3-5) and made table-driven (P7-3) so the whole corpus is asserted
// end-to-end (type/amount/date/merchant) in sms_corpus_test.dart, plus HDFC
// and Axis entries (P3-4) that didn't exist before this round.

class SmsFixture {
  final String description;
  final String sender;
  final String message;
  final String bankName;
  final String transactionType; // 'credit' | 'debit'
  final double amount;
  final DateTime transactionDate;
  final String? merchant;
  final String? referenceNumber;
  final bool isTransfer;

  const SmsFixture({
    required this.description,
    required this.sender,
    required this.message,
    required this.bankName,
    required this.transactionType,
    required this.amount,
    required this.transactionDate,
    this.merchant,
    this.referenceNumber,
    this.isTransfer = false,
  });
}

final List<SmsFixture> smsCorpus = [
  // --- Original corpus (formerly SMSService.getTestSMSMessages) ---
  SmsFixture(
    description: 'ICICI account credit (NEFT)',
    sender: 'ICICIB',
    message:
        'ICICI Bank Account XX340 credited:Rs. 2,45,687.00 on 30-Sep-25. Info NEFT-HSBCN52025093079143616-. Available Balance is Rs. 2,97,158.22.',
    bankName: 'ICICI',
    transactionType: 'credit',
    amount: 245687.00,
    transactionDate: DateTime(2025, 9, 30),
  ),
  SmsFixture(
    description: 'ICICI account debit with dispute footer',
    sender: 'ICICIB',
    message:
        'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; VENDIMAN credited. UPI:528407948322. Call 18002662 for dispute. SMS BLOCK 340 to 9215676766.',
    bankName: 'ICICI',
    transactionType: 'debit',
    amount: 50.00,
    transactionDate: DateTime(2025, 10, 11),
    // No genuine merchant name in this message shape; the digits-only "to
    // 9215676766" dispute-line footer must not be mistaken for one (P3-2).
    merchant: null,
  ),
  SmsFixture(
    description: 'ICICI credit card spend',
    sender: 'ICICIB',
    message:
        'INR 630.00 spent using ICICI Bank Card XX4016 on 19-Oct-25 on INDIGO AIRLINE. Avl Limit: INR 1,45,739.72. If not you, call 1800 2662/SMS BLOCK 4016 to 9215676766.',
    bankName: 'ICICI',
    transactionType: 'debit',
    amount: 630.00,
    transactionDate: DateTime(2025, 10, 19),
    merchant: 'INDIGO AIRLINE',
  ),
  SmsFixture(
    description: 'ICICI credit card bill payment via BBPS (transfer)',
    sender: 'ICICIB',
    message:
        'Payment of Rs 70,000.00 has been received on your ICICI Bank Credit Card XX4016 through Bharat Bill Payment System on 09-DEC-25.',
    bankName: 'ICICI',
    transactionType: 'credit',
    amount: 70000.00,
    transactionDate: DateTime(2025, 12, 9),
    isTransfer: true,
  ),
  SmsFixture(
    description: 'Kotak debit card spend with UPI merchant code prefix',
    sender: 'KOTAKB',
    message:
        'Rs.2000.00 spent via Kotak Debit Card XX7297 at PYU*SAFRESH TECHNOLOGY PR on 10/12/2025. Avl bal Rs.247.77 Not you?Tap https://kotak.com/KBANKT/Fraud',
    bankName: 'Kotak',
    transactionType: 'debit',
    amount: 2000.00,
    transactionDate: DateTime(2025, 12, 10),
    // "PYU*" is a UPI merchant-code prefix, not part of the name (P3-2).
    merchant: 'SAFRESH TECHNOLOGY PR',
  ),
  SmsFixture(
    description: 'Kotak UPI sent',
    sender: 'KOTAKB',
    message:
        'Sent Rs.100.00 from Kotak Bank AC X2285 to q999676030@ybl on 18-12-25.UPI Ref 535215638117. Not you, https://kotak.com/KBANKT/Fraud',
    bankName: 'Kotak',
    transactionType: 'debit',
    amount: 100.00,
    transactionDate: DateTime(2025, 12, 18),
    merchant: 'q999676030@ybl',
    referenceNumber: '535215638117',
  ),
  SmsFixture(
    description: 'Kotak IMPS received',
    sender: 'KOTAKB',
    message:
        'Received Rs. 10000.00 on 01-12-25 in your Kotak Bank A/C x2285 by an A/C linked to mobile x522. IMPS Ref no 533523524027.',
    bankName: 'Kotak',
    transactionType: 'credit',
    amount: 10000.00,
    transactionDate: DateTime(2025, 12, 1),
    referenceNumber: '533523524027',
  ),
  SmsFixture(
    description: 'SBI IMPS sent (the outgoing leg of the Kotak IMPS above)',
    sender: 'CBSSBI',
    message:
        'IMPS from Ac X5706 for Rs.10,000.00 with Ref 533523524027 dt 01.12.25 to Siddha Ac X2285 with KKBK0008336 sent from YONO. If not done by you fwd this SMS to 7400165218 or call 1800111109 - SBI.',
    bankName: 'SBI',
    transactionType: 'debit',
    amount: 10000.00,
    transactionDate: DateTime(2025, 12, 1),
    referenceNumber: '533523524027',
  ),
  SmsFixture(
    description: 'SBI UPI debit (dd Mon yy date, 3-letter month)',
    sender: 'CBSSBI',
    message:
        'Dear UPI user A/C X5706 debited by 1748.0 on date 09Dec25 trf to CRED Club Refno 534352440391 If not u? call-1800111109 for other services-18001234-SBI',
    bankName: 'SBI',
    transactionType: 'debit',
    amount: 1748.0,
    transactionDate: DateTime(2025, 12, 9),
    merchant: 'CRED Club',
    referenceNumber: '534352440391',
  ),
  SmsFixture(
    description: 'SBI account credit (IMPS)',
    sender: 'CBSSBI',
    message:
        'Dear Customer, Your a/c no. XXXXXXXX5706 is credited by Rs.100000.00 on 09-12-25 by a/c linked to mobile 8XXXXXX522-SIDDHARTH SAGAR BAR (IMPS Ref no 534320026033).If not done by you, call 1800111109. -SBI',
    bankName: 'SBI',
    transactionType: 'credit',
    amount: 100000.00,
    transactionDate: DateTime(2025, 12, 9),
    referenceNumber: '534320026033',
  ),

  // --- HDFC (P3-4: previously the most-common bank with no coverage here) ---
  SmsFixture(
    description: 'HDFC UPI debit',
    sender: 'HDFCBK',
    message:
        'Rs.500.00 debited from HDFC Bank A/c XX1234 on 12-Jan-26 to VPA merchant@ybl. Ref No 987654321012. Not you? Call 18002586161',
    bankName: 'HDFC',
    transactionType: 'debit',
    amount: 500.00,
    transactionDate: DateTime(2026, 1, 12),
    merchant: 'VPA merchant@ybl',
    referenceNumber: '987654321012',
  ),
  SmsFixture(
    description: 'HDFC account credit',
    sender: 'HDFCBK',
    message:
        'Your HDFC Bank A/c XX1234 is credited with Rs. 15,000.00 on 05-Feb-26. Avl Bal: Rs 45,230.20 -HDFC Bank',
    bankName: 'HDFC',
    transactionType: 'credit',
    amount: 15000.00,
    transactionDate: DateTime(2026, 2, 5),
  ),

  // --- Axis (P3-4) ---
  SmsFixture(
    description: 'Axis UPI debit',
    sender: 'AXISBK',
    message:
        'Rs.750.00 debited from A/c no. XX5678 on 20-Mar-26 to VPA merchant2@axl. UPI Ref No 112233445566',
    bankName: 'Axis Bank',
    transactionType: 'debit',
    amount: 750.00,
    transactionDate: DateTime(2026, 3, 20),
    merchant: 'VPA merchant2@axl',
    referenceNumber: '112233445566',
  ),
  SmsFixture(
    description: 'Axis account credit',
    sender: 'AXISBK',
    message: 'Your Axis Bank A/c XX1111 is credited with Rs. 10,000.00 on 01/07/2026.',
    bankName: 'Axis Bank',
    transactionType: 'credit',
    amount: 10000.00,
    transactionDate: DateTime(2026, 7, 1),
  ),
];
