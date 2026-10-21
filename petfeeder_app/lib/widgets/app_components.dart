import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PageContent extends StatelessWidget {
  final Widget child;
  const PageContent({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );
}

class PageHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const PageHeading({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  final Widget child;
  const SectionCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatusPill({
    super.key,
    required this.label,
    this.color = AppTheme.accentGreen,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: ShapeDecoration(
      color: color.withAlpha(20),
      shape: const StadiumBorder(),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(icon, size: 14, color: color),
              ),
            ),
          TextSpan(text: label),
        ],
      ),
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppTheme.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: AppTheme.primary),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textMuted, height: 1.5),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
        const SizedBox(height: 12),
      ],
    ),
  );
}

class PortionSelector extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int>? onChanged;
  const PortionSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 150,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Khẩu phần',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$value g',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [20, 30, 45, 60, 80]
            .where((p) => p <= max)
            .map(
              (p) => ChoiceChip(
                label: Text('$p g'),
                selected: value == p,
                showCheckmark: false,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                side: BorderSide(
                  color: value == p ? AppTheme.primary : AppTheme.border,
                ),
                labelStyle: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  color: value == p ? Colors.white : AppTheme.textMain,
                ),
                onSelected: onChanged == null ? null : (_) => onChanged!(p),
              ),
            )
            .toList(),
      ),
      Slider(
        value: value.toDouble(),
        min: 10,
        max: max.toDouble(),
        divisions: (max - 10) ~/ 5,
        label: '$value g',
        semanticFormatterCallback: (v) => '${v.round()} gram',
        onChanged: onChanged == null ? null : (v) => onChanged!(v.round()),
      ),
    ],
  );
}

void showFeedback(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.accentCoral : null,
    ),
  );
}
