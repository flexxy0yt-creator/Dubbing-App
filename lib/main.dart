import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'AI Multi-Speaker Video Dubbing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
        ),
      ),
      home: const MultiSpeakerStudioScreen(),
    );
  }
}

class MultiSpeakerStudioScreen extends StatefulWidget {
  const MultiSpeakerStudioScreen({super.key});

  @override
  State<MultiSpeakerStudioScreen> createState() => _MultiSpeakerStudioScreenState();
}

class _MultiSpeakerStudioScreenState extends State<MultiSpeakerStudioScreen> {
  static const String defaultSarvamKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";
  String sarvamApiKey = defaultSarvamKey;

  final ImagePicker _picker = ImagePicker();
  XFile? selectedVideo;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  Map<int, PlatformFile?> speakerAudios = {
    1: null,
    2: null,
    3: null,
    4: null,
    5: null,
  };

  bool isProcessing = false;
  String currentStatus = "";
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
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      sarvamApiKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
    });
  }

  Future<void> pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          selectedVideo = video;
          outputVideoUrl = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
      );
    }
  }

  Future<void> pickSpeakerAudio(int speakerNumber) async {
    try {
      FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          speakerAudios[speakerNumber] = res.files.first;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Speaker $speakerNumber Reference Added!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // Universal Video URL Finder
  String? findVideoUrl(dynamic json) {
    if (json == null) return null;
    if (json is Map) {
      if (json["dubbed_video_url"] != null && json["dubbed_video_url"].toString().startsWith("http")) {
        return json["dubbed_video_url"].toString();
      }
      if (json["download_url"] != null && json["download_url"].toString().startsWith("http")) {
        return json["download_url"].toString();
      }
      if (json["url"] != null && json["url"].toString().startsWith("http")) {
        return json["url"].toString();
      }
      for (var val in json.values) {
        final res = findVideoUrl(val);
        if (res != null) return res;
      }
    } else if (json is List) {
      for (var item in json) {
        final res = findVideoUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  Future<void> runFullDubbing() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video select karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = "1/4: Initializing Sarvam AI Multi-Speaker Dubbing...";
      outputVideoUrl = null;
    });

    try {
      int activeSpeakers = speakerAudios.values.where((v) => v != null).length;
      if (activeSpeakers == 0) activeSpeakers = 2;

      // 1. Create Dubbing Job (Voice Cloning = True: clones the actual speakers from video)
      final createJobUrl = Uri.parse("https://api.sarvam.ai/dubbing/jobs");
      final jobResponse = await http.post(
        createJobUrl,
        headers: {
          "Content-Type": "application/json",
          "api-subscription-key": sarvamApiKey,
        },
        body: jsonEncode({
          "src_lang": sourceLanguage,
          "target_langs": [targetLanguage],
          "export_options": ["video"],
          "voice_cloning": true,
          "num_speakers": activeSpeakers,
          "job_name": selectedVideo!.name,
        }),
      );

      if (jobResponse.statusCode != 200 && jobResponse.statusCode != 201) {
        throw Exception("API Error (${jobResponse.statusCode}): ${jobResponse.body}");
      }

      final jobData = jsonDecode(jobResponse.body);
      final d = jobData["data"] ?? jobData;
      final String jobId = d["job_id"] ?? d["id"];
      final String uploadUrl = d["upload_url"];

      // 2. Upload Video with Azure BlockBlob header
      setState(() {
        dubbingProgress = 0.25;
        currentStatus = "2/4: Uploading video to AI Cloud...";
      });

      final videoBytes = await selectedVideo!.readAsBytes();
      final uploadRes = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          "Content-Type": "application/octet-stream",
          "x-ms-blob-type": "BlockBlob",
        },
        body: videoBytes,
      );

      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
        throw Exception("Video upload failed to cloud server.");
      }

      // 3. Start Dubbing Pipeline
      setState(() {
        dubbingProgress = 0.45;
        currentStatus = "3/4: AI Separating speakers & cloning character voices into Hindi...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      // 4. Poll live status until video is 100% ready
      bool completed = false;
      int retries = 0;
      String? downloadedVideoUrl;

      while (!completed && retries < 90) {
        await Future.delayed(const Duration(seconds: 5));
        retries++;

        final statusRes = await http.get(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/live-status"),
          headers: {"api-subscription-key": sarvamApiKey},
        );

        if (statusRes.statusCode == 200) {
          final sData = jsonDecode(statusRes.body);
          final liveData = sData["data"] ?? sData;
          String status = liveData["status"] ?? "";
          String? step = liveData["current_step_label"];

          if (step != null) {
            setState(() => currentStatus = "3/4: $step");
          }

          // Direct check for dubbed_video_url in live-status
          downloadedVideoUrl = findVideoUrl(liveData);

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server Dubbing Failed: ${liveData["error_message"]}");
          }
        }
      }

      // 5. Fetch export status if needed
      if (downloadedVideoUrl == null) {
        final exportRes = await http.get(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
          headers: {"api-subscription-key": sarvamApiKey},
        );
        if (exportRes.statusCode == 200) {
          final expData = jsonDecode(exportRes.body);
          downloadedVideoUrl = findVideoUrl(expData);
        }
      }

      setState(() {
        outputVideoUrl = downloadedVideoUrl;
        isProcessing = false;
        dubbingProgress = 1.0;
        currentStatus = outputVideoUrl != null
            ? "Dubbing Complete! Video Ready to Download 🎉"
            : "Dubbing Finished on Server!";
      });
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
        title: const Text("AI Multi-Speaker Dubbing", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        items: languages.entries.where((e) => e.key != "en-IN").map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) => setState(() => targetLanguage = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 5 Speaker Upload Rows
            const Text("Speakers to Dub (1 to 5):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
            const SizedBox(height: 10),

            for (int i = 1; i <= 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.pinkAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          speakerAudios[i] != null
                              ? "Speaker $i: ${speakerAudios[i]!.name}"
                              : "Speaker $i Track",
                          style: TextStyle(
                            fontSize: 13,
                            color: speakerAudios[i] != null ? Colors.greenAccent : Colors.white70,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                        onPressed: () => pickSpeakerAudio(i),
                        child: Text(speakerAudios[i] != null ? "Change" : "Select", style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // Start Dubbing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.rocket_launch, color: Colors.white),
                label: Text(
                  isProcessing ? "Dubbing in Progress..." : "START MULTI-SPEAKER DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
                onPressed: isProcessing ? null : runFullDubbing,
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
                      LinearProgressIndicator(value: dubbingProgress, color: Colors.pinkAccent),
                      const SizedBox(height: 10),
                    ],
                    Text(currentStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

            // 1. Dubbed Video Card (GUARANTEED DOWNLOAD BUTTON)
            if (outputVideoUrl != null) ...[
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
                    const SizedBox(height: 6),
                    const Text("Niche diye gaye button par click karke video download karein:", style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text("Preview Video"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: const Icon(Icons.download),
                            label: const Text("Download"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white60),
                      label: const Text("Copy Video Download Link", style: TextStyle(color: Colors.white60, fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: outputVideoUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link Copied to Clipboard!")));
                      },
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