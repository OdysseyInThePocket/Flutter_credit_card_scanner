import 'package:flutter_credit_card_scanner/iban.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractIbans', () {
    group('valid IBANs detected', () {
      test('Belgian IBAN', () {
        const text = 'Please transfer to BE68539007547034';
        expect(extractIbans(text), equals(['BE68539007547034']));
      });

      test('Dutch IBAN', () {
        const text = 'Account: NL91ABNA0417164300';
        expect(extractIbans(text), equals(['NL91ABNA0417164300']));
      });

      test('German IBAN', () {
        const text = 'IBAN: DE89370400440532013000';
        expect(extractIbans(text), equals(['DE89370400440532013000']));
      });

      test('UK IBAN', () {
        const text = 'Send to GB29NWBK60161331926819';
        expect(extractIbans(text), equals(['GB29NWBK60161331926819']));
      });

      test('French IBAN', () {
        const text = 'FR7630006000011234567890189';
        expect(extractIbans(text), equals(['FR7630006000011234567890189']));
      });

      test('IBAN with spaces (OCR formatting)', () {
        const text = 'IBAN BE68 5390 0754 7034';
        expect(extractIbans(text), equals(['BE68539007547034']));
      });
    });

    group('invalid IBANs rejected', () {
      test('wrong country-code length', () {
        // BE should be 16 chars; this has 17
        const text = 'BE685390075470341';
        expect(extractIbans(text), isEmpty);
      });

      test('wrong checksum', () {
        // Corrupt one digit of a valid BE IBAN
        const text = 'BE69539007547034'; // check digits changed 68→69
        expect(extractIbans(text), isEmpty);
      });

      test('unknown country code', () {
        const text = 'ZZ12345678901234';
        expect(extractIbans(text), isEmpty);
      });
    });

    group('validateChecksum flag', () {
      test('wrong checksum accepted when validateChecksum is false', () {
        const text = 'BE69539007547034';
        final result = extractIbans(text, validateChecksum: false);
        expect(result, equals(['BE69539007547034']));
      });

      test('valid IBAN still returned when validateChecksum is false', () {
        const text = 'BE68539007547034';
        final result = extractIbans(text, validateChecksum: false);
        expect(result, equals(['BE68539007547034']));
      });
    });

    group('OCR confusable repair', () {
      test('O→0, I→1 substitutions yield correct IBAN', () {
        // BE68539007547034 with O→0 and I→1 corruptions in body
        // Original: BE68539007547034
        // Corrupted check digits: 68 stays letters, but body has 0→O, 5→stays
        // Let's corrupt 0→O in the body: BE685390O7547034
        const corrupted = 'BE685390O7547034';
        expect(extractIbans(corrupted), equals(['BE68539007547034']));
      });

      test('O→0 repair handles all-digit BBAN correctly', () {
        // DE89370400440532013000 — 0s corrupted to O by OCR (22 chars total)
        // Positions of 0 in BBAN: DE89|3704|OO44|O532|O13O|OO
        const corrupted = 'DE8937O4OO44O532O13OOO';
        expect(extractIbans(corrupted), equals(['DE89370400440532013000']));
      });
    });

    group('multiple IBANs and mixed content', () {
      test('two IBANs in one document', () {
        const text = '''
          From account: NL91ABNA0417164300
          To account:   BE68539007547034
          Amount: 50.00 EUR
        ''';
        final result = extractIbans(text);
        expect(result, containsAll(['NL91ABNA0417164300', 'BE68539007547034']));
        expect(result.length, 2);
      });

      test('IBAN alongside a credit card number is not confused', () {
        const text = 'Card: 4111 1111 1111 1111\nIBAN: BE68539007547034';
        final result = extractIbans(text);
        expect(result, equals(['BE68539007547034']));
      });

      test('duplicate IBANs deduplicated', () {
        const text = 'BE68539007547034 and also BE68539007547034';
        expect(extractIbans(text).length, 1);
      });

      test('empty string returns empty list', () {
        expect(extractIbans(''), isEmpty);
      });
    });
  });
}
