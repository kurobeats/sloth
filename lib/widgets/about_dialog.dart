import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../todo_theme.dart';

const repoUrl = 'https://github.com/kurobeats/sloth';

/// The version the installed build reports, read once: opening the box again
/// asks nobody, and the answer cannot change while the app runs.
Future<String?>? _version;

Future<String?> _appVersion() => _version ??= () async {
  try {
    // The version name only: Android reports the version *code* as the build
    // number, and the split-per-abi builds carry a 2000 offset, so appending it
    // would read 0.1.7+2010.
    return (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // No platform channel, as in a widget test: show no number rather than a
    // number that could be wrong.
    return null;
  }
}();

/// About box, opened from the home screen overflow menu.
class SlothAboutDialog extends StatelessWidget {
  const SlothAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return AlertDialog(
      title: const Text('Sloth'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String?>(
            future: _appVersion(),
            builder: (context, snapshot) {
              final version = snapshot.data;
              if (version == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Version $version',
                  style: TextStyle(color: c.secondaryText),
                ),
              );
            },
          ),
          Text(
            'A minimal Vikunja client.',
            style: TextStyle(color: c.primaryText),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(repoUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              repoUrl,
              style: TextStyle(
                color: c.accent,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
