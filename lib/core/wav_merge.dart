import 'dart:typed_data';

/// 简易 WAV（PCM）拼接：把多段 16bit PCM WAV 合成一段，段间插入静音
/// 用于听力音频：每题一读，题与题之间留出思考间隔
class WavMerge {
  /// [chunks] 每段 WAV 字节（16bit PCM）；[silenceMs] 段间静音毫秒
  /// 若某段不是标准 16bit PCM WAV，或采样率不一致，直接跳过静音拼接（退化为首段/各段原样）
  static Uint8List merge(List<Uint8List> chunks, {int silenceMs = 3500}) {
    if (chunks.isEmpty) return Uint8List(0);
    if (chunks.length == 1) return chunks.first;

    // 解析各段（返回采样率/采样数据）
    final parsed = <({int rate, Uint8List samples})>[];
    var rate = 0;
    for (final c in chunks) {
      final p = _parsePcm16(c);
      if (p == null) return chunks.first; // 无法解析则退化
      if (rate == 0) rate = p.rate;
      if (p.rate != rate) return chunks.first; // 采样率不一致退化
      parsed.add(p);
    }

    // 静音采样数
    final silenceSamples = rate * silenceMs ~/ 1000;
    // 总采样数（每段 + 中间静音）
    final totalSamples = parsed.fold<int>(0, (s, p) => s + p.samples.length ~/ 2) +
        silenceSamples * 2 * (parsed.length - 1);

    // 合成数据区（16bit little-endian）
    final data = ByteData(totalSamples * 2);
    var offset = 0;
    for (var i = 0; i < parsed.length; i++) {
      final samples = parsed[i].samples;
      for (var j = 0; j < samples.length; j++) {
        data.setUint8(offset++, samples[j]);
      }
      if (i < parsed.length - 1) {
        for (var j = 0; j < silenceSamples * 2; j++) {
          data.setUint8(offset++, 0);
        }
      }
    }

    // 组 WAV 头（44 字节）
    final byteCount = offset;
    final out = ByteData(44 + byteCount);
    void writeStr(int pos, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(pos + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    out.setUint32(4, 36 + byteCount, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    out.setUint32(16, 16, Endian.little); // fmt chunk size
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, rate, Endian.little); // sample rate
    out.setUint32(28, rate * 2, Endian.little); // byte rate
    out.setUint16(32, 2, Endian.little); // block align
    out.setUint16(34, 16, Endian.little); // bits per sample
    writeStr(36, 'data');
    out.setUint32(40, byteCount, Endian.little);

    // 拷贝数据
    final dataBytes = data.buffer.asUint8List();
    for (var i = 0; i < byteCount; i++) {
      out.setUint8(44 + i, dataBytes[i]);
    }
    return out.buffer.asUint8List();
  }

  /// 解析 16bit PCM WAV：返回采样率与数据区字节（不含头）
  static ({int rate, Uint8List samples})? _parsePcm16(Uint8List wav) {
    if (wav.length < 44) return null;
    final b = ByteData.sublistView(wav);
    if (b.getUint8(0) != 0x52 || b.getUint8(1) != 0x49) return null; // 'RI'
    if (b.getUint8(8) != 0x57 || b.getUint8(9) != 0x41) return null; // 'WA'
    final bits = b.getUint16(34, Endian.little);
    final channels = b.getUint16(22, Endian.little);
    if (bits != 16 || channels != 1) return null;
    final rate = b.getUint32(24, Endian.little);
    // 找 data chunk
    var pos = 12;
    var dataSize = 0;
    var dataOff = 0;
    while (pos + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
      final size = b.getUint32(pos + 4, Endian.little);
      if (id == 'data') {
        dataOff = pos + 8;
        dataSize = size;
        break;
      }
      pos += 8 + size;
      if (size == 0) break;
    }
    if (dataSize <= 0 || dataOff + dataSize > wav.length) return null;
    return (rate: rate, samples: wav.sublist(dataOff, dataOff + dataSize));
  }

  /// 生成指定时长的静音 WAV（16bit PCM, 24kHz, mono）
  static Uint8List silence(int ms, {int sampleRate = 24000}) {
    final samples = sampleRate * ms ~/ 1000;
    final dataSize = samples * 2; // 16bit = 2 bytes per sample
    final out = ByteData(44 + dataSize);

    void writeStr(int pos, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(pos + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    out.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    out.setUint32(40, dataSize, Endian.little);
    // data 区域默认为 0（静音）

    return out.buffer.asUint8List();
  }
}
