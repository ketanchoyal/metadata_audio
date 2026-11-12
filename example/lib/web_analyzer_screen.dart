import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:metadata_audio/metadata_audio.dart';
import 'desktop_screen.dart' show parseCustomRangeMs;
import 'platform/platform_helper.dart';

/// Design tokens matching the clean studio aesthetic of Audio Tag Analyzer
class AppTheme {
  static const bg = Color(0xFFF7F8FA);
  static const cardBg = Colors.white;
  static const textDark = Color(0xFF242334);
  static const textSecondary = Color(0xFF796C88);
  static const textMuted = Color(0xFF8D839B);
  static const textLight = Color(0xFFA58AC7);

  static const primaryPurple = Color(0xFF6954D7);
  static const primaryButton = Color(0xFF7257CE);
  static const purpleAccent = Color(0xFF7961CE);
  static const purpleBorder = Color(0xFFC6BCE6);
  static const purpleLightBg = Color(0xFFF3F0FB);
  static const purpleLightHover = Color(0xFFEBE5F7);
  static const purpleBadge = Color(0xFFF0EEF7);
  static const purpleSelected = Color(0xFFF1EDFB);

  static const cardBorder = Color(0xFFE6E6ED);
  static const divider = Color(0xFFEEEAF3);
  static const rowDivider = Color(0xFFF0EDF5);
  static const playerBg = Color(0xFFF8F7FB);
  static const playerBorder = Color(0xFFECE8F2);
}

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
  const WebAnalyzerScreen({
    super.key,
    this.onSwitchToDesktop,
    this.initialFiles,
  });

  final VoidCallback? onSwitchToDesktop;
  final List<AnalyzedFile>? initialFiles;

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
  final TextEditingController _customStartController = TextEditingController(
    text: '0',
  );
  final TextEditingController _customEndController = TextEditingController(
    text: '5000',
  );
  bool _isExtractingChapter = false;

  // Search queries
  String _commonSearch = '';
  String _nativeSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _audioPlayer = WebPlatformHelper.instance.createAudioPlayer();
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _files.addAll(widget.initialFiles!);
      _selectedIndex = 0;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customStartController.dispose();
    _customEndController.dispose();
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

      _initAudioPlayer(file);
    } catch (e) {
      setState(() {
        file.error = e.toString();
        file.isLoading = false;
      });
    }
  }

  void _initAudioPlayer(AnalyzedFile file) {
    if (file.audioUrl == null) {
      final ext = file.name.split('.').last.toLowerCase();
      String mime = 'audio/mpeg';
      if (ext == 'wav') mime = 'audio/wav';
      if (ext == 'ogg') mime = 'audio/ogg';
      if (ext == 'aac' || ext == 'm4a') mime = 'audio/mp4';
      if (ext == 'flac') mime = 'audio/flac';
      file.audioUrl = WebPlatformHelper.instance.createAudioUrl(
        file.bytes,
        mime,
      );
    }
    if (file.audioUrl != null) {
      _audioPlayer.loadUrl(file.audioUrl!);
    }
  }

  void _selectFile(int index) {
    if (index >= 0 && index < _files.length) {
      setState(() => _selectedIndex = index);
      final file = _files[index];
      if (file.metadata != null) {
        _initAudioPlayer(file);
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      final removed = _files.removeAt(index);
      if (removed.audioUrl != null) {
        WebPlatformHelper.instance.revokeAudioUrl(removed.audioUrl!);
      }
      if (_files.isEmpty) {
        _selectedIndex = -1;
        _audioPlayer.pause();
      } else if (_selectedIndex >= _files.length) {
        _selectedIndex = _files.length - 1;
        _selectFile(_selectedIndex);
      } else if (_selectedIndex == index) {
        _selectFile(_selectedIndex);
      }
    });
  }

  void _clearAllFiles() {
    setState(() {
      for (final f in _files) {
        if (f.audioUrl != null) {
          WebPlatformHelper.instance.revokeAudioUrl(f.audioUrl!);
        }
      }
      _files.clear();
      _selectedIndex = -1;
      _audioPlayer.pause();
    });
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: isError ? Colors.red.shade700 : AppTheme.primaryPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('Copied $label to clipboard');
  }

  void _downloadJson(AnalyzedFile file) {
    if (file.metadata == null) return;
    final jsonMap = audioMetadataToJson(file.metadata!);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);
    final filename =
        '${file.name.replaceAll(RegExp(r'\.[^.]+$'), '')}_metadata.json';
    WebPlatformHelper.instance.downloadFile(
      utf8.encode(jsonStr),
      filename,
      'application/json',
    );
  }

  bool _supportsChapterDownload(AnalyzedFile file, AudioMetadata metadata) {
    if (file.bytes.isEmpty) return false;
    final container = metadata.format.container?.toLowerCase() ?? '';
    final codec = metadata.format.codec?.toLowerCase() ?? '';
    final lowerName = file.name.toLowerCase();
    if (container.contains('mp4') ||
        container.contains('m4a') ||
        container.contains('m4b') ||
        container.contains('quicktime') ||
        container.contains('isom') ||
        container.contains('3gp') ||
        container.contains('mpeg') ||
        container.contains('mp3') ||
        container.contains('adts') ||
        codec.contains('mp3') ||
        codec.contains('aac') ||
        codec.contains('alac') ||
        lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.m4a') ||
        lowerName.endsWith('.m4b') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.aac')) {
      return true;
    }
    if (file.bytes.length >= 8) {
      final boxType = String.fromCharCodes(file.bytes.sublist(4, 8));
      if (boxType == 'ftyp' ||
          boxType == 'moov' ||
          boxType == 'mdat' ||
          boxType == 'free' ||
          boxType == 'wide' ||
          boxType == 'skip') {
        return true;
      }
      if (file.bytes[0] == 0xFF && (file.bytes[1] & 0xE0) == 0xE0) {
        return true;
      }
      if (file.bytes.length >= 3 &&
          file.bytes[0] == 0x49 &&
          file.bytes[1] == 0x44 &&
          file.bytes[2] == 0x33) {
        return true;
      }
    }
    return false;
  }

  Future<void> _downloadChapterFromWeb(
    AnalyzedFile file,
    int startMs,
    int endMs, {
    String? title,
  }) async {
    if (_isExtractingChapter) return;
    if (file.bytes.isEmpty) {
      _showSnackbar(
        'File bytes are not available for chapter extraction.',
        isError: true,
      );
      return;
    }
    setState(() => _isExtractingChapter = true);
    _showSnackbar('Extracting chapter audio slice...');
    try {
      final result = await ChapterDownloader.extractChapterBytes(
        sourceBytes: file.bytes,
        chapterStartMs: startMs,
        chapterEndMs: endMs,
        fileName: file.name,
        includeMetadata: true,
        metadata: file.metadata,
      );

      if (!result.isSuccess ||
          result.bytes == null ||
          result.extension == null ||
          result.mimeType == null) {
        _showSnackbar(
          result.error ?? 'Failed to extract chapter audio',
          isError: true,
        );
        return;
      }

      final cleanTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim().replaceAll(RegExp(r'[^\w\-\.]'), '_')
          : 'range_${startMs}_$endMs';
      final filename = 'chapter_$cleanTitle.${result.extension}';

      final savedTarget = await WebPlatformHelper.instance.downloadFile(
        result.bytes!,
        filename,
        result.mimeType!,
      );
      if (savedTarget == null) return;
      _showSnackbar(
        'Downloaded $savedTarget (${_formatFileSize(result.bytes!.length)})',
      );
    } catch (e) {
      _showSnackbar('Failed to extract chapter: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isExtractingChapter = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppTheme.bg,
        colorScheme: const ColorScheme.light(
          primary: AppTheme.primaryPurple,
          surface: AppTheme.cardBg,
          onSurface: AppTheme.textDark,
        ),
        cardColor: AppTheme.cardBg,
        dividerColor: AppTheme.divider,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: Column(
          children: [
            _buildSiteHeader(),
            Expanded(
              child: DropTarget(
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
                onDragDone: _handleDrop,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildIntroSection(),
                          const SizedBox(height: 20),
                          _buildDropzone(),
                          const SizedBox(height: 28),
                          if (_files.isEmpty)
                            _buildEmptyState()
                          else
                            _buildWorkspace(),
                          const SizedBox(height: 32),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Header matching the reference app
  // ==========================================
  Widget _buildSiteHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Row(
        children: [
          // Brand Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x226B56CE),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Audio Tag Analyzer',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Instant in-browser metadata extraction',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Desktop Switcher (Only visible on native desktop)
          if (!kIsWeb && widget.onSwitchToDesktop != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton.icon(
                onPressed: widget.onSwitchToDesktop,
                icon: const Icon(Icons.desktop_windows, size: 14),
                label: const Text(
                  'Desktop Suite',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          // GitHub Source Link
          InkWell(
            onTap: () => WebPlatformHelper.instance.openUrl(
              'https://github.com/ketanchoyal/metadata_audio',
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.cardBorder),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Row(
                children: const [
                  Icon(Icons.code, size: 15, color: AppTheme.textSecondary),
                  SizedBox(width: 6),
                  Text(
                    'GitHub',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
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

  // ==========================================
  // Intro Section
  // ==========================================
  Widget _buildIntroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppTheme.purpleAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            const Text(
              '100% CLIENT-SIDE · PRIVATE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: Color(0xFF82759F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
              letterSpacing: -0.6,
            ),
            children: [
              TextSpan(text: 'Explore every tag in your '),
              TextSpan(
                text: 'audio files',
                style: TextStyle(color: AppTheme.purpleAccent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Private, browser-based audio metadata analysis powered by metadata_audio. Audio never leaves your computer.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Dropzone
  // ==========================================
  Widget _buildDropzone() {
    return Container(
      decoration: BoxDecoration(
        color: _isDragging ? AppTheme.purpleLightHover : AppTheme.purpleLightBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDragging ? AppTheme.primaryPurple : AppTheme.purpleBorder,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: _isDragging
            ? const [
                BoxShadow(
                  color: Color(0x227961CE),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          Row(
            children: [
              // Upload icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE6DFF4)),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: Color(0xFF8873C7),
                  size: 26,
                ),
              ),
              const SizedBox(width: 20),
              // Copy
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Drop audio file to inspect',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Supports MP3, FLAC, M4A, OGG, OPUS, WAV, AAC, WMA, AIFF, WebM, CAF & more',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Choose file button
              ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.file_upload, size: 16),
                label: const Text('Choose file'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryButton,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: const Color(0x227257CE),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Icon(Icons.lock_outline, size: 13, color: Color(0xFF77658B)),
              SizedBox(width: 6),
              Text(
                'Local-only analysis. Audio never leaves your browser.',
                style: TextStyle(fontSize: 11, color: Color(0xFF77658B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Empty State with Vinyl record illustration
  // ==========================================
  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          children: [
            // Vinyl graphic
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  Container(
                    width: 136,
                    height: 136,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE9E3F3),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Vinyl record
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFECE8F5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x186B5595),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFFE3DCED),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF9B87C5),
                          border: Border.all(
                            color: const Color(0xFFB4A4D5),
                            width: 5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'DROP AUDIO FILE TO INSPECT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF88739B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Inspect ID3, Vorbis, MP4 atoms, Chapters & Artwork',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select any audio track from your device to see parsed tags, codec profiles,\nembedded pictures, cue sheets, and chapter markers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            // Format chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children:
                  [
                    'MP3',
                    'FLAC',
                    'M4A',
                    'AAC',
                    'OGG',
                    'OPUS',
                    'WAV',
                    'AIFF',
                    'WMA',
                    'CAF',
                    'WebM',
                  ].map((fmt) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.purpleBadge,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE6DFF4)),
                      ),
                      child: Text(
                        fmt,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8E80AC),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Workspace: 2-column layout (Files left, Details right)
  // ==========================================
  Widget _buildWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 280, child: _buildFilesPanel()),
              const SizedBox(width: 22),
              Expanded(child: _buildResultPanel()),
            ],
          );
        } else {
          return Column(
            children: [
              _buildFilesPanel(),
              const SizedBox(height: 22),
              _buildResultPanel(),
            ],
          );
        }
      },
    );
  }

  // ==========================================
  // Files Sidebar Panel
  // ==========================================
  Widget _buildFilesPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Heading
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                const Text(
                  'FILES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.purpleBadge,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${_files.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8E80AC),
                    ),
                  ),
                ),
                const Spacer(),
                if (_files.isNotEmpty)
                  InkWell(
                    onTap: _clearAllFiles,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // File list
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _files.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final file = _files[index];
                final isSelected = index == _selectedIndex;

                return InkWell(
                  onTap: () => _selectFile(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.purpleSelected
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.audio_file_outlined,
                          size: 18,
                          color: isSelected
                              ? AppTheme.primaryPurple
                              : const Color(0xFF9B89BA),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatFileSize(file.size),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (file.isLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryPurple,
                            ),
                          )
                        else if (file.error != null)
                          const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.redAccent,
                          )
                        else
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Color(0xFF8E7AB6),
                          ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _removeFile(index),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Color(0xFF9E91AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // Local note
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.shield_outlined, size: 14, color: Color(0xFF8E82A2)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Client-side only. Files are never uploaded anywhere.',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8E82A2),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Result Panel (Details right)
  // ==========================================
  Widget _buildResultPanel() {
    final file = _selectedFile;
    if (file == null) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: const Center(
          child: Text(
            'Select a file to inspect metadata',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    if (file.isLoading) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: AppTheme.primaryPurple),
              SizedBox(height: 16),
              Text(
                'Parsing audio metadata...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (file.error != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.red, size: 24),
                SizedBox(width: 10),
                Text(
                  'Failed to parse file',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              file.error!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      );
    }

    final metadata = file.metadata;
    if (metadata == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTrackHeader(file, metadata),
          _buildAudioPlayerBar(file),
          _buildTabBar(metadata),
          _buildTabContent(file, metadata),
        ],
      ),
    );
  }

  // ==========================================
  // Track Header matching reference
  // ==========================================
  Widget _buildTrackHeader(AnalyzedFile file, AudioMetadata metadata) {
    final common = metadata.common;
    final format = metadata.format;
    final pictures = common.picture ?? [];
    final hasPicture = pictures.isNotEmpty && pictures.first.data.isNotEmpty;

    final title = common.title ?? file.name;
    final artist = common.artist ?? 'Unknown Artist';
    final album = common.album ?? 'Unknown Album';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album Cover / Vinyl Placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEEE9F6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE3DCED)),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPicture
                ? Image.memory(
                    Uint8List.fromList(pictures.first.data),
                    fit: BoxFit.cover,
                  )
                : const Center(
                    child: Icon(
                      Icons.album,
                      size: 40,
                      color: AppTheme.textLight,
                    ),
                  ),
          ),
          const SizedBox(width: 18),
          // Heading text & badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR AUDIO, DECODED',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF82759F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$artist · $album',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                // Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (format.container != null)
                      _buildHeaderChip(format.container!.toUpperCase()),
                    if (format.codec != null) _buildHeaderChip(format.codec!),
                    if (format.bitrate != null)
                      _buildHeaderChip(
                        '${(format.bitrate! / 1000).round()} kbps',
                      ),
                    if (format.sampleRate != null)
                      _buildHeaderChip('${format.sampleRate!} Hz'),
                    if (format.numberOfChannels != null)
                      _buildHeaderChip(
                        format.numberOfChannels == 1
                            ? 'Mono'
                            : (format.numberOfChannels == 2
                                  ? 'Stereo'
                                  : '${format.numberOfChannels} ch'),
                      ),
                    if (format.lossless == true)
                      _buildHeaderChip('Lossless', isAccent: true),
                    if (format.chapters != null && format.chapters!.isNotEmpty)
                      InkWell(
                        onTap: () => _tabController.animateTo(1),
                        borderRadius: BorderRadius.circular(4),
                        child: _buildHeaderChip(
                          '${format.chapters!.length} Chapters',
                          isAccent: true,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (format.chapters != null && format.chapters!.isNotEmpty) ...[
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.bookmarks_rounded, size: 14),
              label: Text(
                'Download Chapters (${format.chapters!.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Export JSON button
          OutlinedButton.icon(
            onPressed: () => _downloadJson(file),
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Export JSON', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: Color(0xFFE9E4F0)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(String text, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isAccent ? const Color(0xFFEBE5F7) : const Color(0xFFF5F3F8),
        borderRadius: BorderRadius.circular(4),
        border: isAccent ? Border.all(color: AppTheme.purpleBorder) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: isAccent ? AppTheme.primaryPurple : const Color(0xFF8D7D9E),
        ),
      ),
    );
  }

  // ==========================================
  // Inline Audio Player Bar
  // ==========================================
  Widget _buildAudioPlayerBar(AnalyzedFile file) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24).copyWith(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.playerBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.playerBorder),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _audioPlayer.isPlaying,
          _audioPlayer.currentPosition,
          _audioPlayer.totalDuration,
        ]),
        builder: (context, _) {
          final isPlaying = _audioPlayer.isPlaying.value;
          final current = _audioPlayer.currentPosition.value;
          final total = _audioPlayer.totalDuration.value;
          final maxVal = total > 0 ? total : 1.0;
          final clamped = current.clamp(0.0, maxVal);

          return Row(
            children: [
              // Play/Pause
              InkWell(
                onTap: () {
                  if (isPlaying) {
                    _audioPlayer.pause();
                  } else {
                    _audioPlayer.play();
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryPurple,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Current time
              Text(
                _formatSeconds(current),
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              // Slider
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: AppTheme.primaryPurple,
                    inactiveTrackColor: const Color(0xFFE2DDEC),
                    thumbColor: AppTheme.primaryPurple,
                  ),
                  child: Slider(
                    value: clamped,
                    min: 0.0,
                    max: maxVal,
                    onChanged: (val) {
                      _audioPlayer.seek(val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Total time
              Text(
                _formatSeconds(total),
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                ),
              ),
              if (file.metadata?.format.chapters != null &&
                  file.metadata!.format.chapters!.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.bookmarks_outlined),
                  iconSize: 18,
                  color: AppTheme.primaryPurple,
                  tooltip:
                      'View Chapters (${file.metadata!.format.chapters!.length})',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // Tabs Bar
  // ==========================================
  Widget _buildTabBar(AudioMetadata metadata) {
    final chapterCount = metadata.format.chapters?.length ?? 0;
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFEFEDF4)),
          bottom: BorderSide(color: Color(0xFFEFEDF4)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: const Color(0xFF7D5EC2),
        unselectedLabelColor: const Color(0xFF7D6C8D),
        indicatorColor: const Color(0xFF8A67D1),
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          const Tab(text: 'Overview'),
          Tab(
            text: chapterCount > 0 ? 'Chapters ($chapterCount)' : 'Chapters',
          ),
          const Tab(text: 'Common tags'),
          const Tab(text: 'Media details'),
          const Tab(text: 'Artwork'),
          const Tab(text: 'Native tags'),
          const Tab(text: 'Raw JSON'),
        ],
      ),
    );
  }

  // ==========================================
  // Tab Content Router
  // ==========================================
  Widget _buildTabContent(AnalyzedFile file, AudioMetadata metadata) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          switch (_tabController.index) {
            case 0:
              return _buildOverviewTab(file, metadata);
            case 1:
              return _buildChaptersTab(file, metadata);
            case 2:
              return _buildCommonTagsTab(metadata);
            case 3:
              return _buildMediaDetailsTab(file, metadata);
            case 4:
              return _buildArtworkTab(metadata);
            case 5:
              return _buildNativeTagsTab(metadata);
            case 6:
              return _buildRawJsonTab(file);
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  // ==========================================
  // Tab 1: Overview
  // ==========================================
  Widget _buildOverviewTab(AnalyzedFile file, AudioMetadata metadata) {
    final format = metadata.format;
    final common = metadata.common;
    final chapters = format.chapters ?? [];

    final durationSec = format.duration ?? 0.0;
    final bitrate = format.bitrate != null
        ? '${(format.bitrate! / 1000).round()} kbps'
        : 'Unknown';
    final sampleRate = format.sampleRate != null
        ? '${format.sampleRate!} Hz'
        : 'Unknown';
    final channels = format.numberOfChannels != null
        ? (format.numberOfChannels == 1
              ? '1 (Mono)'
              : (format.numberOfChannels == 2
                    ? '2 (Stereo)'
                    : '${format.numberOfChannels} ch'))
        : 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4 Stats Grid
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              _buildStatTile(
                'DURATION',
                _formatSeconds(durationSec),
                isFirst: true,
              ),
              _buildStatTile('BITRATE', bitrate),
              _buildStatTile('SAMPLE RATE', sampleRate),
              _buildStatTile('CHANNELS', channels, isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Chapters & Slicing Highlight on Overview Tab
        if (chapters.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.bookmarks_rounded,
                size: 16,
                color: AppTheme.primaryPurple,
              ),
              const SizedBox(width: 8),
              Text(
                'CHAPTERS & SLICING (${chapters.length})',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: Text(
                  'View all ${chapters.length} chapters',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryPurple,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.playerBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.playerBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'This audiobook contains ${chapters.length} chapters. Extract standalone playable .m4a/.mp3 chapters with preserved cover art & metadata.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDark,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.list_alt_rounded, size: 14),
                      label: const Text(
                        'Open Chapters Tab',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Show first 3 chapters with direct download buttons
                ...chapters.take(3).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final ch = entry.value;
                  final startSec = ch.start / 1000.0;
                  final endMs =
                      ch.end ??
                      (format.duration != null
                          ? (format.duration! * 1000).round()
                          : (ch.start + 180000));
                  final endSec = ch.end != null ? ch.end! / 1000.0 : null;
                  final sizeBytes =
                      (ch.byteOffset != null && ch.endByteOffset != null)
                          ? ch.endByteOffset! - ch.byteOffset!
                          : null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0ECF8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryPurple,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          endSec != null
                              ? '${_formatSeconds(startSec)} - ${_formatSeconds(endSec)}'
                              : _formatSeconds(startSec),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            ch.title.isNotEmpty
                                ? ch.title
                                : 'Chapter ${index + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        if (sizeBytes != null && sizeBytes >= 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatFileSize(sizeBytes),
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _isExtractingChapter
                              ? null
                              : () => _downloadChapterFromWeb(
                                  file,
                                  ch.start,
                                  endMs,
                                  title: ch.title,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryButton,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 13),
                          label: Text(
                            _isExtractingChapter ? 'Preparing...' : 'Download',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (chapters.length > 3) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: () => _tabController.animateTo(1),
                      child: Text(
                        'View all ${chapters.length} chapters in Chapters tab →',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryPurple,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Tag rows
        const Text(
          'TAG SUMMARY',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        _buildTagRow('Title', 'title', common.title),
        _buildTagRow('Artist', 'artist', common.artist),
        _buildTagRow('Album', 'album', common.album),
        _buildTagRow('Year', 'year', common.year?.toString()),
        _buildTagRow('Genre', 'genre', common.genre?.join(', ')),
        _buildTagRow(
          'Track #',
          'track',
          common.track.no != null
              ? '${common.track.no}${common.track.of != null ? '/${common.track.of}' : ''}'
              : null,
        ),
        _buildTagRow('Container', 'format.container', format.container),
        _buildTagRow('Codec', 'format.codec', format.codec),
        _buildTagRow(
          'Lossless',
          'format.lossless',
          format.lossless != null ? (format.lossless! ? 'Yes' : 'No') : null,
        ),
      ],
    );
  }

  // ==========================================
  // Tab 2: Dedicated Chapters Tab
  // ==========================================
  Widget _buildChaptersTab(AnalyzedFile file, AudioMetadata metadata) {
    final format = metadata.format;
    final chapters = format.chapters ?? [];
    final isSupported = _supportsChapterDownload(file, metadata);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isSupported) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chapter slicing & extraction is optimized for MP4, M4A, M4B, MOV, and MP3 audio files.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        // Hero Header Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.playerBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.playerBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryPurple,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmarks_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Audiobook Chapters & Slicing',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9E3F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${chapters.length} ${chapters.length == 1 ? 'Chapter' : 'Chapters'}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryPurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Download any chapter or custom time range as a standalone playable .m4a or .mp3 file with preserved cover art & metadata.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Custom Range Slicing Card
        _buildCustomRangeDownloadBox(file, format),
        const SizedBox(height: 24),

        // Chapters List Section
        if (chapters.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.bookmark_outline_rounded,
                  size: 40,
                  color: AppTheme.textLight,
                ),
                SizedBox(height: 12),
                Text(
                  'No Chapter Markers Found',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'This audio file does not contain embedded chapter atoms or ID3 CHAP frames.\nYou can still use the Custom Range Download above to extract and slice any portion of this track.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ] else ...[
          Row(
            children: [
              Text(
                'CHAPTERS (${chapters.length})',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(),
              const Text(
                'Click Download to save individual playable chapter files',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...chapters.asMap().entries.map((entry) {
            final index = entry.key;
            final ch = entry.value;
            final startSec = ch.start / 1000.0;
            final endMs =
                ch.end ??
                (format.duration != null
                    ? (format.duration! * 1000).round()
                    : (ch.start + 180000));
            final endSec = ch.end != null ? ch.end! / 1000.0 : null;
            final durationSec = endSec != null ? (endSec - startSec) : null;
            final sizeBytes = (ch.byteOffset != null && ch.endByteOffset != null)
                ? ch.endByteOffset! - ch.byteOffset!
                : null;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  // Chapter Number Badge
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EFFF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDFD5F5)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Title & Duration
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ch.title.isNotEmpty
                              ? ch.title
                              : 'Chapter ${index + 1}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              endSec != null
                                  ? '${_formatSeconds(startSec)} - ${_formatSeconds(endSec)}'
                                  : _formatSeconds(startSec),
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryPurple,
                              ),
                            ),
                            if (durationSec != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '(${_formatSeconds(durationSec)})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                            if (sizeBytes != null && sizeBytes >= 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• ${_formatFileSize(sizeBytes)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Play Chapter in Player
                  IconButton(
                    onPressed: () {
                      _audioPlayer.seek(startSec);
                      _audioPlayer.play();
                    },
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    iconSize: 22,
                    color: AppTheme.primaryPurple,
                    tooltip: 'Play from chapter start',
                  ),
                  const SizedBox(width: 6),

                  // Download Chapter Button
                  ElevatedButton.icon(
                    onPressed: _isExtractingChapter
                        ? null
                        : () => _downloadChapterFromWeb(
                            file,
                            ch.start,
                            endMs,
                            title: ch.title,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryButton,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: Text(
                      _isExtractingChapter ? 'Preparing...' : 'Download',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  // ==========================================
  // Custom Range Download Box
  // ==========================================
  Widget _buildCustomRangeDownloadBox(AnalyzedFile file, Format format) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.playerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.playerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.content_cut_rounded,
                size: 16,
                color: AppTheme.primaryPurple,
              ),
              const SizedBox(width: 8),
              const Text(
                'Custom Range Slicing & Download',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              const Text(
                'Supports ms, s, MM:SS, HH:MM:SS',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customStartController,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDark,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Start (ms / s / MM:SS)',
                    hintText: '0 or 00:00',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _customEndController,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDark,
                  ),
                  decoration: InputDecoration(
                    labelText: 'End (ms / s / MM:SS)',
                    hintText: '5000 or 00:05',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isExtractingChapter
                    ? null
                    : () {
                        final start = parseCustomRangeMs(
                          _customStartController.text,
                        );
                        final end = parseCustomRangeMs(
                          _customEndController.text,
                        );
                        if (start == null || end == null) {
                          _showSnackbar(
                            'Invalid range. Enter ms (15000), seconds (15.5s), or HH:MM:SS.mmm.',
                            isError: true,
                          );
                          return;
                        }
                        if (end <= start) {
                          _showSnackbar(
                            'End time must be greater than Start time.',
                            isError: true,
                          );
                          return;
                        }
                        _downloadChapterFromWeb(file, start, end);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryButton,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.download_rounded, size: 15),
                label: Text(
                  _isExtractingChapter ? 'Preparing...' : 'Download Range',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Extracts a standalone playable audio file with preserved cover art & metadata.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    String label,
    String value, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(right: BorderSide(color: AppTheme.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: Color(0xFF7A6688),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Tab 2: Common Tags
  // ==========================================
  Widget _buildCommonTagsTab(AudioMetadata metadata) {
    final common = metadata.common;
    final Map<String, (String, String?)> allTags = {
      'Title': ('title', common.title),
      'Artist': ('artist', common.artist),
      'Artists': ('artists', common.artists?.join(', ')),
      'Album': ('album', common.album),
      'Album Artist': ('albumartist', common.albumartist),
      'Year': ('year', common.year?.toString()),
      'Date': ('date', common.date),
      'Original Date': ('originaldate', common.originaldate),
      'Genre': ('genre', common.genre?.join(', ')),
      'Track Number': (
        'track.no',
        common.track.no != null
            ? '${common.track.no}${common.track.of != null ? ' of ${common.track.of}' : ''}'
            : null,
      ),
      'Disk Number': (
        'disk.no',
        common.disk.no != null
            ? '${common.disk.no}${common.disk.of != null ? ' of ${common.disk.of}' : ''}'
            : null,
      ),
      'Composer': ('composer', common.composer?.join(', ')),
      'Lyricist': ('lyricist', common.lyricist?.join(', ')),
      'Writer': ('writer', common.writer?.join(', ')),
      'Conductor': ('conductor', common.conductor?.join(', ')),
      'Remixer': ('remixer', common.remixer?.join(', ')),
      'Arranger': ('arranger', common.arranger?.join(', ')),
      'Engineer': ('engineer', common.engineer?.join(', ')),
      'Producer': ('producer', common.producer?.join(', ')),
      'DJ Mixer': ('djmixer', common.djmixer?.join(', ')),
      'Mixer': ('mixer', common.mixer?.join(', ')),
      'Label': ('label', common.label?.join(', ')),
      'ISRC': ('isrc', common.isrc?.join(', ')),
      'BPM': ('bpm', common.bpm?.toString()),
      'Key': ('key', common.key),
      'Mood': ('mood', common.mood),
      'Rating': ('rating', common.rating?.toString()),
      'Copyright': ('copyright', common.copyright),
      'Encoded By': ('encodedby', common.encodedby),
      'Encoder Settings': ('encodersettings', common.encodersettings),
      'Comment': ('comment', common.comment?.join('\n')),
      'MusicBrainz Track ID': (
        'musicbrainz_trackid',
        common.musicbrainz_trackid,
      ),
      'MusicBrainz Album ID': (
        'musicbrainz_albumid',
        common.musicbrainz_albumid,
      ),
      'MusicBrainz Artist ID': (
        'musicbrainz_artistid',
        common.musicbrainz_artistid?.join(', '),
      ),
      'MusicBrainz Recording ID': (
        'musicbrainz_recordingid',
        common.musicbrainz_recordingid,
      ),
      'AcoustID': ('acoustid_id', common.acoustid_id),
    };

    final filtered = allTags.entries.where((entry) {
      final value = entry.value.$2;
      if (value == null || value.trim().isEmpty) return false;
      if (_commonSearch.isEmpty) return true;
      final query = _commonSearch.toLowerCase();
      return entry.key.toLowerCase().contains(query) ||
          entry.value.$1.toLowerCase().contains(query) ||
          value.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section heading + Search
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Common Tags',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${filtered.length} fields found',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Search field
            Container(
              width: 200,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE8E4EE)),
                borderRadius: BorderRadius.circular(7),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 15, color: Color(0xFFAB9DB9)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _commonSearch = val),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF60536E),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Filter tags...',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFAB9DB9),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_commonSearch.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _commonSearch = ''),
                      child: const Icon(
                        Icons.clear,
                        size: 13,
                        color: Color(0xFFAB9DB9),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No matching tags found',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
          )
        else
          ...filtered.map((e) => _buildTagRow(e.key, e.value.$1, e.value.$2)),
      ],
    );
  }

  // ==========================================
  // Tab 3: Media Details
  // ==========================================
  Widget _buildMediaDetailsTab(AnalyzedFile file, AudioMetadata metadata) {
    final format = metadata.format;
    final chapters = format.chapters ?? [];
    final tracks = format.trackInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Container & Stream Specs',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 12),
        _buildTagRow('Container Format', 'container', format.container),
        _buildTagRow('Audio Codec', 'codec', format.codec),
        _buildTagRow('Codec Profile', 'codecProfile', format.codecProfile),
        _buildTagRow('Bitrate', 'bitrate', '${format.bitrate} bps'),
        _buildTagRow('Sample Rate', 'sampleRate', '${format.sampleRate} Hz'),
        _buildTagRow(
          'Bits Per Sample',
          'bitsPerSample',
          format.bitsPerSample?.toString(),
        ),
        _buildTagRow(
          'Channels',
          'numberOfChannels',
          format.numberOfChannels?.toString(),
        ),
        _buildTagRow(
          'Duration',
          'duration',
          '${format.duration?.toStringAsFixed(3)} s',
        ),
        _buildTagRow('Lossless', 'lossless', format.lossless?.toString()),
        _buildTagRow('Tool / Encoder', 'tool', format.tool),
        _buildTagRow(
          'Tag Types Detected',
          'tagTypes',
          format.tagTypes.join(', '),
        ),

        // Tracks/Streams
        if (tracks.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Streams & Tracks (${tracks.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          ...tracks.map((t) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.playerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.playerBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.audiotrack,
                    size: 16,
                    color: AppTheme.primaryPurple,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Track #${t.id ?? '?'}: ${t.type ?? 'Audio'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const Spacer(),
                  if (t.codecName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE0DAEB)),
                      ),
                      child: Text(
                        t.codecName!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.primaryPurple,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],

        // Custom Range Slicing & Download
        const SizedBox(height: 24),
        _buildCustomRangeDownloadBox(file, format),

        // Chapters
        if (chapters.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Chapters (${chapters.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          ...chapters.map((ch) {
            final startSec = ch.start / 1000.0;
            final endMs =
                ch.end ??
                (format.duration != null
                    ? (format.duration! * 1000).round()
                    : (ch.start + 180000));
            final endSec = ch.end != null ? ch.end! / 1000.0 : null;
            final sizeBytes = (ch.byteOffset != null && ch.endByteOffset != null)
                ? ch.endByteOffset! - ch.byteOffset!
                : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  Text(
                    endSec != null
                        ? '${_formatSeconds(startSec)} - ${_formatSeconds(endSec)}'
                        : _formatSeconds(startSec),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryPurple,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      ch.title.isNotEmpty ? ch.title : 'Chapter',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  if (sizeBytes != null && sizeBytes >= 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatFileSize(sizeBytes),
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _isExtractingChapter
                        ? null
                        : () => _downloadChapterFromWeb(
                              file,
                              ch.start,
                              endMs,
                              title: ch.title,
                            ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryPurple,
                      side: const BorderSide(color: AppTheme.purpleBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 13),
                    label: Text(
                      _isExtractingChapter ? 'Preparing...' : 'Download',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  // ==========================================
  // Tab 4: Artwork
  // ==========================================
  Widget _buildArtworkTab(AudioMetadata metadata) {
    final pictures = metadata.common.picture ?? [];

    if (pictures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 36,
                color: Color(0xFFB7B2C5),
              ),
              SizedBox(height: 10),
              Text(
                'No embedded artwork found in this audio file',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Embedded Pictures (${pictures.length})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: pictures.asMap().entries.map((entry) {
            final idx = entry.key;
            final pic = entry.value;
            final mime = pic.format;
            final type = pic.type ?? 'Cover (Front)';

            return Container(
              width: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image preview
                  Container(
                    height: 180,
                    color: const Color(0xFFF3F0FB),
                    child: Image.memory(
                      Uint8List.fromList(pic.data),
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Details
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$mime · ${_formatFileSize(pic.data.length)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Download button
                        OutlinedButton.icon(
                          onPressed: () {
                            final ext = mime.contains('png') ? 'png' : 'jpg';
                            final name = 'cover_$idx.$ext';
                            WebPlatformHelper.instance.downloadFile(
                              pic.data,
                              name,
                              mime,
                            );
                          },
                          icon: const Icon(Icons.download, size: 12),
                          label: const Text(
                            'Download Image',
                            style: TextStyle(fontSize: 10),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryPurple,
                            side: const BorderSide(
                              color: AppTheme.purpleBorder,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ==========================================
  // Tab 5: Native Tags
  // ==========================================
  Widget _buildNativeTagsTab(AudioMetadata metadata) {
    final nativeMap = metadata.native;

    if (nativeMap.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No native tag dictionary present in this audio file',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Heading & Filter
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Native Tags',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${nativeMap.keys.length} formats detected',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Search
            Container(
              width: 180,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE8E4EE)),
                borderRadius: BorderRadius.circular(7),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Color(0xFFAB9DB9)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _nativeSearch = val),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF60536E),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Filter native tags...',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFAB9DB9),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...nativeMap.entries.map((entry) {
          final formatName = entry.key;
          final tags = entry.value;

          final matching = tags.where((tag) {
            if (_nativeSearch.isEmpty) return true;
            final query = _nativeSearch.toLowerCase();
            return tag.id.toLowerCase().contains(query) ||
                tag.value.toString().toLowerCase().contains(query);
          }).toList();

          if (matching.isEmpty) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9F8FB),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    border: Border(bottom: BorderSide(color: AppTheme.divider)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        formatName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryPurple,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.purpleBadge,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${matching.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8E80AC),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: matching.map((t) {
                      final valStr = t.value is List
                          ? (t.value as List).join(', ')
                          : t.value.toString();
                      return _buildTagRow(t.id, t.id, valStr);
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // Tab 6: Raw JSON
  // ==========================================
  Widget _buildRawJsonTab(AnalyzedFile file) {
    if (file.metadata == null) return const SizedBox.shrink();

    final jsonMap = audioMetadataToJson(file.metadata!);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Raw JSON Tree',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _copyToClipboard(jsonStr, 'Raw JSON'),
              icon: const Icon(Icons.copy, size: 12),
              label: const Text('Copy JSON', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: Color(0xFFE9E4F0)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _downloadJson(file),
              icon: const Icon(Icons.download, size: 12),
              label: const Text(
                'Download .json',
                style: TextStyle(fontSize: 11),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFBFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEAE8EE)),
          ),
          child: SelectableText(
            jsonStr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF332D41),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Helper: 2-column Tag Row matching reference
  // ==========================================
  Widget _buildTagRow(String label, String key, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.rowDivider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Label + Code key
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF756780),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  key,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Color(0xFF84738F),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: Value + Copy button
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xFF51465E),
                height: 1.4,
              ),
            ),
          ),
          InkWell(
            onTap: () => _copyToClipboard(value, label),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, size: 13, color: Color(0xFFAEA7BC)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Footer matching reference
  // ==========================================
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8E7EE))),
      ),
      child: Row(
        children: [
          const Text(
            'Powered by metadata_audio · Pure Dart',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF9992A6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () => WebPlatformHelper.instance.openUrl(
              'https://pub.dev/packages/metadata_audio',
            ),
            child: const Text(
              'pub.dev package',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.primaryPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Formatting helpers
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatSeconds(double seconds) {
    final dur = Duration(seconds: seconds.round());
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
