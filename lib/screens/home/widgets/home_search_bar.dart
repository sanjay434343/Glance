import 'package:flutter/material.dart';
import '../../search/search_screen.dart';

class HomeSearchBar extends StatelessWidget {
  final bool isDark;
  final Color iconColor;

  const HomeSearchBar({
    super.key,
    required this.isDark,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const SearchScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: Hero(
        tag: 'search_bar_hero',
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search, color: iconColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search your life or ask AI...',
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, color: Theme.of(context).primaryColor, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
