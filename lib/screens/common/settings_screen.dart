import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../state/theme_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// "Customise your app": each user picks their own colour palette,
/// light/dark mode and text size. Persisted locally so it applies before
/// sign-in too.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final scheme = Theme.of(context).colorScheme;

    return AppShell(
      title: 'Customise',
      body: ContentContainer(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: scheme.heroGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customise your app',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                      'Make EduMate Pro yours — pick your school colours, '
                      'light or dark mode, and a comfortable text size.',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
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
            const SizedBox(height: 16),
            SectionCard(
              title: 'Text size',
              child: SegmentedButton<double>(
                segments: AppTheme.textScales
                    .map((o) => ButtonSegment(
                        value: o.scale, label: Text(o.name)))
                    .toList(),
                selected: {
                  AppTheme.textScales.any((o) => o.scale == theme.textScale)
                      ? theme.textScale
                      : 1.0
                },
                onSelectionChanged: (s) => theme.setTextScale(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
