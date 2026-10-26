import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../todo_theme.dart';

// Keep in sync with pubspec.yaml `version`.
const appVersion = '0.1.6+9';

const repoUrl = 'https://github.com/kurobeats/sloth';

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
          Text('Version $appVersion', style: TextStyle(color: c.secondaryText)),
          const SizedBox(height: 8),
          Text('A minimal Vikunja client.', style: TextStyle(color: c.primaryText)),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => launchUrl(Uri.parse(repoUrl), mode: LaunchMode.externalApplication),
            child: Text(
              repoUrl,
              style: TextStyle(color: c.accent, decoration: TextDecoration.underline),
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