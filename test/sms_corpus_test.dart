// Table-driven pass over the real-world-shaped SMS corpus (P3-4/P7-3): every
// fixture must parse to the expected type/amount/date/merchant, across all
// five banks the corpus covers (ICICI, Kotak, SBI, HDFC, Axis).

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/services/sms_parser_service.dart';

import 'fixtures/sms_corpus.dart';

void main() {
  final parser = SMSParserService();

  for (final fixture in smsCorpus) {
    test('${fixture.bankName}: ${fixture.description}', () async {
      final txn = await parser.parseSMS(fixture.message, fixture.sender);

      expect(txn, isNotNull, reason: 'expected a transaction to be parsed');
      expect(txn!.bankName, fixture.bankName, reason: 'bankName');
      expect(txn.transactionType, fixture.transactionType,
          reason: 'transactionType');
      expect(txn.amount, fixture.amount, reason: 'amount');
      expect(txn.transactionDate, fixture.transactionDate,
          reason: 'transactionDate');
      expect(txn.merchant, fixture.merchant, reason: 'merchant');
      if (fixture.referenceNumber != null) {
        expect(txn.referenceNumber, fixture.referenceNumber,
            reason: 'referenceNumber');
      }
      expect(txn.isTransfer, fixture.isTransfer, reason: 'isTransfer');
    });
  }
}
