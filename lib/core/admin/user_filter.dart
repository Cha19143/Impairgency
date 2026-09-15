/// The dashboard's user filters: who is blind, who is colour blind, who is a
/// guardian.
///
/// Asked for by the testers. Worked out here, on the rows already loaded,
/// rather than as Firestore queries: an equality query per chip would need a
/// read per click, and would give different counts from the table beside it.
library;

import '../profile/impairment.dart';
import 'admin_user.dart';

enum UserFilter {
  all,
  visuallyImpaired,
  blind,
  lowVision,
  colourBlind,
  otherImpairment,
  guardians,
  admins,
}

const Map<UserFilter, String> kUserFilterLabels = {
  UserFilter.all: 'All',
  UserFilter.visuallyImpaired: 'VI users',
  UserFilter.blind: 'Blind',
  UserFilter.lowVision: 'Low vision',
  UserFilter.colourBlind: 'Colour blind',
  UserFilter.otherImpairment: 'Other impairment',
  UserFilter.guardians: 'Guardians',
  UserFilter.admins: 'Admins',
};

bool matchesFilter(AdminUserRow row, UserFilter filter) {
  final impairment = row.isVisuallyImpaired ? row.knownImpairment : null;
  return switch (filter) {
    UserFilter.all => true,
    UserFilter.visuallyImpaired => row.isVisuallyImpaired,
    UserFilter.blind => impairment == ImpairmentType.blind,
    UserFilter.lowVision => impairment == ImpairmentType.lowVision,
    UserFilter.colourBlind => impairment == ImpairmentType.colourBlind,
    UserFilter.otherImpairment => impairment == ImpairmentType.nightBlind ||
        impairment == ImpairmentType.tunnelVision ||
        impairment == ImpairmentType.other,
    UserFilter.guardians => row.isGuardian,
    UserFilter.admins => row.isAdmin,
  };
}

/// Whether [row]'s name or email contains [query], ignoring case.
bool matchesQuery(AdminUserRow row, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return row.name.toLowerCase().contains(q) ||
      (row.email?.toLowerCase().contains(q) ?? false);
}

List<AdminUserRow> filterUsers(
  List<AdminUserRow> rows, {
  UserFilter filter = UserFilter.all,
  String query = '',
}) =>
    [
      for (final row in rows)
        if (matchesFilter(row, filter) && matchesQuery(row, query)) row,
    ];

/// How many rows each chip would show, before the search is applied.
Map<UserFilter, int> countUsers(List<AdminUserRow> rows) => {
      for (final filter in UserFilter.values)
        filter: rows.where((row) => matchesFilter(row, filter)).length,
    };
