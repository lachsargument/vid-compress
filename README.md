# Video Compressor

Video Compressor is a small macOS app that uses FFmpeg to compress a video.
You can set the output format, the frame rate, the resolution, and the quality.

- Formats: MP4 with H.264, MP4 with HEVC, and WebM with VP9.
- The resolution sets the short side of the video. The app does not make a video larger.
- On Apple Silicon, you can select "Use hardware encoding" for H.264 and HEVC.
  Hardware encoding is faster, but the file is usually larger. WebM has no hardware encoder.
- The app always uses hardware decoding when the input codec supports it.

Video Compressor needs FFmpeg. To install FFmpeg, run `brew install ffmpeg`.

To build the app, run `./build.sh`. You need the Xcode command line tools.
