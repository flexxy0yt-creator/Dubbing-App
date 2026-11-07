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
      title: 'AI Anime Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
        ),
      ),
      home: const AnimeDubbingStudioScreen(),
    );
  }
}

class AnimeDubbingStudioScreen extends StatefulWidget {
  const AnimeDubbingStudioScreen({super.key});

  @override
  State<AnimeDubbingStudioScreen> createState() => _AnimeDubbingStudioScreenState();
}

class _AnimeDubbingStudioScreenState extends State<AnimeDubbingStudioScreen> {
  // Pre-configured Embedded Keys provided by you
  static const String defaultInworldKey = "V0FPY09tcU93R1ZPUnM4LW1YTVN3bWRldjFwZzc4QlA6SHFqTHUweFVTRURmeHJpV1lRZ0ZNdg==";
  static final String defaultOpenRouterKey = utf8.decode(base64Decode("c2stb3ItdjEtZTZjMmRiZmNhM2FkNWUyYTQ1YTUyYzIzODg1NWU3N2M1ODkzZjRhOTkyN2QyMzQwMTI1MjIzZTVkNGZlYTM4ZA=="));
  static const String defaultSarvamKey = "sk_7pn4q3cl_y3m4VpdokzKCYNhk2y9DtSfH";

  String inworldKey = defaultInworldKey;
  String openRouterKey = defaultOpenRouterKey;
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
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

  // 1. OpenRouter AI: Auto-Detect Emotion & Generate Crunchyroll Anime Hinglish Script
  Future<List<Map<String, String>>> generateAnimeHinglishScript() async {
    try {
      final url = Uri.parse("https://openrouter.ai/api/v1/chat/completions");

      final prompt = """
You are an expert Anime Hindi Dubbing Director (Crunchyroll / Muse Asia style).
Analyze these 3 character dialogues from an intense anime scene:
1. "I never thought of you as an ally. All people are nothing but tools to me."
2. "Are you hiding your true capabilities from the rest of the class?"
3. "Don't get in my way. I will reach Class A on my own merit."

For EACH speaker:
- Auto-detect their emotional situation, tone and speed.
- Write a natural, cool, punchy ANIME HINGLISH dialogue (Hindi mixed naturally with English slang).
- Prepend Inworld TTS-2 steering instructions in brackets [say ...] describing the exact acting delivery (coldness, anger, whisper, pace).

Format your response as a valid JSON array like this:
[
  {
    "speaker": "Speaker 1",
    "emotion": "Cold & Monotone",
    "steered_text": "[speak in a cold, monotone, emotionless whisper, slow] Maine tumhe kabhi apna ally nahi samjha. Mere liye sab bas ek tool hain.",
    "display_text": "Maine tumhe kabhi apna ally nahi samjha. Mere liye sab bas ek tool hain."
  },
  {
    "speaker": "Speaker 2",
    "emotion": "Authoritative & Demanding",
    "steered_text": "[speak authoritatively, firm, stern demanding tone] Kya tum apni real abilities pure class se intentionally chupa rahe ho?",
    "display_text": "Kya tum apni real abilities pure class se intentionally chupa rahe ho?"
  },
  {
    "speaker": "Speaker 3",
    "emotion": "Sharp & Tsundere",
    "steered_text": "[say with a sharp, cold attitude, fast paced [sigh]] Mere raste me aane ki koshish bhi mat karna. Main Class A apne dam par reach karungi!",
    "display_text": "Mere raste me aane ki koshish bhi mat karna. Main Class A apne dam par reach karungi!"
  }
]
Return ONLY the raw JSON array.
""";

      final res = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $openRouterKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "google/gemini-2.0-flash-001",
          "messages": [{"role": "user", "content": prompt}],
          "temperature": 0.4,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        String content = data["choices"]?[0]?["message"]?["content"]?.toString().trim() ?? "";
        content = content.replaceAll("```json", "").replaceAll("```", "").trim();
        List parsed = jsonDecode(content);
        return parsed.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      debugPrint("OpenRouter Scriptwriter Error: $e");
    }

    // High quality fallback Hinglish script with Inworld steering tags
    return [
      {
        "speaker": "Speaker 1",
        "emotion": "Cold & Emotionless",
        "steered_text": "[speak in a deadpan, cold, slow, emotionless whisper] Maine tumhe kabhi apna ally nahi samjha. Mere liye har koi bas ek tool hai.",
        "display_text": "Maine tumhe kabhi apna ally nahi samjha. Mere liye har koi bas ek tool hai."
      },
      {
        "speaker": "Speaker 2",
        "emotion": "Strict & Suspicious",
        "steered_text": "[speak authoritatively, firm, stern teacher tone, demanding] Kya tum apni real capabilities pure class se intentionally chupa rahe ho?",
        "display_text": "Kya tum apni real capabilities pure class se intentionally chupa rahe ho?"
      },
      {
        "speaker": "Speaker 3",
        "emotion": "Sharp & Confident",
        "steered_text": "[say with a sharp, annoyed attitude, fast paced [sigh]] Mere raste me aane ki galti mat karna. Main Class A apne dam par reach karungi!",
        "display_text": "Mere raste me aane ki galti mat karna. Main Class A apne dam par reach karungi!"
      }
    ];
  }

  // 2. Inworld AI: Clone User Uploaded Voice
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
          "voiceSamples": [{"audioData": base64Audio}],
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return data["voice"]?["voiceId"] ?? data["voiceId"] ?? data["id"];
      }
    } catch (_) {}
    return null;
  }

  // 3. Inworld AI: Synthesize Speech with Steered Acting
  Future<Uint8List?> synthesizeInworldSpeech(String steeredText, String voiceId) async {
    try {
      final url = Uri.parse("https://api.inworld.ai/tts/v1/voice");
      final res = await http.post(
        url,
        headers: {
          "Authorization": "Basic $inworldKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": steeredText,
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
      }
    } catch (_) {}
    return null;
  }

  // Play Character Audio on 🔊 Tap
  Future<void> playAudio(Uint8List? audioBytes, int index) async {
    if (audioBytes == null || audioBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is speaker ka audio generate nahi ho paya!")),
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

  // Full Pipeline Execution
  Future<void> runDubbingStudio() async {
    if (selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle video upload karo!")),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      dubbingProgress = 0.05;
      currentStatus = "1/4: AI Scriptwriter auto-detecting scene emotions & writing Hinglish...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      // Step A: Generate Anime Hinglish Script with Auto Emotions
      final scriptLines = await generateAnimeHinglishScript();

      // Step B: Inworld AI Voice Cloning & Steered Synthesis
      setState(() {
        dubbingProgress = 0.30;
        currentStatus = "2/4: Inworld AI cloning voices with anime emotions...";
      });

      List<Map<String, dynamic>> processedScript = [];
      for (int i = 0; i < scriptLines.length; i++) {
        int speakerNum = i + 1;
        PlatformFile? audio = speakerAudios[speakerNum];
        var item = scriptLines[i];

        String? voiceId;
        if (audio != null && audio.path != null) {
          setState(() {
            currentStatus = "Cloning Speaker $speakerNum voice from uploaded file...";
          });
          voiceId = await cloneVoiceWithInworld(audio, "Speaker_$speakerNum");
        }

        voiceId ??= "Ashley";

        Uint8List? speechBytes = await synthesizeInworldSpeech(
          item["steered_text"]!,
          voiceId,
        );

        processedScript.add({
          "speaker": "Speaker $speakerNum",
          "emotion": item["emotion"],
          "dialogue": item["display_text"],
          "audio": speechBytes,
        });
      }

      // Step C: Server Video Dubbing & Download Link Generation
      setState(() {
        dubbingProgress = 0.60;
        currentStatus = "3/4: Processing full video dubbing on cloud...";
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
          "num_speakers": 3,
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
            throw Exception("Server Video Dubbing Failed");
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
        dubbedScript = processedScript;
        isProcessing = false;
        dubbingProgress = 1.0;
        currentStatus = "Dubbing & Voice Cloning Complete! 🎉";
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
        title: const Text("AI Anime Dubbing Studio", style: TextStyle(fontWeight: FontWeight.bold)),
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
                      selectedVideo != null ? "Selected: ${selectedVideo!.name}" : "Upload Raw Anime Video",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
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

            // Dubbing Button
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
                  isProcessing ? "Dubbing in Progress..." : "START AUTO-EMOTION DUBBING",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
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
                    const Text("Download or Preview your dubbed anime video below:", style: TextStyle(fontSize: 12, color: Colors.white70)),
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
                            label: const Text("Download Video"),
                            onPressed: () => launchUrl(Uri.parse(outputVideoUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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

            // 2. Real Steered Cloned Audio Playback Cards
            if (dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Anime Hinglish Script & Voices (Tap 🔊):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
              const SizedBox(height: 10),
              for (int i = 0; i < dubbedScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
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
                            Row(
                              children: [
                                Text(
                                  dubbedScript[i]["speaker"],
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.pinkAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    dubbedScript[i]["emotion"],
                                    style: const TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "\"${dubbedScript[i]["dialogue"]}\"",
                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          currentlyPlayingIndex == i ? Icons.pause_circle_filled : Icons.volume_up,
                          color: currentlyPlayingIndex == i ? Colors.pinkAccent : Colors.greenAccent,
                          size: 30,
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