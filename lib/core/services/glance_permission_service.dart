import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../native/glance_native_bridge.dart';

/// Represents a single permission required by Glance that has not yet been granted.
class GlancePermissionItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() onRequest;

  const GlancePermissionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onRequest,
  });
}

/// Centralized service to inspect system permissions and return only ungranted ones.
class GlancePermissionService {
  /// Checks all required permissions and returns only the ungranted ones.
  static Future<List<GlancePermissionItem>> getUngrantedPermissions() async {
    final List<GlancePermissionItem> ungranted = [];

    // 1. Usage Access (Tracks active apps and session intervals)
    try {
      final hasUsage = await GlanceNativeBridge.hasUsagePermission();
      if (!hasUsage) {
        ungranted.add(
          GlancePermissionItem(
            id: 'usage',
            title: 'Usage Access',
            subtitle: 'Required to track active apps and screen sessions',
            icon: Icons.apps_rounded,
            onRequest: () async {
              await GlanceNativeBridge.requestUsagePermission();
            },
          ),
        );
      }
    } catch (_) {}

    // 2. Notification Listener (Captures incoming chat alerts & messages)
    try {
      final hasNotifListener = await GlanceNativeBridge.hasNotificationPermission();
      if (!hasNotifListener) {
        ungranted.add(
          GlancePermissionItem(
            id: 'notif_listener',
            title: 'Notification Listener',
            subtitle: 'Required to capture incoming messages and alerts',
            icon: Icons.notifications_active_outlined,
            onRequest: () async {
              await GlanceNativeBridge.requestNotificationPermission();
            },
          ),
        );
      }
    } catch (_) {}

    // 3. Storage & All Files Access (Indexes documents, PDFs, screenshots, and images)
    try {
      final manageStorageGranted = await Permission.manageExternalStorage.isGranted;
      final storageGranted = await Permission.storage.isGranted;
      final photosGranted = await Permission.photos.isGranted;
      if (!manageStorageGranted && !storageGranted && !photosGranted) {
        ungranted.add(
          GlancePermissionItem(
            id: 'photos_storage',
            title: 'Storage & Files Access',
            subtitle: 'Required to read PDFs, documents, screenshots, and media',
            icon: Icons.folder_open_rounded,
            onRequest: () async {
              if (await Permission.manageExternalStorage.isDenied) {
                await Permission.manageExternalStorage.request();
              }
              await [
                Permission.storage,
                Permission.photos,
                Permission.audio,
              ].request();
            },
          ),
        );
      }
    } catch (_) {}

    return ungranted;
  }
}
