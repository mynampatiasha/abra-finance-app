import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// GLOBAL TIMER BAR — shows active timer across all screens
// ============================================================================
// File: lib/core/widgets/global_timer_bar.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'dart:async';
import '../../../../core/services/timer_service.dart';

const Color _navy = Color(0xFF1e3a8a);
const Color _green = Color(0xFF27AE60);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);

class GlobalTimerBar extends StatefulWidget {
  final Widget child;
  const GlobalTimerBar({Key? key, required this.child}) : super(key: key);

  @override
  State<GlobalTimerBar> createState() => _GlobalTimerBarState();
}

class _GlobalTimerBarState extends State<GlobalTimerBar> {
  ActiveTimer? _activeTimer;
  int _elapsedSeconds = 0;
  Timer? _tickTimer;
  Timer? _pollTimer;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _fetchActiveTimer();
    // Poll backend every 30 seconds to sync
    _pollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetchActiveTimer());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchActiveTimer() async {
    try {
      final timers = await TimerService.getActiveTimers();
      if (!mounted) return;
      if (timers.isEmpty) {
        setState(() {
          _activeTimer = null;
          _elapsedSeconds = 0;
        });
        _tickTimer?.cancel();
        return;
      }
      final timer = timers.first;
      setState(() {
        _activeTimer = timer;
        _elapsedSeconds = timer.elapsedSeconds;
      });
      if (timer.isRunning) _startTick();
    } catch (_) {}
  }

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTimer?.isRunning == true) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  Future<void> _stopTimer() async {
    if (_activeTimer == null) return;
    setState(() => _isStopping = true);
    try {
      final result = await TimerService.stopTimer(_activeTimer!.id);
      _tickTimer?.cancel();
      setState(() {
        _activeTimer = null;
        _elapsedSeconds = 0;
        _isStopping = false;
      });
      if (mounted) {
        AppSnackbar.show(context,
            message: 'Timer stopped — ${result.hours} hrs logged');
      }
    } catch (e) {
      setState(() => _isStopping = false);
    }
  }

  Future<void> _pauseResumeTimer() async {
    if (_activeTimer == null) return;
    try {
      if (_activeTimer!.isRunning) {
        await TimerService.pauseTimer(_activeTimer!.id);
        _tickTimer?.cancel();
        setState(() => _activeTimer = ActiveTimer(
              id: _activeTimer!.id,
              projectId: _activeTimer!.projectId,
              projectName: _activeTimer!.projectName,
              taskId: _activeTimer!.taskId,
              taskName: _activeTimer!.taskName,
              userId: _activeTimer!.userId,
              userName: _activeTimer!.userName,
              isBillable: _activeTimer!.isBillable,
              notes: _activeTimer!.notes,
              status: 'paused',
              startedAt: _activeTimer!.startedAt,
              elapsedSeconds: _elapsedSeconds,
              elapsedFormatted: TimerService.formatDuration(_elapsedSeconds),
            ));
      } else {
        await TimerService.resumeTimer(_activeTimer!.id);
        setState(() => _activeTimer = ActiveTimer(
              id: _activeTimer!.id,
              projectId: _activeTimer!.projectId,
              projectName: _activeTimer!.projectName,
              taskId: _activeTimer!.taskId,
              taskName: _activeTimer!.taskName,
              userId: _activeTimer!.userId,
              userName: _activeTimer!.userName,
              isBillable: _activeTimer!.isBillable,
              notes: _activeTimer!.notes,
              status: 'running',
              startedAt: _activeTimer!.startedAt,
              elapsedSeconds: _elapsedSeconds,
              elapsedFormatted: TimerService.formatDuration(_elapsedSeconds),
            ));
        _startTick();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: widget.child),
      if (_activeTimer != null) _buildTimerBar(),
    ]);
  }

  Widget _buildTimerBar() {
    final isRunning = _activeTimer?.isRunning == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _navy,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Row(children: [
        // Pulsing dot
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isRunning ? _green : _orange,
            shape: BoxShape.circle,
            boxShadow: isRunning
                ? [
                    BoxShadow(
                        color: _green.withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 2)
                  ]
                : [],
          ),
        ),
        const SizedBox(width: 10),
        // Project name
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(_activeTimer?.projectName ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis),
              if ((_activeTimer?.taskName ?? '').isNotEmpty)
                Text(_activeTimer!.taskName,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 11),
                    overflow: TextOverflow.ellipsis),
            ])),
        const SizedBox(width: 10),
        // Timer display
        Text(
          TimerService.formatDuration(_elapsedSeconds),
          style: TextStyle(
            color: isRunning ? _green : _orange,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 10),
        // Pause/Resume button
        InkWell(
          onTap: _pauseResumeTimer,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withOpacity(0.4)),
            ),
            child: Icon(
              isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _orange,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Stop button
        InkWell(
          onTap: _isStopping ? null : _stopTimer,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _red.withOpacity(0.4)),
            ),
            child: _isStopping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.stop_rounded, color: _red, size: 20),
          ),
        ),
      ]),
    );
  }
}
