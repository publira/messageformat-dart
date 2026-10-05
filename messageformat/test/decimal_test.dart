import 'package:messageformat/src/decimal.dart';
import 'package:test/test.dart';

void main() {
  group('Decimal', () {
    test('parses number literals only', () {
      for (final literal in ['0', '-0', '42', '-4.20', '0.42e+1', '1E-3']) {
        expect(Decimal.tryParse(literal), isNotNull, reason: literal);
      }
      for (final literal in ['00', '01', '1.', '.1', '+1', '1e', '0x1', '']) {
        expect(Decimal.tryParse(literal), isNull, reason: literal);
      }
    });

    test('reads doubles as their shortest representation', () {
      expect(Decimal.fromNum(0.1).toPlainString(100), '0.1');
      expect(Decimal.fromNum(1e21).toPlainString(100), '1${'0' * 21}');
      expect(Decimal.fromNum(1.5e-7).toPlainString(100), '0.00000015');
      expect(Decimal.fromNum(-0.0).negative, isTrue);
      expect(Decimal.fromNum(double.nan).isNaN, isTrue);
      expect(Decimal.fromNum(double.negativeInfinity).negative, isTrue);
    });

    test('serializes without an exponent or trailing fraction zeros', () {
      expect(Decimal.tryParse('-4.20')!.toPlainString(100), '-4.2');
      expect(Decimal.tryParse('1.50e2')!.toPlainString(100), '150');
      expect(Decimal.tryParse('-0')!.toPlainString(100), '0');
      expect(Decimal.tryParse('1e-3')!.toPlainString(100), '0.001');
      expect(Decimal.tryParse('1e9')!.toPlainString(5), isNull);
    });

    test('knows whether it is an integer', () {
      expect(Decimal.tryParse('1.000')!.isInteger, isTrue);
      expect(Decimal.tryParse('1.5e1')!.isInteger, isTrue);
      expect(Decimal.tryParse('1.05e1')!.isInteger, isFalse);
    });

    test('adds exactly', () {
      final sum = Decimal.fromNum(0.1) + Decimal.fromNum(0.2);
      expect(sum.toPlainString(100), '0.3');
      final zero = Decimal.tryParse('-1')! + Decimal.tryParse('1')!;
      expect((zero.isZero, zero.negative), (true, false));
    });

    test('rounds with each unsigned rounding mode', () {
      String round(String value, UnsignedRounding mode, {int increment = 1}) =>
          Decimal.tryParse(value)!
              .round(-1, mode, increment: increment)
              .toPlainString(100)!;
      expect(round('1.25', UnsignedRounding.zero), '1.2');
      expect(round('1.21', UnsignedRounding.infinity), '1.3');
      expect(round('1.25', UnsignedRounding.halfZero), '1.2');
      expect(round('1.25', UnsignedRounding.halfInfinity), '1.3');
      expect(round('1.25', UnsignedRounding.halfEven), '1.2');
      expect(round('1.35', UnsignedRounding.halfEven), '1.4');
      expect(round('1.26', UnsignedRounding.halfZero), '1.3');
      expect(round('1.22', UnsignedRounding.halfInfinity, increment: 5), '1');
      expect(round('1.27', UnsignedRounding.halfInfinity, increment: 5), '1.5');
      expect(round('1e-50', UnsignedRounding.infinity), '0.1');
      expect(round('1e-50', UnsignedRounding.halfInfinity), '0');
    });
  });
}
