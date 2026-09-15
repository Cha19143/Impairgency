import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/auth/email_address.dart';

void main() {
  test('ordinary addresses pass', () {
    for (final address in [
      'ben@example.com',
      'ana.santos@gmail.com',
      'j.dela-cruz+demo@school.edu.ph',
      '  padded@example.com  ',
    ]) {
      expect(emailAddressProblem(address), isNull, reason: address);
    }
  });

  test('the made-up addresses the old check let through are refused', () {
    // The old rule was "contains @ and has five characters".
    for (final address in [
      'a@b.c',
      'ben@',
      '@example.com',
      'ben@example',
      'ben@@example.com',
      'ben at example.com',
      'ben@exa mple.com',
      'ben@example.c',
      'ben@example.123',
      'ben@-example.com',
      'ben@example..com',
      '.ben@example.com',
      'be..n@example.com',
      '',
    ]) {
      expect(emailAddressProblem(address), kNotAnEmailAddress,
          reason: address);
    }
  });
}
