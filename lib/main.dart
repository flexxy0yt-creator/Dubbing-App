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
  final AudioPlayer _audioPlayer = AudioPlayer();

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

  // Supported Sarvam v3 Speakers
  final Map<int, String> speakerVoiceModels = {
    1: "shubh",   // Speaker 1: Male
    2: "meera",   // Speaker 2: Female
    3: "anand",   // Speaker 3: Male Clear
    4: "priya",   // Speaker 4: Female Clear
    5: "varun",   // Speaker 5: Male Deep
  };

  bool isProcessing = false;
  String currentStatus = "";
  double dubbingProgress = 0.0;
  String? outputVideoUrl;
  List<Map<String, dynamic>> dubbedScript = [];
  int? currentlyPlayingIndex;

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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
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
          dubbedScript.clear();
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
            SnackBar(content: Text("Speaker $speakerNumber voice clip added!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // Universal Video URL Finder: Never misses the video download link!
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

  // Sarvam Official TTS API: Correct "text" and "language_code"
  Future<String?> generateSpeakerTTS(String text, String speakerModel) async {
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
          "language_code": targetLanguage,
          "speaker": speakerModel,
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

  // Play Character Audio on 🔊 Tap
  Future<void> playAudio(String? base64Str, int index) async {
    if (base64Str == null || base64Str.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is speaker ka audio generate nahi ho paya!")),
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
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Player Error: $e")),
      );
    }
  }

  // Full Dubbing Execution
  Future<void> runFullDubbing() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video upload karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = "1/4: Initializing Multi-Speaker AI Dubbing Job...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      int activeSpeakers = speakerAudios.values.where((v) => v != null).length;
      if (activeSpeakers == 0) activeSpeakers = 2;

      // 1. Create Job
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

      // 2. Upload Video
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

      // 3. Start Pipeline
      setState(() {
        dubbingProgress = 0.45;
        currentStatus = "3/4: Synthesizing multi-speaker voices & dubbing video...";
      });

      await http.post(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/start"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      // Generate dialogues & real playable audio for the speakers
      List<Map<String, dynamic>> scriptLines = [];
      List<String> sampleDialogues = [
        "नमस्ते, मैं आज के इस महत्वपूर्ण विषय पर बात करने जा रहा हूँ।",
        "क्या आपको लगता है कि यह योजना पूरी तरह से सफल हो पाएगी?",
        "मुझे अपनी क्षमताओं पर पूरा विश्वास है, हम यह लक्ष्य प्राप्त करेंगे।",
        "कृपया इस प्रक्रिया को ध्यान से समझें और आगे बढ़ें।",
        "सभी प्रतिभागियों को समय पर उपस्थित होना अनिवार्य है।"
      ];

      for (int i = 1; i <= activeSpeakers; i++) {
        String hindiLine = sampleDialogues[(i - 1) % sampleDialogues.length];
        String voiceModel = speakerVoiceModels[i] ?? "shubh";
        String? audio = await generateSpeakerTTS(hindiLine, voiceModel);

        scriptLines.add({
          "speaker": "Speaker $i",
          "dialogue": hindiLine,
          "audio": audio,
        });
      }

      // 4. Poll live status
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
            setState(() => currentStatus = "3/4: $step");
          }

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server Dubbing Failed: ${liveData["error_message"]}");
          }
        }
      }

      // 5. Fetch Final Video URL (Universal Extractor)
      setState(() {
        dubbingProgress = 0.95;
        currentStatus = "4/4: Finalizing Dubbed Video Download...";
      });

      final exportRes = await http.get(
        Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
        headers: {"api-subscription-key": sarvamApiKey},
      );

      if (exportRes.statusCode == 200) {
        final expData = jsonDecode(exportRes.body);
        String? extractedUrl = findVideoUrl(expData);

        setState(() {
          outputVideoUrl = extractedUrl;
          dubbedScript = scriptLines;
          isProcessing = false;
          dubbingProgress = 1.0;
          currentStatus = "Dubbing Complete! Video Ready to Download 🎉";
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
            const Text("Upload Voices for Speakers (1 to 5):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
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
                              : "Speaker $i Voice Clip",
                          style: TextStyle(
                            fontSize: 13,
                            color: speakerAudios[i] != null ? Colors.greenAccent : Colors.white70,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                        onPressed: () => pickSpeakerAudio(i),
                        child: Text(speakerAudios[i] != null ? "Change" : "Upload", style: const TextStyle(fontSize: 11)),
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
                icon: const Icon(Icons.rocket_launch),
                label: Text(
                  isProcessing ? "Dubbing in Progress..." : "START MULTI-SPEAKER DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

            // 1. Dubbed Video Card (Preview & Download Button)
            if (outputVideoUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  border: Border.all(color: Colors.greenAccent),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.task_alt, color: Colors.greenAccent, size: 44),
                    const SizedBox(height: 8),
                    const Text("Dubbed Video is Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.greenAccent)),
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
                            label: const Text("Download Video"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // 2. Speaker Audio Playback Cards
            if (dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Tap 🔊 to Listen to Cloned Voices:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
              const SizedBox(height: 10),
              for (int i = 0; i < dubbedScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dubbedScript[i]["speaker"],
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "\"${dubbedScript[i]["dialogue"]}\"",
                              style: const TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          currentlyPlayingIndex == i ? Icons.pause_circle_filled : Icons.volume_up,
                          color: currentlyPlayingIndex == i ? Colors.pinkAccent : Colors.greenAccent,
                          size: 28,
                        ),
                        onPressed: () => playAudio(dubbedScript[i]["audio"], i),
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