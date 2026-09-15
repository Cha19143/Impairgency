import 'package:flutter_test/flutter_test.dart';
import 'package:impairgency/core/admin/admin_user.dart';
import 'package:impairgency/core/admin/user_filter.dart';
import 'package:impairgency/core/profile/impairment.dart';

const rows = [
  AdminUserRow(
      uid: 'u1',
      role: 'vi',
      displayName: 'Bob Doe',
      email: 'bob@example.com',
      impairment: ImpairmentType.blind),
  AdminUserRow(
      uid: 'u2',
      role: 'vi',
      displayName: 'Cora Lim',
      impairment: ImpairmentType.colourBlind),
  // An older account: no impairment chosen, only the derived category.
  AdminUserRow(uid: 'u3', role: 'vi', displayName: 'Dan', category: 'low vision'),
  AdminUserRow(
      uid: 'u4',
      role: 'vi',
      displayName: 'Eve',
      impairment: ImpairmentType.tunnelVision),
  AdminUserRow(uid: 'u5', role: 'vi', displayName: 'Fay'),
  AdminUserRow(uid: 'g1', role: 'guardian', displayName: 'Ana Reyes'),
  AdminUserRow(uid: 'a1', role: 'admin', email: 'admin@example.com'),
];

List<String> names(UserFilter filter, {String query = ''}) =>
    filterUsers(rows, filter: filter, query: query).map((r) => r.uid).toList();

void main() {
  test('each chip the testers asked for shows only its people', () {
    expect(names(UserFilter.blind), ['u1']);
    expect(names(UserFilter.colourBlind), ['u2']);
    expect(names(UserFilter.guardians), ['g1']);
    expect(names(UserFilter.admins), ['a1']);
  });

  test('an older account is placed by its derived category', () {
    expect(names(UserFilter.lowVision), ['u3']);
  });

  test('other impairments are grouped, and an unrecorded one is not', () {
    expect(names(UserFilter.otherImpairment), ['u4']);
    expect(names(UserFilter.visuallyImpaired), ['u1', 'u2', 'u3', 'u4', 'u5']);
  });

  test('search matches name or email, ignoring case', () {
    expect(names(UserFilter.all, query: 'REYES'), ['g1']);
    expect(names(UserFilter.all, query: 'bob@'), ['u1']);
    expect(names(UserFilter.blind, query: 'cora'), isEmpty);
  });

  test('counts match what each chip would show', () {
    final counts = countUsers(rows);
    for (final filter in UserFilter.values) {
      expect(counts[filter], names(filter).length, reason: '$filter');
    }
    expect(counts[UserFilter.all], rows.length);
  });

  test('every filter has a label', () {
    for (final filter in UserFilter.values) {
      expect(kUserFilterLabels[filter], isNotEmpty);
    }
  });
}
