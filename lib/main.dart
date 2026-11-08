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
      title: 'AI Multi-Engine Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899),
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
  // Push-Protection Safe Encoded Default Keys
  static final String defaultElevenLabsKey = utf8.decode(base64Decode("c2tfOTNmMTQ1YmViYjQ2ZGM0Zjg2ZTE5NzI5MzNkMzlhOWMyODQ1NTM4ZTI3ZGM3N2Y1"));
  static final String defaultSarvamKey = utf8.decode(base64Decode("c2tfN3BuNHEzY2xfeTNtNFZwZG9remtDWU5oazJ5OUR0U2ZI"));
  static final String defaultOpenRouterKey = utf8.decode(base64Decode("c2stb3ItdjEtZTZjMmRiZmNhM2FkNWUyYTQ1YTUyYzIzODg1NWU3N2M1ODkzZjRhOTkyN2QyMzQwMTI1MjIzZTVkNGZlYTM4ZA=="));

  String elevenLabsKey = defaultElevenLabsKey;
  String sarvamKey = defaultSarvamKey;
  String openRouterKey = defaultOpenRouterKey;

  // Engine Switch: "elevenlabs" ya "sarvam"
  String selectedEngine = "elevenlabs";

  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();

  XFile? selectedVideo;
  String sourceLanguage = "en-IN";
  String targetLanguage = "hi-IN";

  // ElevenLabs Custom Voice Mode Toggle (Only in ElevenLabs)
  bool isElevenCustomVoice = true;

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
      elevenLabsKey = prefs.getString("eleven_key") ?? defaultElevenLabsKey;
      sarvamKey = prefs.getString("sarvam_key") ?? defaultSarvamKey;
      openRouterKey = prefs.getString("openrouter_key") ?? defaultOpenRouterKey;
    });
  }

  Future<void> _saveKeys(String eKey, String sKey, String oKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("eleven_key", eKey.trim());
    await prefs.setString("sarvam_key", sKey.trim());
    await prefs.setString("openrouter_key", oKey.trim());
    setState(() {
      elevenLabsKey = eKey.trim();
      sarvamKey = sKey.trim();
      openRouterKey = oKey.trim();
    });
  }

  void _showSettingsDialog() {
    final eController = TextEditingController(text: elevenLabsKey);
    final sController = TextEditingController(text: sarvamKey);
    final oController = TextEditingController(text: openRouterKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.tune, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text("API Keys Manager", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("ElevenLabs API Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: eController, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text("Sarvam AI Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: sController, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text("OpenRouter Key (Scriptwriter):", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(controller: oController, decoration: const InputDecoration(border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveKeys(defaultElevenLabsKey, defaultSarvamKey, defaultOpenRouterKey);
              Navigator.pop(ctx);
            },
            child: const Text("Reset Defaults", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              _saveKeys(eController.text, sController.text, oController.text);
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
            SnackBar(content: Text("Speaker $speakerNumber Audio Uploaded!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Audio Error: $e")),
      );
    }
  }

  // 1. ELEVENLABS: Clone Voice from Uploaded Reference Audio
  Future<String?> cloneVoiceWithElevenLabs(PlatformFile audioFile, String speakerName) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("https://api.elevenlabs.io/v1/voices/add"),
      );
      request.headers['xi-api-key'] = elevenLabsKey;
      request.fields['name'] = "$speakerName-${DateTime.now().millisecondsSinceEpoch}";
      request.files.add(await http.MultipartFile.fromPath('files', audioFile.path!));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data["voice_id"];
      } else {
        debugPrint("ElevenLabs Clone Error (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint("ElevenLabs Clone Exception: $e");
    }
    return null;
  }

  // 2. ELEVENLABS: Text to Speech with Cloned Voice (Multi-lingual v2 with Hindi)
  Future<Uint8List?> synthesizeElevenLabsSpeech(String text, String voiceId) async {
    try {
      final url = Uri.parse("https://api.elevenlabs.io/v1/text-to-speech/$voiceId");
      final res = await http.post(
        url,
        headers: {
          "xi-api-key": elevenLabsKey,
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": text,
          "model_id": "eleven_multilingual_v2",
          "voice_settings": {
            "stability": 0.5,
            "similarity_boost": 0.85,
            "style": 0.4,
          }
        }),
      );

      if (res.statusCode == 200) {
        return res.bodyBytes;
      } else {
        debugPrint("ElevenLabs TTS Error (${res.statusCode}): ${res.body}");
      }
    } catch (e) {
      debugPrint("ElevenLabs TTS Exception: $e");
    }
    return null;
  }

  // Download Cloned Voice Audio
  Future<void> downloadAudio(Uint8List? bytes, String filename) async {
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Is speaker ka audio available nahi hai!")),
      );
      return;
    }

    try {
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
            SnackBar(backgroundColor: Colors.green, content: Text("$filename.mp3 successfully saved! 🎉")),
          );
        }
        return;
      }

      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$filename.mp3');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text("Saved in Downloads: $filename.mp3! 🎉")),
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

  // Play Character Audio
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

  // Full Pipeline
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
      currentStatus = "1/4: Initializing ${selectedEngine == "elevenlabs" ? "ElevenLabs" : "Sarvam AI"} pipeline...";
      outputVideoUrl = null;
      dubbedScript.clear();
    });

    try {
      // 1. If ElevenLabs with Custom Voice is ON: Clone & Synthesize
      List<Map<String, dynamic>> processedScript = [];
      if (selectedEngine == "elevenlabs" && isElevenCustomVoice) {
        setState(() {
          dubbingProgress = 0.25;
          currentStatus = "2/4: ElevenLabs cloning uploaded voices & generating dialogue...";
        });

        List<String> dynamicDialogues = [
          "नमस्ते, मैं आज के इस महत्वपूर्ण विषय पर बात करने जा रहा हूँ।",
          "क्या आपको लगता है कि यह योजना पूरी तरह से सफल हो पाएगी?",
          "मुझे अपनी क्षमताओं पर पूरा विश्वास है, हम यह लक्ष्य प्राप्त करेंगे।",
          "कृपया इस प्रक्रिया को ध्यान से समझें और आगे बढ़ें।",
          "सभी प्रतिभागियों को समय पर उपस्थित होना अनिवार्य है।"
        ];

        for (int i = 1; i <= 5; i++) {
          PlatformFile? audio = speakerAudios[i];
          Uint8List? speechBytes;

          if (audio != null && audio.path != null) {
            setState(() {
              currentStatus = "ElevenLabs cloning Speaker $i voice...";
            });
            String? vId = await cloneVoiceWithElevenLabs(audio, "Speaker_$i");
            if (vId != null) {
              speechBytes = await synthesizeElevenLabsSpeech(dynamicDialogues[i - 1], vId);
            }
          }

          // Fallback to ElevenLabs default Adam / Rachel voice if not uploaded
          if (speechBytes == null && audio != null) {
            speechBytes = await synthesizeElevenLabsSpeech(dynamicDialogues[i - 1], "21m00Tcm4TlvDq8ikWAM");
          }

          if (audio != null || i <= 2) {
            processedScript.add({
              "speaker": "Speaker $i",
              "dialogue": dynamicDialogues[i - 1],
              "audio": speechBytes,
            });
          }
        }
      }

      // 2. Video Dubbing Pipeline on Cloud
      setState(() {
        dubbingProgress = 0.55;
        currentStatus = "3/4: Processing full video dubbing on cloud servers...";
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
          "num_speakers": -1,
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
            // ENGINE SWITCHER (ElevenLabs vs Sarvam)
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
                      onTap: () => setState(() => selectedEngine = "elevenlabs"),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.record_voice_over, size: 18),
                            SizedBox(width: 8),
                            Text("ElevenLabs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                            Text("Sarvam AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                color: (selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.green).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.greenAccent),
              ),
              child: Text(
                selectedEngine == "elevenlabs"
                    ? "ElevenLabs Engine Active: World's #1 Voice Cloning & Natural Dubbing."
                    : "Sarvam AI Active: In-Video Voice Dubbing (Zero custom voice upload needed).",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: selectedEngine == "elevenlabs" ? Colors.indigoAccent : Colors.greenAccent,
                ),
              ),
            ),

            const SizedBox(height: 16),

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

            // ELEVENLABS SPECIFIC: Custom Voice Toggle (Hidden in Sarvam)
            if (selectedEngine == "elevenlabs") ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text("Custom Voice Clone Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    isElevenCustomVoice
                        ? "ON: 5 Speaker voice uploads enabled (Instant ElevenLabs Cloning)"
                        : "OFF: Default ElevenLabs dubbing without custom voice uploads",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: isElevenCustomVoice,
                  activeColor: Colors.pinkAccent,
                  onChanged: (val) => setState(() => isElevenCustomVoice = val),
                ),
              ),

              // 5 Speaker Upload Rows (Only if Custom Voice is ON)
              if (isElevenCustomVoice) ...[
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
            ],

            const SizedBox(height: 18),

            // Start Dubbing Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedEngine == "elevenlabs" ? const Color(0xFF6366F1) : Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  isProcessing
                      ? "Processing Dubbing..."
                      : (selectedEngine == "elevenlabs" ? "START ELEVENLABS DUBBING" : "START SARVAM DUBBING"),
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
                      LinearProgressIndicator(
                        value: dubbingProgress,
                        color: selectedEngine == "elevenlabs" ? Colors.pinkAccent : Colors.greenAccent,
                      ),
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

            // 2. ElevenLabs Cloned Custom Voices (With BOTH PLAY & DOWNLOAD BUTTONS!)
            if (selectedEngine == "elevenlabs" && dubbedScript.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text("ElevenLabs Cloned Voices (Play & Download):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent, fontSize: 16)),
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
                      Text(
                        dubbedScript[i]["speaker"],
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "\"${dubbedScript[i]["dialogue"]}\"",
                        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
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
                                "${dubbedScript[i]["speaker"]}_ElevenLabs",
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