import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:youtube_explode_dart_alpha/youtube_explode_dart_alpha.dart';

class DownloadManager {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final int maxConcurrent = 5;
  int _active = 0;
  final Queue<Future<void> Function()> _queue =
      Queue<Future<void> Function()>();

  void enqueue(Future<void> Function() downloadFunc) {
    _queue.add(downloadFunc);
    _processQueue();
  }

  void _processQueue() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      _active++;
      final func = _queue.removeFirst();
      func().whenComplete(() {
        _active--;
        _processQueue();
      });
    }
  }
}

class DownloadTask {
  final String taskId;
  final StreamController<double> progressCtrl =
      StreamController<double>.broadcast();
  Stream<double> get progressStream => progressCtrl.stream;

  DownloadTask(this.taskId);

  void updateProgress(double p) {
    if (!progressCtrl.isClosed) {
      progressCtrl.add(p.clamp(0.0, 1.0));
    }
  }

  void closeProgress() {
    if (!progressCtrl.isClosed) {
      progressCtrl.close();
    }
  }
}

/// Sanitizes filename by removing invalid characters
String sanitizeFilename(String input) {
  return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
}

/// Class to hold video info
class VideoInfoData {
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnail;
  final String url;
  final int? videoCount;

  VideoInfoData({
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnail,
    required this.url,
    this.videoCount,
  });
}

/// Downloads the highest-quality audio from a YouTube URL to [outputPath]
/// Calls onProgress with a value between 0.0 and 1.0.
Future<void> downloadYoutubeAudio(
  String videoUrl,
  String outputPath, {
  required void Function(double percent) onProgress,
}) async {
  final yt = YoutubeExplode();

  try {
    final video = await yt.videos.get(videoUrl);

    final manifest = await yt.videos.streams.getManifest(
      videoUrl,
      ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
    );

    final audio = manifest.audioOnly.withHighestBitrate();
    if (audio == null) {
      throw Exception('No audio stream found for this video.');
    }

    final file = File(outputPath);
    await file.create(recursive: true);
    final fileStream = file.openWrite();

    final stream = yt.videos.streams.get(audio);
    final totalBytes = audio.size.totalBytes ?? 0;
    int downloaded = 0;

    await for (final chunk in stream) {
      fileStream.add(chunk);
      downloaded += chunk.length;
      if (totalBytes > 0) {
        final progress = downloaded / totalBytes;
        onProgress(progress.clamp(0.0, 1.0));
      } else {
        final heuristic = (downloaded % 1000000) / 1000000;
        onProgress(heuristic.clamp(0.0, 0.95));
      }
    }

    await fileStream.flush();
    await fileStream.close();
    onProgress(1.0);
  } catch (e) {
    rethrow;
  } finally {
    yt.close();
  }
}

/// Fetch video info and return as VideoInfoData
Future<VideoInfoData> fetchVideoInfo(String videoUrl) async {
  final yt = YoutubeExplode();
  try {
    final video = await yt.videos.get(videoUrl);
    return VideoInfoData(
      title: video.title,
      author: video.author,
      duration: video.duration,
      thumbnail: video.thumbnails.standardResUrl,
      url: videoUrl,
    );
  } finally {
    yt.close();
  }
}

/// Fetch playlist info and return as VideoInfoData with first video thumbnail if possible
Future<VideoInfoData> fetchPlaylistInfo(String playlistUrl) async {
  final yt = YoutubeExplode();
  try {
    final playlist = await yt.playlists.get(playlistUrl);
    String thumbnail = playlist.thumbnails.standardResUrl;
    try {
      final firstVideo = await yt.playlists.getVideos(playlist.id).first;
      final firstThumb = firstVideo.thumbnails.standardResUrl;
      if (firstThumb.isNotEmpty) thumbnail = firstThumb;
    } catch (_) {}
    return VideoInfoData(
      title: playlist.title,
      author: playlist.author,
      thumbnail: thumbnail,
      url: playlistUrl,
      videoCount: playlist.videoCount,
    );
  } finally {
    yt.close();
  }
}

/// Check if the URL is a playlist
Future<bool> isPlaylistUrl(String url) async {
  final yt = YoutubeExplode();
  try {
    await yt.playlists.get(url);
    return true;
  } catch (e) {
    return false;
  } finally {
    yt.close();
  }
}

/// Fetch all videos in a playlist
Future<List<VideoInfoData>> fetchPlaylistVideos(String playlistUrl) async {
  final yt = YoutubeExplode();
  try {
    final playlist = await yt.playlists.get(playlistUrl);
    final videos = <VideoInfoData>[];
    await for (final video in yt.playlists.getVideos(playlist.id)) {
      videos.add(VideoInfoData(
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnail: video.thumbnails.standardResUrl,
        url: video.url,
      ));
    }
    return videos;
  } finally {
    yt.close();
  }
}
