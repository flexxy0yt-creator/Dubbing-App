import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const DubbingApp());
}

class DubbingApp extends StatelessWidget {
  const DubbingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Video Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
        ),
      ),
      home: const DubbingHomeScreen(),
    );
  }
}

class DubbingHomeScreen extends StatefulWidget {
  const DubbingHomeScreen({super.key});

  @override
  State<DubbingHomeScreen> createState() => _DubbingHomeScreenState();
}

class _DubbingHomeScreenState extends State<DubbingHomeScreen> {
  static const String defaultApiKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";
  String apiKey = defaultApiKey;

  PlatformFile? rawVideoFile;
  String sourceLanguage = "auto";
  String targetLanguage = "hi-IN";

  bool isMultiSpeakerCustomMode = false;
  Map<int, PlatformFile?> speakerAudios = {
    1: null,
    2: null,
    3: null,
    4: null,
    5: null,
  };

  bool isDubbing = false;
  String statusMessage = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;

  final Map<String, String> languages = {
    "auto": "Auto Detect",
    "hi-IN": "Hindi (हिन्दी)",
    "en-IN": "English (Indian)",
    "bn-IN": "Bengali (বাংলা)",
    "te-IN": "Telugu (తెలుగు)",
    "ta-IN": "Tamil (தமிழ்)",
    "mr-IN": "Marathi (मराठी)",
    "gu-IN": "Gujarati (ગુજરાતી)",
    "kn-IN": "Kannada (ಕನ್ನಡ)",
    "ml-IN": "Malayalam (മലയാളം)",
    "pa-IN": "Punjabi (ਪੰਜਾਬੀ)",
    "od-IN": "Odia (ଓଡ଼ିଆ)",
  };

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiKey = prefs.getString("sarvam_api_key") ?? defaultApiKey;
    });
  }

  Future<void> _saveApiKey(String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("sarvam_api_key", newKey.trim());
    setState(() {
      apiKey = newKey.trim();
    });
  }

  Future<void> pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        rawVideoFile = result.files.first;
        outputVideoUrl = null;
      });
    }
  }

  Future<void> pickSpeakerAudio(int speakerNumber) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        speakerAudios[speakerNumber] = result.files.first;
      });
    }
  }

  Future<void> startDubbingProcess() async {
    if (rawVideoFile == null || rawVideoFile!.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle ek raw video select karo!")),
      );
      return;
    }

    setState(() {
      isDubbing = true;
      dubbingProgress = 0.1;
      statusMessage = "1/4: Initializing AI Dubbing job...";
      outputVideoUrl = null;
    });

    try {
      // 1. Create Job on Sarvam AI
      final createJobUrl = Uri.parse("https://api.sarvam.ai/jobs");
      final response = await http.post(
        createJobUrl,
        headers: {
          "Content-Type": "application/json",
          "api-subscription-key": apiKey,
        },
        body: jsonEncode({
          "job_type": "dubbing",
          "src_lang": sourceLanguage,
          "target_langs": [targetLanguage],
          "voice_cloning": true,
          "export_options": ["video", "audio"]
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception("Job creation failed: ${response.body}");
      }

      final jobData = jsonDecode(response.body);
      final String jobId = jobData["job_id"] ?? jobData["id"];
      final String uploadUrl = jobData["upload_url"];

      // 2. Upload raw video
      setState(() {
        dubbingProgress = 0.35;
        statusMessage = "2/4: Uploading video & analyzing speaker emotions...";
      });

      final videoBytes = await File(rawVideoFile!.path!).readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {"Content-Type": "application/octet-stream"},
        body: videoBytes,
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception("Video upload failed");
      }

      // 3. Start Pipeline
      setState(() {
        dubbingProgress = 0.6;
        statusMessage = isMultiSpeakerCustomMode
            ? "3/4: Synthesizing multi-speaker voice clones..."
            : "3/4: Preserving voice identity & lip-speed sync...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/jobs/$jobId/start"),
        headers: {"api-subscription-key": apiKey},
      );

      // 4. Poll live status
      bool completed = false;
      while (!completed) {
        await Future.delayed(const Duration(seconds: 4));
        final statusRes = await http.get(
          Uri.parse("https://api.sarvam.ai/jobs/$jobId/live-status"),
          headers: {"api-subscription-key": apiKey},
        );

        if (statusRes.statusCode == 200) {
          final sData = jsonDecode(statusRes.body);
          String status = sData["status"] ?? "";
          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Dubbing failed on AI server.");
          }
        }
      }

      // 5. Fetch Exported Video
      setState(() {
        dubbingProgress = 0.95;
        statusMessage = "4/4: Finalizing dubbed video download link...";
      });

      final exportRes = await http.get(
        Uri.parse("https://api.sarvam.ai/jobs/$jobId/export-status"),
        headers: {"api-subscription-key": apiKey},
      );

      if (exportRes.statusCode == 200) {
        final expData = jsonDecode(exportRes.body);
        setState(() {
          outputVideoUrl = expData["download_url"] ??
              expData["outputs"]?[targetLanguage]?["video"];
          isDubbing = false;
          dubbingProgress = 1.0;
          statusMessage = "Video Successfully Dubbed! 🎉";
        });
      }
    } catch (e) {
      setState(() {
        isDubbing = false;
        statusMessage = "Error: ${e.toString()}";
      });
    }
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: apiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Sarvam AI Key Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Default Key add hai, agar apni custom key use karni ho toh yahan change kar sakte hain:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "API Key",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.text = defaultApiKey;
              _saveApiKey(defaultApiKey);
              Navigator.pop(ctx);
            },
            child: const Text("Reset Default", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              _saveApiKey(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Dubbing & Clone Studio"),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Select Card
            InkWell(
              onTap: pickVideo,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: rawVideoFile != null ? Colors.green : Colors.indigoAccent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      rawVideoFile != null ? Icons.check_circle : Icons.video_call,
                      size: 45,
                      color: rawVideoFile != null ? Colors.green : Colors.indigoAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      rawVideoFile != null
                          ? "Video Selected: ${rawVideoFile!.name}"
                          : "Upload Raw Video (Tap to browse)",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Language Selection
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
                        items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() => sourceLanguage = val!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Target Language", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: targetLanguage,
                        items: languages.entries.where((e) => e.key != "auto").map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() => targetLanguage = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Multi-Speaker Voice Clone Toggle Option
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text("Multi-Speaker Custom Voice Clone", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Upload reference audio for up to 5 speakers to match custom voices & emotions", style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: isMultiSpeakerCustomMode,
                activeColor: Colors.pinkAccent,
                onChanged: (val) => setState(() => isMultiSpeakerCustomMode = val),
              ),
            ),

            // If toggle ON, show 5 Speaker Audio Uploaders
            if (isMultiSpeakerCustomMode) ...[
              const SizedBox(height: 12),
              const Text("Upload Reference Voice Clips:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
              const SizedBox(height: 8),
              for (int i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          speakerAudios[i] != null
                              ? "Speaker $i: ${speakerAudios[i]!.name}"
                              : "Speaker $i Voice Clip",
                          style: TextStyle(
                            fontSize: 12,
                            color: speakerAudios[i] != null ? Colors.greenAccent : Colors.grey,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                        icon: const Icon(Icons.mic, size: 16),
                        label: Text(speakerAudios[i] != null ? "Change" : "Upload", style: const TextStyle(fontSize: 11)),
                        onPressed: () => pickSpeakerAudio(i),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 20),

            // Dub Video Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome),
                label: Text(isDubbing ? "Dubbing Video..." : "DUB VIDEO NOW", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: isDubbing ? null : startDubbingProcess,
              ),
            ),

            const SizedBox(height: 20),

            // Progress / Status Box
            if (isDubbing || statusMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (isDubbing) ...[
                      LinearProgressIndicator(value: dubbingProgress, color: Colors.pinkAccent),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: statusMessage.startsWith("Error") ? Colors.redAccent : Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Output / Preview & Download Section
            if (outputVideoUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  border: Border.all(color: Colors.greenAccent),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.task_alt, color: Colors.greenAccent, size: 40),
                    const SizedBox(height: 8),
                    const Text("Dubbed Video is Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.greenAccent)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text("Preview Video"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                            icon: const Icon(Icons.download),
                            label: const Text("Download"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
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