import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/voice/spoken_email.dart';

void main() {
  test('at and dot become the address, without spaces', () {
    expect(spokenEmail('juan at gmail dot com'), 'juan@gmail.com');
    expect(spokenEmail('juan dot cruz at gmail dot com'),
        'juan.cruz@gmail.com');
  });

  test('letters said one at a time are joined', () {
    expect(spokenEmail('j u a n at gmail dot com'), 'juan@gmail.com');
  });

  test('is read back with at and dot as words', () {
    expect(spokenEmailAloud('juan@gmail.com'), 'j u a n at gmail dot com');
    expect(
      spokenEmailAloud('juan.cruz@gmail.com'),
      'j u a n dot c r u z at gmail dot com',
    );
  });
}
