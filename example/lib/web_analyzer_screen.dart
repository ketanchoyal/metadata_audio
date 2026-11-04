import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  // Playback speed
  double _playbackSpeed = 1.0;

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

  void _cyclePlaybackSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.25;
      } else if (_playbackSpeed == 1.25) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
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
    final filename = 'artwork_${index + 1}.$extension';
    WebPlatformHelper.instance.downloadFile(pic.data, filename, pic.format);
    _showSnackbar('Downloaded $filename');
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('Copied $label to clipboard');
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF06B6D4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16), // Ultra dark slate
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
      backgroundColor: const Color(0xFF0D131F),
      elevation: 0,
      titleSpacing: 24,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFF1E293B), height: 1),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'v1.0',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Private in-browser metadata explorer · Powered by metadata_audio',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Privacy Badge with pulsing dot
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF131D2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF223049)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '100% Client-Side · Private',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // GitHub button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.code_rounded, size: 16),
            label: const Text('GitHub', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF223049)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => WebPlatformHelper.instance.openUrl(
              'https://github.com/ketanchoyal/metadata_audio',
            ),
          ),
        ),
        // Desktop Switcher is ONLY shown on Desktop (hidden on Web)
        if (!kIsWeb && widget.onSwitchToDesktop != null) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Switch to Desktop Suite',
            icon: const Icon(
              Icons.desktop_windows_outlined,
              color: Colors.white70,
            ),
            onPressed: widget.onSwitchToDesktop,
          ),
        ],
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Sidebar: Files & Dropzone
        SizedBox(width: 350, child: _buildSidebar()),
        Container(width: 1, color: const Color(0xFF1E293B)),
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
          color: const Color(0xFF131D2E),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to files'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF06B6D4),
                ),
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
      color: const Color(0xFF0D131F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dropzone / File Picker Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _pickFiles,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isDragging
                        ? [
                            const Color(0xFF06B6D4).withValues(alpha: 0.15),
                            const Color(0xFF6366F1).withValues(alpha: 0.15),
                          ]
                        : [const Color(0xFF141C2B), const Color(0xFF111724)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging
                        ? const Color(0xFF06B6D4)
                        : const Color(0xFF223049),
                    width: _isDragging ? 2 : 1.2,
                  ),
                  boxShadow: _isDragging
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF06B6D4,
                            ).withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cloud_upload_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Drop audio files here',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children:
                          [
                                'MP3',
                                'FLAC',
                                'M4A',
                                'WAV',
                                'OGG',
                                'OPUS',
                                'AAC',
                                'WMA',
                                'CAF',
                              ]
                              .map(
                                (ext) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF090D16),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  child: Text(
                                    ext,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.cyan.shade300,
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
                  'FILES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2638),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_files.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
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
                    child: Text(
                      'Clear all',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Files List
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 36,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No files loaded',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: [
                                    const Color(0xFF1E293B),
                                    const Color(0xFF162133),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFF1E293B),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _selectFile(index),
                          dense: true,
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(
                                      0xFF06B6D4,
                                    ).withValues(alpha: 0.15)
                                  : const Color(0xFF090D16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(
                                        0xFF06B6D4,
                                      ).withValues(alpha: 0.5)
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              ext.length <= 4 ? ext : ext.substring(0, 4),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? const Color(0xFF38BDF8)
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          title: Text(
                            file.metadata?.common.title ?? file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            '${_formatBytes(file.size)}${file.metadata?.format.duration != null ? " · ${_formatDuration(file.metadata!.format.duration!)}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.cyan.shade200
                                  : Colors.grey.shade400,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
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
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF06B6D4),
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Analyzing audio metadata...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (file.error != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 36,
                  color: Colors.redAccent,
                ),
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
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 13,
                  height: 1.4,
                ),
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
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.25),
                    const Color(0xFF06B6D4).withValues(alpha: 0.25),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.album_rounded,
                size: 52,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Decode your audio files',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Drop an audio file to explore metadata, cover art, chapters, format specs,\nand raw native tags in private, client-side detail.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildFeatureCard(
                    Icons.tag_rounded,
                    'Every Tag',
                    'ID3v1, ID3v2, Vorbis, QuickTime, ASF, APE, RIFF, EBML',
                    const Color(0xFF6366F1),
                  ),
                  _buildFeatureCard(
                    Icons.image_outlined,
                    'Cover Artwork',
                    'Extract full-resolution images, format details & download',
                    const Color(0xFF06B6D4),
                  ),
                  _buildFeatureCard(
                    Icons.play_circle_outline,
                    'In-Browser Playback',
                    'Listen to your audio file immediately without uploading',
                    const Color(0xFF10B981),
                  ),
                  _buildFeatureCard(
                    Icons.speed_rounded,
                    'Chapters & Specs',
                    'Bitrates, sample rates, multi-streams & chapter timestamps',
                    const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.file_open_outlined, size: 20),
              label: const Text(
                'Browse Audio File',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                elevation: 4,
                shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    height: 1.3,
                  ),
                ),
              ],
            ),
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
        color: Color(0xFF0D131F),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Art with 3D shadow and zoom cursor
              MouseRegion(
                cursor: firstPicture != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: firstPicture != null
                      ? () => _showImageDialog(firstPicture)
                      : null,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161F30),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF24334C)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
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
                            size: 52,
                            color: Color(0xFF475569),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 22),
              // Track Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR AUDIO, DECODED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: Colors.cyan.shade400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      common.title?.isNotEmpty == true
                          ? common.title!
                          : file.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${common.artist ?? "Unknown artist"} · ${common.album ?? "Unknown album"}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                            icon: format.lossless!
                                ? Icons.check_circle_rounded
                                : Icons.compress_rounded,
                          ),
                        _buildBadge(
                          _formatBytes(file.size),
                          const Color(0xFF475569),
                        ),
                        if (format.duration != null)
                          _buildBadge(
                            _formatDuration(format.duration!),
                            const Color(0xFF0284C7),
                            icon: Icons.timer_outlined,
                          ),
                        if (format.bitrate != null)
                          _buildBadge(
                            '${(format.bitrate! / 1000).round()} kbps',
                            const Color(0xFF7C3AED),
                          ),
                        if (format.sampleRate != null)
                          _buildBadge(
                            '${(format.sampleRate! / 1000).toStringAsFixed(1)} kHz',
                            const Color(0xFF0D9488),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Export JSON Button
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text(
                  'Export JSON',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF334155)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _exportJson(file),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Audio Player Control Bar
          _buildPlayerBar(file),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(AnalyzedFile file) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223049)),
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
                      // Play/Pause button
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF06B6D4,
                              ).withValues(alpha: 0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 26,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              _audioPlayer.pause();
                            } else {
                              _audioPlayer.play();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Time display
                      Text(
                        _formatSeconds(currentPos),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Seek Slider
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            activeTrackColor: const Color(0xFF06B6D4),
                            inactiveTrackColor: const Color(0xFF1E293B),
                            thumbColor: Colors.white,
                            overlayColor: const Color(
                              0xFF06B6D4,
                            ).withValues(alpha: 0.2),
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
                      const SizedBox(width: 10),
                      Text(
                        _formatSeconds(duration),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Speed toggle button
                      TextButton(
                        onPressed: _cyclePlaybackSpeed,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(40, 28),
                          backgroundColor: const Color(0xFF1C2638),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
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

  Widget _buildBadge(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(AudioMetadata metadata) {
    final artworkCount = (metadata.common.picture ?? const []).length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D131F),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: const Color(0xFF06B6D4),
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade400,
        tabAlignment: TabAlignment.start,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
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
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      '$artworkCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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
          const Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 18,
                color: Color(0xFF06B6D4),
              ),
              SizedBox(width: 8),
              Text(
                'Technical Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                Icons.timer_outlined,
                'Duration',
                format.duration != null
                    ? '${_formatDuration(format.duration!)} (${format.duration!.toStringAsFixed(2)}s)'
                    : '—',
              ),
              _buildMetricCard(
                Icons.speed_rounded,
                'Bitrate',
                format.bitrate != null
                    ? '${(format.bitrate! / 1000).round()} kbps'
                    : '—',
              ),
              _buildMetricCard(
                Icons.inventory_2_outlined,
                'Container',
                format.container ?? '—',
              ),
              _buildMetricCard(
                Icons.audiotrack_outlined,
                'Codec',
                format.codec ?? '—',
              ),
              _buildMetricCard(
                Icons.surround_sound_outlined,
                'Channels',
                format.numberOfChannels != null
                    ? '${format.numberOfChannels} ${_channelName(format.numberOfChannels!)}'
                    : '—',
              ),
              _buildMetricCard(
                Icons.waves_rounded,
                'Sample rate',
                format.sampleRate != null
                    ? '${(format.sampleRate! / 1000).toStringAsFixed(1)} kHz'
                    : '—',
              ),
              _buildMetricCard(
                Icons.high_quality_outlined,
                'Bit depth',
                format.bitsPerSample != null
                    ? '${format.bitsPerSample}-bit'
                    : '—',
              ),
              _buildMetricCard(
                Icons.verified_outlined,
                'Lossless',
                format.lossless != null
                    ? (format.lossless! ? 'Yes' : 'No')
                    : '—',
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Track information
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 8),
              Text(
                'Track Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 32),
          // Quality & Warnings
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: warnings.isNotEmpty
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                  : const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: warnings.isNotEmpty
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                    : const Color(0xFF10B981).withValues(alpha: 0.35),
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
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      warnings.isNotEmpty
                          ? '${warnings.length} parser warning${warnings.length == 1 ? "" : "s"}'
                          : 'Analysis complete · Clean metadata extraction',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...warnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '• ${w.message}',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                          height: 1.3,
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

  Widget _buildMetricCard(IconData icon, String label, String value) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141C2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF223049)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF06B6D4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
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
        color: const Color(0xFF141C2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223049)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFF1E293B)),
        itemBuilder: (context, index) {
          final row = filtered[index];
          final isEven = index.isEven;

          return Container(
            color: isEven
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.015),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    row.$2!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  color: Colors.grey.shade600,
                  tooltip: 'Copy',
                  onPressed: () => _copyToClipboard(row.$2!, row.$1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
              hintText: 'Search ${entries.length} common tags...',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF06B6D4),
              ),
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
                    'No common tags match "$_commonSearch"',
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 190,
                            child: SelectableText(
                              item.$1,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                height: 1.4,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            color: Colors.grey.shade600,
                            tooltip: 'Copy',
                            onPressed: () => _copyToClipboard(item.$2, item.$1),
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
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: Color(0xFF06B6D4)),
              SizedBox(width: 8),
              Text(
                'Container & Codec Properties',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
            const SizedBox(height: 32),
            Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tracks (${trackInfo.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...trackInfo.map(
              (track) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      track.type == TrackType.video
                          ? Icons.videocam_outlined
                          : Icons.audiotrack_outlined,
                      color: const Color(0xFF818CF8),
                      size: 20,
                    ),
                  ),
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
            const SizedBox(height: 32),
            Row(
              children: [
                const Icon(
                  Icons.bookmarks_outlined,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Text(
                  'Chapters (${chapters.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141C2B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF223049)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: chapters.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF1E293B)),
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
                          fontWeight: FontWeight.bold,
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
                        color: Colors.cyan.shade300,
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
              size: 52,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 14),
            Text(
              'No embedded artwork found in this file',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.76,
      ),
      itemCount: pictures.length,
      itemBuilder: (context, index) {
        final pic = pictures[index];

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141C2B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF223049)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
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
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pic.type ?? pic.description ?? 'Picture #${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download, size: 14),
                        label: const Text(
                          'Download Image',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF06B6D4),
                          side: const BorderSide(color: Color(0xFF223049)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF06B6D4),
              ),
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

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141C2B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF223049)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  shape: const Border(),
                  title: Row(
                    children: [
                      Text(
                        groupName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF06B6D4,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${filtered.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: filtered
                      .map(
                        (tag) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 160,
                                child: SelectableText(
                                  tag.id,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
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
                                    height: 1.3,
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
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(
                'Full Metadata JSON Tree',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy JSON'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF223049)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  _showSnackbar('Copied JSON to clipboard');
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Download .json'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _exportJson(file),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                jsonString,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFFE2E8F0),
                  height: 1.45,
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
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 800),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 30,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      pic.type ?? pic.description ?? 'Artwork',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${pic.format} · ${_formatBytes(pic.data.length)})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  color: Colors.black45,
                  child: Image.memory(
                    Uint8List.fromList(pic.data),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
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
