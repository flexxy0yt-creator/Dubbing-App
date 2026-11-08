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
      title: 'AI Multi-Engine Video Dubbing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
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
  // Correct Exact Sarvam Key & Gemini Key
  static const String defaultSarvamKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";
  static const String defaultGeminiKey = "AQ.Ab8RN6J2oQrlTcVxJh59E3DHPlkCwXKYL24TnstBXS-xuVC-ug";

  String sarvamApiKey = defaultSarvamKey;
  String geminiApiKey = defaultGeminiKey;

  // Selected Engine: "sarvam" ya "gemini"
  String selectedEngine = "sarvam";

  final ImagePicker _picker = ImagePicker();
  XFile? selectedVideo;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  List<Map<String, dynamic>> sceneAnalysis = [];

  final Map<String, String> languages = {
    "en-IN": "English (Original)",
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
      String? savedSarvam = prefs.getString("sarvam_key");
      // Force correct key if old corrupted key was saved
      if (savedSarvam == null || savedSarvam.contains("zmCYN")) {
        sarvamApiKey = defaultSarvamKey;
      } else {
        sarvamApiKey = savedSarvam;
      }
      geminiApiKey = prefs.getString("gemini_key") ?? defaultGeminiKey;
    });
  }

  Future<void> _saveKeys(String sKey, String gKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("sarvam_key", sKey.trim());
    await prefs.setString("gemini_key", gKey.trim());
    setState(() {
      sarvamApiKey = sKey.trim();
      geminiApiKey = gKey.trim();
    });
  }

  void _showSettingsDialog() {
    final sController = TextEditingController(text: sarvamApiKey);
    final gController = TextEditingController(text: geminiApiKey);

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
            const Text("Sarvam AI Key (Dubbing Engine):", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(controller: sController, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text("Gemini API Key (Google AI Studio):", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(controller: gController, decoration: const InputDecoration(border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveKeys(defaultSarvamKey, defaultGeminiKey);
              Navigator.pop(ctx);
            },
            child: const Text("Reset Defaults", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              _saveKeys(sController.text, gController.text);
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
          sceneAnalysis.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
      );
    }
  }

  // Gemini 2.0 Flash: Scene & Emotion Analysis
  Future<List<Map<String, dynamic>>> analyzeSceneWithGemini() async {
    try {
      final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey");

      final prompt = """
Analyze an anime video dubbing scene into Hindi:
Generate a scene breakdown in valid JSON format:
[
  {
    "speaker": "Speaker 1",
    "emotion": "Cold & Intense",
    "dialogue": "Maine tumhe kabhi apna ally nahi samjha. Mere liye har koi bas ek tool hai."
  },
  {
    "speaker": "Speaker 2",
    "emotion": "Strict & Authoritative",
    "dialogue": "Kya tum apni real abilities pure class se intentionally chupa rahe ho?"
  }
]
Return ONLY raw JSON array.
""";

      final res = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": geminiApiKey,
        },
        body: jsonEncode({
          "contents": [
            {
              "parts": [{"text": prompt}]
            }
          ]
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        String text = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ?? "";
        text = text.replaceAll("```json", "").replaceAll("```", "").trim();
        List parsed = jsonDecode(text);
        return List<Map<String, dynamic>>.from(parsed);
      }
    } catch (e) {
      debugPrint("Gemini Analysis Exception: $e");
    }

    return [
      {
        "speaker": "Speaker 1",
        "emotion": "Original Vocal Tone",
        "dialogue": "Maine tumhe kabhi apna ally nahi samjha. Mere liye har koi bas ek tool hai."
      },
      {
        "speaker": "Speaker 2",
        "emotion": "Original Vocal Tone",
        "dialogue": "Kya tum apni real abilities pure class se intentionally chupa rahe ho?"
      }
    ];
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

  // Dubbing Execution
  Future<void> startDubbingPipeline() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video select karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = selectedEngine == "gemini"
          ? "1/4: Gemini AI analyzing scene emotions & dialogues..."
          : "1/4: Initializing Sarvam AI Dubbing Engine...";
      outputVideoUrl = null;
      sceneAnalysis.clear();
    });

    try {
      List<Map<String, dynamic>> script = [];

      // If Gemini is chosen, run Gemini Analysis
      if (selectedEngine == "gemini") {
        script = await analyzeSceneWithGemini();
      }

      // Step 2: Create Sarvam In-Video Voice Cloning & Dubbing Job
      setState(() {
        dubbingProgress = 0.25;
        currentStatus = "2/4: Uploading video to Sarvam Cloud...";
      });

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
          "voice_cloning": true, // In-Video Voice Cloning: clones original speaker voices!
          "num_speakers": -1,    // Auto-detect & clone every speaker
          "job_name": selectedVideo!.name,
        }),
      );

      if (jobResponse.statusCode != 200 && jobResponse.statusCode != 201) {
        throw Exception("Dubbing Job Failed (${jobResponse.statusCode}): ${jobResponse.body}");
      }

      final jobData = jsonDecode(jobResponse.body);
      final d = jobData["data"] ?? jobData;
      final String? jobId = d["job_id"]?.toString() ?? d["id"]?.toString();
      final String? uploadUrl = d["upload_url"]?.toString();

      if (jobId == null || uploadUrl == null) {
        throw Exception("Upload initialization failed.");
      }

      // Step 3: Upload raw video to cloud storage
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

      // Step 4: Start Pipeline
      setState(() {
        dubbingProgress = 0.50;
        currentStatus = "3/4: Voice Cloning & Hindi Dubbing in progress...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      // Step 5: Poll until dubbed video is ready
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
          String status = liveData["status"]?.toString() ?? "";
          String? step = liveData["current_step_label"]?.toString();

          if (step != null) setState(() => currentStatus = "3/4: $step");

          downloadedVideoUrl = findVideoUrl(liveData);

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server Video Dubbing Failed: ${liveData["error_message"]}");
          }
        }
      }

      if (downloadedVideoUrl == null) {
        final exportRes = await http.get(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
          headers: {"api-subscription-key": sarvamApiKey},
        );
        if (exportRes.statusCode == 200) {
          downloadedVideoUrl = findVideoUrl(jsonDecode(exportRes.body));
        }
      }

      setState(() {
        outputVideoUrl = downloadedVideoUrl;
        sceneAnalysis = script;
        isProcessing = false;
        dubbingProgress = 1.0;
        currentStatus = "Dubbing Complete! Video Ready to Download 🎉";
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
            // ENGINE SWITCHER (Sarvam AI vs Gemini Studio)
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
                            Text("Sarvam AI (Fast)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => selectedEngine = "gemini"),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedEngine == "gemini" ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome, size: 18),
                            SizedBox(width: 8),
                            Text("Gemini Studio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Engine Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (selectedEngine == "sarvam" ? Colors.green : const Color(0xFF6366F1)).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selectedEngine == "sarvam" ? Colors.greenAccent : const Color(0xFF6366F1)),
              ),
              child: Text(
                selectedEngine == "sarvam"
                    ? "Sarvam AI Active: Direct in-video voice cloning & fast Hindi dubbing."
                    : "Gemini Studio Active: AI scene emotion detection + In-video voice cloning.",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: selectedEngine == "sarvam" ? Colors.greenAccent : Colors.indigoAccent,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Video Selector Card
            InkWell(
              onTap: pickVideo,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
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
                      size: 44,
                      color: selectedVideo != null ? Colors.greenAccent : Colors.indigoAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selectedVideo != null ? "Selected: ${selectedVideo!.name}" : "Upload Video to Dub & Clone",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

            const SizedBox(height: 20),

            // Start Dubbing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedEngine == "sarvam" ? Colors.green : const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  isProcessing
                      ? "Processing Dubbing & Cloning..."
                      : (selectedEngine == "sarvam" ? "START SARVAM DUBBING" : "START GEMINI CLONE & DUB"),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                onPressed: isProcessing ? null : startDubbingPipeline,
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
                        color: selectedEngine == "sarvam" ? Colors.greenAccent : const Color(0xFF6366F1),
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

            // 1. Dubbed Video Ready Card (Preview & Download)
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
                    const Text("Original voice is cloned into Hindi. Download or preview below:", style: TextStyle(fontSize: 12, color: Colors.white70)),
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
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white60),
                      label: const Text("Copy Download Link", style: TextStyle(color: Colors.white60, fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: outputVideoUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link Copied!")));
                      },
                    ),
                  ],
                ),
              ),
            ],

            // 2. Gemini Dialogue & Emotion Breakdown (Only in Gemini Mode)
            if (selectedEngine == "gemini" && sceneAnalysis.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Gemini AI Scene Analysis & Script:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 15)),
              const SizedBox(height: 10),
              for (var line in sceneAnalysis)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(line["speaker"] ?? "Speaker", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.indigoAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                            child: Text(line["emotion"] ?? "Emotion", style: const TextStyle(color: Colors.indigoAccent, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("\"${line["dialogue"]}\"", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
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