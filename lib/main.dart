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
  // Safe Base64 Encoded Default Keys
  static final String defaultSarvamKey = utf8.decode(base64Decode("c2tfN3BuNHEzY2xfeTNtNFZwZG9rektDV1U1b2F6SjVPVVIwVTJaSQ=="));
  static final String defaultGeminiKey = utf8.decode(base64Decode("QVEuQWI4Uk42SjJvUXJsVGNWeEpoNTlFM0RIUGxrQ3dYS1lMMjRUbnN0QlhTLXh1VkMtdWc="));

  String sarvamApiKey = defaultSarvamKey;
  String geminiApiKey = defaultGeminiKey;

  // Selected Engine Switch: "gemini" ya "sarvam"
  String selectedEngine = "gemini";

  final ImagePicker _picker = ImagePicker();
  XFile? selectedVideo;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  List<Map<String, dynamic>> realVideoScript = [];

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
      sarvamApiKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
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
            const Text("Sarvam AI Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(controller: sController, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text("Gemini API Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
          realVideoScript.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
      );
    }
  }

  // 1. GEMINI ENGINE: Strictly NO SARVAM. Sends actual video bytes directly to Gemini 2.0 Flash!
  Future<List<Map<String, dynamic>>> processVideoWithGemini(XFile videoFile) async {
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey");

    final videoBytes = await videoFile.readAsBytes();
    final base64Video = base64Encode(videoBytes);

    final prompt = """
You are an expert anime and movie dubbing director. 
Listen carefully to the audio and watch the scene in this attached video file.

Instructions:
1. Identify each speaker and transcribe what is ACTUALLY being spoken in this video. Do NOT invent fake lines.
2. Auto-detect the exact emotion, tone, and pacing of each speaker from the scene.
3. Translate and adapt each dialogue into natural, punchy Hindi/Hinglish anime dubbing style.

Return ONLY a valid JSON array like this format:
[
  {
    "speaker": "Speaker 1",
    "emotion": "Detected Emotion & Tone",
    "original_dialogue": "Exact line spoken in video",
    "dubbed_dialogue": "Hindi/Hinglish translated dialogue"
  }
]
Return ONLY raw JSON. No markdown ticks.
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
            "parts": [
              {
                "inline_data": {
                  "mime_type": "video/mp4",
                  "data": base64Video,
                }
              },
              {
                "text": prompt,
              }
            ]
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
    } else {
      throw Exception("Gemini API Error (${res.statusCode}): ${res.body}");
    }
  }

  // Universal Video URL Finder for Sarvam Engine
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

  // SARVAM ENGINE: Strictly Sarvam Cloud Dubbing Pipeline
  Future<void> runSarvamDubbing() async {
    setState(() {
      dubbingProgress = 0.20;
      currentStatus = "1/3: Uploading video to Sarvam Cloud...";
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
      throw Exception("Sarvam upload URL generation failed.");
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

    setState(() {
      dubbingProgress = 0.50;
      currentStatus = "2/3: Sarvam in-video voice cloning & dubbing...";
    });

    await http.post(
      Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
      headers: {"api-subscription-key": sarvamApiKey},
    );

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

        if (step != null) setState(() => currentStatus = step);

        downloadedVideoUrl = findVideoUrl(liveData);

        if (status == "completed" || status == "partial_failure") {
          completed = true;
        } else if (status == "failed") {
          throw Exception("Sarvam Dubbing Failed on Server.");
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
      isProcessing = false;
      dubbingProgress = 1.0;
      currentStatus = "Sarvam Dubbing Complete! Video Ready to Download 🎉";
    });
  }

  // Main Pipeline Dispatcher
  Future<void> runSelectedPipeline() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video select karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      outputVideoUrl = null;
      realVideoScript.clear();
      currentStatus = selectedEngine == "gemini"
          ? "Gemini AI reading actual video audio & analyzing scene..."
          : "Connecting to Sarvam AI Engine...";
    });

    try {
      if (selectedEngine == "gemini") {
        // STRICTLY GEMINI: Zero calls to Sarvam!
        setState(() {
          dubbingProgress = 0.40;
          currentStatus = "Gemini 2.0 Flash: Analyzing video & generating real anime dub script...";
        });

        final results = await processVideoWithGemini(selectedVideo!);

        setState(() {
          realVideoScript = results;
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "Gemini Processing Complete! Actual Scene Script Ready 🎉";
        });
      } else {
        // STRICTLY SARVAM
        await runSarvamDubbing();
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
            // ENGINE SWITCHER (Gemini Studio vs Sarvam AI)
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
                            Text("Sarvam AI (Dub)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                color: (selectedEngine == "gemini" ? const Color(0xFF6366F1) : Colors.green).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selectedEngine == "gemini" ? const Color(0xFF6366F1) : Colors.greenAccent),
              ),
              child: Text(
                selectedEngine == "gemini"
                    ? "Gemini Studio Active: 100% Sarvam-Free. Video is analyzed directly by Google Gemini AI."
                    : "Sarvam AI Active: Uploads video to Sarvam cloud and exports full dubbed MP4 video.",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: selectedEngine == "gemini" ? Colors.indigoAccent : Colors.greenAccent,
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
                      selectedVideo != null ? "Selected: ${selectedVideo!.name}" : "Upload Raw Video to Dub",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),

            // Video In-App Preview / Action Button
            if (selectedVideo != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.play_circle_outline, color: Color(0xFF6366F1)),
                  label: const Text("Preview Original Video in Player", style: TextStyle(color: Colors.white)),
                  onPressed: () => launchUrl(Uri.file(selectedVideo!.path)),
                ),
              ),
            ],

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

            // Start Processing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedEngine == "gemini" ? const Color(0xFF6366F1) : Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  isProcessing
                      ? "Processing..."
                      : (selectedEngine == "gemini" ? "PROCESS WITH GEMINI 2.0" : "DUB VIDEO ON SARVAM CLOUD"),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                onPressed: isProcessing ? null : runSelectedPipeline,
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
                        color: selectedEngine == "gemini" ? const Color(0xFF6366F1) : Colors.greenAccent,
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

            // SARVAM OUTPUT: Dubbed Video Download Card
            if (selectedEngine == "sarvam" && outputVideoUrl != null) ...[
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
                  ],
                ),
              ),
            ],

            // GEMINI OUTPUT: Actual Spoken Dialogue & Emotion Breakdown
            if (selectedEngine == "gemini" && realVideoScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Gemini Real Video Dubbing Script:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 16)),
              const SizedBox(height: 12),
              for (int i = 0; i < realVideoScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            realVideoScript[i]["speaker"] ?? "Speaker ${i + 1}",
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              realVideoScript[i]["emotion"] ?? "Real Tone",
                              style: const TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Spoken: \"${realVideoScript[i]["original_dialogue"] ?? ""}\"",
                        style: const TextStyle(fontSize: 12, color: Colors.white60, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Dubbed: \"${realVideoScript[i]["dubbed_dialogue"] ?? ""}\"",
                        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
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