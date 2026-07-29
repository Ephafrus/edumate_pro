import 'package:flutter/material.dart';

import '../models/school.dart';

/// The school's badge.
///
/// A logo is loaded over the network, which can be slow or can fail, and the
/// places this appears — app bar, sidebar, school switcher — must not shift
/// or break while that happens. So it always occupies the same square, falls
/// back to the school's initial before the image arrives or if it never does,
/// and never shows a broken-image icon.
class SchoolLogo extends StatelessWidget {
  const SchoolLogo({super.key, required this.school, this.size = 32});

  final School school;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = size / 4;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            school.initial,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.45,
            ),
          ),
        );

    if (!school.hasLogo) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        school.logoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A missing or unreachable logo is not an error worth showing a
        // parent — the initial reads perfectly well.
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback(),
      ),
    );
  }
}
