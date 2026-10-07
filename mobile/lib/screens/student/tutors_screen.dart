import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/repo.dart';
import '../../widgets/ui.dart';
import 'tutor_detail_screen.dart';

/// Phase 2: Connected Tutors List — display_name ("Ashraf Sir") + circular photo,
/// BorderRadius 16, soft shadow, flutter_animate fade+slide list animation.
class TutorsScreen extends StatefulWidget {
  const TutorsScreen({super.key});

  @override
  State<TutorsScreen> createState() => _TutorsScreenState();
}

class _TutorsScreenState extends State<TutorsScreen> {
  final _key = GlobalKey<LoaderState<List<ConnectedTutor>>>();

  Future<List<ConnectedTutor>> _load() async {
    final repo = context.read<Repo>();
    final rows = await repo.myTutors();
    return rows.map(ConnectedTutor.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Tutors', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
      body: Loader<List<ConnectedTutor>>(
        key: _key,
        load: _load,
        builder: (context, tutors, reload) {
          if (tutors.isEmpty) {
            return const PageBody(children: [
              EmptyState(
                icon: Icons.handshake_outlined,
                title: 'No connected tutors yet',
                message: 'Once your tutor accepts, they appear here as e.g. "Ashraf Sir".',
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: tutors.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _TutorCard(
              tutor: tutors[i],
              index: i,
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TutorDetailScreen(tutorId: tutors[i].id, title: tutors[i].displayName),
                ),
              ).then((_) => _key.currentState?.reload()),
            ),
          );
        },
      ),
    );
  }
}

class _TutorCard extends StatelessWidget {
  const _TutorCard({required this.tutor, required this.index, required this.onOpen});
  final ConnectedTutor tutor;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final photo = tutor.photo;
    final url = (photo != null && photo.isNotEmpty) ? context.read<Repo>().api.mediaUrl(photo) : '';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: url.isEmpty ? const Icon(Icons.person, size: 30) : null,
        ),
        title: Text(tutor.displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17)),
        subtitle: Text('@${tutor.username}', style: GoogleFonts.inter(color: Colors.grey, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          HapticFeedback.lightImpact();
          onOpen();
        },
      ),
    ).animate().fade(duration: 350.ms, delay: (index * 80).ms).slideY(begin: 0.2, end: 0);
  }
}
