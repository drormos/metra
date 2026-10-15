import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'editor_scaffold.dart';
import 'haptics.dart';
import 'theme.dart';

/// Menu > About (ui-spec.md "Menu"): Send feedback, About Metra, and the
/// version line.

const feedbackEmail = 'dror945@gmail.com';

/// The app's version and build.
Future<PackageInfo> appVersion() => PackageInfo.fromPlatform();

/// "Metra 1.0.0 (2)": shown in the Menu, copied on long-press.
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
  // Held here: the Menu rebuilds often (the offset test's flash).
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
          height: 44,
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
