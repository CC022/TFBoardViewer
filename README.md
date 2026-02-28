# TFBoardViewer

A native macOS app for browsing TensorBoard event logs (`tfevents`) without running a web server.

## Overview

TFBoardViewer parses TensorBoard log folders and displays:
- Scalars as line charts
- Images as a grid
- Media entries (GIF/MP4)
- Video frame sequences

The app is built with SwiftUI and uses a lightweight protobuf/TFRecord parser implemented in this repository.

## Features

- Open a TensorBoard run folder from file picker
- Drag-and-drop folder support
- Sidebar grouped by TensorBoard tag
- Scalar chart rendering with CSV copy
- Image and video/media preview per tag
- Parses multiple `tfevents` files in a run

## Requirements

- macOS 14 or newer
- Xcode 15 or newer

## Run Locally

1. Clone this repository.
2. Open `TFBoardViewer.xcodeproj` in Xcode.
3. Select the `TFBoardViewer` scheme.
4. Build and run the app.
5. In the app, click **Open Folder…** (or drag/drop) and select a TensorBoard log directory.

## Supported Data (Current)

- Scalars (`simple_value` and tensor numeric values)
- Images (summary image and tensor string/image content)
- Media blobs (GIF/MP4)
- Tensor video-like frame sequences

## Project Structure

```text
TFBoardViewer/
  AppState.swift         # app-level loading/parsing state
  ContentView.swift      # main UI: sidebar, charts, image/video views
  EventParser.swift      # TFRecord + TensorBoard event parsing
  Models.swift           # parsed domain models
  ProtoWire.swift        # minimal protobuf wire reader
  TFBoardViewerApp.swift # app entry point
```

## Notes

- This project focuses on local desktop viewing for common TensorBoard artifacts.
- Some TensorBoard plugins/formats may not be fully supported yet.
