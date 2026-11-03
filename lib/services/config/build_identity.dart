import 'package:package_info_plus/package_info_plus.dart';

/// Build metadata baked in by paired Windows/iOS GitHub Actions.
/// The app version and platform build number still come from the installed
/// binary, so a stale installer cannot pretend to be the newest build.
abstract final class BuildIdentity {
  static const String commit = String.fromEnvironment(
    'PLAYTORRIO_COMMIT', defaultValue: '');
  static const String workflowRun = String.fromEnvironment(
    'PLAYTORRIO_RUN', defaultValue: '');

  static String versionLabel(PackageInfo package) =>
      'v${package.version} (Build ${package.buildNumber})';

  static String get shortCommit =>
      commit.length >= 10 ? commit.substring(0, 10) : commit;

  static String get sourceLabel {
    if (shortCommit.isEmpty) return 'Local or untracked build';
    // PLAYTORRIO_RUN is a native build number, not always the GitHub run.
    // In paired iOS packages it is GITHUB_RUN_NUMBER + 3.
    final runLabel = workflowRun.isEmpty ? '' : ' · App build $workflowRun';
    return 'Revision $shortCommit$runLabel';
  }
}
