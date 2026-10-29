import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/windows_whisper_transcriber.dart';

void main() {
  test('whisper.cpp word JSON timestamps map to absolute playback seconds', () {
    final json = jsonEncode({'transcription': [
      {'text': ' Hello', 'offsets': {'from': 1200, 'to': 1600}},
      {'text': ' world!', 'offsets': {'from': 1650, 'to': 1980}},
      {'text': '[BLANK_AUDIO]', 'offsets': {'from': -10, 'to': 0}},
    ]});
    final result = WindowsWhisperTranscriber.parseJson(json, 300);
    expect(result[0].text, 'Hello');
    expect(result[0].startSeconds, closeTo(301.2, 0.001));
    expect(result[1].text, 'world');
    expect(result[1].startSeconds, closeTo(301.65, 0.001));
    expect(result.length, 2);
  });

  test('Whisper audio conversion produces 16 kHz mono signed WAV', () {
    final input = Uint8List(44 + 48000 * 4);
    final d = ByteData.sublistView(input);
    void tag(int p, String value) =>
        input.setRange(p, p + value.length, ascii.encode(value));
    tag(0, 'RIFF'); d.setUint32(4, input.length - 8, Endian.little);
    tag(8, 'WAVE'); tag(12, 'fmt ');
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 2, Endian.little);
    d.setUint32(24, 48000, Endian.little);
    d.setUint32(28, 192000, Endian.little);
    d.setUint16(32, 4, Endian.little);
    d.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    d.setUint32(40, input.length - 44, Endian.little);
    for (var i = 0; i < 48000; i++) {
      d.setInt16(44 + i * 4, 15000, Endian.little);
      d.setInt16(44 + i * 4 + 2, -5000, Endian.little);
    }
    final wav = WindowsWhisperTranscriber.whisperWave(input);
    final output = ByteData.sublistView(wav);
    expect(wav.length, 44 + 16000 * 2);
    expect(output.getUint32(24, Endian.little), 16000);
    expect(output.getUint16(22, Endian.little), 1);
    expect(output.getUint16(34, Endian.little), 16);
    expect(output.getInt16(44, Endian.little), closeTo(5000, 1));
  });

  test('unsupported or malformed audio fails closed', () {
    expect(() => WindowsWhisperTranscriber.whisperWave(Uint8List(50)),
        throwsFormatException);
    expect(() => WindowsWhisperTranscriber.parseJson('{}', 0),
        throwsFormatException);
  });
}
