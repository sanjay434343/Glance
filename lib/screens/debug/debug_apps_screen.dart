import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/glance_native_bridge.dart';
import '../../core/providers/glance_providers.dart';

class DebugAppsScreen extends ConsumerStatefulWidget {
  const DebugAppsScreen({super.key});

  @override
  ConsumerState<DebugAppsScreen> createState() => _DebugAppsScreenState();
}

class _DebugAppsScreenState extends ConsumerState<DebugAppsScreen> {
  List<Map<String, dynamic>> _allApps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'Launchable'; // 'All', 'Launchable', 'User', 'System'

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    final apps = await GlanceNativeBridge.getAllInstalledApps();
    if (mounted) {
      setState(() {
        _allApps = apps;
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    final query = _searchQuery.toLowerCase();
    setState(() {
      _filteredApps = _allApps.where((app) {
        final name = (app['appName'] as String? ?? '').toLowerCase();
        final pkg = (app['packageName'] as String? ?? '').toLowerCase();
        final matchesSearch = name.contains(query) || pkg.contains(query);
        if (!matchesSearch) return false;

        final hasLaunch = app['hasLaunchIntent'] == true;
        final isSystem = app['isSystemApp'] == true;

        switch (_selectedFilter) {
          case 'Launchable':
            return hasLaunch;
          case 'User':
            return !isSystem;
          case 'System':
            return isSystem;
          case 'All':
          default:
            return true;
        }
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final launchableCount = _allApps.where((a) => a['hasLaunchIntent'] == true).length;
    final userCount = _allApps.where((a) => a['isSystemApp'] == false).length;
    final systemCount = _allApps.where((a) => a['isSystemApp'] == true).length;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Device Apps Debugger',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textColor),
            onPressed: _loadApps,
            tooltip: 'Refresh installed apps',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFF3478F6).withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.bug_report, color: Color(0xFF3478F6)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Found ${_allApps.length} total apps ($launchableCount launchable, $userCount user apps)',
                          style: const TextStyle(
                            color: Color(0xFF3478F6),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (val) {
                      _searchQuery = val;
                      _applyFilters();
                    },
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search app name or package (e.g. youtube, instagram)...',
                      hintStyle: TextStyle(color: subColor, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: subColor),
                      filled: true,
                      fillColor: cardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Filter Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildFilterChip('Launchable', 'Launchable ($launchableCount)', isDark),
                      _buildFilterChip('User', 'User Apps ($userCount)', isDark),
                      _buildFilterChip('All', 'All (${_allApps.length})', isDark),
                      _buildFilterChip('System', 'System ($systemCount)', isDark),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Apps List
                Expanded(
                  child: _filteredApps.isEmpty
                      ? Center(
                          child: Text(
                            'No apps matched standard filters',
                            style: TextStyle(color: subColor),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredApps.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            final appName = app['appName'] as String? ?? 'App';
                            final pkgName = app['packageName'] as String? ?? '';
                            final iconBase64 = app['iconBase64'] as String? ?? '';
                            final hasLaunch = app['hasLaunchIntent'] == true;
                            final isSystem = app['isSystemApp'] == true;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // App Icon
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: iconBase64.isNotEmpty
                                        ? Image.memory(
                                            base64Decode(iconBase64),
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => _defaultIcon(),
                                          )
                                        : _defaultIcon(),
                                  ),
                                  const SizedBox(width: 12),

                                  // App Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          appName,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          pkgName,
                                          style: TextStyle(
                                            color: subColor,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            _buildBadge(
                                              hasLaunch ? 'LAUNCHABLE' : 'NO LAUNCH INTENT',
                                              hasLaunch ? Colors.green : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            _buildBadge(
                                              isSystem ? 'SYSTEM' : 'USER APP',
                                              isSystem ? Colors.orange : Colors.blue,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Manual Trigger Test Button
                                  IconButton(
                                    icon: const Icon(Icons.add_task, color: Color(0xFF3478F6)),
                                    tooltip: 'Simulate app open in Glance memory',
                                    onPressed: () async {
                                      final scanner = ref.read(deviceMemoryScannerProvider);
                                      await scanner.recordAppOpened(appName, pkgName, iconBase64: iconBase64);
                                      ref.invalidate(allMemoriesProvider);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Added $appName to Glance timeline!'),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final isSelected = _selectedFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF3478F6),
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB),
        onSelected: (val) {
          if (val) {
            setState(() {
              _selectedFilter = key;
              _applyFilters();
            });
          }
        },
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: 44,
      height: 44,
      color: Colors.grey[300],
      child: const Icon(Icons.android, color: Colors.grey),
    );
  }
}
