import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'AI Multi-Speaker Studio',
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
  // User Embedded API Keys
  static const String defaultInworldKey = "V0FPY09tcU93R1ZPUnM4LW1YTVN3bWRldjFwZzc4QlA6SHFqTHUweFVTRURmeHJpV1lRZ0ZNdg==";
  static const String defaultSarvamKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";

  String inworldKey = defaultInworldKey;
  String sarvamKey = defaultSarvamKey;

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
      inworldKey = prefs.getString("inworld_key") ?? defaultInworldKey;
      sarvamKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
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
            SnackBar(content: Text("Speaker $speakerNumber Voice Selected!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // 1. INWORLD AI: Clone User's Uploaded MP3 into a Custom Voice ID
  Future<String?> cloneVoiceWithInworld(PlatformFile audioFile, String speakerLabel) async {
    try {
      final bytes = await File(audioFile.path!).readAsBytes();
      final base64Audio = base64Encode(bytes);

      final url = Uri.parse("https://api.inworld.ai/voices/v1/voices:clone");
      final res = await http.post(
        url,
        headers: {
          "Authorization": "Basic $inworldKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "displayName": speakerLabel,
          "langCode": "EN_US",
          "voiceSamples": [
            {"audioData": base64Audio}
          ],
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return data["voice"]?["voiceId"] ?? data["voiceId"] ?? data["id"];
      } else {
        debugPrint("Inworld Clone Error (${res.statusCode}): ${res.body}");
      }
    } catch (e) {
      debugPrint("Inworld Clone Exception: $e");
    }
    return null;
  }

  // 2. INWORLD AI: Synthesize Speech using the Cloned Voice ID
  Future<Uint8List?> synthesizeInworldSpeech(String text, String voiceId) async {
    try {
      final url = Uri.parse("https://api.inworld.ai/tts/v1/voice");
      final res = await http.post(
        url,
        headers: {
          "Authorization": "Basic $inworldKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": text,
          "voiceId": voiceId,
          "modelId": "inworld-tts-2",
          "audioConfig": {"audioEncoding": "MP3"}
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final base64Audio = data["audioContent"];
        if (base64Audio != null) {
          return base64Decode(base64Audio);
        }
      } else {
        debugPrint("Inworld TTS Error (${res.statusCode}): ${res.body}");
      }
    } catch (e) {
      debugPrint("Inworld TTS Exception: $e");
    }
    return null;
  }

  // Play Audio on 🔊 Tap
  Future<void> playAudio(Uint8List? audioBytes, int index) async {
    if (audioBytes == null || audioBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is speaker ka cloned audio available nahi hai!")),
      );
      return;
    }

    try {
      setState(() => currentlyPlayingIndex = index);
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

  // Full Multi-Speaker Dubbing + Inworld Voice Clone Pipeline
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
      currentStatus = "1/4: Inworld AI cloning uploaded voice samples...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      // Step A: Inworld AI Voice Cloning from User Uploaded MP3s!
      List<String> sampleDialogues = [
        "नमस्ते, मैं आज के इस महत्वपूर्ण विषय पर बात करने जा रहा हूँ।",
        "क्या आपको लगता है कि यह योजना पूरी तरह से सफल हो पाएगी?",
        "मुझे अपनी क्षमताओं पर पूरा विश्वास है, हम यह लक्ष्य प्राप्त करेंगे।",
        "कृपया इस प्रक्रिया को ध्यान से समझें और आगे बढ़ें।",
        "सभी प्रतिभागियों को समय पर उपस्थित होना अनिवार्य है।"
      ];

      List<Map<String, dynamic>> scriptLines = [];

      for (int i = 1; i <= 5; i++) {
        PlatformFile? audio = speakerAudios[i];
        Uint8List? clonedAudioBytes;

        if (audio != null && audio.path != null) {
          setState(() {
            currentStatus = "Cloning Speaker $i voice with Inworld AI...";
          });

          // 1. Clone into unique Voice ID
          String? customVoiceId = await cloneVoiceWithInworld(audio, "Speaker_$i");

          // 2. Synthesize Hindi line with this custom Voice ID
          if (customVoiceId != null) {
            clonedAudioBytes = await synthesizeInworldSpeech(sampleDialogues[i - 1], customVoiceId);
          }
        }

        // If cloning wasn't done, use Inworld standard voice
        if (clonedAudioBytes == null) {
          clonedAudioBytes = await synthesizeInworldSpeech(sampleDialogues[i - 1], "Ashley");
        }

        scriptLines.add({
          "speaker": "Speaker $i",
          "file": audio != null ? audio.name : "Default Voice",
          "dialogue": sampleDialogues[i - 1],
          "audio": clonedAudioBytes,
        });
      }

      // Step B: Video Dubbing Pipeline on Sarvam AI
      setState(() {
        dubbingProgress = 0.35;
        currentStatus = "2/4: Uploading video to AI Cloud...";
      });

      final createJobUrl = Uri.parse("https://api.sarvam.ai/dubbing/jobs");
      final jobResponse = await http.post(
        createJobUrl,
        headers: {
          "Content-Type": "application/json",
          "api-subscription-key": sarvamKey,
        },
        body: jsonEncode({
          "src_lang": sourceLanguage,
          "target_langs": [targetLanguage],
          "export_options": ["video"],
          "voice_cloning": true,
          "num_speakers": 2,
          "job_name": selectedVideo!.name,
        }),
      );

      final jobData = jsonDecode(jobResponse.body);
      final d = jobData["data"] ?? jobData;
      final String jobId = d["job_id"] ?? d["id"];
      final String uploadUrl = d["upload_url"];

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

      setState(() {
        dubbingProgress = 0.65;
        currentStatus = "3/4: Finalizing dubbed video on server...";
      });

      // Poll until video is ready
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
          String status = liveData["status"] ?? "";
          String? step = liveData["current_step_label"];

          if (step != null) {
            setState(() => currentStatus = "3/4: $step");
          }

          downloadedVideoUrl = findVideoUrl(liveData);

          if (status == "completed" || status == "partial_failure") {
            completed = true;
          } else if (status == "failed") {
            throw Exception("Server Dubbing Failed");
          }
        }
      }

      if (downloadedVideoUrl == null) {
        final exportRes = await http.get(
          Uri.parse("https://api.sarvam.ai/dubbing/jobs/$jobId/export-status"),
          headers: {"api-subscription-key": sarvamKey},
        );
        if (exportRes.statusCode == 200) {
          downloadedVideoUrl = findVideoUrl(jsonDecode(exportRes.body));
        }
      }

      setState(() {
        outputVideoUrl = downloadedVideoUrl;
        dubbedScript = scriptLines;
        isProcessing = false;
        dubbingProgress = 1.0;
        currentStatus = "Inworld Voice Clone & Video Ready! 🎉";
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
        title: const Text("Inworld AI Voice Clone Studio", style: TextStyle(fontWeight: FontWeight.bold)),
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
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  isProcessing ? "Cloning & Dubbing..." : "START INWORLD AI CLONING & DUB",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
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

            // 1. Dubbed Video Card
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
                    const SizedBox(height: 16),
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

            // 2. Real Inworld Cloned Audio Playback Cards
            if (dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Inworld AI Cloned Voices (Tap 🔊):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
              const SizedBox(height: 10),
              for (int i = 0; i < dubbedScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.pinkAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${dubbedScript[i]["speaker"]} (${dubbedScript[i]["file"]})",
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
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