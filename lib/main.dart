import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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

  final ImagePicker _picker = ImagePicker();
  XFile? rawVideoFile;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  bool isCustomVoiceMode = false;
  PlatformFile? customVoiceAudio;

  bool isDubbing = false;
  String statusMessage = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;

  final Map<String, String> languages = {
    "en-IN": "English (Indian)",
    "hi-IN": "Hindi (हिन्दी)",
    "bn-IN": "Bengali (বাংলা)",
    "te-IN": "Telugu (తెలుగు)",
    "ta-IN": "Tamil (தமிழ்)",
    "mr-IN": "Marathi (मराठी)",
    "gu-IN": "Gujarati (ગુજરાતી)",
    "kn-IN": "Kannada (ಕನ್ನಡ)",
    "ml-IN": "Malayalam (മലയാളം)",
    "pa-IN": "Punjabi (ਪੰਜਾਬੀ)",
    "or-IN": "Odia (ଓଡ଼ିଆ)",
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
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          rawVideoFile = video;
          outputVideoUrl = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Video Selected: ${video.name}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
        );
      }
    }
  }

  Future<void> pickCustomAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          customVoiceAudio = result.files.first;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Custom Voice Selected: ${result.files.first.name}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
        );
      }
    }
  }

  // 1. Function to create a custom Voice ID from the uploaded MP3
  Future<String?> createCustomVoiceId(PlatformFile audioFile) async {
    setState(() {
      statusMessage = "1/5: Uploading reference audio & creating Voice Clone ID...";
      dubbingProgress = 0.15;
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("https://api.sarvam.ai/voices/create"),
      );

      request.headers['api-subscription-key'] = apiKey;
      request.fields['name'] = audioFile.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      request.fields['language'] = targetLanguage;

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path!,
      ));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final data = resData["data"] ?? resData;
        return data["voice_id"] ?? data["id"];
      } else {
        throw Exception("Voice clone failed (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      throw Exception("Voice Clone Error: $e");
    }
  }

  Future<void> startDubbingProcess() async {
    if (rawVideoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle ek raw video select karo!")),
      );
      return;
    }

    if (sourceLanguage == targetLanguage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Source aur Target bhasha alag honi chahiye!")),
      );
      return;
    }

    setState(() {
      isDubbing = true;
      dubbingProgress = 0.05;
      statusMessage = "Initializing AI Studio...";
      outputVideoUrl = null;
    });

    try {
      String? customVoiceId;

      // Agar custom voice toggle ON hai aur file selected hai
      if (isCustomVoiceMode && customVoiceAudio != null && customVoiceAudio!.path != null) {
        customVoiceId = await createCustomVoiceId(customVoiceAudio!);
      }

      // 2. Create Dubbing Job
      setState(() {
        dubbingProgress = 0.25;
        statusMessage = "2/5: Creating Sarvam AI Dubbing Job...";
      });

      final createJobUrl = Uri.parse("https://api.sarvam.ai/dubbing/jobs");

      final Map<String, dynamic> requestBody = {
        "src_lang": sourceLanguage,
        "target_langs": [targetLanguage],
        "export_options": ["video"],
        "num_speakers": 1,
        "job_name": rawVideoFile!.name,
      };

      if (customVoiceId != null) {
        // Custom Voice mode: cloning = false, voice_id = customVoiceId
        requestBody["voice_cloning"] = false;
        requestBody["voice_id"] = customVoiceId;
      } else {
        // In-Video Voice clone mode: auto-clones the speakers in the video
        requestBody["voice_cloning"] = true;
      }

      final response = await http.post(
        createJobUrl,
        headers: {
          "Content-Type": "application/json",
          "api-subscription-key": apiKey,
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception("API Error (${response.statusCode}): ${response.body}");
      }

      final jobData = jsonDecode(response.body);
      final data = jobData["data"] ?? jobData;
      final String jobId = data["job_id"] ?? data["id"];
      final String uploadUrl = data["upload_url"];

      // 3. Upload raw video
      setState(() {
        dubbingProgress = 0.45;
        statusMessage = "3/5: Uploading video to cloud storage...";
      });

      final videoBytes = await rawVideoFile!.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          "Content-Type": "application/octet-stream",
          "x-ms-blob-type": "BlockBlob",
        },
        body: videoBytes,
      );

      if (uploadResponse.statusCode != 200 && uploadResponse.statusCode != 201) {
        throw Exception("Video upload failed (${uploadResponse.statusCode}): ${uploadResponse.body}");
      }

      // 4. Start Pipeline
      setState(() {
        dubbingProgress = 0.65;
        statusMessage = customVoiceId != null
            ? "4/5: Dubbing video with your Custom Cloned Voice..."
            : "4/5: Preserving video emotions & voice tone...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": apiKey},
      );

      // 5. Poll live status
      bool completed = false;
      int retries = 0;
      while (!completed && retries < 90) {
        await Future.delayed(const Duration(seconds: 5));
        retries++;

        final statusRes = await http.get(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/live-status"),
          headers: {"api-subscription-key": apiKey},
        );

        if (statusRes.statusCode == 200) {
          final sData = jsonDecode(statusRes.body);
          final liveData = sData["data"] ?? sData;
          String status = liveData["status"] ?? "";
          String? stepLabel = liveData["current_step_label"];

          if (stepLabel != null) {
            setState(() {
              statusMessage = "4/5: $stepLabel";
            });
          }

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("AI processing failed: ${liveData["error_message"]}");
          }
        }
      }

      // 6. Fetch Exported Video
      setState(() {
        dubbingProgress = 0.95;
        statusMessage = "5/5: Preparing download link...";
      });

      final exportRes = await http.get(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
        headers: {"api-subscription-key": apiKey},
      );

      if (exportRes.statusCode == 200) {
        final expData = jsonDecode(exportRes.body);
        final expOutputs = expData["data"] ?? expData;

        setState(() {
          outputVideoUrl = expOutputs["download_url"] ??
              expOutputs["outputs"]?[targetLanguage]?["video"]?["download_url"] ??
              expOutputs["outputs"]?[targetLanguage]?["video"];
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
        title: const Text("Sarvam API Key Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Default Key pre-loaded hai. Custom key lagane ke liye yahan edit karein:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
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
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: rawVideoFile != null ? Colors.greenAccent : Colors.indigoAccent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      rawVideoFile != null ? Icons.check_circle : Icons.video_call,
                      size: 45,
                      color: rawVideoFile != null ? Colors.greenAccent : Colors.indigoAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      rawVideoFile != null
                          ? "Selected: ${rawVideoFile!.name}"
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
                        items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() => targetLanguage = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Custom Voice Clone Toggle
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text("Custom Voice Clone (from MP3)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Apni pasand ki aawaz (Ayankoji/Teacher) ka audio upload karke usi aawaz me dub karein", style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: isCustomVoiceMode,
                activeColor: Colors.pinkAccent,
                onChanged: (val) => setState(() => isCustomVoiceMode = val),
              ),
            ),

            // Custom Audio Picker
            if (isCustomVoiceMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.pinkAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        customVoiceAudio != null
                            ? "Voice: ${customVoiceAudio!.name}"
                            : "Select Reference Audio (MP3/WAV)",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: customVoiceAudio != null ? Colors.greenAccent : Colors.white70,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                      onPressed: pickCustomAudio,
                      child: Text(customVoiceAudio != null ? "Change" : "Browse"),
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
                label: Text(
                  isDubbing ? "Dubbing in Progress..." : "DUB VIDEO NOW",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
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
                            label: const Text("Preview"),
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