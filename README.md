## What is Fast Cut?

Fast Cut allows to visually cut and join videos then export losslessly.

> :warning: The project is still experimental.

The main purposes are to
* join camcorder footages and
* clean a recording from the commercial breaks.

Fast Cut provides a graphical user interface for [FFmpeg](https://www.ffmpeg.org/), you could use your own ffmpeg binaries.
It is based on [luajls](https://github.com/javalikescript/luajls) and supports both Linux and Windows OSes.
Mac OS is not supported as I do not have access to.

The main supported format is MPEG Transport Stream (ts, m2ts) to MPEG-4 Part 14 (mp4), but any FFmpeg supported format could be used.

If you need advanced features you could try [LosslessCut](https://github.com/mifi/lossless-cut) or [OpenShot](https://www.openshot.org/).

## What are the features?

Fast Cut provides:
* frame preview, no audio
* preview time line with cut parts
* binary search to find a cut point
* lossless export when supported by codecs and format
* could run on a remote server such as a NAS
* small, under 1Mb without FFmpeg
* plain lua, html and javascript, no compiler

## What does it look like?

![screenshot-windows](https://user-images.githubusercontent.com/9386420/144749617-b4d8ef5b-3957-4409-a090-d71b73654b2e.jpg)


![screenshot-linux](https://user-images.githubusercontent.com/9386420/144749623-427bf569-8fdb-4c57-9673-4b89a02dbf09.jpg)


https://user-images.githubusercontent.com/9386420/144749626-fd66a1c7-0c76-4cbc-80d1-9242f5c8f487.mp4


## How to install it?

Grab the [last release](https://github.com/javalikescript/fcut/releases/latest),
[download FFmpeg](https://www.ffmpeg.org/download.html) if needed and provide the FFmpeg location at startup using the `-ffmpeg` argument.
