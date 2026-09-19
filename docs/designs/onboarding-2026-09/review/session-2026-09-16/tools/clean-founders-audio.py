"""Reproduce the local speech cleanup and mux it over unchanged review video.

Requires PyAV + numpy, and the official DeepFilterNet 0.5.6 Mac binary.
No upload, voice synthesis, time stretching, or picture generation occurs.
"""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import av
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('--original', type=Path, required=True)
parser.add_argument('--base-cut', type=Path, required=True)
parser.add_argument('--deep-filter', type=Path, required=True)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.work.mkdir(parents=True, exist_ok=True)
rate, start, end = 48000, 23.5, 114.465
original_pcm = args.work / 'original-stereo.wav'
if not original_pcm.exists():
    container = av.open(str(args.original))
    resampler = av.AudioResampler(format='s16', layout='stereo', rate=rate)
    chunks = []
    for frame in container.decode(container.streams.audio[0]):
        chunks.extend(f.to_ndarray().reshape(-1, 2) for f in resampler.resample(frame))
    chunks.extend(f.to_ndarray().reshape(-1, 2) for f in resampler.resample(None))
    with wave.open(str(original_pcm), 'wb') as output:
        output.setnchannels(2); output.setsampwidth(2); output.setframerate(rate)
        output.writeframes(np.concatenate(chunks).astype(np.int16).tobytes())
denoised = args.work / 'denoised/original-stereo.wav'
if not denoised.exists():
    subprocess.run([str(args.deep_filter), '-D', '-a', '18', '--reduce-mask', '1', '-o', str(denoised.parent), str(original_pcm)], check=True)

def read_pcm(path):
    with wave.open(str(path), 'rb') as source:
        assert source.getframerate() == rate and source.getnchannels() == 2 and source.getsampwidth() == 2
        return np.frombuffer(source.readframes(source.getnframes()), np.int16).reshape(-1, 2)

original, cleaned = read_pcm(original_pcm), read_pcm(denoised)
# -D compensates lookahead. The processor drops its 30 ms trailing flush;
# retain the source timeline with silence only after the recorded final word.
trailing = len(original) - len(cleaned)
assert 0 <= trailing <= rate // 20
cleaned = np.pad(cleaned, ((0, trailing), (0, 0)))
cut = cleaned[round(start * rate):round(end * rate)]
expected = round((end - start) * rate)
assert len(cut) == expected
cut_wav = args.work / 'cleaned-cut.wav'
with wave.open(str(cut_wav), 'wb') as output:
    output.setnchannels(2); output.setsampwidth(2); output.setframerate(rate); output.writeframes(cut.tobytes())

source = av.open(str(args.base_cut))
video = source.streams.video[0]
assert (video.width, video.height) == (540, 960), 'Export the portrait base cut with ReviewMedia first.'
destination = av.open(str(args.output), mode='w', options={'movflags': '+faststart'})
video_out = destination.add_stream_from_template(video)
audio_out = destination.add_stream('aac', rate=rate)
audio_out.layout = 'stereo'; audio_out.bit_rate = 192000
packets = []
for packet in source.demux(video):
    if packet.dts is not None:
        packet.stream = video_out
        packets.append((float(packet.dts * packet.time_base), packet))
for position in range(0, len(cut), 1024):
    samples = cut[position:position+1024].astype(np.float32).T.copy() / 32768
    frame = av.AudioFrame.from_ndarray(samples, format='fltp', layout='stereo')
    frame.sample_rate = rate; frame.time_base = Fraction(1, rate); frame.pts = position
    packets.extend((float(p.dts * p.time_base), p) for p in audio_out.encode(frame))
packets.extend((float(p.dts * p.time_base), p) for p in audio_out.encode(None))
for _, packet in sorted(packets, key=lambda item: item[0]):
    destination.mux(packet)
destination.close(); source.close()

def packet_hash(path):
    digest = hashlib.sha256(); c = av.open(str(path)); count = 0
    for packet in c.demux(c.streams.video[0]):
        if packet.dts is not None:
            digest.update(bytes(packet)); count += 1
    return digest.hexdigest(), count

assert packet_hash(args.base_cut) == packet_hash(args.output), 'Video packets changed.'
report = {'tool': 'DeepFilterNet 0.5.6, embedded model', 'attenuationLimitDb': 18,
          'delayCompensated': True, 'postFilter': False, 'gain': 1, 'sampleRate': rate,
          'channels': 2, 'startSeconds': start, 'endSeconds': end,
          'durationSeconds': len(cut)/rate, 'trailingPaddingSeconds': trailing/rate,
          'clippedSamples': int((abs(cut.astype(np.int32)) >= 32767).sum()),
          'originalVideoPacketsUnchanged': True, 'videoPacketCount': packet_hash(args.output)[1],
          'audioSourceSha256': hashlib.sha256(args.original.read_bytes()).hexdigest(),
          'outputSha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
          'subjectiveListeningApproval': 'pending Joe', 'higgsfieldCreditsUsed': 0}
args.output.with_suffix('.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
