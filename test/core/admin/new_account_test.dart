import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/admin/admin_user.dart';
import 'package:impairgency/core/profile/impairment.dart';

void main() {
  group('the form refuses', () {
    String? problem({
      String email = 'ben@example.com',
      String name = 'Ben',
      String age = '',
      String phone = '',
      String role = 'vi',
      bool checkEmail = true,
    }) =>
        newAccountProblem(
            email: email,
            name: name,
            age: age,
            phone: phone,
            role: role,
            checkEmail: checkEmail);

    test('a complete form passes', () => expect(problem(age: '40'), isNull));
    test('a made-up email', () => expect(problem(email: 'a@b.c'), isNotNull));
    test('no name', () => expect(problem(name: ' '), contains('name')));
    test('an age that is not one',
        () => expect(problem(age: 'forty'), contains('Age')));
    test('a short phone', () => expect(problem(phone: '123'), contains('phone')));
    test('the admin role', () => expect(problem(role: 'admin'), isNotNull));
    test('the email is not checked when editing',
        () => expect(problem(email: '', checkEmail: false), isNull));
  });

  test('a visually impaired account starts with every consent off', () {
    const account = NewAccount(
      email: ' ben@example.com ',
      name: ' Ben ',
      role: 'vi',
      impairment: ImpairmentType.blind,
      age: 40,
    );
    final doc = account.toUserDocument('u1');
    expect(doc['uid'], 'u1');
    expect(doc['email'], 'ben@example.com');
    expect(doc['role'], 'vi');
    expect(doc['displayName'], 'Ben');
    expect(doc['impairment'], 'blind');
    expect(doc['consent'], isA<Map<String, Object?>>());
    expect((doc['consent'] as Map).values.every((v) => v == false), isTrue);
    expect(doc.containsKey('password'), isFalse);
    expect(account.profileComplete, isTrue);
  });

  test('a guardian account carries no consent or impairment', () {
    const account = NewAccount(
        email: 'ana@example.com', name: 'Ana', role: 'guardian', phone: '0917 000 0000');
    final doc = account.toUserDocument('g1');
    expect(doc['role'], 'guardian');
    expect(doc.containsKey('consent'), isFalse);
    expect(doc.containsKey('impairment'), isFalse);
    expect(account.profileComplete, isFalse);
  });
}
