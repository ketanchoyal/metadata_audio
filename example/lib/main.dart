import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:metadata_audio/metadata_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Metadata Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MetadataViewerPage(),
    );
  }
}

class MetadataViewerPage extends StatefulWidget {
  const MetadataViewerPage({super.key});

  @override
  State<MetadataViewerPage> createState() => _MetadataViewerPageState();
}

class _MetadataViewerPageState extends State<MetadataViewerPage> {
  final TextEditingController _urlController = TextEditingController();

  AudioMetadata? _metadata;
  bool _isLoading = false;
  String _errorMessage = '';

  void _observeMetadata(MetadataEvent event) {
    setState(() {
      _metadata = event.metadata;
    });
  }

  Future<void> _parseUrl(String url) async {
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _metadata = null;
    });

    try {
      final metadata = await parseUrl(
        url,
        options: ParseOptions(
          includeChapters: true,
          observer: _observeMetadata,
        ),
      );
      setState(() {
        _metadata = metadata;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndParseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb, // Get bytes on web
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
          _metadata = null;
        });

        final file = result.files.first;
        AudioMetadata metadata;

        if (kIsWeb) {
          metadata = await parseBytes(
            file.bytes!,
            fileInfo: FileInfo(mimeType: 'audio/${file.extension}', path: file.name),
            options: ParseOptions(
              includeChapters: true,
              observer: _observeMetadata,
            ),
          );
        } else {
          metadata = await parseFile(
            file.path!,
            options: ParseOptions(
              includeChapters: true,
              observer: _observeMetadata,
            ),
          );
        }

        setState(() {
          _metadata = metadata;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Metadata Parser'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Audio URL',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _parseUrl,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _parseUrl(_urlController.text),
                  child: const Text('Parse URL'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _pickAndParseFile,
                  child: const Text('Pick File'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) const LinearProgressIndicator(),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(
              child: _metadata == null
                  ? const Center(child: Text('No metadata loaded'))
                  : _buildMetadataView(_metadata!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataView(AudioMetadata metadata) {
    return ListView(
      children: [
        _buildSectionHeader('Common Metadata'),
        _buildCommonSection(metadata.common),
        const Divider(),
        _buildSectionHeader('Format Information'),
        _buildFormatSection(metadata.format),
        if (metadata.format.chapters != null && metadata.format.chapters!.isNotEmpty) ...[
          const Divider(),
          _buildSectionHeader('Chapters (${metadata.format.chapters!.length})'),
          _buildChaptersSection(metadata.format.chapters!),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildCommonSection(CommonTags common) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (common.picture != null && common.picture!.isNotEmpty)
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 200,
              child: Image.memory(
                Uint8List.fromList(common.picture!.first.data),
                fit: BoxFit.contain,
              ),
            ),
          ),
        _buildInfoRow('Title', common.title),
        _buildInfoRow('Artist', common.artist),
        _buildInfoRow('Album', common.album),
        _buildInfoRow('Year', common.year?.toString()),
        _buildInfoRow('Track', '${common.track.no ?? ''} / ${common.track.of ?? ''}'),
        _buildInfoRow('Disk', '${common.disk.no ?? ''} / ${common.disk.of ?? ''}'),
        _buildInfoRow('Genre', common.genre?.join(', ')),
      ],
    );
  }

  Widget _buildFormatSection(Format format) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Container', format.container),
        _buildInfoRow('Codec', format.codec),
        _buildInfoRow('Bitrate', format.bitrate != null ? '${(format.bitrate! / 1000).toStringAsFixed(1)} kbps' : null),
        _buildInfoRow('Sample Rate', format.sampleRate != null ? '${format.sampleRate} Hz' : null),
        _buildInfoRow('Duration', format.duration != null ? _formatDuration(format.duration!) : null),
        _buildInfoRow('Lossless', format.lossless?.toString()),
      ],
    );
  }

  Widget _buildChaptersSection(List<Chapter> chapters) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final start = _formatDuration(chapter.start / 1000);
        final end = chapter.end != null ? ' - ${_formatDuration(chapter.end! / 1000)}' : '';
        return ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(chapter.title),
          subtitle: Text('$start$end'),
        );
      },
    );
  }

  String _formatDuration(double seconds) {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    final minutes = duration.inMinutes;
    final remainingSeconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.isEmpty || value == ' / ') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
