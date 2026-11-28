@echo off
setlocal
set "ASTROHYBRID_VR=1"
rem AstroHybrid supplies both eyes. Keep the system R.E.A.L. VR layer out of this session.
set "DISABLE_VK_LAYER_RealVR_1=1"
rem Per-draw crash markers are opt-in; retain device-fault reporting below.
if not defined KYTY_DEVICE_FAULT_DIAGNOSTICS set "KYTY_DEVICE_FAULT_DIAGNOSTICS=0"
if not defined KYTY_DEVICE_FAULT_EXT set "KYTY_DEVICE_FAULT_EXT=1"
if exist "%~dp0Build\RunHybrid\PipelineLists\PPSA21567.kyplst" (
  if not defined KYTY_PIPELINE_LIST set "KYTY_PIPELINE_LIST=1"
  if not defined KYTY_SHADER_PRECOMPILE set "KYTY_SHADER_PRECOMPILE=1"
  if not defined KYTY_SHADER_PRECOMPILE_WAIT set "KYTY_SHADER_PRECOMPILE_WAIT=1"
  if not defined KYTY_SHADER_PRECOMPILE_THREADS set "KYTY_SHADER_PRECOMPILE_THREADS=8"
  if not defined KYTY_PIPELINE_JOURNAL set "KYTY_PIPELINE_JOURNAL=1"
  if not defined KYTY_PIPELINE_JOURNAL_WAIT set "KYTY_PIPELINE_JOURNAL_WAIT=1"
  if not defined KYTY_PIPELINE_FAST_FIRST_THREADS set "KYTY_PIPELINE_FAST_FIRST_THREADS=4"
)
if not defined KYTY_NATIVE_IMAGE_POOL_MB set "KYTY_NATIVE_IMAGE_POOL_MB=64"
if not defined KYTY_VRAM_BUDGET_MB set "KYTY_VRAM_BUDGET_MB=23552"
if not defined KYTY_VRAM_GC_BUDGET set "KYTY_VRAM_GC_BUDGET=1"
if not defined KYTY_VRAM_PRESSURE_FRAMES set "KYTY_VRAM_PRESSURE_FRAMES=12"
if not defined KYTY_RAM_SMALL_UPLOAD_RING set "KYTY_RAM_SMALL_UPLOAD_RING=1"
if not defined KYTY_TILER_SCRATCH_POOL_MB set "KYTY_TILER_SCRATCH_POOL_MB=128"
if not defined KYTY_GUEST_BACKING_LAZY_COMMIT set "KYTY_GUEST_BACKING_LAZY_COMMIT=1"
if not defined KYTY_GUEST_BACKING_LAZY_ZERO set "KYTY_GUEST_BACKING_LAZY_ZERO=1"
if not defined KYTY_BUFFER_LRU_SKIP set "KYTY_BUFFER_LRU_SKIP=1"
if not defined KYTY_VRAM_STATS set "KYTY_VRAM_STATS=1"
if not defined KYTY_VRAM_STATS_SECONDS set "KYTY_VRAM_STATS_SECONDS=15"
if not defined KYTY_VRAM_STATS_FILE set "KYTY_VRAM_STATS_FILE=%~dp0Logs\vr-memory.log"
set "KYTY_OPENXR=1"
set "KYTY_FLAT_CAMERA_VR=1"
set "KYTY_FLAT_STEREO=1"
set "KYTY_FLAT_STEREO_SAME_FRAME=1"
set "KYTY_FLAT_STEREO_MIRROR=1"
if not defined KYTY_VR_OUTPUT_PIXELS set "KYTY_VR_OUTPUT_PIXELS=1"
if not defined KYTY_VR_FOV_COVERAGE set "KYTY_VR_FOV_COVERAGE=1.35"
rem Both eye binding plans are reset when speculative preparation slots are reused.
if not defined KYTY_DRAW_PREP set "KYTY_DRAW_PREP=parallel"
rem Upstream 1.2.13: order compute dispatches to avoid GPU stalls.
if not defined KYTY_DISPATCH_OVERLAP set "KYTY_DISPATCH_OVERLAP=0"
rem Support upstream exFAT/FAT32 alias dumps (#135) and non-destructive mods/ overlays (#22).
if not defined APS5_PATH_ALIASES if exist "%~dp0Build\RunHybrid\app0-aliases.txt" set /p APS5_PATH_ALIASES=<"%~dp0Build\RunHybrid\app0-aliases.txt"
if not defined APS5_PATH_OVERLAYS if exist "%~dp0mods\" set "APS5_PATH_OVERLAYS=/app0=%~dp0mods"
set "KYTY_STEREO_PREP_BINDINGS=1"
set "KYTY_STEREO_REGISTER_BORROW=1"
set "KYTY_STEREO_SHARED_PLAN=1"
rem KYTY_CP_RECORDER=1 is safe with OFXR (CopyToSwapchain waits on producer->IsFree) and offloads ~14.5% of CP Vulkan calls.
if not defined KYTY_CP_RECORDER set "KYTY_CP_RECORDER=1"
if not defined KYTY_CP_RECORDER_WAIT_SUBMIT set "KYTY_CP_RECORDER_WAIT_SUBMIT=1"
if "%KYTY_CP_RECORDER%"=="1" if not defined KYTY_CP_BINDING_BATCH_PREFETCH set "KYTY_CP_BINDING_BATCH_PREFETCH=find"
rem Cross-frame texture set reuse + 64K texture memo (fits in 9800X3D 96 MiB L3; 68.5% Sky Garden revalidation).
if not defined KYTY_XFRAME_REUSE set "KYTY_XFRAME_REUSE=1"
if not defined KYTY_XFRAME_REUSE_SLOTS set "KYTY_XFRAME_REUSE_SLOTS=16384"
if not defined KYTY_TEXTURE_MEMO_SLOTS set "KYTY_TEXTURE_MEMO_SLOTS=65536"
if not defined KYTY_CP_COMMIT set "KYTY_CP_COMMIT=all"
if not defined KYTY_PIPELINE_SKIP set "KYTY_PIPELINE_SKIP=1"
if not defined KYTY_PIPELINE_SKIP_THREADS set "KYTY_PIPELINE_SKIP_THREADS=4"
if not defined KYTY_PIPELINE_SKIP_WAIT_US set "KYTY_PIPELINE_SKIP_WAIT_US=1000"
set "KYTY_HOST_INPUT_MIN_PRESS_MS=120"
set "KYTY_ASTRO_INTERNAL_PIXELS=0"
set "KYTY_ASTRO_EXPANDED_MEMORY=0"
if not defined ASTROHYBRID_DLSS set "ASTROHYBRID_DLSS=0"
set "ASTROHYBRID_DLSSG=0"
set "ASTROHYBRID_GAME_SPEED=1"
set "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1"
if not exist "%~dp0Build\RunHybrid\AstroHybridVR.ready" (
  echo The AstroHybrid VR renderer has not been installed.
  exit /b 1
)
call "%~dp0Run-AstroHybrid.bat" %*
exit /b %ERRORLEVEL%

