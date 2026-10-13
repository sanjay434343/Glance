import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NavBar extends StatelessWidget {
  const NavBar({super.key});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/timeline')) return 1;
    if (location.startsWith('/capture')) return 2;
    if (location.startsWith('/collection')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0; // default
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/timeline');
        break;
      case 2:
        context.go('/capture');
        break;
      case 3:
        context.go('/collection');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed, // needed for > 3 items
      currentIndex: _calculateSelectedIndex(context),
      onTap: (int index) => _onItemTapped(index, context),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.timeline_outlined),
          activeIcon: Icon(Icons.timeline),
          label: 'Timeline',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.camera_alt_outlined),
          activeIcon: Icon(Icons.camera_alt),
          label: 'Capture',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.collections_bookmark_outlined),
          activeIcon: Icon(Icons.collections_bookmark),
          label: 'Collection',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
