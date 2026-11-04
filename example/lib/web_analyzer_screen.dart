import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:metadata_audio/metadata_audio.dart';
import 'platform/platform_helper.dart';

/// Representation of an audio file loaded into the analyzer.
class AnalyzedFile {
  AnalyzedFile({required this.name, required this.size, required this.bytes});

  final String name;
  final int size;
  final Uint8List bytes;

  AudioMetadata? metadata;
  String? error;
  bool isLoading = false;
  String? audioUrl;
}

class WebAnalyzerScreen extends StatefulWidget {
  const WebAnalyzerScreen({super.key, this.onSwitchToDesktop});

  final VoidCallback? onSwitchToDesktop;

  @override
  State<WebAnalyzerScreen> createState() => _WebAnalyzerScreenState();
}

class _WebAnalyzerScreenState extends State<WebAnalyzerScreen>
    with SingleTickerProviderStateMixin {
  final List<AnalyzedFile> _files = [];
  int _selectedIndex = -1;
  bool _isDragging = false;
  late TabController _tabController;
  late final AudioPlayerService _audioPlayer;

  // Search queries
  String _commonSearch = '';
  String _nativeSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _audioPlayer = WebPlatformHelper.instance.createAudioPlayer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    for (final file in _files) {
      if (file.audioUrl != null) {
        WebPlatformHelper.instance.revokeAudioUrl(file.audioUrl!);
      }
    }
    super.dispose();
  }

  AnalyzedFile? get _selectedFile {
    if (_selectedIndex >= 0 && _selectedIndex < _files.length) {
      return _files[_selectedIndex];
    }
    return null;
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'm4a',
          'm4b',
          'aac',
          'flac',
          'ogg',
          'opus',
          'wav',
          'aif',
          'aiff',
          'wma',
          'asf',
          'caf',
          'wv',
          'dsf',
          'dff',
          'webm',
          'mpc',
        ],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      for (final picked in result.files) {
        final bytes = picked.bytes;
        if (bytes != null) {
          await _addAndAnalyzeFile(picked.name, picked.size, bytes);
        }
      }
    } catch (e) {
      _showSnackbar('Failed to pick file: $e', isError: true);
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _isDragging = false);
    for (final xfile in details.files) {
      try {
        final bytes = await xfile.readAsBytes();
        await _addAndAnalyzeFile(xfile.name, bytes.length, bytes);
      } catch (e) {
        _showSnackbar('Failed to read dropped file: $e', isError: true);
      }
    }
  }

  Future<void> _addAndAnalyzeFile(
    String name,
    int size,
    Uint8List bytes,
  ) async {
    final file = AnalyzedFile(name: name, size: size, bytes: bytes);
    setState(() {
      _files.add(file);
      _selectedIndex = _files.length - 1;
      file.isLoading = true;
    });

    try {
      final metadata = await parseBytes(
        bytes,
        options: const ParseOptions(
          includeChapters: true,
          duration: true,
          mkvUseIndex: true,
        ),
      );

      setState(() {
        file.metadata = metadata;
        file.isLoading = false;
      });

      // Prepare audio playback
      final mimeType = metadata.format.container != null
          ? 'audio/${metadata.format.container!.toLowerCase()}'
          : 'audio/*';
      final url = WebPlatformHelper.instance.createAudioUrl(bytes, mimeType);
      if (url != null) {
        file.audioUrl = url;
        if (_selectedFile == file) {
          _audioPlayer.loadUrl(url);
        }
      }
    } catch (e) {
      setState(() {
        file.error = e.toString();
        file.isLoading = false;
      });
    }
  }

  void _selectFile(int index) {
    if (_selectedIndex == index) return;
    _audioPlayer.stop();
    setState(() {
      _selectedIndex = index;
      _commonSearch = '';
      _nativeSearch = '';
    });
    final file = _selectedFile;
    if (file?.audioUrl != null) {
      _audioPlayer.loadUrl(file!.audioUrl!);
    }
  }

  void _removeFile(int index) {
    final removed = _files.removeAt(index);
    if (removed.audioUrl != null) {
      WebPlatformHelper.instance.revokeAudioUrl(removed.audioUrl!);
    }
    _audioPlayer.stop();

    setState(() {
      if (_files.isEmpty) {
        _selectedIndex = -1;
      } else if (_selectedIndex >= _files.length) {
        _selectedIndex = _files.length - 1;
      }
    });

    final current = _selectedFile;
    if (current?.audioUrl != null) {
      _audioPlayer.loadUrl(current!.audioUrl!);
    }
  }

  void _exportJson(AnalyzedFile file) {
    final metadata = file.metadata;
    if (metadata == null) return;

    final jsonMap = audioMetadataToJson(metadata);
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);
    final bytes = utf8.encode(jsonString);
    final filename = '${file.name}.metadata.json';

    WebPlatformHelper.instance.downloadFile(
      bytes,
      filename,
      'application/json;charset=utf-8',
    );
    Clipboard.setData(ClipboardData(text: jsonString));
    _showSnackbar('Exported $filename and copied JSON to clipboard!');
  }

  void _downloadArtwork(Picture pic, int index) {
    final extension = pic.format.split('/').last;
    final filename = 'artwork_$index.$extension';
    WebPlatformHelper.instance.downloadFile(pic.data, filename, pic.format);
    _showSnackbar('Downloaded $filename');
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: _buildAppBar(),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: _handleDrop,
        child: Container(
          decoration: BoxDecoration(
            border: _isDragging
                ? Border.all(color: const Color(0xFF06B6D4), width: 3)
                : null,
          ),
          child: isWide ? _buildWideLayout() : _buildCompactLayout(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0B0F19),
      elevation: 0,
      titleSpacing: 24,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Audio Tag Analyzer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              Text(
                'Browser-based audio metadata explorer',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Privacy Badge
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 14,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              Text(
                '100% Client-Side',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade300,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (widget.onSwitchToDesktop != null)
          IconButton(
            tooltip: 'Switch to Desktop Test Suite',
            icon: const Icon(
              Icons.desktop_windows_outlined,
              color: Colors.white70,
            ),
            onPressed: widget.onSwitchToDesktop,
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Sidebar: Files & Dropzone
        SizedBox(width: 340, child: _buildSidebar()),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF1E293B)),
        // Right Main Panel
        Expanded(child: _buildMainPanel()),
      ],
    );
  }

  Widget _buildCompactLayout() {
    if (_files.isEmpty || _selectedFile == null) {
      return _buildSidebar();
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to files'),
                onPressed: () => setState(() => _selectedIndex = -1),
              ),
              const Spacer(),
              Text(
                _selectedFile?.name ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(child: _buildMainPanel()),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dropzone / File Picker Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _pickFiles,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: _isDragging
                      ? const Color(0xFF0E7490).withValues(alpha: 0.25)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging
                        ? const Color(0xFF06B6D4)
                        : const Color(0xFF334155),
                    width: _isDragging ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_upload_outlined,
                        color: Color(0xFF818CF8),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Drop audio files here',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'or click to browse from device',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children:
                          ['MP3', 'FLAC', 'M4A', 'WAV', 'OGG', 'OPUS', 'AAC']
                              .map(
                                (ext) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B0F19),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    ext,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Files Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Files',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_files.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
                const Spacer(),
                if (_files.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _audioPlayer.stop();
                      setState(() {
                        _files.clear();
                        _selectedIndex = -1;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 24),
                    ),
                    child: const Text(
                      'Clear all',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          // Files List
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Text(
                      'No files analyzed yet',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isSelected = index == _selectedIndex;
                      final ext = file.name.split('.').last.toUpperCase();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _selectFile(index),
                          dense: true,
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0F19),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              ext.length <= 4 ? ext : ext.substring(0, 4),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                          title: Text(
                            file.metadata?.common.title ?? file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            '${_formatBytes(file.size)}${file.metadata?.format.duration != null ? " · ${_formatDuration(file.metadata!.format.duration!)}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            color: Colors.grey.shade500,
                            tooltip: 'Remove',
                            onPressed: () => _removeFile(index),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPanel() {
    final file = _selectedFile;

    if (file == null) {
      return _buildEmptyState();
    }

    if (file.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF06B6D4)),
            SizedBox(height: 16),
            Text(
              'Analyzing audio metadata...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (file.error != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(24),
          constraints: const Duration(milliseconds: 500) == Duration.zero
              ? null
              : const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              const Text(
                'Parsing Error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                file.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final metadata = file.metadata;
    if (metadata == null) return _buildEmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Track Header & Playback
        _buildTrackHeader(file, metadata),
        // Tabs
        _buildTabBar(metadata),
        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(metadata),
              _buildCommonTagsTab(metadata),
              _buildMediaDetailsTab(metadata),
              _buildArtworkTab(metadata),
              _buildNativeTagsTab(metadata),
              _buildJsonTab(file),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.2),
                    const Color(0xFF06B6D4).withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 46,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Drop an audio file to analyze',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an audio file to uncover its full story, from artist and album\nto the smallest technical detail.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildFeatureChip(Icons.tag_rounded, 'Every tag'),
                _buildFeatureChip(Icons.image_outlined, 'Cover artwork'),
                _buildFeatureChip(Icons.play_circle_outline, 'Audio playback'),
                _buildFeatureChip(
                  Icons.speed_rounded,
                  'Chapters & technical specs',
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('Browse audio file'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackHeader(AnalyzedFile file, AudioMetadata metadata) {
    final common = metadata.common;
    final format = metadata.format;
    final pictures = common.picture ?? const [];
    final firstPicture = pictures.isNotEmpty ? pictures.first : null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F19),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Art
              GestureDetector(
                onTap: firstPicture != null
                    ? () => _showImageDialog(firstPicture)
                    : null,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: firstPicture != null
                      ? Image.memory(
                          Uint8List.fromList(firstPicture.data),
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(
                          Icons.album_rounded,
                          size: 48,
                          color: Color(0xFF475569),
                        ),
                ),
              ),
              const SizedBox(width: 20),
              // Track Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR AUDIO, DECODED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.cyan.shade400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      common.title?.isNotEmpty == true
                          ? common.title!
                          : file.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${common.artist ?? "Unknown artist"} · ${common.album ?? "Unknown album"}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildBadge(
                          format.container ?? 'Audio',
                          const Color(0xFF6366F1),
                        ),
                        if (format.lossless != null)
                          _buildBadge(
                            format.lossless! ? 'Lossless' : 'Lossy',
                            format.lossless!
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        _buildBadge(
                          _formatBytes(file.size),
                          const Color(0xFF475569),
                        ),
                        if (format.duration != null)
                          _buildBadge(
                            _formatDuration(format.duration!),
                            const Color(0xFF0284C7),
                          ),
                        if (format.bitrate != null)
                          _buildBadge(
                            '${(format.bitrate! / 1000).round()} kbps',
                            const Color(0xFF7C3AED),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Export JSON Button
              IconButton.filledTonal(
                icon: const Icon(Icons.download_rounded, size: 20),
                tooltip: 'Export metadata as JSON',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _exportJson(file),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Audio Player Control Bar
          _buildPlayerBar(file),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(AnalyzedFile file) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: _audioPlayer.isPlaying,
        builder: (context, isPlaying, _) {
          return ValueListenableBuilder<double>(
            valueListenable: _audioPlayer.currentPosition,
            builder: (context, currentPos, _) {
              return ValueListenableBuilder<double>(
                valueListenable: _audioPlayer.totalDuration,
                builder: (context, totalDur, _) {
                  final duration = totalDur > 0
                      ? totalDur
                      : (file.metadata?.format.duration ?? 0.0);
                  final progress = duration > 0
                      ? (currentPos / duration).clamp(0.0, 1.0)
                      : 0.0;

                  return Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          size: 32,
                          color: const Color(0xFF06B6D4),
                        ),
                        onPressed: () {
                          if (isPlaying) {
                            _audioPlayer.pause();
                          } else {
                            _audioPlayer.play();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSeconds(currentPos),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            activeTrackColor: const Color(0xFF06B6D4),
                            inactiveTrackColor: const Color(0xFF334155),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: duration > 0
                                ? (val) {
                                    _audioPlayer.seek(val * duration);
                                  }
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSeconds(duration),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.95),
        ),
      ),
    );
  }

  Widget _buildTabBar(AudioMetadata metadata) {
    final artworkCount = (metadata.common.picture ?? const []).length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F19),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: const Color(0xFF06B6D4),
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        tabAlignment: TabAlignment.start,
        tabs: [
          const Tab(
            icon: Icon(Icons.dashboard_outlined, size: 18),
            text: 'Overview',
          ),
          const Tab(
            icon: Icon(Icons.tag_rounded, size: 18),
            text: 'Common tags',
          ),
          const Tab(
            icon: Icon(Icons.tune_rounded, size: 18),
            text: 'Media details',
          ),
          Tab(
            icon: const Icon(Icons.image_outlined, size: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Artwork'),
                if (artworkCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$artworkCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(
            icon: Icon(Icons.folder_special_outlined, size: 18),
            text: 'Native tags',
          ),
          const Tab(icon: Icon(Icons.code_rounded, size: 18), text: 'Raw JSON'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(AudioMetadata metadata) {
    final format = metadata.format;
    final common = metadata.common;
    final warnings = metadata.quality.warnings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Technical summary
          const Text(
            'Technical Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                'Duration',
                format.duration != null
                    ? '${_formatDuration(format.duration!)} (${format.duration!.toStringAsFixed(2)}s)'
                    : '—',
              ),
              _buildMetricCard(
                'Bitrate',
                format.bitrate != null
                    ? '${(format.bitrate! / 1000).round()} kbps'
                    : '—',
              ),
              _buildMetricCard('Container', format.container ?? '—'),
              _buildMetricCard('Codec', format.codec ?? '—'),
              _buildMetricCard(
                'Channels',
                format.numberOfChannels != null
                    ? '${format.numberOfChannels} ${_channelName(format.numberOfChannels!)}'
                    : '—',
              ),
              _buildMetricCard(
                'Sample rate',
                format.sampleRate != null
                    ? '${(format.sampleRate! / 1000).toStringAsFixed(1)} kHz'
                    : '—',
              ),
              _buildMetricCard(
                'Bit depth',
                format.bitsPerSample != null
                    ? '${format.bitsPerSample}-bit'
                    : '—',
              ),
              _buildMetricCard(
                'Lossless',
                format.lossless != null
                    ? (format.lossless! ? 'Yes' : 'No')
                    : '—',
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Track information
          const Text(
            'Track Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTable([
            ('Title', common.title),
            ('Artist', common.artist),
            ('Album', common.album),
            ('Album Artist', common.albumartist),
            ('Year / Date', common.year?.toString() ?? common.date),
            (
              'Track',
              common.track.no != null
                  ? '${common.track.no}${common.track.of != null ? " of ${common.track.of}" : ""}'
                  : null,
            ),
            (
              'Disk',
              common.disk.no != null
                  ? '${common.disk.no}${common.disk.of != null ? " of ${common.disk.of}" : ""}'
                  : null,
            ),
            ('Genre', common.genre?.join(', ')),
            ('Composer', common.composer?.join(', ')),
          ]),
          const SizedBox(height: 28),
          // Quality & Warnings
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: warnings.isNotEmpty
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                  : const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: warnings.isNotEmpty
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                    : const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      warnings.isNotEmpty
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color: warnings.isNotEmpty
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      warnings.isNotEmpty
                          ? '${warnings.length} parser warning${warnings.length == 1 ? "" : "s"}'
                          : 'Analysis complete · Clean parsing',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...warnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• ${w.message}',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTable(List<(String, String?)> rows) {
    final filtered = rows
        .where((r) => r.$2 != null && r.$2!.isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFF334155)),
        itemBuilder: (context, index) {
          final row = filtered[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    row.$1,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommonTagsTab(AudioMetadata metadata) {
    final entries = <(String, String)>[];
    final common = metadata.common;

    void add(String key, dynamic value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is List && value.isEmpty) return;
      if (value is List) {
        entries.add((key, value.join(' · ')));
      } else {
        entries.add((key, value.toString()));
      }
    }

    add('title', common.title);
    add('artist', common.artist);
    add('artists', common.artists);
    add('album', common.album);
    add('albumartist', common.albumartist);
    add('year', common.year);
    add('date', common.date);
    add(
      'track',
      common.track.no != null
          ? '${common.track.no}${common.track.of != null ? " of ${common.track.of}" : ""}'
          : null,
    );
    add(
      'disk',
      common.disk.no != null
          ? '${common.disk.no}${common.disk.of != null ? " of ${common.disk.of}" : ""}'
          : null,
    );
    add('genre', common.genre);
    add('composer', common.composer);
    add('lyricist', common.lyricist);
    add('writer', common.writer);
    add('conductor', common.conductor);
    add('remixer', common.remixer);
    add('producer', common.producer);
    add('engineer', common.engineer);
    add('technician', common.technician);
    add('bpm', common.bpm);
    add('isrc', common.isrc);
    add('barcode', common.barcode);
    add('catalognumber', common.catalognumber);
    add('label', common.label);
    add('comment', common.comment);
    add('lyrics', common.lyrics);
    add('copyright', common.copyright);
    add('encodedby', common.encodedby);
    add('encodersettings', common.encodersettings);
    add('musicbrainz_trackid', common.musicbrainz_trackid);
    add('musicbrainz_albumid', common.musicbrainz_albumid);
    add('musicbrainz_artistid', common.musicbrainz_artistid);
    add('musicbrainz_recordingid', common.musicbrainz_recordingid);
    add('acoustid_id', common.acoustid_id);

    final filtered = entries.where((e) {
      if (_commonSearch.isEmpty) return true;
      final q = _commonSearch.toLowerCase();
      return e.$1.toLowerCase().contains(q) || e.$2.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search common tags...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _commonSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _commonSearch = ''),
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _commonSearch = val),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No common tags match query',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFF1E293B)),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 180,
                            child: Text(
                              item.$1,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Colors.cyan.shade300,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMediaDetailsTab(AudioMetadata metadata) {
    final format = metadata.format;
    final chapters = format.chapters;
    final trackInfo = format.trackInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Container & Codec Properties',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTable([
            ('Container', format.container),
            ('Codec', format.codec),
            ('Codec Profile', format.codecProfile),
            (
              'Duration',
              format.duration != null ? '${format.duration} seconds' : null,
            ),
            (
              'Bitrate',
              format.bitrate != null
                  ? '${format.bitrate} bps (${(format.bitrate! / 1000).round()} kbps)'
                  : null,
            ),
            (
              'Sample Rate',
              format.sampleRate != null ? '${format.sampleRate} Hz' : null,
            ),
            (
              'Channels',
              format.numberOfChannels != null
                  ? '${format.numberOfChannels}'
                  : null,
            ),
            (
              'Bits Per Sample',
              format.bitsPerSample != null ? '${format.bitsPerSample}' : null,
            ),
            ('Number of Samples', format.numberOfSamples?.toString()),
            (
              'Lossless',
              format.lossless != null
                  ? (format.lossless! ? 'true' : 'false')
                  : null,
            ),
            (
              'Container Duration',
              format.containerDuration != null
                  ? '${format.containerDuration} seconds'
                  : null,
            ),
            (
              'Overall Bitrate',
              format.overallBitrate != null
                  ? '${(format.overallBitrate! / 1000).round()} kbps'
                  : null,
            ),
          ]),
          if (trackInfo.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Tracks (${trackInfo.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ...trackInfo.map(
              (track) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    '${track.type ?? "Track"} · ${track.codecName ?? "Unknown Codec"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Track ID: ${track.id ?? "N/A"} · Duration: ${track.duration != null ? _formatDuration(track.duration!) : "N/A"}',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
          if (chapters != null && chapters.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Chapters (${chapters.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: chapters.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF334155)),
                itemBuilder: (context, i) {
                  final ch = chapters[i];
                  final start = _formatSeconds(ch.start / 1000.0);
                  final end = ch.end != null
                      ? _formatSeconds(ch.end! / 1000.0)
                      : '';

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(
                        0xFF06B6D4,
                      ).withValues(alpha: 0.2),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                    title: Text(
                      ch.title.isNotEmpty ? ch.title : 'Chapter ${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Text(
                      end.isNotEmpty ? '$start - $end' : start,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArtworkTab(AudioMetadata metadata) {
    final pictures = metadata.common.picture ?? const [];

    if (pictures.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 12),
            Text(
              'No embedded artwork found in this file',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: pictures.length,
      itemBuilder: (context, index) {
        final pic = pictures[index];

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showImageDialog(pic),
                  child: Container(
                    color: Colors.black26,
                    child: Image.memory(
                      Uint8List.fromList(pic.data),
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pic.type ?? pic.description ?? 'Picture #${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pic.format} · ${_formatBytes(pic.data.length)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download, size: 14),
                        label: const Text(
                          'Download',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _downloadArtwork(pic, index),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNativeTagsTab(AudioMetadata metadata) {
    final nativeGroups = metadata.native;

    if (nativeGroups.isEmpty) {
      return Center(
        child: Text(
          'No native tags found',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search native tags...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _nativeSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _nativeSearch = ''),
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _nativeSearch = val),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: nativeGroups.length,
            itemBuilder: (context, gIndex) {
              final groupName = nativeGroups.keys.elementAt(gIndex);
              final tags = nativeGroups[groupName] ?? [];

              final filtered = tags.where((tag) {
                if (_nativeSearch.isEmpty) return true;
                final q = _nativeSearch.toLowerCase();
                return tag.id.toLowerCase().contains(q) ||
                    tag.value.toString().toLowerCase().contains(q);
              }).toList();

              if (filtered.isEmpty) return const SizedBox.shrink();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(
                    groupName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  children: filtered
                      .map(
                        (tag) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Text(
                                  tag.id,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  tag.value is Uint8List
                                      ? '${(tag.value as Uint8List).length} bytes binary data'
                                      : tag.value.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJsonTab(AnalyzedFile file) {
    final metadata = file.metadata;
    if (metadata == null) return const SizedBox.shrink();

    final jsonMap = audioMetadataToJson(metadata);
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy JSON'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  _showSnackbar('Copied JSON to clipboard');
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Download .json'),
                onPressed: () => _exportJson(file),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0F19),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                jsonString,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showImageDialog(Picture pic) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                Uint8List.fromList(pic.data),
                fit: BoxFit.contain,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _formatSeconds(double seconds) {
    final s = seconds.floor();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _channelName(int channels) {
    switch (channels) {
      case 1:
        return '(Mono)';
      case 2:
        return '(Stereo)';
      case 6:
        return '(5.1 Surround)';
      case 8:
        return '(7.1 Surround)';
      default:
        return '';
    }
  }
}
