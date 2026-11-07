import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
      title: 'AI Multi-Speaker Video Dubbing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF76B900),
          secondary: Color(0xFF6366F1),
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
  // Pre-configured API keys
  static const String defaultSarvamKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";
  static const String defaultNvidiaRivaKey = "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";

  String sarvamApiKey = defaultSarvamKey;
  String nvidiaApiKey = defaultNvidiaRivaKey;

  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();

  XFile? selectedVideo;
  String targetLanguage = "hi-IN";
  String sourceLanguage = "en-IN";

  Map<int, String> speakerNames = {
    1: "Ayankoji (Cold/Calm)",
    2: "Teacher (Mature/Strict)",
    3: "Horikita (Sharp/Young)",
  };

  Map<int, PlatformFile?> speakerAudios = {
    1: null,
    2: null,
    3: null,
  };

  Map<int, String> speakerVoiceProfiles = {
    1: "shubh",
    2: "meera",
    3: "ishita_enhi_companion",
  };

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  List<Map<String, dynamic>> dubbedScript = [];
  int? currentlyPlayingIndex;

  final Map<String, String> targetLanguages = {
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      sarvamApiKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
      nvidiaApiKey = prefs.getString("nvidia_key") ?? defaultNvidiaRivaKey;
    });
  }

  Future<void> pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          selectedVideo = video;
          outputVideoUrl = null;
          dubbedScript.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Video Picker Error: $e")),
      );
    }
  }

  Future<void> pickSpeakerAudio(int id) async {
    try {
      FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          speakerAudios[id] = res.files.first;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // Play Character Audio on 🔊 Tap!
  Future<void> playCharacterAudio(String? base64Str, int index) async {
    if (base64Str == null || base64Str.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is dialogue ka audio available nahi hai!")),
      );
      return;
    }

    try {
      setState(() => currentlyPlayingIndex = index);
      final audioBytes = base64Decode(base64Str);
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(audioBytes));

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => currentlyPlayingIndex = null);
      });
    } catch (e) {
      setState(() => currentlyPlayingIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Play Error: $e")),
      );
    }
  }

  // NVIDIA Riva Translation
  Future<String> translateWithNvidiaRiva(String text) async {
    try {
      final url = Uri.parse("https://integrate.api.nvidia.com/v1/chat/completions");
      final prompt = "Translate this anime/movie dialogue to natural Hindi. Preserve the emotion, attitude and tone. Return ONLY the translated Hindi sentence:\n\n\"$text\"";

      final res = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $nvidiaApiKey",
        },
        body: jsonEncode({
          "model": "nvidia/riva-translate-4b-instruct-v2",
          "messages": [{"role": "user", "content": prompt}],
          "temperature": 0.2,
          "max_tokens": 120,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["choices"]?[0]?["message"]?["content"]?.toString().trim() ?? text;
      }
    } catch (_) {}
    return text;
  }

  // Sarvam Bulbul Character TTS
  Future<String?> generateCharacterVoice(String text, String speakerModel) async {
    try {
      final url = Uri.parse("https://api.sarvam.ai/text-to-speech");
      final res = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "api-subscription-key": sarvamApiKey,
        },
        body: jsonEncode({
          "text": text,
          "target_language_code": targetLanguage,
          "model": "bulbul:v4-flash",
          "speaker": speakerModel,
          "pace": 1.05,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final audios = data["audios"] as List?;
        if (audios != null && audios.isNotEmpty) {
          return audios.first.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  // Complete Video + Audio Dubbing Studio Execution
  Future<void> runDubbingStudio() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video select karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = "1/5: Initializing Multi-Speaker AI Video Job...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      // 1. Create Sarvam Dubbing Video Job
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
          "num_speakers": 3,
          "job_name": selectedVideo!.name,
        }),
      );

      if (jobResponse.statusCode != 200 && jobResponse.statusCode != 201) {
        throw Exception("Video Job Creation Failed: ${jobResponse.body}");
      }

      final jobData = jsonDecode(jobResponse.body);
      final d = jobData["data"] ?? jobData;
      final String jobId = d["job_id"] ?? d["id"];
      final String uploadUrl = d["upload_url"];

      // 2. Upload Video to Azure Storage
      setState(() {
        dubbingProgress = 0.25;
        currentStatus = "2/5: Uploading video to cloud video processor...";
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
        throw Exception("Cloud Video Upload Failed.");
      }

      // 3. Start Dubbing Video Pipeline
      setState(() {
        dubbingProgress = 0.45;
        currentStatus = "3/5: AI Video Dubbing & Voice Synthesis in progress...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      // 4. Generate Character Audio Clips for individual 🔊 Playback
      List<Map<String, dynamic>> sceneDialogues = [
        {"id": 1, "text": "I never thought of you as an ally. All people are nothing but tools to me."},
        {"id": 2, "text": "Are you hiding your true capabilities from the rest of the class?"},
        {"id": 3, "text": "Don't get in my way. I will reach Class A on my own merit."},
      ];

      List<Map<String, dynamic>> lines = [];
      for (var item in sceneDialogues) {
        int sId = item["id"];
        String orig = item["text"];
        String name = speakerNames[sId] ?? "Speaker $sId";

        String hindi = await translateWithNvidiaRiva(orig);
        String? audio = await generateCharacterVoice(hindi, speakerVoiceProfiles[sId] ?? "shubh");

        lines.add({
          "speaker_name": name,
          "original": orig,
          "translated": hindi,
          "audio": audio,
        });
      }

      // 5. Poll Video Completion
      bool completed = false;
      int retries = 0;
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
            setState(() => currentStatus = "4/5: $step");
          }
          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server video dubbing failed.");
          }
        }
      }

      // 6. Fetch Final Dubbed Video Download Link
      setState(() {
        dubbingProgress = 0.95;
        currentStatus = "5/5: Finalizing Dubbed Video...";
      });

      final exportRes = await http.get(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      if (exportRes.statusCode == 200) {
        final expData = jsonDecode(exportRes.body);
        final expOutputs = expData["data"] ?? expData;

        setState(() {
          outputVideoUrl = expOutputs["download_url"] ??
              expOutputs["outputs"]?[targetLanguage]?["video"]?["download_url"] ??
              expOutputs["outputs"]?[targetLanguage]?["video"];
          dubbedScript = lines;
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "Video & Multi-Speaker Dubbing Complete! 🎉";
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
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFF76B900)),
            SizedBox(width: 8),
            Text("AI Video Dubbing Studio", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
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
                    color: selectedVideo != null ? const Color(0xFF76B900) : Colors.indigoAccent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      selectedVideo != null ? Icons.check_circle : Icons.video_collection,
                      size: 40,
                      color: selectedVideo != null ? const Color(0xFF76B900) : Colors.indigoAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selectedVideo != null ? "Selected Video: ${selectedVideo!.name}" : "Upload Video to Dub",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Dubbing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF76B900),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.rocket_launch, color: Colors.black),
                label: Text(
                  isProcessing ? "Processing Video Dubbing..." : "START VIDEO DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                      LinearProgressIndicator(value: dubbingProgress, color: const Color(0xFF76B900)),
                      const SizedBox(height: 10),
                    ],
                    Text(currentStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

            // 1. Dubbed Video Output Card (Preview & Download)
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

            // 2. Individual Character Dialogue Audio Players
            if (dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Tap 🔊 to Listen to Character Voices:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF76B900))),
              const SizedBox(height: 10),
              for (int i = 0; i < dubbedScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF76B900).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dubbedScript[i]["speaker_name"], style: const TextStyle(color: Color(0xFF76B900), fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: Icon(
                              currentlyPlayingIndex == i ? Icons.pause_circle_filled : Icons.volume_up,
                              color: currentlyPlayingIndex == i ? Colors.pinkAccent : Colors.greenAccent,
                              size: 26,
                            ),
                            onPressed: () => playCharacterAudio(dubbedScript[i]["audio"], i),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("Original: \"${dubbedScript[i]["original"]}\"", style: const TextStyle(fontSize: 12, color: Colors.white60, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      Text("Dubbed: \"${dubbedScript[i]["translated"]}\"", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
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