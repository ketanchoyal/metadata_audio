import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:metadata_audio/metadata_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Metadata Parser',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.dark,
          background: const Color(0xFF0F172A), // Slate 900
          surface: const Color(0xFF1E293B), // Slate 800
          primary: const Color(0xFF818CF8), // Indigo 400
          secondary: const Color(0xFF38BDF8), // Sky 400
          tertiary: const Color(0xFF34D399), // Emerald 400
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1), // Slate 700
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _urlController = TextEditingController(
    text: 'https://archive.org/download/city_of_fire_2209_librivox/CityFire_librivox.m4b',
  );

  // Parse Options
  bool _includeChapters = true;
  bool _duration = true;
  bool _skipCovers = false;
  bool _skipPostHeaders = false;

  // Custom HTTP Parsing Strategies
  ParseStrategy? _forcedParseStrategy;
  ProbeStrategy? _forcedProbeStrategy;

  // State
  bool _isLoading = false;
  String? _loadingStatus;
  String? _errorMessage;
  AudioMetadata? _metadata;
  String? _parsedSource;
  String? _strategyReason;
  ParseStrategy? _selectedStrategy;



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _parseLocalFile() async {
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Selecting file...';
      _errorMessage = null;
      _metadata = null;
      _parsedSource = null;
      _strategyReason = null;
      _selectedStrategy = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'flac', 'ogg', 'oga', 'opus', 'wav', 'wave', 'aiff', 'aif',
          'ape', 'asf', 'wma', 'mkv', 'mka', 'webm', 'mpc', 'wv', 'dsf', 'dff',
          'm4a', 'm4b', 'm4p', 'm4r', 'mp4', 'aac'
        ],
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final path = result.files.single.path!;
      setState(() {
        _loadingStatus = 'Parsing local file: ${path.split('/').last}...';
      });

      final options = ParseOptions(
        includeChapters: _includeChapters,
        duration: _duration,
        skipCovers: _skipCovers,
        skipPostHeaders: _skipPostHeaders,
      );

      final metadata = await parseFile(path, options: options);

      setState(() {
        _metadata = metadata;
        _parsedSource = path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to parse file: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _parseRemoteUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a valid URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = 'Connecting to remote server...';
      _errorMessage = null;
      _metadata = null;
      _parsedSource = null;
      _strategyReason = null;
      _selectedStrategy = null;
    });

    try {
      final options = ParseOptions(
        includeChapters: _includeChapters,
        duration: _duration,
        skipCovers: _skipCovers,
        skipPostHeaders: _skipPostHeaders,
      );

      final metadata = await parseUrl(
        url,
        options: options,
        strategy: _forcedParseStrategy,
        probeStrategy: _forcedProbeStrategy,
        onStrategySelected: (strategy, reason) {
          setState(() {
            _selectedStrategy = strategy;
            _strategyReason = _formatStrategyReason(reason);
            _loadingStatus = 'Parsing with strategy: ${strategy.name}...';
          });
        },
      );

      setState(() {
        _metadata = metadata;
        _parsedSource = url;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to parse URL: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _testPartialDownload(Chapter chapter) async {
    final url = _parsedSource;
    if (url == null || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partial downloads require a parsed remote URL source.')),
      );
      return;
    }

    final cleanTitle = chapter.title.replaceAll(RegExp(r'[^\w\-\.]'), '_');
    final defaultFileName = 'chapter_${cleanTitle}_${chapter.start}.aac';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save partial chapter download to:',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['aac'],
    );

    if (savePath == null) {
      // User cancelled
      return;
    }

    // Notifiers for download tracking
    final progressNotifier = ValueNotifier<double>(0.0);
    final phaseNotifier = ValueNotifier<ChapterDownloadPhase>(
      ChapterDownloadPhase.connecting,
    );

    String _phaseLabel(ChapterDownloadPhase phase) {
      switch (phase) {
        case ChapterDownloadPhase.connecting:
          return 'Connecting to source...';
        case ChapterDownloadPhase.analyzing:
          return 'Analyzing audio structure...';
        case ChapterDownloadPhase.resolvingSamples:
          return 'Resolving chapter samples...';
        case ChapterDownloadPhase.downloading:
          return 'Downloading chapter audio...';
        case ChapterDownloadPhase.writing:
          return 'Writing playable AAC file...';
      }
    }

    // Show Progress Dialog with phase-aware indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Extracting AAC Chapter: ${chapter.title}'),
          content: SizedBox(
            width: 320,
            child: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) {
                final isDownloading = progress > 0;
                final pct = (progress * 100).clamp(0, 100).toStringAsFixed(1);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: isDownloading ? progress.clamp(0.0, 1.0) : null,
                    ),
                    const SizedBox(height: 12),
                    if (isDownloading)
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<ChapterDownloadPhase>(
                      valueListenable: phaseNotifier,
                      builder: (context, phase, _) {
                        return Text(
                          _phaseLabel(phase),
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final endMs = chapter.end ?? 
        (_metadata?.format.duration != null 
            ? (_metadata!.format.duration! * 1000).toInt() 
            : (chapter.start + 180000));

    final result = await ChapterDownloader.downloadChapter(
      originalUrl: url,
      chapterStartMs: chapter.start,
      chapterEndMs: endMs,
      outputPath: savePath,
      onProgress: (progress) {
        progressNotifier.value = progress;
      },
      onPhase: (phase) {
        phaseNotifier.value = phase;
      },
    );

    if (Navigator.canPop(context)) {
      Navigator.of(context).pop(); // Dismiss progress dialog
    }
    progressNotifier.dispose();
    phaseNotifier.dispose();

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playable chapter downloaded successfully to:\n${result.outputPath}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: ${result.error}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar (Controls & Config)
          Container(
            width: 380,
            decoration: const BoxDecoration(
              color: Color(0xFF0B0F19), // Darker slate sidebar
              border: Border(right: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Logo
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.audiotrack_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Metadata Audio',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Dart-Native Parser',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Navigation Tabs (Local vs Remote)
                    TabBar(
                      controller: _tabController,
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [
                        Tab(text: 'Local File', icon: Icon(Icons.file_open_rounded, size: 20)),
                        Tab(text: 'Remote URL', icon: Icon(Icons.cloud_rounded, size: 20)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tab Views
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          // Local file tab content
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Extract metadata from local audio files. Supports MP3, FLAC, M4A, WAV, OGG, AIFF, MKV, DSF, and more.',
                                style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _isLoading ? null : _parseLocalFile,
                                icon: const Icon(Icons.search_rounded),
                                label: const Text('Browse Audio File', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const Spacer(),
                            ],
                          ),

                          // Remote URL tab content
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Test range-aware stream parsing from direct audio URLs. Ideal for streaming M4B audiobooks.',
                                  style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _urlController,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    labelText: 'Audio File URL',
                                    alignLabelWithHint: true,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Force strategy selector
                                const Text(
                                  'HTTP Parse Strategy',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigoAccent),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<ParseStrategy?>(
                                  value: _forcedParseStrategy,
                                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Auto-detect (Recommended)')),
                                    ...ParseStrategy.values.map(
                                      (s) => DropdownMenuItem(value: s, child: Text(s.name)),
                                    )
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _forcedParseStrategy = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Override Probe Strategy',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigoAccent),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<ProbeStrategy?>(
                                  value: _forcedProbeStrategy,
                                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Auto-detect from format')),
                                    ...ProbeStrategy.values.map(
                                      (s) => DropdownMenuItem(value: s, child: Text(s.name)),
                                    )
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _forcedProbeStrategy = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isLoading ? null : _parseRemoteUrl,
                                  icon: const Icon(Icons.cloud_download_rounded),
                                  label: const Text('Parse Remote URL', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: Color(0xFF1E293B), height: 32),

                    // Options Configuration Panel
                    const Text(
                      'Parser Configurations',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    _buildSwitchTile('Extract Chapters', _includeChapters, (val) => setState(() => _includeChapters = val)),
                    _buildSwitchTile('Calculate Duration', _duration, (val) => setState(() => _duration = val)),
                    _buildSwitchTile('Skip Cover Images', _skipCovers, (val) => setState(() => _skipCovers = val)),
                    _buildSwitchTile('Skip Post Headers', _skipPostHeaders, (val) => setState(() => _skipPostHeaders = val)),
                  ],
                ),
              ),
            ),
          ),

          // Right Content Pane (Results display)
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A), // Slate 900
              child: SafeArea(
                child: _buildMainContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 24),
            Text(
              _loadingStatus ?? 'Parsing audio data...',
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF451A21), // Slate-red background
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text('Parsing Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              SelectableText(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
      );
    }

    final metadata = _metadata;
    if (metadata == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_rounded, size: 72, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            const Text(
              'No Audio Selected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a local file or pass a remote URL in the left panel to begin.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL Strategy Selection Info
          if (_selectedStrategy != null) ...[
            _buildStrategyCard(),
            const SizedBox(height: 24),
          ],

          // Album Art & Quick Details
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Art Card
              _buildCoverArt(metadata),
              const SizedBox(width: 32),

              // Title, Artist, Album, etc.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      metadata.common.title ?? 'Unknown Track',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      metadata.common.artist ?? 'Unknown Artist',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _buildTagChips(metadata),
                    const SizedBox(height: 20),
                    _buildSpecsGrid(metadata),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Chapters Section
          if (_includeChapters) ...[
            _buildChaptersCard(metadata),
            const SizedBox(height: 32),
          ],

          // Quality Warnings
          if (metadata.quality.warnings.isNotEmpty) ...[
            _buildWarningsCard(metadata),
            const SizedBox(height: 32),
          ],

          // Native Tags Card
          _buildNativeTagsCard(metadata),
        ],
      ),
    );
  }

  Widget _buildStrategyCard() {
    return Card(
      color: const Color(0xFF1E1B4B), // Indigo-950
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF4338CA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.yellow, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HTTP Streaming Strategy Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    _strategyReason ?? 'Automatic heuristic evaluation',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF312E81),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF4338CA)),
              ),
              child: Text(
                _selectedStrategy?.name.toUpperCase() ?? '',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCoverArt(AudioMetadata metadata) {
    final pictures = metadata.common.picture;
    final cover = selectCover(pictures);

    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: cover != null
            ? Image.memory(
                Uint8List.fromList(cover.data),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholderIcon(),
              )
            : _buildPlaceholderIcon(),
      ),
    );
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 72, color: Colors.white),
      ),
    );
  }

  Widget _buildTagChips(AudioMetadata metadata) {
    final chips = <Widget>[];

    if (metadata.common.album != null) {
      chips.add(_buildChip(Icons.album_rounded, metadata.common.album!));
    }
    if (metadata.common.genre != null && metadata.common.genre!.isNotEmpty) {
      chips.add(_buildChip(Icons.style_rounded, metadata.common.genre!.join(', ')));
    }
    if (metadata.common.year != null) {
      chips.add(_buildChip(Icons.calendar_today_rounded, metadata.common.year!.toString()));
    }
    if (metadata.common.track.no != null) {
      final total = metadata.common.track.of;
      chips.add(_buildChip(Icons.tag_rounded, 'Track ${metadata.common.track.no}${total != null ? "/$total" : ""}'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.indigoAccent.shade100),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsGrid(AudioMetadata metadata) {
    final durationText = metadata.format.duration != null
        ? _formatDuration(metadata.format.duration!)
        : 'Unknown';

    final specs = [
      {'label': 'Container', 'value': metadata.format.container?.toUpperCase() ?? 'Unknown'},
      {'label': 'Codec', 'value': metadata.format.codec?.toUpperCase() ?? 'Unknown'},
      {'label': 'Duration', 'value': durationText},
      {
        'label': 'Bitrate',
        'value': metadata.format.bitrate != null
            ? '${(metadata.format.bitrate! / 1000).toStringAsFixed(0)} kbps'
            : 'Unknown'
      },
      {
        'label': 'Sample Rate',
        'value': metadata.format.sampleRate != null
            ? '${(metadata.format.sampleRate! / 1000).toStringAsFixed(1)} kHz'
            : 'Unknown'
      },
      {
        'label': 'Bit Depth',
        'value': metadata.format.bitsPerSample != null
            ? '${metadata.format.bitsPerSample} bit'
            : 'Unknown'
      },
      {'label': 'Channels', 'value': metadata.format.numberOfChannels?.toString() ?? 'Unknown'},
      {'label': 'Lossless', 'value': metadata.format.lossless == true ? 'Yes' : 'No'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 76,
      ),
      itemCount: specs.length,
      itemBuilder: (context, index) {
        final spec = specs[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                spec['label']!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                spec['value']!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChaptersCard(AudioMetadata metadata) {
    final chapters = metadata.format.chapters;
    if (chapters == null || chapters.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.toc_rounded, size: 48, color: Colors.grey.shade700),
              const SizedBox(height: 12),
              const Text('No Chapters Found', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('This file does not contain chapter markers.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final isRemote = _parsedSource?.startsWith('http') ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapters & Byte Offsets (${chapters.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Shows specific positions in the file. Test downloading partial byte ranges.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                if (isRemote)
                  Chip(
                    backgroundColor: Colors.indigo.withOpacity(0.3),
                    side: const BorderSide(color: Colors.indigo),
                    label: const Text('Range Request Ready', style: TextStyle(fontSize: 11, color: Colors.indigoAccent)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155)),
              itemBuilder: (context, index) {
                final ch = chapters[index];
                final startTime = _formatDurationMs(ch.start);
                final endTime = ch.end != null ? _formatDurationMs(ch.end!) : 'End';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      // Chapter Number
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Title & Time Range
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.title.trim().isNotEmpty ? ch.title : 'Chapter ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.copy_rounded, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    final sec = (ch.start / 1000).toStringAsFixed(3);
                                    Clipboard.setData(ClipboardData(text: sec));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Copied start: $sec seconds'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      startTime,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigoAccent.shade100,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                const Text(' - ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                InkWell(
                                  onTap: ch.end == null ? null : () {
                                    final sec = (ch.end! / 1000).toStringAsFixed(3);
                                    Clipboard.setData(ClipboardData(text: sec));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Copied end: $sec seconds'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      endTime,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ch.end != null ? Colors.indigoAccent.shade100 : Colors.grey,
                                        decoration: ch.end != null ? TextDecoration.underline : TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (ch.end != null) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () {
                                  final durationSec = ((ch.end! - ch.start) / 1000).toStringAsFixed(3);
                                  Clipboard.setData(ClipboardData(text: durationSec));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Copied duration: $durationSec seconds'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Text(
                                    'Duration: ${((ch.end! - ch.start) / 1000).toStringAsFixed(3)}s',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Byte Offsets & Size Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Size: ${_getChapterPossibleSize(ch, metadata)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: ch.byteOffset == null ? null : () {
                              Clipboard.setData(ClipboardData(text: ch.byteOffset!.toString()));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied start offset: ${ch.byteOffset}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                ch.byteOffset != null
                                    ? 'Start: ${ch.byteOffset} B'
                                    : 'Start Offset: N/A',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: ch.byteOffset != null ? Colors.indigoAccent.shade100 : Colors.grey,
                                  decoration: ch.byteOffset != null ? TextDecoration.underline : TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: ch.endByteOffset == null ? null : () {
                              Clipboard.setData(ClipboardData(text: ch.endByteOffset!.toString()));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied end offset: ${ch.endByteOffset}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                ch.endByteOffset != null
                                    ? 'End: ${ch.endByteOffset} B'
                                    : 'End Offset: N/A',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: ch.endByteOffset != null ? Colors.indigoAccent.shade100 : Colors.grey,
                                  decoration: ch.endByteOffset != null ? TextDecoration.underline : TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),

                      // Actions Column (Download & FFmpeg Command)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isRemote) ...[
                            ElevatedButton.icon(
                              onPressed: ch.byteOffset == null ? null : () => _testPartialDownload(ch),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF334155)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.download_rounded, size: 14),
                              label: const Text('Download', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 6),
                          ],
                          OutlinedButton.icon(
                            onPressed: () {
                              final startSec = (ch.start / 1000).toStringAsFixed(3);
                              final endSec = ch.end != null
                                  ? (ch.end! / 1000).toStringAsFixed(3)
                                  : null;
                              final cleanTitle = ch.title.trim().isNotEmpty
                                  ? ch.title.replaceAll(RegExp(r'[^\w\-\.]'), '_')
                                  : 'chapter_${index + 1}';
                              final ext = _parsedSource?.split('?').first.split('.').lastOrNull ?? 'm4b';

                              final toPart = endSec != null ? ' -to $endSec' : '';
                              final sourceStr = _parsedSource ?? 'input.$ext';
                              final cmd = 'ffmpeg -ss $startSec$toPart -i "$sourceStr" -c copy "${cleanTitle}.$ext"';

                              Clipboard.setData(ClipboardData(text: cmd));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied FFmpeg command for "${ch.title}"!'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF334155)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.terminal_rounded, size: 14),
                            label: const Text('Copy FFmpeg', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsCard(AudioMetadata metadata) {
    return Card(
      color: const Color(0xFF2D1E12), // Warning orange tint
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Parser Warnings (${metadata.quality.warnings.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metadata.quality.warnings.length,
              itemBuilder: (context, index) {
                final w = metadata.quality.warnings[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    '• ${w.message}',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                  ),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNativeTagsCard(AudioMetadata metadata) {
    final nativeTypes = metadata.native.keys.toList();
    if (nativeTypes.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raw Native Tags',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Format-specific tags found inside the audio file.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: nativeTypes.length,
              itemBuilder: (context, index) {
                final type = nativeTypes[index];
                final tagsList = metadata.native[type] ?? [];

                return ExpansionTile(
                  title: Text(
                    '${type.toUpperCase()} tags (${tagsList.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  textColor: Theme.of(context).colorScheme.primary,
                  iconColor: Theme.of(context).colorScheme.primary,
                  childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: tagsList.map((tag) {
                    final valueString = tag.value is List
                        ? '[Binary Data: ${(tag.value as List).length} bytes]'
                        : tag.value.toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 140,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: SelectableText(
                              tag.id,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: SelectableText(
                                valueString,
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    } else {
      return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
  }

  String _formatDurationMs(int milliseconds) {
    final s = milliseconds ~/ 1000;
    final ms = milliseconds % 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;

    final base = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

    return '$base.${ms.toString().padLeft(3, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final value = bytes / pow(1024, i);
    return '${value.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatStrategyReason(String reason) {
    final regex = RegExp(r'File size:\s*(\d+)KB');
    final match = regex.firstMatch(reason);
    if (match != null) {
      final kbStr = match.group(1);
      if (kbStr != null) {
        final kb = int.tryParse(kbStr);
        if (kb != null) {
          final bytes = kb * 1024;
          final formattedSize = _formatBytes(bytes);
          return reason.replaceFirst(regex, 'File size: $formattedSize');
        }
      }
    }
    return reason;
  }

  String _getChapterPossibleSize(Chapter ch, AudioMetadata metadata) {
    if (ch.byteOffset != null && ch.endByteOffset != null) {
      final size = ch.endByteOffset! - ch.byteOffset!;
      return _formatBytes(size);
    }

    // Estimate size using duration and average bitrate
    final endVal = ch.end ?? (metadata.format.duration != null ? (metadata.format.duration! * 1000).round() : ch.start);
    final durationMs = endVal - ch.start;
    final durationSec = durationMs / 1000.0;
    final bitrate = metadata.format.bitrate; // in bps

    if (bitrate != null && bitrate > 0) {
      final estimatedBytes = (durationSec * bitrate) / 8.0;
      return '~${_formatBytes(estimatedBytes.round())} (Est.)';
    }

    return 'Unknown';
  }
}
