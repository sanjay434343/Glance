import 'package:flutter/material.dart';

import '../../core/models/memory_models.dart';
import 'app_activity_detail_screen.dart';
import 'copied_text_detail_screen.dart';
import 'document_detail_screen.dart';
import 'image_detail_screen.dart';
import 'location_detail_screen.dart';
import 'notification_detail_screen.dart';
import 'web_detail_screen.dart';

/// Opens dedicated detail page tailored specifically to the memory category.
class DetailRouter {
  static void openDetailScreen(BuildContext context, Memory memory, {List<Memory>? sameTimeMemories}) {
    Widget targetScreen;

    switch (memory.type.toLowerCase()) {
      case 'app_activity':
        targetScreen = AppActivityDetailScreen(memory: memory);
        break;
      case 'copied_text':
      case 'clipboard':
        targetScreen = CopiedTextDetailScreen(memory: memory);
        break;
      case 'webpage':
      case 'url':
        targetScreen = WebDetailScreen(memory: memory);
        break;
      case 'screenshot':
      case 'photo':
      case 'camera_capture':
        targetScreen = ImageDetailScreen(memory: memory, sameTimeMemories: sameTimeMemories);
        break;
      case 'pdf':
      case 'document':
      case 'file':
        targetScreen = DocumentDetailScreen(memory: memory);
        break;
      case 'location':
        targetScreen = LocationDetailScreen(memory: memory);
        break;
      case 'notification':
      case 'call_log':
      case 'sms':
      case 'calendar_event':
        targetScreen = NotificationDetailScreen(memory: memory);
        break;
      default:
        targetScreen = AppActivityDetailScreen(memory: memory);
        break;
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => targetScreen),
    );
  }
}
