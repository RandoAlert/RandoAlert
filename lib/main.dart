import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' as xml;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ========== CONFIG ==========
class AppConfig {
  static const String githubOwner = 'RandoAlert';
  static const String githubRepo = 'RandoAlert-signalements-issues';
  static const String issuesUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/issues?state=open&per_page=100';
  static const String createIssueUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/issues';
}

// ========== SERVICES ==========
class GitHubService {
  static Future<List<Signalement>> chargerSignalements() async {
    try {
      final response = await http.get(
        Uri.parse(AppConfig.issuesUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> issues = jsonDecode(response.body);
        final List<Signalement> signalements = [];

        for (final issue in issues) {
          try {
            final title = issue['title'] as String? ?? '';
            final body = issue['body'] as String? ?? '';
            final parts = title.split(' | ');

            if (parts.length >= 3) {
              final lat = double.tryParse(parts[1].trim());
              final lon = double.tryParse(parts[2].trim());

              if (lat != null && lon != null) {
                signalements.add(
                  Signalement(
                    id: issue['number'] as int,
                    type: parts[0].trim(),
                    latitude: lat,
                    longitude: lon,
                    description: body,
                    auteur: (issue['user'] as Map<String, dynamic>?)
                            ?['login'] as String? ??
                        'anonyme',
                    createdAt: DateTime.parse(issue['created_at'] as String),
                  ),
                );
              }
            }
          } catch (e) {
            print('Erreur parsing issue ${issue['number']}: $e');
            continue;
          }
        }

        return signalements;
      } else {
        print('Erreur HTTP: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Erreur chargement signalements: $e');
      return [];
    }
  }

  static Future<bool> creerSignalement({
    required String token,
    required String type,
    required double latitude,
    required double longitude,
    required String description,
    required String auteur,
  }) async {
    if (token.isEmpty) return false;

    try {
      final title =
          '$type | ${latitude.toStringAsFixed(6)} | ${longitude.toStringAsFixed(6)}';
      final body = auteur.isEmpty
          ? description
          : '**Signalé par:** $auteur\n\n$description';

      final response = await http.post(
        Uri.parse(AppConfig.createIssueUrl),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          'body': body,
          'labels': ['signalement', 'en-cours'],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        print('✅ Signalement créé avec succès');
        return true;
      } else {
        print('❌ Erreur création: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Exception: $e');
      return false;
    }
  }
}

class GeoService {
  static Future<String> getDepartementCode(LatLng position) async {
    // TODO: Implémenter vrai service de géolocalisation département
    return '49'; // Force Maine-et-Loire pour test
  }
}

class MeteoService {
  static Color getCouleurVigilance(String couleur) {
    switch (couleur.toLowerCase()) {
      case 'jaune':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'rouge':
        return Colors.red;
      default:
        return Colors.transparent;
    }
  }

  static Color getTextColor(Color background) {
    return background == Colors.yellow ? Colors.black : Colors.white;
  }
}

// ========== MODÈLES ==========
class CarteDef {
  final String nom;
  final String url;
  final int maxZoom;

  const CarteDef({required this.nom, required this.url, this.maxZoom = 19});
}

class PointGPX {
  final LatLng position;
  final double altitude;

  const PointGPX({required this.position, required this.altitude});
}

class Signalement {
  final int id;
  final String type;
  final double latitude;
  final double longitude;
  final String description;
  final String auteur;
  final DateTime createdAt;

  const Signalement({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.auteur,
    required this.createdAt,
  });

  LatLng get position => LatLng(latitude, longitude);

  bool get estExpire {
    final duree = _getTypeSignalement(type).dureeHeures;
    return DateTime.now().difference(createdAt).inHours > duree;
  }

  TypeSignalement _getTypeSignalement(String nom) {
    return typesSignalement.firstWhere(
      (t) => t.nom == nom,
      orElse: () => typesSignalement.last,
    );
  }

  String get dureeRestante {
    final type = _getTypeSignalement(this.type);
    final expiresAt = createdAt.add(Duration(hours: type.dureeHeures));
    final now = DateTime.now();
    if (expiresAt.isBefore(now)) return 'Expiré';
    final diff = expiresAt.difference(now);
    if (diff.inHours > 0) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }
}

class TypeSignalement {
  final String nom;
  final IconData icone;
  final Color couleur;
  final int dureeHeures;
  final String dureeLabel;

  const TypeSignalement({
    required this.nom,
    required this.icone,
    required this.couleur,
    required this.dureeHeures,
    required this.dureeLabel,
  });
}

const List<TypeSignalement> typesSignalement = [
  TypeSignalement(
    nom: 'Troupeau / Clôture',
    icone: Icons.pets,
    couleur: Colors.brown,
    dureeHeures: 4,
    dureeLabel: '4 heures',
  ),
  TypeSignalement(
    nom: 'Sentier inondé',
    icone: Icons.water,
    couleur: Colors.blue,
    dureeHeures: 336,
    dureeLabel: '2 semaines',
  ),
  TypeSignalement(
    nom: 'Arbre / Branche tombée',
    icone: Icons.forest,
    couleur: Colors.green,
    dureeHeures: 672,
    dureeLabel: '4 semaines',
  ),
  TypeSignalement(
    nom: 'Balisage manquant',
    icone: Icons.wrong_location,
    couleur: Colors.red,
    dureeHeures: 672,
    dureeLabel: '4 semaines',
  ),
  TypeSignalement(
    nom: 'Travaux / Chemin fermé',
    icone: Icons.construction,
    couleur: Colors.orange,
    dureeHeures: 720,
    dureeLabel: '30 jours',
  ),
  TypeSignalement(
    nom: 'Autre',
    icone: Icons.warning,
    couleur: Colors.grey,
    dureeHeures: 720,
    dureeLabel: '30 jours',
  ),
];

const List<CarteDef> fondsDeCartes = [
  CarteDef(
    nom: 'OSM Standard',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: 19,
  ),
  CarteDef(
    nom: 'OSM France',
    url: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    maxZoom: 20,
  ),
  CarteDef(
    nom: 'Open Topo Map',
    url: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
    maxZoom: 17,
  ),
];

// ========== MAIN ==========
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await fmtc.FMTCObjectBoxBackend().initialise();
  final store = fmtc.FMTCStore('mapCache');
  await store.manage.create();
  runApp(const RandoAlerteApp());
}

// ========== APPLICATION ==========
class RandoAlerteApp extends StatelessWidget {
  const RandoAlerteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RandoAlert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: false,
      ),
      home: const CartePage(),
    );
  }
}

class CartePage extends StatefulWidget {
  const CartePage({super.key});

  @override
  State<CartePage> createState() => _CartePageState();
}

class _CartePageState extends State<CartePage> {
  final MapController _mapController = MapController();
  String _githubToken = '';
  final TextEditingController _tokenController = TextEditingController();
  LatLng? _position;
  bool _chargement = true;
  List<PointGPX> _pointsGPX = [];
  bool _afficherTrace = true;
  bool _afficherSentiers = false;
  bool _afficherSignalements = true;
  bool _afficherAlertesMeteo = true;
  CarteDef _carteActive = fondsDeCartes[0];
  bool _modeViseur = false;
  LatLng? _centreViseActuel;
  List<Signalement> _signalements = [];
  String? _alerteMeteo;
  Color _couleurAlerte = Colors.transparent;
  String _departementActuel = '49';

  @override
  void initState() {
    super.initState();
    _initialiserGPS();
    _chargerSignalements();
    _verifierAlerteMeteo();

    // Recharger les signalements toutes les 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      if (mounted) {
        _chargerSignalements();
      }
    });
  }

  Future<void> _initialiserGPS() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _chargement = false);
      return;
    }

    try {
      Geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).listen((Position pos) {
        if (mounted) {
          setState(() {
            _position = LatLng(pos.latitude, pos.longitude);
            _chargement = false;
          });
        }
      });
    } catch (e) {
      print('Erreur GPS: $e');
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _verifierAlerteMeteo() async {
    if (mounted) {
      setState(() {
        _departementActuel = '49';
        _alerteMeteo = "Vigilance orange en Maine-et-Loire";
        _couleurAlerte = Colors.orange;
      });
    }
  }

  Future<void> _chargerSignalements() async {
    try {
      final signalements = await GitHubService.chargerSignalements();
      if (mounted) {
        setState(() {
          // Filtrer les signalements expirés
          _signalements =
              signalements.where((s) => !s.estExpire).toList();
        });
      }
    } catch (e) {
      print("Erreur chargement signalements: $e");
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Paramètres GitHub"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: "Token GitHub (PAT)",
                hintText: "ghp_...",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "📖 Comment créer un token :",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "1. Allez sur: https://github.com/settings/tokens\n"
                    "2. Cliquez: Generate new token (classic)\n"
                    "3. Scope requis: ✅ repo (accès complet)\n"
                    "4. Copiez le token ci-dessus",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://github.com/settings/tokens'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Text(
                      "🔗 Ouvrir GitHub tokens",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              _githubToken = _tokenController.text.trim();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_githubToken.isEmpty
                      ? "⚠️ Token vide"
                      : "✅ Token sauvegardé"),
                  backgroundColor: _githubToken.isEmpty
                      ? Colors.orange
                      : Colors.green,
                ),
              );
            },
            child: const Text("Sauvegarder"),
          ),
        ],
      ),
    );
  }

  double _altitudeAuPoint(LatLng point) {
    if (_pointsGPX.isEmpty) return 0;
    double minDist = double.infinity;
    double alt = 0;
    for (final pt in _pointsGPX) {
      double d = const Distance().as(LengthUnit.Meter, point, pt.position);
      if (d < minDist) {
        minDist = d;
        alt = pt.altitude;
      }
    }
    return alt;
  }

  double get _altitudeGPX => _pointsGPX.isEmpty
      ? 0
      : _altitudeAuPoint(_position ?? _pointsGPX.first.position);

  double get _distanceVise => _position == null || _centreViseActuel == null
      ? 0
      : const Distance().as(LengthUnit.Meter, _position!, _centreViseActuel!);

  double get _deniveleVise =>
      _position == null || _centreViseActuel == null || _pointsGPX.isEmpty
          ? 0
          : _altitudeAuPoint(_centreViseActuel!) - _altitudeGPX;

  double get _penteVise =>
      _distanceVise == 0 ? 0 : (_deniveleVise / _distanceVise) * 100;

  double get _distanceRestante {
    if (_pointsGPX.isEmpty || _position == null) return 0;
    double minDist = double.infinity;
    int indexProche = 0;
    for (int i = 0; i < _pointsGPX.length; i++) {
      double d = const Distance().as(
        LengthUnit.Meter,
        _position!,
        _pointsGPX[i].position,
      );
      if (d < minDist) {
        minDist = d;
        indexProche = i;
      }
    }
    double dist = 0;
    for (int i = indexProche; i < _pointsGPX.length - 1; i++) {
      dist += const Distance().as(
        LengthUnit.Meter,
        _pointsGPX[i].position,
        _pointsGPX[i + 1].position,
      );
    }
    return dist;
  }

  double get _denivelePositif {
    if (_pointsGPX.isEmpty || _position == null) return 0;
    int indexProche = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _pointsGPX.length; i++) {
      double d = const Distance().as(
        LengthUnit.Meter,
        _position!,
        _pointsGPX[i].position,
      );
      if (d < minDist) {
        minDist = d;
        indexProche = i;
      }
    }
    double dPlus = 0;
    for (int i = indexProche; i < _pointsGPX.length - 1; i++) {
      double diff = _pointsGPX[i + 1].altitude - _pointsGPX[i].altitude;
      if (diff > 0) dPlus += diff;
    }
    return dPlus;
  }

  double get _deniveleNegatif {
    if (_pointsGPX.isEmpty || _position == null) return 0;
    int indexProche = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _pointsGPX.length; i++) {
      double d = const Distance().as(
        LengthUnit.Meter,
        _position!,
        _pointsGPX[i].position,
      );
      if (d < minDist) {
        minDist = d;
        indexProche = i;
      }
    }
    double dMoins = 0;
    for (int i = indexProche; i < _pointsGPX.length - 1; i++) {
      double diff = _pointsGPX[i + 1].altitude - _pointsGPX[i].altitude;
      if (diff < 0) dMoins += diff.abs();
    }
    return dMoins;
  }

  Future<void> _exporterGPX() async {
    if (_pointsGPX.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Aucune trace GPX chargée !")),
        );
      }
      return;
    }

    final gpxContent =
        '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RandoAlert" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Parcours RandoAlert</name>
    <trkseg>
${_pointsGPX.map((p) => '      <trkpt lat="${p.position.latitude}" lon="${p.position.longitude}"><ele>${p.altitude}</ele></trkpt>').join('\n')}
    </trkseg>
  </trk>
</gpx>''';

    final result = await FilePicker.saveFile(
      fileName: 'parcours_${DateTime.now().millisecondsSinceEpoch}.gpx',
      bytes: Uint8List.fromList(gpxContent.codeUnits),
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Parcours exporté !"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _ouvrirGPX() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    if (result == null) return;

    try {
      final file = File(result.files.single.path!);
      final contenu = await file.readAsString();
      final document = xml.XmlDocument.parse(contenu);
      final points = document.findAllElements("trkpt");

      final List<PointGPX> newPoints = [];
      for (final point in points) {
        final lat = double.tryParse(point.getAttribute("lat") ?? "");
        final lon = double.tryParse(point.getAttribute("lon") ?? "");
        final eleElem = point.findElements("ele").firstOrNull;
        final alt = eleElem != null ? double.tryParse(eleElem.text) : null;

        if (lat != null && lon != null) {
          newPoints.add(
            PointGPX(
              position: LatLng(lat, lon),
              altitude: alt ?? 0,
            ),
          );
        }
      }

      if (newPoints.isNotEmpty && mounted) {
        setState(() => _pointsGPX = newPoints);
        _mapController.move(newPoints.first.position, 14);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${newPoints.length} points chargés"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Erreur: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _centrerSurMoi() {
    if (_position != null) _mapController.move(_position!, 15);
  }

  void _toggleViseur() {
    if (mounted) {
      setState(() {
        _modeViseur = !_modeViseur;
        if (!_modeViseur) {
          _centreViseActuel = null;
        } else {
          _centreViseActuel = _mapController.camera.center;
        }
      });
    }
  }

  TypeSignalement _getTypeSignalement(String nom) {
    return typesSignalement.firstWhere(
      (t) => t.nom == nom,
      orElse: () => typesSignalement.last,
    );
  }

  void _signalerProbleme() {
    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Localisation GPS nécessaire"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    TypeSignalement typeChoisi = typesSignalement.first;
    String description = '';
    String auteur = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "📍 Signaler un problème",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: typesSignalement.map(
                    (type) => RadioListTile<TypeSignalement>(
                      title: Row(
                        children: [
                          Icon(type.icone, color: type.couleur),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(type.nom),
                                Text(
                                  "Valable ${type.dureeLabel}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      value: type,
                      groupValue: typeChoisi,
                      onChanged: (val) =>
                          setModalState(() => typeChoisi = val!),
                    ),
                  ).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Description du problème",
                    hintText: "Décrivez le problème rencontré...",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => description = val,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: "Votre nom (optionnel)",
                    hintText: "Anonyme",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => auteur = val,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(
                    "✅ Envoyer — Valable ${typeChoisi.dureeLabel}",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);

                    if (_githubToken.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "⚠️ Token GitHub manquant !\nAjoutez-le dans ⚙️ Paramètres",
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }

                    // Afficher un loader
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text("Envoi en cours..."),
                            ],
                          ),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }

                    final success = await GitHubService.creerSignalement(
                      token: _githubToken,
                      type: typeChoisi.nom,
                      latitude: _position!.latitude,
                      longitude: _position!.longitude,
                      description: description.isEmpty
                          ? "Aucune description"
                          : description,
                      auteur: auteur,
                    );

                    if (mounted) {
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "✅ Signalement créé automatiquement !",
                            ),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        await Future.delayed(const Duration(seconds: 1));
                        await _chargerSignalements();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "❌ Erreur lors de la création.\nVérifiez votre token.",
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _choisirCarte() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Material(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "🗺️ Fond de carte",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ...fondsDeCartes.map(
                (carte) => ListTile(
                  leading: Icon(
                    Icons.map,
                    color: _carteActive.nom == carte.nom
                        ? Colors.green
                        : Colors.grey,
                  ),
                  title: Text(carte.nom),
                  subtitle: Text("Zoom max: ${carte.maxZoom}"),
                  trailing: _carteActive.nom == carte.nom
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() => _carteActive = carte);
                    Navigator.pop(context);
                  },
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "📊 Couches",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              SwitchListTile(
                title: const Text("Sentiers balisés"),
                secondary: const Icon(Icons.hiking, color: Colors.green),
                value: _afficherSentiers,
                onChanged: (val) => setState(() => _afficherSentiers = val),
              ),
              SwitchListTile(
                title: const Text("Signalements communautaires"),
                secondary: const Icon(Icons.warning, color: Colors.orange),
                value: _afficherSignalements,
                onChanged: (val) =>
                    setState(() => _afficherSignalements = val),
              ),
              SwitchListTile(
                title: const Text("Alertes météo"),
                secondary: const Icon(Icons.cloud, color: Colors.blue),
                value: _afficherAlertesMeteo,
                onChanged: (val) =>
                    setState(() => _afficherAlertesMeteo = val),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double metres) {
    return metres >= 1000
        ? "${(metres / 1000).toStringAsFixed(1)} km"
        : "${metres.toInt()} m";
  }

  Widget _infoItem(
    IconData icone,
    String texte, {
    Color couleur = Colors.white,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, color: couleur, size: 16),
        const SizedBox(height: 2),
        Text(
          texte,
          style: TextStyle(
            color: couleur,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool gpxCharge = _pointsGPX.isNotEmpty;
    final signalementsFiltres =
        _signalements.where((s) => !s.estExpire).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("🏕️ RandoAlert"),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (gpxCharge)
            IconButton(
              icon: Icon(
                _afficherTrace ? Icons.visibility : Icons.visibility_off,
              ),
              tooltip: "Masquer/Afficher trace",
              onPressed: () => setState(() => _afficherTrace = !_afficherTrace),
            ),
          IconButton(
            icon: Icon(
              Icons.gps_not_fixed,
              color: _modeViseur ? Colors.yellow : Colors.white,
            ),
            tooltip: "Mode viseur",
            onPressed: _toggleViseur,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: "Importer/Exporter GPX",
            onPressed: _ouvrirGPX,
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: "Paramètres carte",
            onPressed: _choisirCarte,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recharger les signalements",
            onPressed: () {
              _chargerSignalements();
              _verifierAlerteMeteo();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_location),
            tooltip: "Signaler un problème",
            onPressed: _signalerProbleme,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Paramètres GitHub",
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _position ?? const LatLng(47.4784, -0.5632),
                    initialZoom: 15,
                    maxZoom: _carteActive.maxZoom.toDouble(),
                    onPositionChanged: (camera, hasGesture) {
                      if (_modeViseur && hasGesture) {
                        setState(() => _centreViseActuel = camera.center);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _carteActive.url,
                      userAgentPackageName: 'com.example.randoalert',
                      tileProvider: fmtc.FMTCStore('mapCache')
                          .getTileProvider(),
                    ),
                    if (_afficherSentiers)
                      TileLayer(
                        urlTemplate:
                            "https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png",
                        userAgentPackageName: 'com.example.randoalert',
                        tileProvider: fmtc.FMTCStore('mapCache')
                            .getTileProvider(),
                      ),
                    if (gpxCharge && _afficherTrace)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points:
                                _pointsGPX.map((p) => p.position).toList(),
                            strokeWidth: 4,
                            color: Colors.red,
                          ),
                        ],
                      ),
                    if (_modeViseur &&
                        _position != null &&
                        _centreViseActuel != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [_position!, _centreViseActuel!],
                            strokeWidth: 2,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    if (_afficherSignalements &&
                        signalementsFiltres.isNotEmpty)
                      MarkerLayer(
                        markers: signalementsFiltres.map((s) {
                          final type = _getTypeSignalement(s.type);
                          return Marker(
                            point: s.position,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Row(
                                    children: [
                                      Icon(type.icone,
                                          color: type.couleur),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(s.type),
                                      ),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (s.description.isNotEmpty) ...[
                                        Text(s.description),
                                        const SizedBox(height: 8),
                                      ],
                                      Text(
                                        "Signalé par: ${s.auteur}",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        "Expires in: ${s.dureeRestante}",
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "📍 ${s.latitude.toStringAsFixed(4)}, ${s.longitude.toStringAsFixed(4)}",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context),
                                      child: const Text("Fermer"),
                                    ),
                                  ],
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: type.couleur,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: type.couleur
                                          .withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  type.icone,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (_position != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _position!,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // INFO BAR
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _infoItem(
                            Icons.gps_fixed,
                            _position != null
                                ? "${_position!.latitude.toStringAsFixed(4)}\n${_position!.longitude.toStringAsFixed(4)}"
                                : "GPS...",
                          ),
                          if (gpxCharge) ...[
                            const SizedBox(width: 12),
                            _infoItem(
                              Icons.terrain,
                              "${_altitudeGPX.toInt()} m",
                              couleur: Colors.lightGreen,
                            ),
                            const SizedBox(width: 12),
                            _infoItem(
                              Icons.straighten,
                              _formatDistance(_distanceRestante),
                            ),
                            const SizedBox(width: 12),
                            _infoItem(
                              Icons.trending_up,
                              "+${_denivelePositif.toInt()} m",
                              couleur: Colors.lightGreen,
                            ),
                            const SizedBox(width: 12),
                            _infoItem(
                              Icons.trending_down,
                              "-${_deniveleNegatif.toInt()} m",
                              couleur: Colors.orange,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // BANDEAU MÉTÉO
                if (_afficherAlertesMeteo && _alerteMeteo != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      color: _couleurAlerte,
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_alerteMeteo!.contains('jaune'))
                              const Icon(
                                Icons.info_outline,
                                color: Colors.black,
                              ),
                            if (_alerteMeteo!.contains('orange'))
                              const Icon(Icons.warning, color: Colors.white),
                            if (_alerteMeteo!.contains('rouge'))
                              const Icon(Icons.error, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _alerteMeteo!,
                                style: TextStyle(
                                  color: MeteoService.getTextColor(
                                    _couleurAlerte,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              color: _couleurAlerte == Colors.yellow
                                  ? Colors.black
                                  : Colors.white,
                              onPressed: () => setState(
                                () => _afficherAlertesMeteo = false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // VISEUR
                if (_modeViseur)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_position != null && _centreViseActuel != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${_formatDistance(_distanceVise)}  ${_deniveleVise >= 0 ? '+' : ''}${_deniveleVise.toInt()} m  ${_penteVise.toStringAsFixed(1)}%",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 30,
                              height: 2,
                              color: Colors.white,
                            ),
                            Container(
                              width: 2,
                              height: 30,
                              color: Colors.white,
                            ),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // BOUTONS
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _centrerSurMoi,
                    backgroundColor: Colors.green,
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }
}
