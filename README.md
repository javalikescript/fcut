## What is Fast Cut?

Fast Cut allows to visually cut and join videos then export losslessly.

> :warning: The project is still experimental.

The main purpose are to join camcorder footages and to clean a recording from the commercial breaks.

Fast Cut provides a graphical user interface for [FFmpeg](https://www.ffmpeg.org/), you could use your own ffmpeg binaries.
It is based on [luajls](https://github.com/javalikescript/luajls) and supports both Linux and Windows OSes.
Mac OS is not supported as I do not have access to.

The main supported format are MPEG Transport Stream (ts, m2ts) to MPEG-4 Part 14 (mp4), but any FFmpeg supported format could be used.

If you need advanced features you could try [LosslessCut](https://github.com/mifi/lossless-cut) or [OpenShot](https://www.openshot.org/).

## What are the features?

Fast Cut provides:
* frame preview, no audio
* preview time line with cut parts
* binary search to find a cut point
* lossless export when supported by codecs and format
* small, under 1Mb without FFmpeg

## What does it look like?

<div align="center">
<img src="https://github.com/javalikescript/fcut/raw/main/screenshot.jpg" />
</div>
