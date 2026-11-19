# Presentation video is separate

The 1.8 code-only handoff does not include a competition presentation render. User-approved visual direction: square, light-grey background, centered metal device, no external titles, one subtle uniform push-in and silent audio. This document describes only how the live reference UI can be captured later; it does not claim a new video has been produced for this handoff.

`./run-ios-demo.sh <simulator-udid> --capture-canvas` lays out the same live components in 402 × 612 pt for the housing aperture. A full-screen normal run is the default. Compact context-menu sizing retains all commands. Crop the complete capture canvas without stretching; on the previously measured iPhone 17 capture it was x=0,y=393,w=1206,h=1836. Measure bounds again for another device/runtime. tools/CropDemoCapture.swift provides the crop operation.

Capture actual publication/deletion, profile → Edit → Recent Actions, long-press → Restore and the return of the original. Preserve the continuous restore result. Recording is simulated from a prepared clip, and recovery uses the local reference backend; the accompanying submission text explains these boundaries. A separately generated smoother character clip has not been substituted into this source release.
