import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'firebase_options.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MedSlotApp());
}

class MedSlotApp extends StatelessWidget {
  const MedSlotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    home: const MainNavigationScreen(),
  );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;
  final List<Widget> _tabs = [const SymptomCheckerScreen(), const AdminDashboardScreen()];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: _tabs[_index],
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _index,
      onTap: (i) => setState(() => _index = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI Triage'), 
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard')
      ],
    ),
  );
}

class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key});
  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  final TextEditingController _symptom = TextEditingController(), _name = TextEditingController();
  String _specialty = "";
  bool _loading = false;
  List<Map<String, dynamic>> _hospitals = [];
  
  // Use your actual key from Google AI Studio
  final String _key = "AIzaSyAGpkFl378Jnk6z0YRDAZJGZIZJm0NhS4E";

  // Repairs database with 2026 data standards
  Future<void> _setupDatabase() async {
    try {
      final hospitals = FirebaseFirestore.instance.collection('Hospitals');
      final List<Map<String, dynamic>> testData = [
        {'name': 'Metro Cardiology', 'specialty': 'Cardiologist', 'dist': '1.5'},
        {'name': 'City Skin Clinic', 'specialty': 'Dermatologist', 'dist': '1.2'},
        {'name': 'ENT Care Center', 'specialty': 'ENT Specialist', 'dist': '2.0'},
        {'name': 'General Health Plus', 'specialty': 'General Physician', 'dist': '0.5'},
        {'name': 'Orthopedic Hub', 'specialty': 'Orthopedic', 'dist': '3.1'},
      ];
      for (var data in testData) {
        await hospitals.doc(data['name']).set(data);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Repaired!")));
    } catch (e) { print("Setup Error: $e"); }
  }

  Future<void> _runSearch() async {
    if (_symptom.text.isEmpty) return;
    setState(() { _loading = true; _hospitals = []; _specialty = ""; });
    
    try {
      // Updated endpoint to use Gemini 2.5 Flash to avoid 404 errors
      final res = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": "You are a triage doctor. Map: '${_symptom.text}' to one: [Cardiologist, Dermatologist, ENT Specialist, General Physician, Orthopedic]. Return ONLY the specialty name."}]}]
        }),
      );

      if (res.statusCode == 200) {
        _specialty = jsonDecode(res.body)['candidates'][0]['content']['parts'][0]['text'].trim();
        
        QuerySnapshot snap = await FirebaseFirestore.instance.collection('Hospitals').get();
        List<Map<String, dynamic>> temp = [];
        
        for (var doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data.containsKey('specialty')) {
            String dbSpec = data['specialty'].toString().toLowerCase();
            if (dbSpec.contains(_specialty.toLowerCase())) {
              temp.add({'name': data['name'], 'dist': data['dist'] ?? "1.5"});
            }
          }
        }
        setState(() { _hospitals = temp; });
      }
    } catch (e) { print("API Error: $e"); }
    setState(() => _loading = false);
  }

  Future<void> _book(String hosp) async {
    await FirebaseFirestore.instance.collection('appointments').add({
      'patient': _name.text.isEmpty ? "Patient" : _name.text,
      'hospital': hosp,
      'specialty': _specialty,
      'time': FieldValue.serverTimestamp()
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booked at $hosp!")));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("🏥 MedSlot AI")),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: "Patient Name")),
      TextField(controller: _symptom, decoration: const InputDecoration(labelText: "How do you feel? (e.g. itchy skin)")),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: _loading ? null : _runSearch, child: _loading ? const CircularProgressIndicator() : const Text("Analyze & Find Doctor")),
      if (_specialty.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text("Triage Result: $_specialty", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal))),
        ..._hospitals.map((h) => Card(child: ListTile(
          leading: const Icon(Icons.local_hospital, color: Colors.teal),
          title: Text(h['name']), subtitle: Text("${h['dist']} KM away"),
          trailing: ElevatedButton(onPressed: () => _book(h['name']), child: const Text("Book")),
        ))),
      ],
      const SizedBox(height: 50),
      TextButton.icon(onPressed: _setupDatabase, icon: const Icon(Icons.settings), label: const Text("Repair Database"))
    ]),
  );
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("📋 Clinic Dashboard")),
    body: StreamBuilder(
      stream: FirebaseFirestore.instance.collection('appointments').orderBy('time', descending: true).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(children: snap.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return Card(child: ListTile(title: Text(data['patient'] ?? "Guest"), subtitle: Text("${data['specialty']} @ ${data['hospital']}")));
        }).toList());
      },
    ),
  );
}