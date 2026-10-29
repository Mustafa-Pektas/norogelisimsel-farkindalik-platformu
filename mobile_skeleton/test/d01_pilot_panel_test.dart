import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/d01_pilot_result.dart';
import 'package:neuro_awareness_app/widgets/d01_pilot_panel.dart';

import 'support/d01_pilot_fixtures.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    ControlledPilotApi api, {
    Object? identity,
    File? file,
    Duration interval = const Duration(seconds: 5),
    Duration limit = const Duration(minutes: 20),
    bool opening = false,
    bool noVideo = false,
    Future<void> Function(Duration)? seek,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: D01PilotPanel(
              api: api,
              video: noVideo ? null : file ?? File('selected.mp4'),
              videoIdentity: noVideo ? null : identity ?? 'controller-1',
              duration: const Duration(seconds: 7),
              openingVideo: opening,
              initialAccessKey: 'session-only',
              pollInterval: interval,
              trackingLimit: limit,
              onSeek: seek ?? (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'No automatic upload, idle without video, session key clear; no scenario address changes',
    (tester) async {
      final api = ControlledPilotApi();
      await mount(tester, api, noVideo: true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('pilot-start')))
            .onPressed,
        isNull,
      );
      expect(api.tasks, isEmpty);
      await tap(tester, 'pilot-clear-key');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pilot-key')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pilot-key')))
            .obscureText,
        isTrue,
      );
      await close(tester);
    },
  );

  testWidgets(
    'Upload, nonoverlapping polls, completion and raw/EMA seek use candidate start, not confirmation',
    (tester) async {
      final api = ControlledPilotApi();
      final gate = Completer<D01PilotStatus>();
      final task = ControlledPilotTask()..readStatus = () => gate.future;
      api.makeTask = () => task;
      final sought = <Duration>[];
      await mount(
        tester,
        api,
        seek: (t) async {
          sought.add(t);
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('pilot-address')),
        'http://10.0.2.2:8000',
      );
      await tap(tester, 'pilot-start');
      expect(task.submits, 1);
      expect(task.polls, 1);
      expect(api.keys, ['session-only']);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('pilot-start')))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 20));
      expect(task.polls, 1);
      gate.complete(D01PilotStatus.fromJson(pilotStatusJson('completed')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Pilot tamamlandı'), findsOneWidget);
      expect(find.textContaining('Ham matrislerden'), findsOneWidget);
      expect(find.textContaining('EMA α=0.50'), findsOneWidget);
      await tap(tester, 'pilot-raw-candidate_001');
      await tap(tester, 'pilot-ema-candidate_001');
      expect(sought, [
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 1500),
      ]);
      expect(task.results, 1);
      expect(task.closes, 1);
      await close(tester);
      expect(task.closes, 1);
      expect(task.cancels, 0);
    },
  );

  testWidgets(
    'DELETE accepted is not cancelled until terminal; stale pre-cancel completion is ignored',
    (tester) async {
      final api = ControlledPilotApi();
      final old = Completer<D01PilotStatus>();
      final task = ControlledPilotTask()..readStatus = () => old.future;
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await tap(tester, 'pilot-cancel');
      expect(task.cancels, 1);
      expect(task.closes, 0);
      expect(find.textContaining('İptal istendi;'), findsOneWidget);
      task.readStatus = () async => D01PilotStatus.fromJson(
        pilotStatusJson('interrupted', 'cancelled_locally'),
      );
      old.complete(D01PilotStatus.fromJson(pilotStatusJson('completed')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Pilot işi kesildi.'), findsOneWidget);
      expect(task.results, 0);
      expect(task.closes, 1);
      await close(tester);
    },
  );

  testWidgets(
    'Cancel error is visible; no fake terminal success; close only stops client',
    (tester) async {
      final api = ControlledPilotApi();
      final task = ControlledPilotTask()
        ..onCancel = () async =>
            throw const D01PilotException('connection_error');
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await tap(tester, 'pilot-cancel');
      expect(find.textContaining('İptal doğrulanamadı.'), findsOneWidget);
      expect(find.text('Pilot işi kesildi.'), findsNothing);
      expect(task.submits, 1);
      await close(tester);
      expect(task.closes, 1);
      expect(task.cancels, 1);
    },
  );

  testWidgets(
    'Connection failure stops polling; explicit resume uses same job, not POST',
    (tester) async {
      final api = ControlledPilotApi();
      final task = ControlledPilotTask()
        ..readStatus = () async =>
            throw const D01PilotException('http_timeout');
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await tester.pump(const Duration(seconds: 30));
      expect(task.polls, 1);
      expect(find.textContaining('Bağlantı zaman aşımına'), findsOneWidget);
      task.readStatus = () async =>
          D01PilotStatus.fromJson(pilotStatusJson('completed'));
      await tap(tester, 'pilot-resume');
      await tester.pump();
      expect(task.submits, 1);
      expect(task.polls, 2);
      expect(find.textContaining('Pilot tamamlandı'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'Leaving during pending DELETE closes local resources once; no late polling',
    (tester) async {
      final api = ControlledPilotApi();
      final gate = Completer<void>();
      final task = ControlledPilotTask()..onCancel = () => gate.future;
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await tap(tester, 'pilot-cancel');
      final polls = task.polls;
      await close(tester);
      gate.complete();
      await tester.pump();
      expect(task.closes, 1);
      expect(task.cancels, 1);
      expect(task.polls, polls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Changing video rejects late result and only releases local tracking',
    (tester) async {
      final api = ControlledPilotApi();
      final gate = Completer<D01PilotResult>();
      final task = ControlledPilotTask();
      task.readStatus = () async =>
          D01PilotStatus.fromJson(pilotStatusJson('completed'));
      task.readResult = () => gate.future;
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await mount(
        tester,
        api,
        identity: 'controller-2',
        file: File('different.mp4'),
      );
      expect(task.closes, 1);
      expect(task.cancels, 0);
      gate.complete(
        D01PilotResult.fromJson(pilotResultJson(), expectedJobId: pilotTestId),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pilot-raw-candidate_001')),
        findsNothing,
      );
      expect(find.textContaining(pilotTestId), findsNothing);
      await close(tester);
    },
  );

  testWidgets(
    'Pending upload after screen exit never starts polling or server cancel',
    (tester) async {
      final api = ControlledPilotApi();
      final gate = Completer<D01PilotStatus>();
      final task = ControlledPilotTask()..onSubmit = () => gate.future;
      api.makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      expect(find.textContaining('Video yükleniyor'), findsOneWidget);
      await close(tester);
      gate.complete(D01PilotStatus.fromJson(pilotStatusJson()));
      await tester.pump();
      expect(task.polls, 0);
      expect(task.cancels, 0);
      expect(task.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final code in [
    'analysis_timeout',
    'unsupported_video',
    'pilot_busy',
    'unauthorized',
  ]) {
    testWidgets('Terminal error remains visible: $code', (tester) async {
      final task = ControlledPilotTask()
        ..readStatus = () async =>
            D01PilotStatus.fromJson(pilotStatusJson('failed', code));
      final api = ControlledPilotApi()..makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      expect(find.text(D01PilotException(code).message), findsOneWidget);
      expect(find.textContaining('Pilot tamamlandı'), findsNothing);
      await close(tester);
    });
  }

  testWidgets(
    'Missing/out-of-range intervals disabled; opening a new candidate also disables seek',
    (tester) async {
      final data = pilotResultJson();
      data['movements']['raw'][0]['movement_start_s'] = null;
      data['movements']['ema_050'][0]['movement_end_s'] = 99;
      final task = ControlledPilotTask();
      task.readStatus = () async =>
          D01PilotStatus.fromJson(pilotStatusJson('completed'));
      task.readResult = () async =>
          D01PilotResult.fromJson(data, expectedJobId: pilotTestId);
      final api = ControlledPilotApi()..makeTask = () => task;
      await mount(tester, api);
      await tap(tester, 'pilot-start');
      await tester.pump();
      for (final method in ['raw', 'ema']) {
        expect(
          tester
              .widget<ListTile>(
                find.byKey(ValueKey('pilot-$method-candidate_001')),
              )
              .onTap,
          isNull,
        );
      }
      await mount(tester, api, opening: true);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('pilot-raw-candidate_001')),
            )
            .onTap,
        isNull,
      );
      await close(tester);
    },
  );

  testWidgets(
    '320 px / double text: config, start, result and cancellation remain accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 744));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ControlledPilotApi();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: D01PilotPanel(
                  video: File('selected.mp4'),
                  videoIdentity: '1',
                  duration: const Duration(seconds: 7),
                  openingVideo: false,
                  onSeek: (_) async {},
                  api: api,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('pilot-address')));
      await tester.enterText(
        find.byKey(const ValueKey('pilot-address')),
        'http://10.0.2.2:8000',
      );
      await tap(tester, 'pilot-start');
      await tester.ensureVisible(find.byKey(const ValueKey('pilot-cancel')));
      expect(
        find.byKey(const ValueKey('pilot-cancel')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      api.tasks.single.readStatus = () async =>
          D01PilotStatus.fromJson(pilotStatusJson('completed'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      for (final method in ['raw', 'ema']) {
        final candidate = find.byKey(ValueKey('pilot-$method-candidate_001'));
        await tester.ensureVisible(candidate);
        await tester.pump();
        expect(candidate.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
