# AstroHybrid VR

An experimental PC VR mod for **Astro Bot (PS5)** using [AstroHybrid](https://github.com/imnotsharingmyname/pcportastrobot), the KytyPS5 GPU renderer, and OpenXR.

Both eyes render from the **same game frame**. Features include head tracking, headset-shaped eye targets, aligned loading screens and overlays, a saved-settings launcher, and optional NVIDIA optical-flow frame generation through [OFXR-Bridge](https://github.com/tig3rmast3r/OFXR-Bridge).

**This is a VR add-on to AstroHybrid 1.2.1. No game executable, game assets, keys, or saves are included.** Setup patches the supported executable produced from your own game dump, locally on your PC.

## Requirements

- Windows 10/11 x64, a Vulkan-capable GPU, and the Microsoft Visual C++ 2015–2022 x64 runtime.
- A PC VR headset and working OpenXR runtime. SteamVR has been tested. Connect the headset and keep the PC VR session awake before launching.
- Your own decrypted **PPSA21567, version 01.019.000** Astro Bot dump. The installer recognizes both AMD and Intel conversions from AstroHybrid 1.2.1, as well as the original supported conversion. It verifies the full executable before and after patching.
- [AstroHybrid 1.2.1](https://github.com/imnotsharingmyname/pcportastrobot/releases/tag/v1.2.1), installed and working in desktop mode.
- A gamepad or PC VR controllers (Oculus/Meta Touch, Valve Index, WMR, HTC Vive, or generic OpenXR controllers) with haptic feedback. Gamepad and VR controllers coexist seamlessly.
- NVIDIA optical-flow frame generation requires a compatible NVIDIA GPU and driver. This mod was developed on an RTX 5090 with 32 GB VRAM; comparable performance on other GPUs has not been established. Start at the lower presets. The 5184 and 6000 presets can consume substantial VRAM.

## Upgrading an existing installation

Close the game, extract the v0.1.7 Windows ZIP into the same AstroHybrid installation, and run **Install VR.bat** again. Your saved launcher preferences carry forward. The installer creates a VR-specific layout for tutorial videos, holoboard instructions, construction prompts, coin counters and level-name banners using your installed assets.

## First-time installation

1. Download and extract the **AstroHybrid 1.2.1** ZIP from the link above. For example, extract it to `D:\Games\AstroHybrid`.
2. Open its **AstroHybrid.exe** and complete setup. Select your own decrypted game dump folder: the folder containing `eboot.bin`, `sce_module`, and `sce_sys`. **Keep the game files in that dump folder. Do not put a PKG or a game archive into the VR mod folder.** AstroHybrid reads that folder and creates the Windows executable and loader files under `Build\RunHybrid`.
3. Verify that the game starts in desktop mode, then close it.
4. Download **AstroHybrid-VR-v0.1.7-Windows.zip** from this repository's [releases](https://github.com/evertec82/AstroHybrid-VR/releases). Extract its contents **directly into the same AstroHybrid folder**, alongside `AstroHybrid.exe`. After extraction, `Install VR.bat` and `Play AstroHybrid VR - Launcher.bat` should be beside `AstroHybrid.exe`.
5. Run **Install VR.bat**. It verifies the mod files and exact game build, creates both VR game variants from your converted executable, copies the six loader sidecars, installs the VR renderer, and prepares the local OFXR layer. The original game executable remains unchanged. The previous renderer and video-out shim are copied to a timestamped `VR-backup-*` folder.
6. Connect your headset through your usual PC VR software. Make sure the intended OpenXR runtime is active and the headset is awake.
7. Open **Play AstroHybrid VR - Launcher.bat**, choose settings, and press **Start VR**.

The installer requires no Python, compiler, or separate OFXR tray setup. OFXR is loaded only for launches that enable frame generation. Launches do not register the bundled bridge globally. Do not run an additional OFXR copy for this game.

If setup reports an unrecognized conversion, run **Check Conversion.bat** beside the installer and share the resulting **AstroHybrid-conversion-report.json**. It contains hashes and conversion settings.

## Launcher settings

Settings are saved in `vr-launcher-settings.json`.

| Setting | Choices |
| --- | --- |
| Per-eye output width | 2048, 2560, 3200, 3520, 4512, 5184, 6000 |
| DLSS Super Resolution (RTX) | Off, Performance, Balanced, Quality, DLAA |
| Frame generation | Off / NVIDIA optical flow |
| Output multiplier | 2x, 3x, 4x; higher multipliers are experimental |
| Flow quality | Fast, Medium, Quality |
| Flow estimation resolution | 25%, 50%, 75%, 100% |
| Performance overlay | Off by default |
| Detailed diagnostics | Off by default |
| Skip intro | Optional |

The public default is **3520 pixels per eye**, 2x generation, Medium flow quality, 25% flow estimation, and no overlay. The height follows the headset's aspect ratio and runtime limits. On the development headset, 6000 produces **6000 × 5536 per eye**. The launcher shows when a mode uses full-size targets. At 6000 it requires DLSS upscaling. Large targets can exhaust GPU memory.

Both eyes render the same game frame. DLSS Super Resolution maintains a separate history for each eye. Frame generation uses NVIDIA optical flow independently of Super Resolution. F10 opens OFXR's in-headset settings when generation is enabled. Disable additional runtime motion smoothing/Virtual Desktop SSW when comparing OFXR; ordinary compositor head-pose correction remains necessary.

Frame-generation launches use a **24576 MiB renderer-cache planning cap**, tuned for the development PC's 32 GB GPU. This is an eviction target, not a hard heap allocation limit. Smaller GPUs still have their driver-reported budget, but this setting is not a guarantee that a selected resolution will fit. `KYTY_VRAM_BUDGET_MB` can override the planning cap before launch.

## Experimental status and known issues

- Sky Aztec now treats a collision query containing an invalid coordinate (NaN) as a miss. The guard passed 28 native regression cases. A local level test completed 2,400 same-frame stereo pairs at 6000 × 5536 per eye. Other physics failure modes may still exist.
- The renderer includes a bounded diagnostic capture for that Havok fault. It records traversal locals and tree data without consuming the exception or modifying physics state.
- High resolutions plus frame generation can cause VRAM pressure, long copy waits, and stalls. The 6000 preset is an available option, not a performance recommendation.
- Optical-flow interpolation can produce ghosting or warping. Results depend on scene, GPU load, headset refresh rate, and runtime. Vulkan bridging is experimental.
- A short earlier scene reached about 90 displayed FPS from 45 fresh stereo pairs/second on the development PC. This is not a claim about full-game performance, and pauses/crashes have subsequently occurred in heavier gameplay.
- The source-readiness gate now waits at most 2 ms **after** runtime pacing; the earlier 75 ms pre-pacing gate has been removed. GPU copies and bridge submission can still block independently; the logs distinguish those costs.

## Reporting a problem

After a freeze or crash, copy these files **before launching again**, because the next run replaces the main logs:

- `Logs\hybrid-run.out.log`
- `Logs\hybrid-run.err.log`
- `Logs\vr-memory.log` if present
- `vr-launcher-settings.json`
- Relevant `Build\FrameGeneration\ofxr\*.log` files if detailed diagnostics were enabled

Include the level, last action, headset, OpenXR runtime, GPU/VRAM, and whether audio/game input also stopped. The renderer's 10-second summary separates fresh stereo pairs, reused sources, runtime waits, image copies/releases, and frame submission. App submissions are not proof of newly rendered or generated frames. Share logs in a GitHub issue after checking them for personal paths or other information you do not want to publish.

## Returning to desktop mode

Close the game. From the AstroHybrid folder, run `powershell -ExecutionPolicy Bypass -File .\Install-HudLayout.ps1 -RunDirectory (Resolve-Path .\Build\RunHybrid) -Restore` in PowerShell to restore the original HUD layout. Restore `kyty_gpu.dll` and `libSceVideoOut.prx` from the installer-created backup (the shim belongs under `Build\RunHybrid\libs`), then use the original AstroHybrid launcher. Keep your game dump, existing saves, and original executable. An AstroHybrid self-update may replace the VR renderer; reinstall the VR mod only if the game build still passes its compatibility check.

## Source, credits, and licenses

- [AstroHybrid](https://github.com/imnotsharingmyname/pcportastrobot), based on AnyPS5 and KytyPS5.
- [KytyPS5](https://github.com/Jetsku/KytyPS5): the custom GPU renderer is derived from the AstroHybrid hybrid renderer and licensed under GPL-2.0. `Source/astrohybrid-vr.patch` records the VR changes; the release's **source ZIP** contains the complete modified renderer source snapshot and dependency pins.
- [OFXR-Bridge](https://github.com/tig3rmast3r/OFXR-Bridge), version 0.3.3-v983, GPL-3.0. Its original license, notices, provider licenses, and build provenance are retained. The source ZIP also contains the corresponding bridge source at commit `b683b687c0fa83963a6475df9bc6b623fefb6e25`.
- NVIDIA and other third-party components retain their respective licenses, included with the bundled bridge. OpenXR and Vulkan dependencies retain their original licenses.

See [BUILDING.md](BUILDING.md) for source reconstruction and build details. This project is not affiliated with Sony, Team Asobi, or the upstream projects.
