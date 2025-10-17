import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ytb.dart';

String formatDuration(dynamic raw) {
  if (raw == null) return "Unknown";
  try {
    Duration d;
    if (raw is Duration) {
      d = raw;
    } else if (raw is String) {
      final parts = raw.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = double.parse(parts[2]).floor();
        d = Duration(hours: hours, minutes: minutes, seconds: seconds);
      } else {
        return raw;
      }
    } else {
      return raw.toString();
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  } catch (_) {
    return raw.toString();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyAppRoot());
}

class MyAppRoot extends StatelessWidget {
  const MyAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: const CupertinoApp(
        debugShowCheckedModeBanner: false,
        home: MyApp(),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _permissionGranted = false;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionOnStart();
  }

  Future<void> _requestPermissionOnStart() async {
    PermissionStatus status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    setState(() => _permissionGranted = status.isGranted);
  }

  void _toggleDarkMode(bool value) {
    setState(() => _darkMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: _darkMode ? Brightness.dark : Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
      ),
      home: _permissionGranted
          ? YtbDownloader(
              darkMode: _darkMode,
              toggleDarkMode: _toggleDarkMode,
            )
          : CupertinoPageScaffold(
              child: Center(
                child: Text(
                  'Storage permission required to save files in Downloads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                  ),
                ),
              ),
            ),
    );
  }
}

class YtbDownloader extends StatefulWidget {
  final bool darkMode;
  final Function(bool) toggleDarkMode;
  const YtbDownloader({
    super.key,
    required this.darkMode,
    required this.toggleDarkMode,
  });

  @override
  State<YtbDownloader> createState() => _YtbDownloaderState();
}

class _YtbDownloaderState extends State<YtbDownloader> {
  final TextEditingController _urlController = TextEditingController();
  final List<DownloadCard> _downloads = [];
  bool _fetching = false;
  final FocusNode _urlFocusNode = FocusNode(); // Add FocusNode
  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose(); // Dispose FocusNode
    super.dispose();
  }

  void _showIOSBanner(String title, String subtitle, {bool isError = false}) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
        return CupertinoAlertDialog(
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              fontSize: 18 * MediaQuery.of(context).textScaleFactor,
            ),
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? CupertinoColors.systemGrey3
                    : CupertinoColors.systemGrey,
                fontSize: 14 * MediaQuery.of(context).textScaleFactor,
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                "OK",
                style: TextStyle(
                  color: isError
                      ? CupertinoColors.systemRed
                      : CupertinoColors.activeBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchInfo() async {
    if (_urlController.text.trim().isEmpty) return;
    setState(() => _fetching = true);
    try {
      final url = _urlController.text.trim();
      final isPlaylist = await isPlaylistUrl(url);
      if (isPlaylist) {
        final info = await fetchPlaylistInfo(url);
        final card = DownloadCard(
          url: url,
          title: info.title,
          author: info.author,
          duration: null,
          thumbnail: info.thumbnail,
          showBanner: _showIOSBanner,
          isPlaylist: true,
          videoCount: info.videoCount,
        );
        setState(() => _downloads.insert(0, card));
        _showIOSBanner("Playlist detected successfully.", "");
        _urlController.clear();
      } else {
        final info = await fetchVideoInfo(url);
        final card = DownloadCard(
          url: url,
          title: info.title,
          author: info.author,
          duration: formatDuration(info.duration),
          thumbnail: info.thumbnail,
          showBanner: _showIOSBanner,
          isPlaylist: false,
        );
        setState(() => _downloads.insert(0, card));
        _showIOSBanner("Download ready", info.title);
        _urlController.clear();
      }
    } catch (e) {
      _showIOSBanner("Error fetching info", e.toString(), isError: true);
    } finally {
      setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = screenWidth * 0.04;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: "YouTube to ",
                style: TextStyle(
                  fontSize: 20 * MediaQuery.of(context).textScaleFactor,
                  fontWeight: FontWeight.bold,
                  color:
                      CupertinoTheme.of(context).brightness == Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                ),
              ),
              TextSpan(
                text: "MP3",
                style: TextStyle(
                  fontSize: 20 * MediaQuery.of(context).textScaleFactor,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.activeBlue,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                showCupertinoDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return CupertinoAlertDialog(
                      title: Text(
                        "Developer Info",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18 * MediaQuery.of(context).textScaleFactor,
                        ),
                      ),
                      content: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          children: [
                            Text(
                              "Developed by Abdallah Driouich",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize:
                                    14 * MediaQuery.of(context).textScaleFactor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () async {
                                final url = Uri.parse(
                                  "https://abdallah.driouich.site/",
                                );
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              child: Text(
                                "https://abdallah.driouich.site",
                                style: TextStyle(
                                  color: CupertinoColors.activeBlue,
                                  fontSize: 14 *
                                      MediaQuery.of(context).textScaleFactor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        CupertinoDialogAction(
                          isDefaultAction: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            "Close",
                            style: TextStyle(
                              fontSize:
                                  16 * MediaQuery.of(context).textScaleFactor,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Icon(
                CupertinoIcons.info_circle,
                size: 26 * MediaQuery.of(context).textScaleFactor,
                color: CupertinoColors.activeBlue,
              ),
            ),
            SizedBox(width: padding),
            CupertinoSwitch(
              value: widget.darkMode,
              onChanged: widget.toggleDarkMode,
              activeColor: CupertinoColors.activeBlue,
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                children: [
                  Flexible(
                    child: CupertinoTextField(
                      controller: _urlController,
                      placeholder: "Enter Video or Playlists URL",
                      focusNode: _urlFocusNode, // Assign FocusNode
                      onTapOutside: (event) {
                        _urlFocusNode.unfocus(); // Unfocus when tapping outside
                      },
                      padding: EdgeInsets.all(padding),
                      clearButtonMode: OverlayVisibilityMode.editing,
                      style: TextStyle(
                        fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                      ),
                    ),
                  ),
                  SizedBox(width: padding),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: screenWidth * 0.15,
                      maxWidth: screenWidth * 0.25,
                    ),
                    child: CupertinoButton.filled(
                      onPressed: _fetching ? null : _fetchInfo,
                      padding: EdgeInsets.symmetric(
                        horizontal: padding * 1.5,
                        vertical: padding,
                      ),
                      child: _fetching
                          ? const CupertinoActivityIndicator()
                          : Icon(
                              CupertinoIcons.arrow_down_circle,
                              size: 24 * MediaQuery.of(context).textScaleFactor,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _downloads.isEmpty
                  ? Center(
                      child: Text(
                        "No downloads yet. Add a URL above.",
                        style: TextStyle(
                          fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(padding),
                      itemCount: _downloads.length,
                      itemBuilder: (_, i) => _downloads[i],
                      shrinkWrap: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadCard extends StatefulWidget {
  final String url;
  final String title;
  final String author;
  final dynamic duration;
  final String thumbnail;
  final void Function(String, String, {bool isError}) showBanner;
  final bool isPlaylist;
  final int? videoCount;

  const DownloadCard({
    super.key,
    required this.url,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnail,
    required this.showBanner,
    this.isPlaylist = false,
    this.videoCount,
  });

  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  bool _downloading = false;
  double _progress = 0.0;
  final Map<String, double> _videoProgress = {};
  int _tasksCompleted = 0;
  int _playlistTotal = 0;
  bool _completedShown = false;

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|$]'), '_');
  }

  void _startDownload() async {
    setState(() {
      _downloading = true;
      _completedShown = false;
      _videoProgress.clear();
      _progress = 0.0;
      _tasksCompleted = 0;
      _playlistTotal = 0;
    });

    widget.showBanner("Download started", widget.title);

    try {
      PermissionStatus status =
          await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        throw "Storage permission denied!";
      }

      final dir = Directory('/storage/emulated/0/Download/MP3tube');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      List<VideoInfoData> videos;
      if (widget.isPlaylist) {
        videos = await fetchPlaylistVideos(widget.url);
      } else {
        videos = [
          VideoInfoData(
            title: widget.title,
            author: widget.author,
            duration: widget.duration is Duration ? widget.duration : null,
            thumbnail: widget.thumbnail,
            url: widget.url,
          )
        ];
      }

      setState(() {
        _playlistTotal = videos.length;
      });

      for (final video in videos) {
        final safeTitle = _sanitizeFilename("${video.title}.mp3");
        final fullPath = '${dir.path}/$safeTitle';
        final task = DownloadTask(video.url);
        _videoProgress[video.url] = 0.0;

        task.progressStream.listen(
          (p) {
            if (mounted) {
              setState(() {
                _videoProgress[video.url] = p;
                final values = _videoProgress.values;
                if (values.isNotEmpty) {
                  _progress = values.reduce((a, b) => a + b) / values.length;
                }
              });
            }
          },
          onError: (e) {
            widget.showBanner(
                "Download failed for ${video.title}", e.toString(),
                isError: true);
          },
          onDone: () {
            if (mounted) {
              setState(() {
                _tasksCompleted++;
                if (_tasksCompleted == _playlistTotal) {
                  _downloading = false;
                  if (!_completedShown) {
                    _completedShown = true;
                    widget.showBanner("Download completed", widget.title);
                  }
                }
              });
            }
          },
        );

        final downloadFunc = () async {
          try {
            await downloadYoutubeAudio(
              video.url,
              fullPath,
              onProgress: (p) => task.updateProgress(p),
            );
            if (Platform.isAndroid) {
              await Process.run('am', [
                'broadcast',
                '-a',
                'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                '-d',
                'file://$fullPath',
              ]);
            }
          } catch (e) {
            task.progressCtrl.addError(e);
            rethrow;
          } finally {
            task.closeProgress();
          }
        };

        DownloadManager.instance.enqueue(downloadFunc);
      }
    } catch (e) {
      setState(() => _downloading = false);
      widget.showBanner("Download failed", e.toString(), isError: true);
    }
  }

  void _download() {
    if (_downloading) return;

    if (widget.isPlaylist) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          final isDark =
              CupertinoTheme.of(context).brightness == Brightness.dark;
          return CupertinoAlertDialog(
            title: Text(
              "Confirm Playlist Download",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                fontSize: 18 * MediaQuery.of(context).textScaleFactor,
              ),
            ),
            content: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                "Start downloading ${widget.title} as MP3?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey3
                      : CupertinoColors.systemGrey,
                  fontSize: 14 * MediaQuery.of(context).textScaleFactor,
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  _startDownload();
                },
                child: Text(
                  "Download Playlist Audio",
                  style: TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                  ),
                ),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "Cancel",
                  style: TextStyle(
                    color: CupertinoColors.systemRed,
                    fontWeight: FontWeight.w600,
                    fontSize: 16 * MediaQuery.of(context).textScaleFactor,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      _startDownload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = screenWidth * 0.03;
    final textScale = MediaQuery.of(context).textScaleFactor;

    return Container(
      margin: EdgeInsets.symmetric(vertical: padding),
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.systemGrey6.darkColor
            : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(padding * 1.5),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? CupertinoColors.black.withOpacity(0.5)
                : CupertinoColors.systemGrey.withOpacity(0.2),
            blurRadius: padding * 1.5,
            offset: Offset(0, padding),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(padding),
                    child: Image.network(
                      widget.thumbnail,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child:
                              CupertinoActivityIndicator(radius: padding * 1.5),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 30 * textScale,
                        ),
                      ),
                    ),
                  ),
                  if (widget.isPlaylist)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          CupertinoIcons.music_note_list,
                          color: CupertinoColors.white,
                          size: 30 * textScale,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: padding),
            Text(
              "Title: ${widget.title}",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                fontSize: 16 * textScale,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "Author: ${widget.author}",
              style: TextStyle(
                color: isDark
                    ? const Color.fromARGB(255, 58, 58, 104)
                    : CupertinoColors.systemGrey,
                fontSize: 14 * textScale,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.isPlaylist)
              Text(
                "Videos: ${widget.videoCount ?? 'Unknown'}",
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey2
                      : CupertinoColors.systemGrey,
                  fontSize: 14 * textScale,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                "Duration: ${formatDuration(widget.duration)}",
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey2
                      : CupertinoColors.systemGrey,
                  fontSize: 14 * textScale,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (widget.isPlaylist && _downloading)
              Text(
                "Playlist Progress: ${(_progress * 100).toStringAsFixed(0)}% ($_tasksCompleted/$_playlistTotal)",
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey2
                      : CupertinoColors.systemGrey,
                  fontSize: 14 * textScale,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: padding),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _downloading ? null : _download,
                padding: EdgeInsets.symmetric(vertical: padding),
                child: _downloading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CupertinoActivityIndicator(radius: padding * 1.5),
                          SizedBox(width: padding),
                          Text(
                            "${(_progress * 100).toStringAsFixed(0)}%",
                            style: TextStyle(
                              fontSize: 16 * textScale,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        widget.isPlaylist
                            ? "Download Playlist Audio"
                            : "Download MP3",
                        style: TextStyle(
                          fontSize: 16 * textScale,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
