import 'package:ferrule/core/router.dart';
import 'package:flutter_test/flutter_test.dart';

const _locs = [
  '/', '/consent', '/setup', '/lock', '/welcome', '/privacy', '/tickets',
];

String _settle(String start,
    {required bool loggedIn,
    required bool consentNeeded,
    required bool lockRequired,
    required bool tourDone}) {
  var loc = start;
  final seen = <String>{loc};
  while (true) {
    final next = appRedirect(
      loc: loc,
      loggedIn: loggedIn,
      consentNeeded: consentNeeded,
      lockRequired: lockRequired,
      tourDone: tourDone,
    );
    if (next == null) return loc;
    if (!seen.add(next)) {
      fail('redirect loop from $start: ${[...seen, next].join(' -> ')}');
    }
    loc = next;
  }
}

void main() {
  test('no state combination loops, and each lands where it should', () {
    for (final loggedIn in [false, true]) {
      for (final consentNeeded in [false, true]) {
        for (final lockRequired in [false, true]) {
          for (final tourDone in [false, true]) {
            for (final start in _locs) {
              final end = _settle(start,
                  loggedIn: loggedIn,
                  consentNeeded: consentNeeded,
                  lockRequired: lockRequired,
                  tourDone: tourDone);
              final why = 'start=$start loggedIn=$loggedIn '
                  'consent=$consentNeeded lock=$lockRequired tour=$tourDone';
              if (start == '/privacy') {
                expect(end, '/privacy', reason: why);
              } else if (consentNeeded) {
                expect(end, '/consent', reason: why);
              } else if (!loggedIn) {
                expect(end, '/setup', reason: why);
              } else if (lockRequired) {
                expect(end, '/lock', reason: why);
              } else if (!tourDone) {
                expect(end, '/welcome', reason: why);
              } else {
                expect(['/consent', '/setup', '/lock'].contains(end), isFalse,
                    reason: why);
              }
            }
          }
        }
      }
    }
  });

  test('the 1.2.1 loop: signed in, consent unanswered, tour not done', () {
    expect(
        _settle('/',
            loggedIn: true,
            consentNeeded: true,
            lockRequired: false,
            tourDone: false),
        '/consent');
  });
}
