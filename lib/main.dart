import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Camera error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'J.A.R.V.I.S Universal Scanner',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
        ),
      ),
      home: const CameraScanScreen(),
    );
  }
}

class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isProcessing = false;
  String _resultTitle = "SYSTEM ONLINE.";
  String _resultSource = "READY TO SCAN OBJECTS/ANIMALS.";
  int _currentCameraIndex = 0;
  String? _matchUrl;

  late AnimationController _scanAnimationController;

  final String _imgbbApiKey = "bb6150eb061f34a1b38348f63ab8bd77";
  final String _serpApiKey =
      "f953ecf3237300773ae650dba261a4903ef1810434726e52bbc4c967e644f253";

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    if (cameras.isNotEmpty) {
      _currentCameraIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;
      _initCamera(_currentCameraIndex);
    }
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (_controller != null) await _controller!.dispose();
    _controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );
    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      print("Camera init error: $e");
    }
  }

  void _switchCamera() {
    if (cameras.length < 2) return;
    setState(() {
      _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    });
    _initCamera(_currentCameraIndex);
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _launchUrl() async {
    if (_matchUrl != null) {
      final Uri url = Uri.parse(_matchUrl!);
      try {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open link')));
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _captureAndSearch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _resultTitle = "UPLOADING IMAGE...";
      _resultSource = "PLEASE WAIT";
      _matchUrl = null;
    });

    try {
      final XFile file = await _controller!.takePicture();
      List<int> imageBytes = await file.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      var uploadResponse = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload?key=$_imgbbApiKey'),
        body: {'image': base64Image},
      );

      if (uploadResponse.statusCode == 200) {
        var uploadJson = jsonDecode(uploadResponse.body);
        String imageUrl = uploadJson['data']['url'];

        setState(() {
          _resultTitle = "ANALYZING OBJECT...";
          _resultSource = "SEARCHING GLOBAL DATABASE";
        });

        var serpResponse = await http.get(
          Uri.parse(
            'https://serpapi.com/search.json?engine=google_lens&url=${Uri.encodeComponent(imageUrl)}&api_key=$_serpApiKey',
          ),
        );

        if (serpResponse.statusCode == 200) {
          var data = jsonDecode(serpResponse.body);
          if (data['visual_matches'] != null &&
              (data['visual_matches'] as List).isNotEmpty) {
            var topMatch = data['visual_matches'][0];
            setState(() {
              _resultTitle = topMatch['title'] ?? 'UNKNOWN OBJECT';
              _resultSource = "Source: ${topMatch['source'] ?? 'Web'}";
              _matchUrl = topMatch['link'];
            });
          } else {
            setState(() {
              _resultTitle = "NO EXACT MATCH FOUND";
              _resultSource = "TRY A DIFFERENT ANGLE";
            });
          }
        } else {
          setState(() {
            _resultTitle = "SERP-API ERROR: ${serpResponse.statusCode}";
            _resultSource = "CHECK API KEY";
          });
        }
      } else {
        setState(() {
          _resultTitle = "UPLOAD FAILED";
          _resultSource = "ERR: ${uploadResponse.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _resultTitle = "SYSTEM ERROR";
        _resultSource = e.toString();
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "J.A.R.V.I.S LENS",
          style: TextStyle(
            letterSpacing: 2,
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (cameras.length > 1)
            IconButton(
              icon: const Icon(
                Icons.flip_camera_android,
                color: Colors.cyanAccent,
              ),
              onPressed: _isProcessing ? null : _switchCamera,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child:
                      (_controller != null && _controller!.value.isInitialized)
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(_controller!),
                            Center(
                              child: Container(
                                width: 250,
                                height: 350,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.cyanAccent.withValues(alpha: 0.7),
                                    width: 1.5,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                            left: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                            right: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                            left: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                            right: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _scanAnimationController,
                              builder: (context, child) {
                                return Positioned(
                                  top:
                                      _scanAnimationController.value *
                                      MediaQuery.of(context).size.height *
                                      0.5,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 3,
                                    decoration: const BoxDecoration(
                                      color: Colors.cyanAccent,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.cyanAccent,
                                          blurRadius: 10,
                                          spreadRadius: 3,
                                        ),
                                        BoxShadow(
                                          color: Colors.white,
                                          blurRadius: 5,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: Colors.cyanAccent,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              color: Colors.black,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _resultTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.cyanAccent,
                      shadows: [
                        Shadow(color: Colors.cyanAccent, blurRadius: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _resultSource,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 15),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _captureAndSearch,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.radar, color: Colors.black),
                        label: Text(
                          _isProcessing ? "SCANNING..." : "SCAN OBJECT",
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),

                      if (_matchUrl != null)
                        OutlinedButton.icon(
                          onPressed: _launchUrl,
                          icon: const Icon(
                            Icons.language,
                            color: Colors.cyanAccent,
                          ),
                          label: const Text(
                            "WEB INFO",
                            style: TextStyle(color: Colors.cyanAccent),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.cyanAccent),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
