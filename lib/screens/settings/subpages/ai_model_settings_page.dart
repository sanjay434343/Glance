import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/gemma_mediapipe_service.dart';
import '../../../core/theme/theme.dart';
import '../../model_download/model_download_screen.dart';

class AiModelSettingsPage extends StatefulWidget {
  const AiModelSettingsPage({super.key});

  @override
  State<AiModelSettingsPage> createState() => _AiModelSettingsPageState();
}

class _AiModelSettingsPageState extends State<AiModelSettingsPage> {
  GemmaHardwareInfo? _hwInfo;
  String? _modelPath;
  int _modelFileSize = 0;
  bool _isLoading = true;
  bool _gpuEnabled = true;
  bool _isTogglingGpu = false;

  // Real-time Load/Unload Operation state
  bool _isOperating = false;
  String? _operatingAction; // 'loading' or 'unloading'

  @override
  void initState() {
    super.initState();
    _loadAllInfo();
  }

  Future<void> _loadAllInfo() async {
    try {
      final hw = await GemmaMediaPipeService.instance.fetchHardwareInfo();
      final path = await GemmaMediaPipeService.instance.resolveModelPath();
      final size = await GemmaMediaPipeService.instance.getModelFileSize();
      final gpuOn = await GemmaMediaPipeService.instance.isGpuEnabled();
      if (mounted) {
        setState(() {
          _hwInfo = hw;
          _modelPath = path;
          _modelFileSize = size;
          _gpuEnabled = gpuOn;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _handleGpuToggle(bool value) async {
    setState(() {
      _isTogglingGpu = true;
    });

    await GemmaMediaPipeService.instance.setGpuEnabled(value);
    await _loadAllInfo();

    if (mounted) {
      setState(() {
        _isTogglingGpu = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'GPU / Vulkan acceleration enabled.'
                : 'GPU disabled. Forcing CPU execution.',
          ),
          backgroundColor: value ? const Color(0xFF10B981) : Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleLoadModel() async {
    // Immediately show loader in card & action tile upon tap
    setState(() {
      _isOperating = true;
      _operatingAction = 'loading';
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Loading model into device memory...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final success = await GemmaMediaPipeService.instance.initModel(preferredBackend: 'AUTO');
      await _loadAllInfo();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Model loaded into memory (${_hwInfo?.activeBackend ?? (_gpuEnabled ? 'GPU' : 'CPU')}).'
                  : 'Failed to load model. Check model file.',
            ),
            backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to load model: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
          _operatingAction = null;
        });
      }
    }
  }

  Future<void> _handleUnloadModel() async {
    // Immediately show loader in card & action tile upon tap
    setState(() {
      _isOperating = true;
      _operatingAction = 'unloading';
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Unloading model from RAM and GPU VRAM...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final success = await GemmaMediaPipeService.instance.unloadModel();
      await _loadAllInfo();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Model unloaded from RAM and GPU VRAM.'
                  : 'Failed to unload model.',
            ),
            backgroundColor: success ? const Color(0xFF10B981) : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to unload model: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
          _operatingAction = null;
        });
      }
    }
  }

  Future<void> _handleSelectModelFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['task', 'bin'],
      );
      if (files.isNotEmpty && files.single.path != null) {
        final selectedPath = files.single.path!;
        final name = files.single.name;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected $name. Initializing...'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        final success = await GemmaMediaPipeService.instance.initModel(
          customModelPath: selectedPath,
          preferredBackend: 'AUTO',
        );
        await _loadAllInfo();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Model loaded and initialized successfully!'
                    : 'Failed to load selected model file.',
              ),
              backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File picker error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteModel() async {
    final sizeFormatted = _formatBytes(_modelFileSize);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('Delete Model File?'),
          ],
        ),
        content: Text(
          'This will permanently delete the model file ($sizeFormatted) from device storage and release all RAM/VRAM.\n\nYou will need to download or copy the model file again to run on-device AI queries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete File'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final deleted = await GemmaMediaPipeService.instance.deleteModelFile();
      await _loadAllInfo();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deleted
                  ? 'Model file deleted and storage space freed.'
                  : 'Could not delete model file.',
            ),
            backgroundColor: deleted ? Colors.red : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppTheme.getScaffoldBackground(isDark);
    final cardBg = AppTheme.getCardBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);
    final textColor = AppTheme.getPrimaryText(isDark);
    final subColor = AppTheme.getSecondaryText(isDark);

    final isLoaded = _hwInfo?.isModelLoaded ?? false;
    final hasFile = _modelPath != null && _modelFileSize > 0;
    final modelFileName = _modelPath != null
        ? _modelPath!.split(RegExp(r'[/\\]')).last
        : 'gemma-3n-E2B-it-int4.task';

    final Color statusColor;
    final String statusText;

    if (_isOperating) {
      statusColor = _operatingAction == 'loading' ? const Color(0xFF6366F1) : Colors.amber[800]!;
      statusText = _operatingAction == 'loading'
          ? 'Loading model into memory...'
          : 'Unloading model from RAM & VRAM...';
    } else if (isLoaded) {
      statusColor = const Color(0xFF10B981);
      statusText = 'Active in Memory (${_hwInfo?.activeBackend ?? (_gpuEnabled ? 'GPU' : 'CPU')})';
    } else if (hasFile) {
      statusColor = Colors.amber[700]!;
      statusText = 'Unloaded from RAM (Idle)';
    } else {
      statusColor = Colors.grey[500]!;
      statusText = 'No Model File Installed';
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'AI Engine & GPU',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: textColor,
            tooltip: 'Refresh Status',
            onPressed: _isOperating ? null : _loadAllInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── STATUS HERO CARD WITH REAL-TIME LOADER ──
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _isOperating
                              ? statusColor.withValues(alpha: 0.5)
                              : cardBorder,
                        ),
                        boxShadow: [
                          if (_isOperating)
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: _isOperating
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: statusColor,
                                        ),
                                      )
                                    : Icon(
                                        isLoaded ? Icons.memory_rounded : Icons.offline_bolt_outlined,
                                        color: statusColor,
                                        size: 24,
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      modelFileName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if (!_isOperating)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        if (!_isOperating) const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: statusColor,
                                              fontWeight: _isOperating ? FontWeight.bold : FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Real-time Linear Loader Bar when Operating
                          if (_isOperating) ...[
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 4,
                                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                color: statusColor,
                              ),
                            ),
                          ],

                          // Direct Tap to Load / Unload Button inside the Card
                          if (hasFile) ...[
                            const SizedBox(height: 14),
                            InkWell(
                              onTap: _isOperating
                                  ? null
                                  : (isLoaded ? _handleUnloadModel : _handleLoadModel),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: _isOperating
                                      ? statusColor.withValues(alpha: 0.1)
                                      : (isLoaded
                                          ? Colors.amber.withValues(alpha: 0.12)
                                          : const Color(0xFF10B981).withValues(alpha: 0.12)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _isOperating
                                        ? statusColor.withValues(alpha: 0.3)
                                        : (isLoaded
                                            ? Colors.amber[700]!.withValues(alpha: 0.35)
                                            : const Color(0xFF10B981).withValues(alpha: 0.35)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isOperating)
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: statusColor,
                                        ),
                                      )
                                    else
                                      Icon(
                                        isLoaded ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                                        size: 18,
                                        color: isLoaded ? Colors.amber[800]! : const Color(0xFF10B981),
                                      ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isOperating
                                          ? (_operatingAction == 'unloading'
                                              ? 'Unloading Model...'
                                              : 'Loading Model...')
                                          : (isLoaded ? 'Tap to Unload Model' : 'Tap to Load Model'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _isOperating
                                            ? statusColor
                                            : (isLoaded ? Colors.amber[800]! : const Color(0xFF10B981)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          if (hasFile && !_isOperating) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Size on Disk',
                                    style: TextStyle(fontSize: 12, color: subColor),
                                  ),
                                  Text(
                                    _formatBytes(_modelFileSize),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── GPU HARDWARE ACCELERATION CARD ──
                    Text(
                      'HARDWARE ACCELERATION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.speed_rounded,
                                  color: Color(0xFF6366F1),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GPU Acceleration (Vulkan)',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _gpuEnabled
                                          ? 'Fast inference using on-device GPU & Vulkan.'
                                          : 'Running strictly on CPU fallback mode.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subColor,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _isTogglingGpu || _isOperating
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Switch.adaptive(
                                      value: _gpuEnabled,
                                      activeColor: const Color(0xFF6366F1),
                                      onChanged: _isOperating ? null : _handleGpuToggle,
                                    ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Hardware Engine',
                                style: TextStyle(fontSize: 12.5, color: subColor),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _gpuEnabled
                                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                      : Colors.grey.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _gpuEnabled ? 'Vulkan / OpenCL (GPU)' : 'CPU Only',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: _gpuEnabled ? const Color(0xFF10B981) : subColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── MODEL MANAGEMENT ACTIONS ──
                    Text(
                      'MODEL OPERATIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          // Load Model
                          if (!isLoaded && hasFile) ...[
                            _buildActionTile(
                              icon: Icons.play_arrow_rounded,
                              iconColor: const Color(0xFF10B981),
                              title: 'Load Model into Memory',
                              subtitle: _isOperating && _operatingAction == 'loading'
                                  ? 'Loading weights into GPU/VRAM now...'
                                  : 'Activates weights for on-device reasoning',
                              onTap: _isOperating ? null : _handleLoadModel,
                              isLoading: _isOperating && _operatingAction == 'loading',
                              textColor: textColor,
                              subColor: subColor,
                            ),
                            const Divider(height: 1, thickness: 0.5),
                          ],

                          // Unload Model
                          if (isLoaded) ...[
                            _buildActionTile(
                              icon: Icons.power_settings_new_rounded,
                              iconColor: Colors.amber[800]!,
                              title: 'Unload Model from Memory',
                              subtitle: _isOperating && _operatingAction == 'unloading'
                                  ? 'Freeing RAM and VRAM now...'
                                  : 'Frees ~2 GB of RAM and GPU VRAM',
                              onTap: _isOperating ? null : _handleUnloadModel,
                              isLoading: _isOperating && _operatingAction == 'unloading',
                              textColor: textColor,
                              subColor: subColor,
                            ),
                            const Divider(height: 1, thickness: 0.5),
                          ],

                          // Download Model Page
                          _buildActionTile(
                            icon: Icons.cloud_download_rounded,
                            iconColor: const Color(0xFF3478F6),
                            title: 'Download AI Model (.task)',
                            subtitle: 'Gemma 3N E2B IT Int4 high-speed downloader',
                            onTap: _isOperating
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const ModelDownloadScreen()),
                                    );
                                    _loadAllInfo();
                                  },
                            textColor: textColor,
                            subColor: subColor,
                          ),
                          const Divider(height: 1, thickness: 0.5),

                          // Import Custom File
                          _buildActionTile(
                            icon: Icons.folder_open_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            title: 'Import Custom Model File',
                            subtitle: 'Pick .task or .bin weights from storage',
                            onTap: _isOperating ? null : _handleSelectModelFile,
                            textColor: textColor,
                            subColor: subColor,
                          ),

                          // Delete Model
                          if (hasFile) ...[
                            const Divider(height: 1, thickness: 0.5),
                            _buildActionTile(
                              icon: Icons.delete_outline_rounded,
                              iconColor: Colors.red,
                              title: 'Delete Model File',
                              subtitle: 'Frees ${_formatBytes(_modelFileSize)} storage space',
                              onTap: _isOperating ? null : _handleDeleteModel,
                              textColor: Colors.red,
                              subColor: subColor,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required Color textColor,
    required Color subColor,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
          ],
        ),
      ),
    );
  }
}
