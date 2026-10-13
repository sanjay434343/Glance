import 'package:flutter/material.dart';
import '../onboarding_theme.dart';

/// Stage 03 — Interactive search demonstration.
/// "Try remembering something."
class StageSearch extends StatefulWidget {
  final VoidCallback onContinue;
  const StageSearch({super.key, required this.onContinue});

  @override
  State<StageSearch> createState() => _StageSearchState();
}

class _StageSearchState extends State<StageSearch> with TickerProviderStateMixin {
  late AnimationController _enterController;
  late AnimationController _resultsController;
  final TextEditingController _searchController = TextEditingController();
  bool _showResults = false;
  bool _showSuccess = false;

  final List<_DemoResult> _results = const [
    _DemoResult('Payment UI', 'Screenshot', 'Yesterday · 4:21 PM', Icons.screenshot_outlined),
    _DemoResult('WebRTC Payment', 'Website', 'Yesterday · 4:27 PM', Icons.language_outlined),
    _DemoResult('Payment Flow', 'Copied text', 'Yesterday · 4:31 PM', Icons.content_copy_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _resultsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _enterController.forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    _resultsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.trim().isNotEmpty && !_showResults) {
      setState(() => _showResults = true);
      _resultsController.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _showSuccess = true);
        });
      });
    }
  }

  void _prefillQuery() {
    _searchController.text = 'that payment screenshot';
    _onSearch(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnboardingTheme.marginH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: OnboardingTheme.spacingXXL + 16),

          FadeTransition(
            opacity: CurvedAnimation(parent: _enterController, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
            child: Text(
              'Try remembering something.',
              style: OnboardingTheme.headline(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingSM),

          FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterController,
              curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
            ),
            child: Text(
              'Search the way you remember it,\nnot where you saved it.',
              style: OnboardingTheme.body(context),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXL),

          // Search field
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterController,
              curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: OnboardingTheme.card(context),
                borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                border: Border.all(color: OnboardingTheme.divider),
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: _onSearch,
                style: TextStyle(
                  fontSize: 16,
                  color: OnboardingTheme.primary(context),
                ),
                decoration: InputDecoration(
                  hintText: 'What do you remember?',
                  hintStyle: TextStyle(color: OnboardingTheme.textTertiary),
                  prefixIcon: Icon(Icons.search, color: OnboardingTheme.textTertiary, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
          ),

          // Tap-to-try hint
          if (!_showResults) ...[
            const SizedBox(height: OnboardingTheme.spacingMD),
            GestureDetector(
              onTap: _prefillQuery,
              child: Text(
                'Try: "that payment screenshot"',
                style: OnboardingTheme.label(context).copyWith(
                  color: OnboardingTheme.cta(context).withValues(alpha: 0.6),
                  decoration: TextDecoration.underline,
                  decorationColor: OnboardingTheme.cta(context).withValues(alpha: 0.3),
                ),
              ),
            ),
          ],

          const SizedBox(height: OnboardingTheme.spacingLG),

          // Results
          if (_showResults)
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  // Safe stagger: begin 0.0–0.4, end 0.4–0.8
                  final begin = (i / _results.length) * 0.4;
                  final end = begin + 0.4;
                  final opacity = CurvedAnimation(
                    parent: _resultsController,
                    curve: Interval(begin, end, curve: Curves.easeOut),
                  );
                  return FadeTransition(
                    opacity: opacity,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.1),
                        end: Offset.zero,
                      ).animate(opacity),
                      child: _buildResultCard(context, _results[i]),
                    ),
                  );
                },
              ),
            )
          else
            const Spacer(),

          // Success message + CTA
          if (_showSuccess)
            AnimatedOpacity(
              opacity: _showSuccess ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Padding(
                padding: const EdgeInsets.only(bottom: OnboardingTheme.spacingLG),
                child: Text(
                  'That\'s how you\'ll search your life.',
                  style: OnboardingTheme.headline(context).copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _showResults ? widget.onContinue : null,
              style: FilledButton.styleFrom(
                backgroundColor: OnboardingTheme.cta(context),
                foregroundColor: OnboardingTheme.ctaText(context),
                disabledBackgroundColor: OnboardingTheme.accentSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
                ),
                elevation: 0,
              ),
              child: const Text('Continue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: OnboardingTheme.spacingXXL),
        ],
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, _DemoResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnboardingTheme.card(context),
        borderRadius: BorderRadius.circular(OnboardingTheme.radiusSM),
        border: Border.all(color: OnboardingTheme.divider.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: OnboardingTheme.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(result.icon, size: 20, color: OnboardingTheme.secondary(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: OnboardingTheme.primary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${result.type} · ${result.time}',
                  style: OnboardingTheme.label(context).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoResult {
  final String title;
  final String type;
  final String time;
  final IconData icon;
  const _DemoResult(this.title, this.type, this.time, this.icon);
}
