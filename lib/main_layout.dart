import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

class MainLayout extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainLayout({super.key, required this.navigationShell});

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = navigationShell.currentIndex;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: selectedIndex,
        onItemTapped: _onItemTapped,
        bottomPadding: bottomPadding,
      ),
    );
  }
}

// ─── Floating Nav Bar with center bump ───────────────────────────────

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final double bottomPadding;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.bottomPadding,
  });

  // Dimensions
  static const double barHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      color: barColor, // background behind the stack for bottom padding
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // The main nav bar background and border
          Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: barColor,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  index: 0,
                  selectedIndex: selectedIndex,
                  icon: HugeIcons.strokeRoundedHome01,
                  activeIcon: HugeIcons.strokeRoundedHome11,
                  label: 'Home',
                  onTap: onItemTapped,
                ),
                _NavItem(
                  index: 1,
                  selectedIndex: selectedIndex,
                  icon: HugeIcons.strokeRoundedTime01,
                  activeIcon: HugeIcons.strokeRoundedTime04,
                  label: 'Timeline',
                  onTap: onItemTapped,
                ),
                // Placeholder space for the floating center button
                const Expanded(child: SizedBox()),
                _NavItem(
                  index: 3,
                  selectedIndex: selectedIndex,
                  icon: HugeIcons.strokeRoundedFolder01,
                  activeIcon: HugeIcons.strokeRoundedFolder02,
                  label: 'Collections',
                  onTap: onItemTapped,
                ),
                _NavItem(
                  index: 4,
                  selectedIndex: selectedIndex,
                  icon: HugeIcons.strokeRoundedSettings01,
                  activeIcon: HugeIcons.strokeRoundedSettings02,
                  label: 'Settings',
                  onTap: onItemTapped,
                ),
              ],
            ),
          ),
          
          // Overlapping Center Button (Add/Capture)
          Positioned(
            top: -24, // Overlap the top edge
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onItemTapped(2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black, // User requested black button
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        color: Colors.white,
                        size: 18.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Capture',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selectedIndex == 2
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selectedIndex == 2
                          ? const Color(0xFF3478F6)
                          : Colors.grey[500]!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single nav item ─────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final int index;
  final int selectedIndex;
  final dynamic icon;
  final dynamic activeIcon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selectedIndex;
    final color = isSelected ? const Color(0xFF3478F6) : Colors.grey[500]!;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: isSelected ? activeIcon : icon, color: color, size: 24.0),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

