import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/glance_providers.dart';
import 'collection_detail_screen.dart';
import 'custom_collection_detail_screen.dart';
import 'widgets/collection_header.dart';
import 'widgets/collection_grid_item.dart';
import 'widgets/create_collection_bottom_sheet.dart';
import 'widgets/smart_collection_card.dart';
import '../home/widgets/home_section_header.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  void _openCollectionDetail(BuildContext context, String title, Set<String> targetTypes, String iconAsset) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CollectionDetailScreen(
          collectionTitle: title,
          targetTypes: targetTypes,
          iconAsset: iconAsset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);

    final memoriesAsync = ref.watch(allMemoriesProvider);
    final customCollectionsAsync = ref.watch(customCollectionsProvider);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allMemoriesProvider);
            ref.invalidate(customCollectionsProvider);
          },
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CollectionHeader(),
                const SizedBox(height: 24),

                memoriesAsync.when(
                  data: (memories) {
                    final formatter = NumberFormat('#,##0');

                    int screenshotsCount = 0;
                    int websitesCount = 0;
                    int copiedTextCount = 0;
                    int documentsCount = 0;
                    int imagesCount = 0;
                    int locationsCount = 0;
                    int notificationsCount = 0;
                    int appActivityCount = 0;

                    for (final mem in memories) {
                      final type = mem.type.toLowerCase();
                      switch (type) {
                        case 'screenshot':
                          screenshotsCount++;
                          break;
                        case 'webpage':
                        case 'url':
                          websitesCount++;
                          break;
                        case 'copied_text':
                        case 'clipboard':
                          copiedTextCount++;
                          break;
                        case 'pdf':
                        case 'document':
                        case 'file':
                          documentsCount++;
                          break;
                        case 'photo':
                        case 'camera_capture':
                          imagesCount++;
                          break;
                        case 'location':
                          locationsCount++;
                          break;
                        case 'notification':
                        case 'call_log':
                        case 'sms':
                          notificationsCount++;
                          break;
                        case 'app_activity':
                          appActivityCount++;
                          break;
                        default:
                          break;
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Grid with live counts from SQLite DB
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.4,
                          children: [
                            CollectionGridItem(
                              imagePath: 'assets/icons/screenshot.png',
                              iconColor: Colors.pinkAccent,
                              title: 'Screenshots',
                              count: formatter.format(screenshotsCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Screenshots',
                                {'screenshot'},
                                'assets/icons/screenshot.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/website.png',
                              iconColor: Colors.blueAccent,
                              title: 'Websites',
                              count: formatter.format(websitesCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Websites',
                                {'webpage', 'url'},
                                'assets/icons/website.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/copied_text.png',
                              iconColor: Colors.orangeAccent,
                              title: 'Copied Text',
                              count: formatter.format(copiedTextCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Copied Text',
                                {'copied_text', 'clipboard'},
                                'assets/icons/copied_text.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/documens.png',
                              iconColor: Colors.blue,
                              title: 'Documents',
                              count: formatter.format(documentsCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Documents',
                                {'pdf', 'document', 'file'},
                                'assets/icons/documens.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/images.png',
                              iconColor: Colors.green,
                              title: 'Images',
                              count: formatter.format(imagesCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Images',
                                {'photo', 'camera_capture'},
                                'assets/icons/images.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/location.png',
                              iconColor: Colors.pink,
                              title: 'Locations',
                              count: formatter.format(locationsCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Locations',
                                {'location'},
                                'assets/icons/location.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/notification.png',
                              iconColor: Colors.blue,
                              title: 'Notifications',
                              count: formatter.format(notificationsCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'Notifications',
                                {'notification', 'call_log', 'sms'},
                                'assets/icons/notification.png',
                              ),
                            ),
                            CollectionGridItem(
                              imagePath: 'assets/icons/ap_activity.png',
                              iconColor: Colors.purpleAccent,
                              title: 'App Activity',
                              count: formatter.format(appActivityCount),
                              isDark: isDark,
                              onTap: () => _openCollectionDetail(
                                context,
                                'App Activity',
                                {'app_activity'},
                                'assets/icons/ap_activity.png',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        HomeSectionHeader(
                          title: 'Smart Collections',
                          titleColor: textColor,
                          actionColor: Colors.transparent, // Default required param
                        ),
                        const SizedBox(height: 16),

                        Builder(
                          builder: (context) {
                            final rawCollections = customCollectionsAsync.valueOrNull ?? [];
                            final sortedCollections = List<Map<String, dynamic>>.from(rawCollections);
                            sortedCollections.sort((a, b) {
                              final aTime = (a['created_at'] ?? a['updated_at'] ?? 0) as int;
                              final bTime = (b['created_at'] ?? b['updated_at'] ?? 0) as int;
                              return bTime.compareTo(aTime); // Newest at top
                            });

                            final cardWidth = (MediaQuery.of(context).size.width - 32 - 16) / 3;

                            if (sortedCollections.isEmpty) {
                              return Wrap(
                                spacing: 8,
                                runSpacing: 16,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    child: SmartCollectionCard(
                                      image: Container(
                                        color: isDark ? const Color(0xFF1E2024) : const Color(0xFFF1F4F9),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 32,
                                          color: isDark ? Colors.white38 : Colors.black26,
                                        ),
                                      ),
                                      title: '',
                                      itemsCount: '',
                                      isDark: isDark,
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          useRootNavigator: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (ctx) => const CreateCollectionBottomSheet(),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Wrap(
                              spacing: 8,
                              runSpacing: 16,
                              children: sortedCollections.map((col) {
                                return SizedBox(
                                  width: cardWidth,
                                  child: SmartCollectionCard(
                                    image: Container(
                                      color: Colors.blue.withValues(alpha: 0.15),
                                      alignment: Alignment.center,
                                      child: Image.asset(
                                        col['icon'] ?? 'assets/icons/documens.png',
                                        width: 48,
                                        height: 48,
                                      ),
                                    ),
                                    title: col['title'] ?? '',
                                    itemsCount: 'Custom',
                                    isDark: isDark,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomCollectionDetailScreen(
                                            collectionId: col['id'],
                                            title: col['title'] ?? '',
                                            iconAsset: col['icon'] ?? 'assets/icons/documens.png',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, stack) => Center(
                    child: Text('Error loading collections: $err', style: const TextStyle(color: Colors.red)),
                  ),
                ),

                const SizedBox(height: 100), // padding for nav bar
              ],
            ),
          ),
        ),
      ),
    );
  }
}
