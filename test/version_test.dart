import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android installs an update over the old app only when its versionCode is
/// higher. The build number in pubspec.yaml is the versionCode, derived from
/// the version: major*10000 + minor*100 + patch (1.0.1 -> 10001). Bumping the
/// version without the build number (or the other way round) fails here.
void main() {
  test('build number is derived from the version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'version must look like 1.0.0+10000');
    final major = int.parse(match!.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    final build = int.parse(match.group(4)!);
    expect(minor, lessThan(100));
    expect(patch, lessThan(100));
    expect(build, major * 10000 + minor * 100 + patch);
  });
}
