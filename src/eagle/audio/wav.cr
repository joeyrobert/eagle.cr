module Eagle
  module Codecs
    # WAV decoding (8, 16, 24 and 32-bit PCM, 32 and 64-bit float) and encoding (16-bit PCM).
    module WAV
      # True when *data* starts with a RIFF/WAVE header.
      def self.wav?(data : Bytes) : Bool
        data.size >= 12 && data[0, 4] == "RIFF".to_slice && data[8, 4] == "WAVE".to_slice
      end

      # Decodes WAV bytes into an `AudioBuffer`.
      def self.decode(data : Bytes) : AudioBuffer
        raise AssetError.new("Not a WAV file") unless wav?(data)
        le = IO::ByteFormat::LittleEndian
        pos = 12
        format = 0; channels = 0; rate = 0; bits = 0
        pcm : Bytes? = nil
        while pos + 8 <= data.size
          id = String.new(data[pos, 4])
          size = le.decode(UInt32, data[pos + 4, 4]).to_i
          body = data[pos + 8, Math.min(size, data.size - pos - 8)]
          case id
          when "fmt "
            format = le.decode(UInt16, body[0, 2]).to_i
            channels = le.decode(UInt16, body[2, 2]).to_i
            rate = le.decode(UInt32, body[4, 4]).to_i
            bits = le.decode(UInt16, body[14, 2]).to_i
            if format == 0xFFFE && body.size >= 26 # WAVE_FORMAT_EXTENSIBLE
              format = le.decode(UInt16, body[24, 2]).to_i
            end
          when "data"
            pcm = body
          end
          pos += 8 + size + (size & 1)
        end
        raise AssetError.new("WAV has no data chunk") unless pcm
        raise AssetError.new("WAV has no fmt chunk") if channels == 0
        bytes_per = bits // 8
        frames = pcm.size // (bytes_per * channels)
        samples = Slice(Float32).new(frames * channels)
        case {format, bits}
        when {1, 8}
          samples.size.times { |i| samples[i] = (pcm[i].to_i - 128) / 128_f32 }
        when {1, 16}
          samples.size.times { |i| samples[i] = le.decode(Int16, pcm[i * 2, 2]) / 32768_f32 }
        when {1, 24}
          samples.size.times do |i|
            v = (pcm[i * 3].to_i32) | (pcm[i * 3 + 1].to_i32 << 8) | (pcm[i * 3 + 2].to_i32 << 16)
            v -= 0x1000000 if v & 0x800000 != 0
            samples[i] = v / 8388608_f32
          end
        when {1, 32}
          samples.size.times { |i| samples[i] = le.decode(Int32, pcm[i * 4, 4]) / 2147483648_f32 }
        when {3, 32}
          samples.size.times { |i| samples[i] = le.decode(Float32, pcm[i * 4, 4]) }
        when {3, 64}
          samples.size.times { |i| samples[i] = le.decode(Float64, pcm[i * 8, 8]).to_f32 }
        else
          raise AssetError.new("Unsupported WAV format #{format} / #{bits}-bit")
        end
        AudioBuffer.new(rate, channels, samples)
      end

      # Encodes an `AudioBuffer` as 16-bit PCM WAV, for saving generated sounds.
      def self.encode(buf : AudioBuffer) : Bytes
        le = IO::ByteFormat::LittleEndian
        data_size = buf.samples.size * 2
        io = IO::Memory.new(44 + data_size)
        io.write("RIFF".to_slice); io.write_bytes((36 + data_size).to_u32, le); io.write("WAVE".to_slice)
        io.write("fmt ".to_slice); io.write_bytes(16_u32, le); io.write_bytes(1_u16, le)
        io.write_bytes(buf.channels.to_u16, le); io.write_bytes(buf.sample_rate.to_u32, le)
        io.write_bytes((buf.sample_rate * buf.channels * 2).to_u32, le)
        io.write_bytes((buf.channels * 2).to_u16, le); io.write_bytes(16_u16, le)
        io.write("data".to_slice); io.write_bytes(data_size.to_u32, le)
        buf.samples.each { |s| io.write_bytes((s.clamp(-1_f32, 1_f32) * 32767).round.to_i16, le) }
        io.to_slice
      end
    end
  end
end
