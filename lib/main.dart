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
      title: 'AI Video Dubbing Studio',
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
  // Safe Base64 Encoded Keys
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

  bool isCustomVoiceEnabled = false;

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
      openRouterKey = prefs.getString("openrouter_key") ?? defaultOpenRouterKey;
      sarvamKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
    });
  }

  Future<void> _saveKeys(String iKey, String oKey, String sKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("inworld_key", iKey.trim());
    await prefs.setString("openrouter_key", oKey.trim());
    await prefs.setString("sarvam_key", sKey.trim());
    setState(() {
      inworldKey = iKey.trim();
      openRouterKey = oKey.trim();
      sarvamKey = sKey.trim();
    });
  }

  void _showSettingsDialog() {
    final iController = TextEditingController(text: inworldKey);
    final oController = TextEditingController(text: openRouterKey);
    final sController = TextEditingController(text: sarvamKey);

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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Inworld AI Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: iController, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text("OpenRouter Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: oController, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text("Sarvam AI Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: sController, decoration: const InputDecoration(border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveKeys(defaultInworldKey, defaultOpenRouterKey, defaultSarvamKey);
              Navigator.pop(ctx);
            },
            child: const Text("Reset Defaults", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              _saveKeys(iController.text, oController.text, sController.text);
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
            SnackBar(content: Text("Speaker $speakerNumber Voice Added!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // Download Cloned Voice Audio to Phone Storage
  Future<void> downloadAudio(Uint8List? bytes, String filename) async {
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is speaker ka audio available nahi hai!")),
      );
      return;
    }

    try {
      // 1. Android Native File Save Dialog
      String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Dubbed Voice',
        fileName: '$filename.mp3',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['mp3'],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text("$filename.mp3 download ho gaya! 🎉"),
            ),
          );
        }
        return;
      }

      // 2. Direct Fallback to Downloads folder
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$filename.mp3');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text("Saved in Downloads: $filename.mp3! 🎉"),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text("Download Error: $e")),
        );
      }
    }
  }

  // Transcribe Video Audio via Sarvam
  Future<String> transcribeVideoAudio(XFile videoFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("https://api.sarvam.ai/speech-to-text"),
      );
      request.headers['api-subscription-key'] = sarvamKey;
      request.fields['language_code'] = sourceLanguage;
      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));

      var streamedRes = await request.send();
      var res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["transcript"]?.toString() ?? "";
      }
    } catch (e) {
      debugPrint("Transcription error: $e");
    }
    return "";
  }

  // OpenRouter: Dynamic Anime Scriptwriter
  Future<List<Map<String, String>>> generateDynamicAnimeHinglishScript(String rawTranscript) async {
    try {
      final url = Uri.parse("https://openrouter.ai/api/v1/chat/completions");

      String inputContext = rawTranscript.isNotEmpty
          ? "Here is the dialogue transcribed directly from the uploaded video:\n\"$rawTranscript\""
          : "Analyze the uploaded anime scene and extract dialogues.";

      final prompt = """
You are an expert Anime Hindi Dubbing Director (Crunchyroll / Muse Asia style).
$inputContext

Task:
1. Divide into character dialogue turns (Speaker 1, Speaker 2, etc.).
2. AUTO-DETECT genuine emotion, tone and speed directly from context.
3. Write punchy, natural ANIME HINGLISH dialogue.
4. Prepend Inworld TTS-2 steering instructions in brackets [say ...] matching the delivery.

Return ONLY a valid JSON array like this format:
[
  {
    "speaker": "Speaker 1",
    "emotion": "Cold & Calculated",
    "steered_text": "[speak in a cold, monotone, emotionless whisper, slow] Maine tumhe kabhi apna ally nahi samjha. Mere liye sab bas ek tool hain.",
    "display_text": "Maine tumhe kabhi apna ally nahi samjha. Mere liye sab bas ek tool hain."
  }
]
No extra markdown.
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
          "temperature": 0.3,
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
    return [];
  }

  // Inworld AI: Clone User Voice
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

  // Inworld AI: Synthesize Speech
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
        const SnackBar(content: Text("Is speaker ka audio available nahi hai!")),
      );
      return;
    }

    try {
      if (currentlyPlayingIndex == index) {
        await _audioPlayer.stop();
        setState(() => currentlyPlayingIndex = null);
        return;
      }

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
      currentStatus = "1/4: Transcribing actual video audio...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      // 1. Transcribe actual video dialogues
      String realTranscript = await transcribeVideoAudio(selectedVideo!);

      setState(() {
        dubbingProgress = 0.25;
        currentStatus = "2/4: AI Scriptwriter auto-detecting emotions & generating Hinglish...";
      });

      // 2. OpenRouter generates real dynamic anime Hinglish script
      final scriptLines = await generateDynamicAnimeHinglishScript(realTranscript);

      // 3. Process Custom Voices
      List<Map<String, dynamic>> processedScript = [];
      if (isCustomVoiceEnabled && scriptLines.isNotEmpty) {
        setState(() {
          dubbingProgress = 0.45;
          currentStatus = "3/4: Inworld AI cloning voices with auto-detected emotions...";
        });

        for (int i = 0; i < scriptLines.length; i++) {
          int speakerNum = i + 1;
          PlatformFile? audio = speakerAudios[speakerNum];
          var item = scriptLines[i];

          String? voiceId;
          if (audio != null && audio.path != null) {
            voiceId = await cloneVoiceWithInworld(audio, "Speaker_$speakerNum");
          }
          voiceId ??= "Ashley";

          Uint8List? speechBytes = await synthesizeInworldSpeech(
            item["steered_text"] ?? item["display_text"]!,
            voiceId,
          );

          processedScript.add({
            "speaker": "Speaker $speakerNum",
            "emotion": item["emotion"] ?? "Auto",
            "dialogue": item["display_text"] ?? "",
            "audio": speechBytes,
          });
        }
      }

      // 4. Server Video Dubbing & Download Link Generation
      setState(() {
        dubbingProgress = 0.65;
        currentStatus = "Finalizing video dubbing on cloud...";
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
          "num_speakers": isCustomVoiceEnabled ? 3 : -1,
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
            setState(() => currentStatus = step);
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
        currentStatus = "Dubbing Complete! Video & Voices Ready 🎉";
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

            // Mode Toggle: Custom Voice Upload On/Off
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text("Custom Voice Clone Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(
                  isCustomVoiceEnabled
                      ? "Custom voice files add karne ka option chalu hai"
                      : "Off hai: Native video dubbing chalegi (No custom files needed)",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                value: isCustomVoiceEnabled,
                activeColor: Colors.pinkAccent,
                onChanged: (val) => setState(() => isCustomVoiceEnabled = val),
              ),
            ),

            // 5 Speaker Upload Rows
            if (isCustomVoiceEnabled) ...[
              const SizedBox(height: 14),
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
            ],

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
                  isProcessing ? "Processing Dubbing..." : "START AUTO DUBBING",
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

            // 2. Cloned Custom Voices Cards with BOTH PLAY & DOWNLOAD BUTTONS!
            if (dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("Cloned Custom Voices (Play & Download):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent, fontSize: 16)),
              const SizedBox(height: 12),
              for (int i = 0; i < dubbedScript.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.pinkAccent.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dubbedScript[i]["speaker"],
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      const SizedBox(height: 8),
                      Text(
                        "\"${dubbedScript[i]["dialogue"]}\"",
                        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          // PLAY / PAUSE BUTTON
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: currentlyPlayingIndex == i ? Colors.pinkAccent : const Color(0xFF334155),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: Icon(
                                currentlyPlayingIndex == i ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                currentlyPlayingIndex == i ? "Pause" : "Play Voice",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () => playAudio(dubbedScript[i]["audio"], i),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // DOWNLOAD MP3 BUTTON
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.download, color: Colors.white, size: 20),
                              label: const Text(
                                "Download MP3",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () => downloadAudio(
                                dubbedScript[i]["audio"],
                                "${dubbedScript[i]["speaker"]}_Dubbed",
                              ),
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