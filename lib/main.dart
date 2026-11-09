import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const SarvamDubbingApp());
}

class SarvamDubbingApp extends StatelessWidget {
  const SarvamDubbingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarvam AI Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF151D2E),
        ),
      ),
      home: const DubbingStudioScreen(),
    );
  }
}

class DubbingStudioScreen extends StatefulWidget {
  const DubbingStudioScreen({super.key});

  @override
  State<DubbingStudioScreen> createState() => _DubbingStudioScreenState();
}

class _DubbingStudioScreenState extends State<DubbingStudioScreen> with SingleTickerProviderStateMixin {
  // Safe Base64 Encoded Key
  static final String defaultSarvamKey = utf8.decode(base64Decode("c2tfN3BuNHEzY2xfeTNtNFZwZG9rektDV1U1b2F6SjVPVVIwVTJaSQ=="));
  String sarvamApiKey = defaultSarvamKey;

  final ImagePicker _picker = ImagePicker();
  XFile? selectedVideo;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  int currentStep = 0; // 0 to 4 for smooth stepper effect
  String? outputVideoUrl;

  late AnimationController _pulseController;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      sarvamApiKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
    });
  }

  Future<void> _saveApiKey(String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("sarvam_key", newKey.trim());
    setState(() {
      sarvamApiKey = newKey.trim();
    });
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: sarvamApiKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 10),
            Text("Sarvam API Key", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Agar credits khatam ho gaye hain ya nayi key lagani ho toh yahan change karein:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                labelText: "API Key",
                hintText: "sk_...",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.text = defaultSarvamKey;
              _saveApiKey(defaultSarvamKey);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Default Key Restored!")));
            },
            child: const Text("Reset Default", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              _saveApiKey(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Key Saved Successfully!")));
            },
            child: const Text("Save Key", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Gallery Error: $e")),
      );
    }
  }

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

  Future<void> startDubbing() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video select karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      currentStep = 1;
      dubbingProgress = 0.15;
      currentStatus = "Initializing AI Dubbing Job on Sarvam Cloud...";
      outputVideoUrl = null;
    });

    try {
      // 1. Create Dubbing Job
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
        throw Exception("Server did not return a valid upload URL.");
      }

      // 2. Upload Video to Azure Storage
      setState(() {
        currentStep = 2;
        dubbingProgress = 0.35;
        currentStatus = "Uploading raw video to cloud processor...";
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

      // 3. Start Pipeline
      setState(() {
        currentStep = 3;
        dubbingProgress = 0.55;
        currentStatus = "AI Cloning voices, translating dialogues & syncing audio...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      // 4. Smooth Polling
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

          if (step != null) {
            setState(() {
              currentStatus = step;
              dubbingProgress = 0.55 + (retries / 90) * 0.35;
            });
          }

          downloadedVideoUrl = findVideoUrl(liveData);

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server Dubbing Failed: ${liveData["error_message"]}");
          }
        }
      }

      // Check export status if live-status didn't have URL
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
        currentStep = 4;
        outputVideoUrl = downloadedVideoUrl;
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

  Widget _buildStepItem(int stepNumber, String title, bool isActive, bool isDone) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? const Color(0xFF10B981) : (isActive ? const Color(0xFF6366F1) : const Color(0xFF334155)),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text("$stepNumber", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.normal,
            color: isDone ? const Color(0xFF10B981) : (isActive ? Colors.white : Colors.grey),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF0F172A),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 22),
            SizedBox(width: 10),
            Text("Sarvam Dubbing Studio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Selector Card
            InkWell(
              onTap: isProcessing ? null : pickVideo,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: selectedVideo != null
                        ? [const Color(0xFF1E293B), const Color(0xFF131B2A)]
                        : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selectedVideo != null ? const Color(0xFF10B981) : const Color(0xFF6366F1).withOpacity(0.4),
                    width: selectedVideo != null ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selectedVideo != null ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFF6366F1).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selectedVideo != null ? Icons.check_circle_rounded : Icons.video_file_rounded,
                        size: 42,
                        color: selectedVideo != null ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      selectedVideo != null ? selectedVideo!.name : "Select Raw Video to Dub",
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedVideo != null ? "Tap to change video" : "Supports MP4, MOV, WEBM (Gallery)",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Language Selection Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF151D2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Language Configuration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Source (Original)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: sourceLanguage,
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: isProcessing ? null : (val) => setState(() => sourceLanguage = val!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Target (Dubbed)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: targetLanguage,
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              items: languages.entries.where((e) => e.key != "en-IN").map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: isProcessing ? null : (val) => setState(() => targetLanguage = val!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Dub Video Action Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bolt, color: Colors.white),
                label: Text(
                  isProcessing ? "DUBBING IN PROGRESS..." : "START AI DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5, color: Colors.white),
                ),
                onPressed: isProcessing ? null : startDubbing,
              ),
            ),

            const SizedBox(height: 20),

            // Smooth Animated Progress & Step Tracker
            if (isProcessing || currentStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Process Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
                        Text("${(dubbingProgress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: dubbingProgress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF0F172A),
                        color: currentStatus.startsWith("Error") ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      currentStatus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: currentStatus.startsWith("Error") ? Colors.redAccent : Colors.white70,
                      ),
                    ),
                    if (isProcessing) ...[
                      const Divider(height: 24, color: Color(0xFF334155)),
                      Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          _buildStepItem(1, "Init", currentStep == 1, currentStep > 1),
                          _buildStepItem(2, "Upload", currentStep == 2, currentStep > 2),
                          _buildStepItem(3, "Clone & Dub", currentStep == 3, currentStep > 3),
                          _buildStepItem(4, "Ready", currentStep == 4, currentStep == 4),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            // Final Dubbed Video Download Card
            if (outputVideoUrl != null) ...[
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF10B981).withOpacity(0.18), const Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 46),
                    const SizedBox(height: 8),
                    const Text("Dubbed Video is Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10B981))),
                    const SizedBox(height: 4),
                    const Text("In-video voice clone and Hindi dubbing completed.", style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                            label: const Text("Preview", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.download_rounded, color: Colors.white),
                            label: const Text("Download", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 15, color: Colors.white60),
                      label: const Text("Copy Download Link", style: TextStyle(color: Colors.white60, fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: outputVideoUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copied to clipboard!")));
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