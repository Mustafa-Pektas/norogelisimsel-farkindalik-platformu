import 'package:flutter/material.dart';
import '../models/models.dart';

class InstitutionsScreen extends StatelessWidget {
  const InstitutionsScreen({super.key});

  final List<HealthCenter> _institutions = const [
    HealthCenter(
      name: 'Ankara Üniversitesi Tıp Fakültesi Çocuk Ruh Sağlığı ve Hastalıkları AD',
      department: 'Çocuk ve Ergen Ruh Sağlığı / Gelişimsel Pediatri',
      city: 'Ankara',
      phone: '0 (312) 595 60 00',
      address: 'Mebusevleri, Dögol Cd. No:8, Çankaya/Ankara',
    ),
    HealthCenter(
      name: 'Hacettepe Üniversitesi İhsan Doğramacı Çocuk Hastanesi',
      department: 'Gelişimsel Pediatri Ünitesi',
      city: 'Ankara',
      phone: '0 (312) 305 11 40',
      address: 'Sıhhıye, Altındağ/Ankara',
    ),
    HealthCenter(
      name: 'İstanbul Üniversitesi-Cerrahpaşa Çocuk Ruh Sağlığı AD',
      department: 'Çocuk ve Ergen Psikiyatrisi',
      city: 'İstanbul',
      phone: '0 (212) 414 30 00',
      address: 'Cerrahpaşa Yerleşkesi, Fatih/İstanbul',
    ),
    HealthCenter(
      name: 'Ege Üniversitesi Çocuk Sağlığı ve Hastalıkları AD',
      department: 'Gelişimsel Nöroloji ve Çocuk Psikiyatrisi',
      city: 'İzmir',
      phone: '0 (232) 390 10 00',
      address: 'Kazımdirik, Üniversite Cd., Bornova/İzmir',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurum bilgileri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Etik ve Rehberlik Bilgilendirmesi
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kayıtlı kurum ve iletişim bilgileri güncellik açısından doğrulanmadı; başvurmadan önce resmî kanallardan kontrol edin. Bu ekran arama, harita veya randevu açmaz.',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade900, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          ..._institutions.map((c) {
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.department,
                      style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c.address, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(c.phone, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
