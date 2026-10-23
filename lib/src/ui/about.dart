import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'editor_scaffold.dart';
import 'haptics.dart';
import 'theme.dart';
import '../model/whats_new.dart';

/// Settings → About (ui-spec.md "Settings"): Send feedback, All updates,
/// About Metra, and the version line.

const feedbackEmail = 'metra.application@gmail.com';

/// The app's version and build.
Future<PackageInfo> appVersion() => PackageInfo.fromPlatform();

/// "Metra 1.0.0 (2)": shown in Settings, copied on long-press.
String versionLine(PackageInfo app) =>
    'Metra ${app.version} (${app.buildNumber})';

/// The device lines that start a feedback email; empty if unknown.
Future<String> _deviceLines() async {
  final info = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return 'Phone: ${a.manufacturer} ${a.model}\n'
          'Android ${a.version.release} (SDK ${a.version.sdkInt})';
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return 'Phone: ${i.modelName}\n${i.systemName} ${i.systemVersion}';
    }
    if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      return 'Mac: ${m.modelName}\nmacOS ${m.osRelease}';
    }
  } on Exception {
    // Not worth failing the email over (also: no plugin in tests).
  }
  return '';
}

/// The feedback email: subject with the version, body starting with the
/// version and device, then an empty line for the message.
Future<Uri> feedbackUri() async {
  final app = await appVersion();
  final subject = 'Metra feedback (v${app.version} build ${app.buildNumber})';
  final body = '${versionLine(app)}\n${await _deviceLines()}\n\n';
  // Encoded by hand: Uri's queryParameters would turn spaces into "+",
  // which mail apps show literally.
  return Uri(
    scheme: 'mailto',
    path: feedbackEmail,
    query:
        'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
  );
}

/// The privacy policy (PRIVACY.md in the public repo), also the store
/// listing's policy link.
const privacyPolicyUrl =
    'https://github.com/drormos/metra/blob/main/PRIVACY.md';

/// Opens the privacy policy in the browser (the app itself has no network
/// access); says where to find it if no browser opens.
Future<void> openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(privacyPolicyUrl),
      mode: LaunchMode.externalApplication,
    );
  } on PlatformException {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Privacy policy: $privacyPolicyUrl')),
    );
  }
}

/// Opens an email app; says where to write if there's none.
Future<void> sendFeedback(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(await feedbackUri());
  } on PlatformException {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No email app found. Write to $feedbackEmail'),
      ),
    );
  }
}

/// The centred, muted "Metra 1.0.0 (2)"; long-press copies it.
class VersionLine extends StatefulWidget {
  const VersionLine({super.key});

  @override
  State<VersionLine> createState() => _VersionLineState();
}

class _VersionLineState extends State<VersionLine> {
  // Held here: Settings rebuilds often (the offset test's flash).
  late final _app = appVersion();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _app,
    builder: (context, snapshot) {
      final app = snapshot.data;
      if (app == null) return const SizedBox(height: 44);
      final line = versionLine(app);
      return GestureDetector(
        onLongPress: () {
          Haptics.medium();
          Clipboard.setData(ClipboardData(text: line));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            line,
            style: TextStyle(fontSize: 13, color: context.colors.muted),
          ),
        ),
      );
    },
  );
}

/// "About Metra": why the app exists.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const note =
      "I'm a drummer. Every good metronome app I tried was either paid, "
      'full of ads, or missing the one thing I needed on stage.\n\n'
      'So I built my own, with everything I wanted, and made it free.';

  static const promise =
      'No ads, no account, no tracking. Your songs stay on your phone.';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackBar(title: 'About Metra'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                children: [
                  const Text(note, style: TextStyle(fontSize: 18, height: 1.5)),
                  const SizedBox(height: 16),
                  const Text(
                    '— Dror',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    promise,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openAllUpdates(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => const AllUpdatesScreen()),
);

/// Every version from `assets/whats_new.md`, newest first: a small
/// heading ("1.4.0 · Oct 2026") with its lines (ui-spec.md "What's new").
class AllUpdatesScreen extends StatelessWidget {
  const AllUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackBar(title: 'All updates'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  for (final release in WhatsNew.releases) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 6),
                      child: Semantics(
                        header: true,
                        child: Text(
                          release.heading,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ),
                    for (final line in release.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '·  $line',
                          style: const TextStyle(fontSize: 16, height: 1.4),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
