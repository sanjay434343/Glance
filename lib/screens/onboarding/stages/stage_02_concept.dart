import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 02 — Concept reveal.
/// "Your phone is full of fragments."
class StageConcept extends StatefulWidget {
  final VoidCallback onContinue;
  const StageConcept({super.key, required this.onContinue});

  @override
  State<StageConcept> createState() => _StageConceptState();
}

class _StageConceptState extends State<StageConcept> with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _connectController;

  final List<_FragmentItem> _items = const [
    _FragmentItem(Icons.screenshot_outlined, 'Screenshot'),
    _FragmentItem(Icons.language_outlined, 'Website'),
    _FragmentItem(Icons.content_copy_outlined, 'Copied text'),
    _FragmentItem(Icons.photo_outlined, 'Photo'),
    _FragmentItem(Icons.insert_drive_file_outlined, 'File'),
    _FragmentItem(Icons.place_outlined, 'Location'),
    _FragmentItem(Icons.notifications_none_outlined, 'Notification'),
  ];

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _connectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _enterController.forward();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) _connectController.forward();
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    _connectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        children: [
          const Spacer(flex: 2),

          FadeTransition(
            opacity: CurvedAnimation(parent: _enterController, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
            child: Text(
              'Your phone is full of fragments.',
              style: OnboardingTheme.headline(context),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingMD),

          FadeTransition(
            opacity: CurvedAnimation(parent: _enterController, curve: const Interval(0.1, 0.4, curve: Curves.easeOut)),
            child: Text(
              'Screenshots, websites, copied text, files, places, photos,\nand tiny pieces of information.',
              style: OnboardingTheme.body(context),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL),

          // Fragment chips — staggered fade in
          ..._buildChips(context),

          const SizedBox(height: OnboardingTheme.spacingXL),

          // Secondary statement
          FadeTransition(
            opacity: CurvedAnimation(parent: _connectController, curve: Curves.easeOut),
            child: Text(
              'We connect the pieces.',
              style: OnboardingTheme.headline(context).copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
          ),

          const Spacer(flex: 3),

          // CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: widget.onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: OnboardingTheme.cta(context),
                foregroundColor: OnboardingTheme.ctaText(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                ),
                elevation: 0,
              ),
              child: const Text('See how', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  List<Widget> _buildChips(BuildContext context) {
    // Build chips in rows to control stagger properly
    final rows = <List<_FragmentItem>>[
      _items.sublist(0, 3),
      _items.sublist(3, 5),
      _items.sublist(5, 7),
    ];

    return List.generate(rows.length, (rowIndex) {
      // Each row gets a staggered interval that stays within 0.0–1.0
      final begin = 0.25 + rowIndex * 0.15; // 0.25, 0.40, 0.55
      final end = (begin + 0.35).clamp(0.0, 1.0); // 0.60, 0.75, 0.90

      final anim = CurvedAnimation(
        parent: _enterController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(anim),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: rows[rowIndex]
                  .map((item) => _buildChip(context, item))
                  .toList(),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildChip(BuildContext context, _FragmentItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
        border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 18, color: OnboardingTheme.secondary(context)),
          const SizedBox(width: 8),
          Text(item.label, style: OnboardingTheme.label(context)),
        ],
      ),
    );
  }
}

class _FragmentItem {
  final IconData icon;
  final String label;
  const _FragmentItem(this.icon, this.label);
}
