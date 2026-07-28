import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../state/theme_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Appearance settings: pick a colour palette and light/dark mode. Persisted
/// locally so it applies before sign-in too.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();

    return AppShell(
      title: 'Appearance',
      body: ContentContainer(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Colour palette',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AppTheme.seeds.map((opt) {
                  final selected = theme.seed == opt.color;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => theme.setSeed(opt.color),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          width: selected ? 2 : 1,
                          color: selected
                              ? opt.color
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 9, backgroundColor: opt.color),
                          const SizedBox(width: 8),
                          Text(opt.name),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check, size: 16, color: opt.color),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Mode',
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode)),
                  ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode)),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
