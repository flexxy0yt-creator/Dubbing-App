import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Startup crash rokne ke liye
  runApp(const FreeDubbingApp());
}

class FreeDubbingApp extends StatelessWidget {
  const FreeDubbingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Free GPU AI Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
        ),
      ),
      home: const CustomDubbingScreen(),
    );
  }
}

class CustomDubbingScreen extends StatefulWidget {
  const CustomDubbingScreen({super.key});

  @override
  State<CustomDubbingScreen> createState() => _CustomDubbingScreenState();
}

class _CustomDubbingScreenState extends State<CustomDubbingScreen> {
  String colabServerUrl = "https://your-colab-link.trycloudflare.com";

  final ImagePicker _picker = ImagePicker();
  XFile? selectedVideo;
  PlatformFile? refAudioFile;
  String targetLanguage = "hi";

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  String? dubbedDialogue;

  final Map<String, String> languages = {
    "hi": "Hindi (हिन्दी)",
    "en": "English",
    "bn": "Bengali (বাংলা)",
    "te": "Telugu (తెలుగు)",
    "ta": "Tamil (தமிழ்)",
    "mr": "Marathi (मराठी)",
    "gu": "Gujarati (ગુજરાતી)",
  };

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      colabServerUrl = prefs.getString("colab_url") ?? colabServerUrl;
    });
  }

  Future<void> _saveServerUrl(String url) async {
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("colab_url", cleanUrl);
    setState(() {
      colabServerUrl = cleanUrl;
    });
  }

  void _showServerSettings() {
    final controller = TextEditingController(text: colabServerUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text("Colab GPU Server URL", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Colab notebook me jo 'trycloudflare.com' link aayi hai, use yahan paste karein:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: "https://...trycloudflare.com",
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              _saveServerUrl(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Server URL Saved!")));
            },
            child: const Text("Save URL"),
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
          dubbedDialogue = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gallery Error: $e")));
    }
  }

  Future<void> pickRefAudio() async {
    try {
      FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          refAudioFile = res.files.first;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Audio Error: $e")));
    }
  }

  Future<void> startDubbing() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pehle video select karo!")));
      return;
    }

    if (!colabServerUrl.startsWith("http")) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pehle Colab Server URL daalo!")));
      _showServerSettings();
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.15;
      currentStatus = "1/4: Connecting to your Google Colab T4 GPU Server...";
      outputVideoUrl = null;
      dubbedDialogue = null;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse("$colabServerUrl/dub"));
      request.fields['target_lang'] = targetLanguage;

      setState(() {
        dubbingProgress = 0.35;
        currentStatus = "2/4: Uploading video & reference vocal to Colab...";
      });

      request.files.add(await http.MultipartFile.fromPath('video', selectedVideo!.path));

      if (refAudioFile != null && refAudioFile!.path != null) {
        request.files.add(await http.MultipartFile.fromPath('ref_audio', refAudioFile!.path!));
      }

      setState(() {
        dubbingProgress = 0.60;
        currentStatus = "3/4: Colab GPU: Whisper transcribing & XTTS-v2 cloning voice...";
      });

      var streamedRes = await request.send();
      var res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final String downloadPath = data["download_url"];

        setState(() {
          outputVideoUrl = "$colabServerUrl$downloadPath";
          dubbedDialogue = data["dialogue"];
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "Dubbing Complete! 100% Free Video Ready 🎉";
        });
      } else {
        throw Exception("Server Error (${res.statusCode}): ${res.body}");
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
        elevation: 0,
        backgroundColor: const Color(0xFF0F172A),
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 8),
            Text("Free AI Dubbing Studio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_rounded, color: Colors.white70),
            onPressed: _showServerSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server URL Status Card
            InkWell(
              onTap: _showServerSettings,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "GPU Server: $colabServerUrl",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                    const Icon(Icons.edit, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Video Selector Card
            InkWell(
              onTap: isProcessing ? null : pickVideo,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D2E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selectedVideo != null ? const Color(0xFF10B981) : const Color(0xFF334155),
                    width: selectedVideo != null ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      selectedVideo != null ? Icons.check_circle_rounded : Icons.video_file_rounded,
                      size: 40,
                      color: selectedVideo != null ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedVideo != null ? selectedVideo!.name : "Select Video to Dub",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Reference Vocal Upload Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF151D2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: Color(0xFFEC4899), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Character Voice Sample (Optional)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(
                          refAudioFile != null ? refAudioFile!.name : "Select MP3 to clone or uses video voice",
                          style: TextStyle(fontSize: 11, color: refAudioFile != null ? Colors.greenAccent : Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                    onPressed: isProcessing ? null : pickRefAudio,
                    child: Text(refAudioFile != null ? "Change" : "Browse", style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Target Language Dropdown
            DropdownButtonFormField<String>(
              value: targetLanguage,
              dropdownColor: const Color(0xFF1E293B),
              decoration: InputDecoration(
                labelText: "Target Dubbing Language",
                filled: true,
                fillColor: const Color(0xFF151D2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: isProcessing ? null : (val) => setState(() => targetLanguage = val!),
            ),

            const SizedBox(height: 20),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded, color: Colors.white),
                label: Text(
                  isProcessing ? "COLAB GPU PROCESSING..." : "START FREE DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                onPressed: isProcessing ? null : startDubbing,
              ),
            ),

            const SizedBox(height: 18),

            // Status Box
            if (isProcessing || currentStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF151D2E), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    if (isProcessing) ...[
                      LinearProgressIndicator(value: dubbingProgress, color: const Color(0xFF10B981)),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      currentStatus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: currentStatus.startsWith("Error") ? Colors.redAccent : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),

            // Result Card
            if (outputVideoUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFF10B981)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 44),
                    const SizedBox(height: 8),
                    const Text("Dubbed Video is Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF10B981))),
                    if (dubbedDialogue != null) ...[
                      const SizedBox(height: 6),
                      Text("\"$dubbedDialogue\"", textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text("Preview Video"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                            icon: const Icon(Icons.download_rounded),
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