import 'package:flutter_credit_card_scanner/process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProccessCreditCard.processNumber', () {
    ProccessCreditCard makeProcessor() => ProccessCreditCard(
          useLuhnValidation: true,
          checkCreditCardNumber: true,
          checkCreditCardName: false,
          checkCreditCardExpiryDate: false,
        );

    test('extracts card number from a single-line full number', () {
      final process = makeProcessor();
      process.processNumber('4111 1111 1111 1111');
      expect(process.cardNumber, '4111 1111 1111 1111');
    });

    test('assembles card number from consecutive 4-digit groups', () {
      final process = makeProcessor();
      for (final group in ['4111', '1111', '1111', '1111']) {
        process.processNumber(group);
      }
      expect(process.cardNumber, '4111111111111111');
    });
  });

  group('extractCardFromLines (static image scan)', () {
    test('extracts a label-prefixed single-line PAN (Belfius "CARD ...")', () {
      // Full OCR line set from the Belfius bug report. The PAN arrives fused to
      // a "CARD" label, which the live per-line accumulator drops.
      final card = extractCardFromLines(
        const [
          'Belfius',
          ')',
          '12/26 N2',
          'ANOUK BONNARENS',
          'IBAN BE46 7785 9387 0936',
          'CARD 6703 0514 6144 6300 1',
          'Bancontact',
          'maestro',
        ],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNotNull);
      expect(card!.number, '67030514614463001');
    });

    test('extracts a card number split across consecutive group lines', () {
      final card = extractCardFromLines(
        const ['4111', '1111', '1111', '1111'],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNotNull);
      expect(card!.number, '4111111111111111');
    });

    test('ignores IBAN groups preceding the card groups (no contamination)',
        () {
      // The all-digit IBAN groups must not be assembled into a false PAN; only
      // the trailing four card groups form a valid number.
      final card = extractCardFromLines(
        const [
          'IBAN BE68 5390 0754 7034',
          '4111',
          '1111',
          '1111',
          '1111',
        ],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNotNull);
      expect(card!.number, '4111111111111111');
    });

    test('returns null when only an IBAN line is present (no false positive)',
        () {
      final card = extractCardFromLines(
        const ['IBAN BE46 7785 9387 0936'],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNull);
    });

    test('reads a trailing "O" as 0 and drops a glued artifact ("… O N3")', () {
      // The standalone "O" is the final PAN digit (0); "N3" is an OCR artifact
      // that must not inject a stray 3.
      final card = extractCardFromLines(
        const ['6703 4201 9755 4702 O N3'],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNotNull);
      expect(card!.number, '67034201975547020');
    });

    test('extracts a label-prefixed 17-digit PAN ("CARD … 8")', () {
      final card = extractCardFromLines(
        const ['CARD 6703 0516 2748 7700 8'],
        detectCardHolder: false,
        detectCardExpiryDate: false,
      );
      expect(card, isNotNull);
      expect(card!.number, '67030516274877008');
    });
  });
}
