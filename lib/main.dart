import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // <-- Added for Video MIME type
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const DubbingApp());
}

class DubbingApp extends StatelessWidget {
  const DubbingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Multi-Engine Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
        ),
      ),
      home: const MultiEngineStudioScreen(),
    );
  }
}

class MultiEngineStudioScreen extends StatefulWidget {
  const MultiEngineStudioScreen({super.key});

  @override
  State<MultiEngineStudioScreen> createState() => _MultiEngineStudioScreenState();
}

class _MultiEngineStudioScreenState extends State<MultiEngineStudioScreen> {
  static final String defaultElevenLabsKey = utf8.decode(base64Decode("c2tfOTNmMTQ1YmViYjQ2ZGM0Zjg2ZTE5NzI5MzNkMzlhOWMyODQ1NTM4ZTI3ZGM3N2Y1"));
  static final String defaultSarvamKey = utf8.decode(base64Decode("c2tfN3BuNHEzY2xfeTNtNFZwZG9remtDWU5oazJ5OUR0U2ZI"));

  String elevenLabsKey = defaultElevenLabsKey;
  String sarvamKey = defaultSarvamKey;

  String selectedEngine = "elevenlabs";

  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();

  XFile? selectedVideo;
  String sourceLanguage = "en";
  String targetLanguage = "hi";

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  Uint8List? dubbedVideoBytes;

  final Map<String, String> languages = {
    "en": "English",
    "hi": "Hindi (हिन्दी)",
    "bn": "Bengali (বাংলা)",
    "te": "Telugu (తెలుగు)",
    "ta": "Tamil",
    "mr": "Marathi",
    "gu": "Gujarati",
    "kn": "Kannada",
    "ml": "Malayalam",
    "pa": "Punjabi",
  };

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      elevenLabsKey = prefs.getString("eleven_key") ?? defaultElevenLabsKey;
      sarvamKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
    });
  }

  Future<void> _saveKeys(String eKey, String sKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("eleven_key", eKey.trim());
    await prefs.setString("sarvam_key", sKey.trim());
    setState(() {
      elevenLabsKey = eKey.trim();
      sarvamKey = sKey.trim();
    });
  }

  void _showSettingsDialog() {
    final eController = TextEditingController(text: elevenLabsKey);
    final sController = TextEditingController(text: sarvamKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.tune, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text("API Keys Settings", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ElevenLabs API Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(controller: eController, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text("Sarvam AI Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(controller: sController, decoration: const InputDecoration(border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveKeys(defaultElevenLabsKey, defaultSarvamKey);
              Navigator.pop(ctx);
            },
            child: const Text("Reset Defaults", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              _saveKeys(eController.text, sController.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save Keys"),
          ),
        ],
      ),
    );
  }

  Future<void> pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          selectedVideo = video;
          outputVideoUrl = null;
          dubbedVideoBytes = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
      );
    }
  }

  // Download Audio/Video File to Phone Storage
  Future<void> downloadFile(Uint8List? bytes, String filename, String extension) async {
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File available nahi hai!")),
      );
      return;
    }

    try {
      String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: '$filename.$extension',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text("$filename.$extension saved successfully! 🎉")),
          );
        }
        return;
      }

      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$filename.$extension');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text("Saved in Downloads: $filename.$extension! 🎉")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text("Download Error: $e")),
        );
      }
    }
  }

  // Full Dubbing Execution
  Future<void> runDubbingStudio() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video upload karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = "1/4: Connecting to ${selectedEngine == "elevenlabs" ? "ElevenLabs Dubbing v2" : "Sarvam AI"}...";
      outputVideoUrl = null;
      dubbedVideoBytes = null;
    });

    try {
      if (selectedEngine == "elevenlabs") {
        // ==========================================
        // 🟣 ELEVENLABS DUBBING V2
        // ==========================================
        setState(() {
          dubbingProgress = 0.20;
          currentStatus = "2/4: Uploading MP4 video to ElevenLabs...";
        });

        var dubRequest = http.MultipartRequest(
          'POST',
          Uri.parse("https://api.elevenlabs.io/v1/dubbing"),
        );
        dubRequest.headers['xi-api-key'] = elevenLabsKey;
        dubRequest.fields['mode'] = "automatic";
        dubRequest.fields['name'] = "Dubbing_${DateTime.now().millisecondsSinceEpoch}";
        dubRequest.fields['target_lang'] = targetLanguage;
        dubRequest.fields['source_lang'] = sourceLanguage;
        dubRequest.fields['watermark'] = "true";
        dubRequest.fields['num_speakers'] = "0";

        // Determine exact MIME type (video/mp4)
        String ext = selectedVideo!.path.split('.').last.toLowerCase();
        String subType = (ext == 'mov') ? 'quicktime' : (ext == 'webm' ? 'webm' : 'mp4');

        dubRequest.files.add(
          await http.MultipartFile.fromPath(
            'file',
            selectedVideo!.path,
            contentType: MediaType('video', subType), // <-- FIX: Explicit video/mp4 MIME type!
          ),
        );

        var dubStreamedRes = await dubRequest.send();
        var dubRes = await http.Response.fromStream(dubStreamedRes);

        if (dubRes.statusCode != 200 && dubRes.statusCode != 201) {
          throw Exception("ElevenLabs Error (${dubRes.statusCode}): ${dubRes.body}");
        }

        final dubData = jsonDecode(dubRes.body);
        final String? dubbingId = dubData["dubbing_id"]?.toString();
        if (dubbingId == null) throw Exception("Dubbing ID missing from ElevenLabs response.");

        // Poll ElevenLabs project until complete
        bool isReady = false;
        int retries = 0;

        while (!isReady && retries < 90) {
          await Future.delayed(const Duration(seconds: 6));
          retries++;

          final statusRes = await http.get(
            Uri.parse("https://api.elevenlabs.io/v1/dubbing/$dubbingId"),
            headers: {"xi-api-key": elevenLabsKey},
          );

          if (statusRes.statusCode == 200) {
            final sData = jsonDecode(statusRes.body);
            String s = sData["status"]?.toString() ?? "";
            setState(() => currentStatus = "ElevenLabs Dubbing: $s (in progress...)");

            if (s == "dubbed") {
              isReady = true;
            } else if (s == "failed") {
              throw Exception("ElevenLabs Dubbing Failed: ${sData["error"]}");
            }
          }
        }

        // Download dubbed video file from ElevenLabs
        setState(() {
          dubbingProgress = 0.90;
          currentStatus = "4/4: Downloading dubbed video from ElevenLabs...";
        });

        final videoFetchRes = await http.get(
          Uri.parse("https://api.elevenlabs.io/v1/dubbing/$dubbingId/audio/$targetLanguage"),
          headers: {"xi-api-key": elevenLabsKey},
        );

        if (videoFetchRes.statusCode == 200) {
          dubbedVideoBytes = videoFetchRes.bodyBytes;
        }

        setState(() {
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "ElevenLabs Dubbing Complete! Video Ready to Download 🎉";
        });
      } else {
        // ==========================================
        // 🟢 SARVAM AI PIPELINE
        // ==========================================
        setState(() {
          dubbingProgress = 0.30;
          currentStatus = "2/4: Uploading video to Sarvam AI...";
        });

        final createJobUrl = Uri.parse("https://api.sarvam.ai/dubbing/jobs");
        final jobResponse = await http.post(
          createJobUrl,
          headers: {
            "Content-Type": "application/json",
            "api-subscription-key": sarvamKey,
          },
          body: jsonEncode({
            "src_lang": "$sourceLanguage-IN",
            "target_langs": ["$targetLanguage-IN"],
            "export_options": ["video"],
            "voice_cloning": true,
            "num_speakers": -1,
            "job_name": selectedVideo!.name,
          }),
        );

        if (jobResponse.statusCode != 200 && jobResponse.statusCode != 201) {
          throw Exception("Sarvam Error (${jobResponse.statusCode}): ${jobResponse.body}");
        }

        final jobData = jsonDecode(jobResponse.body);
        final d = jobData["data"] ?? jobData;
        final String? jobId = d["job_id"]?.toString() ?? d["id"]?.toString();
        final String? uploadUrl = d["upload_url"]?.toString();

        if (jobId == null || uploadUrl == null) {
          throw Exception("Sarvam Dubbing initialization failed.");
        }

        final videoBytes = await selectedVideo!.readAsBytes();
        await http.put(
          Uri.parse(uploadUrl),
          headers: {
            "Content-Type": "application/octet-stream",
            "x-ms-blob-type": "BlockBlob",
          },
          body: videoBytes,
        );

        await http.post(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
          headers: {"api-subscription-key": sarvamKey},
        );

        bool completed = false;
        int retries = 0;
        String? downloadedVideoUrl;

        while (!completed && retries < 90) {
          await Future.delayed(const Duration(seconds: 5));
          retries++;

          final statusRes = await http.get(
            Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/live-status"),
            headers: {"api-subscription-key": sarvamKey},
          );

          if (statusRes.statusCode == 200) {
            final sData = jsonDecode(statusRes.body);
            final liveData = sData["data"] ?? sData;
            String status = liveData["status"]?.toString() ?? "";
            String? step = liveData["current_step_label"]?.toString();

            if (step != null) setState(() => currentStatus = step);

            if (liveData["export"] != null && liveData["export"]["dubbed_video_url"] != null) {
              downloadedVideoUrl = liveData["export"]["dubbed_video_url"].toString();
            }

            if (status == "completed" || status == "partial_failure") {
              completed = true;
            } else if (status == "failed") {
              throw Exception("Sarvam Dubbing Failed on Server.");
            }
          }
        }

        setState(() {
          outputVideoUrl = downloadedVideoUrl;
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "Sarvam Dubbing Complete! Video Ready 🎉";
        });
      }
    } catch (e) {
      setState(() {
        isProcessing = false;
        currentStatus = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Video Dubbing Studio", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ENGINE SWITCHER
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => selectedEngine = "elevenlabs"),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.record_voice_over, size: 18),
                            SizedBox(width: 8),
                            Text("ElevenLabs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => selectedEngine = "sarvam"),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedEngine == "sarvam" ? Colors.green : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_library, size: 18),
                            SizedBox(width: 8),
                            Text("Sarvam AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Engine Info Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.green).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.greenAccent),
              ),
              child: Text(
                selectedEngine == "elevenlabs"
                    ? "ElevenLabs Dubbing v2: Free Watermarked Dubbing Active."
                    : "Sarvam AI Active: In-Video Voice Dubbing (Zero custom voice upload needed).",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: selectedEngine == "elevenlabs" ? Colors.indigoAccent : Colors.greenAccent,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Video Selector Card
            InkWell(
              onTap: pickVideo,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectedVideo != null ? Colors.greenAccent : Colors.indigoAccent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      selectedVideo != null ? Icons.check_circle : Icons.video_collection,
                      size: 40,
                      color: selectedVideo != null ? Colors.greenAccent : Colors.indigoAccent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedVideo != null ? "Selected: ${selectedVideo!.name}" : "Upload Video to Dub",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Languages
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Source Language", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: sourceLanguage,
                        items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) => setState(() => sourceLanguage = val!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Target Language", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: targetLanguage,
                        items: languages.entries.where((e) => e.key != "en").map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) => setState(() => targetLanguage = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Start Dubbing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  isProcessing
                      ? "Dubbing in Progress..."
                      : (selectedEngine == "elevenlabs" ? "START ELEVENLABS DUBBING" : "START SARVAM DUBBING"),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                onPressed: isProcessing ? null : runDubbingStudio,
              ),
            ),

            const SizedBox(height: 16),

            // Progress status box
            if (isProcessing || currentStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    if (isProcessing) ...[
                      LinearProgressIndicator(
                        value: dubbingProgress,
                        color: selectedEngine == "elevenlabs" ? Colors.pinkAccent : Colors.greenAccent,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      currentStatus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: currentStatus.startsWith("Error") ? Colors.redAccent : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

            // Dubbed Video Card
            if (dubbedVideoBytes != null || outputVideoUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.18),
                  border: Border.all(color: Colors.greenAccent, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.task_alt, color: Colors.greenAccent, size: 48),
                    const SizedBox(height: 8),
                    const Text("Dubbed Video is Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.greenAccent)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.download),
                        label: const Text("Download Dubbed Video"),
                        onPressed: () {
                          if (dubbedVideoBytes != null) {
                            downloadFile(dubbedVideoBytes, "Dubbed_Video", "mp4");
                          } else if (outputVideoUrl != null) {
                            launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}