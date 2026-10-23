import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ansight_flutter/ansight.dart';
import 'package:ansight_pencil/ansight_pencil.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  final options = createOptionsBuilder().withAnsightDefaults()
      .withTouchCapture().withSessionJpegCapture(const AnsightSessionJpegCaptureOptions(intervalMilliseconds: 250))
      .withHostConnection(const AnsightHostConnectionOptions(discoveryPort: 49432))
      .withSimulatorPenInput().build();
  await Ansight.instance.initializeAndActivate(options);
  await AnsightFlutterInstrumentation.instance.install();
  runApp(MaterialApp(home: PencilPage(file: File('${directory.path}/pencil-framework-observations.json'))));
}
class PencilPage extends StatefulWidget {
  const PencilPage({super.key, required this.file});
  final File file;
  @override State<PencilPage> createState() => _PencilPageState();
}
class _PencilPageState extends State<PencilPage> {
  final observations = <Map<String, Object?>>[];
  final points = <Offset>[];
  Future<void> saving = Future.value();
  void receive(PointerEvent event, String phase) {
    final row = <String,Object?>{'phase':phase,'kind':event.kind.name,'x':event.position.dx,'y':event.position.dy,
      'pressure':event.pressure,'tilt':event.tilt,'orientation':event.orientation,'distance':event.distance,
      'pencil':event.ansightPencil};
    setState(() { observations.add(row); if(event is PointerDownEvent || event is PointerMoveEvent) points.add(event.localPosition); });
    final json = jsonEncode(observations);
    saving = saving.then((_) async { await widget.file.writeAsString(json); });
  }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xff0c1727),body:AnsightPencilSurface(
    id:'drawing-canvas',child:Listener(behavior:HitTestBehavior.opaque,
      onPointerDown:(e)=>receive(e,'down'),onPointerMove:(e)=>receive(e,'move'),
      onPointerUp:(e)=>receive(e,'up'),onPointerCancel:(e)=>receive(e,'cancel'),onPointerHover:(e)=>receive(e,'hover'),
      child:CustomPaint(painter:_Drawing(points),child:SizedBox.expand(child:IgnorePointer(child:Padding(
        padding:const EdgeInsets.all(50),child:Text('FLUTTER / FRAMEWORK PENCIL\n${observations.length} handler events\n${observations.isEmpty ? "Waiting" : observations.last}',
          style:const TextStyle(color:Colors.white,fontSize:22)))))))));
}
class _Drawing extends CustomPainter {
  _Drawing(this.points);
  final List<Offset> points;
  @override void paint(Canvas canvas, Size size) { for(final point in points) { canvas.drawCircle(point,3,Paint()..color=Colors.tealAccent); } }
  @override bool shouldRepaint(_Drawing oldDelegate)=>true;
}
